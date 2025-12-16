// -------------------------------------------------------
// hmac_controller.v
// HMAC-SHA3-512 controller with 32-bit streaming message input
// -------------------------------------------------------
module hmac_controller(
    input               clk,
    input               reset,

    input               start_puf,
    input               start_hmac,

    input      [703:0]  puf_input,

    input      [31:0]   msg_word,
    input               msg_valid,
    input               msg_last,
    output reg          msg_ready,

    output reg [511:0]  puf_key_out,
    output reg [511:0]  hmac_out,
    output reg          done,

    output reg          mode_puf,
    output reg          mode_block,

    output reg          sha_start_puf,
    output reg [703:0]  sha_puf_data,

    output reg          sha_start_block,
    output reg [31:0]   sha_block_word,
    output reg          sha_block_word_valid,
    output reg          sha_block_last,
    output reg [5:0]    sha_words_in_block,

    input      [511:0]  sha_out,
    input               sha_out_ready,
    input               sha_busy,
    input               sha_buffer_full
);

    localparam integer RATE_WORDS = 18;

    // SHA3 HMAC ipad/opad
    wire [575:0] IPAD = {72{8'h36}};
    wire [575:0] OPAD = {72{8'h5C}};

    reg  [511:0] inner_hash;

    wire [575:0] key_padded   = {puf_key_out, 64'b0};
    wire [575:0] key_xor_ipad = key_padded ^ IPAD;
    wire [575:0] key_xor_opad = key_padded ^ OPAD;

    // sending buffer (one block worth)
    reg  [575:0] send_buf;
    reg  [5:0]   send_words_left;
    reg          send_last_flag;     // this block ends the whole message?

    // message collector (up to 18 words)
    reg  [575:0] msg_buf;
    reg  [5:0]   msg_count;          // 0..18
    reg          msg_buf_has_last;

    // one-shot start control
    reg          block_started;

    // Word accepted by SHA streamer
    wire sha_word_accepted = (sha_busy && sha_block_word_valid && !sha_buffer_full);

    // -------------------------
    // State encoding (Verilog)
    // -------------------------
    localparam S_IDLE             = 5'd0;

    localparam S_PUF_START        = 5'd1;
    localparam S_PUF_WAIT         = 5'd2;

    localparam S_INNER_IPAD_LOAD  = 5'd3;
    localparam S_INNER_IPAD_SEND  = 5'd4;

    localparam S_MSG_COLLECT      = 5'd5;
    localparam S_MSG_BLOCK_LOAD   = 5'd6;
    localparam S_MSG_BLOCK_SEND   = 5'd7;

    localparam S_INNER_WAIT       = 5'd8;

    localparam S_OUTER_OPAD_LOAD  = 5'd9;
    localparam S_OUTER_OPAD_SEND  = 5'd10;

    localparam S_OUTER_INNER_LOAD = 5'd11;
    localparam S_OUTER_INNER_SEND = 5'd12;

    localparam S_OUTER_WAIT       = 5'd13;

    localparam S_DONE             = 5'd14;

    reg [4:0] state, nstate;

    // -------------------------
    // Sequential
    // -------------------------
    always @(posedge clk) begin
        if (reset) begin
            state <= S_IDLE;

            puf_key_out <= 0;
            hmac_out    <= 0;
            inner_hash  <= 0;

            send_buf        <= 0;
            send_words_left <= 0;
            send_last_flag  <= 0;

            msg_buf          <= 0;
            msg_count        <= 0;
            msg_buf_has_last <= 0;

            block_started <= 0;
        end else begin
            state <= nstate;

            // capture sha outputs
            if (state == S_PUF_WAIT && sha_out_ready)
                puf_key_out <= sha_out;

            if (state == S_INNER_WAIT && sha_out_ready)
                inner_hash <= sha_out;

            if (state == S_OUTER_WAIT && sha_out_ready)
                hmac_out <= sha_out;

            // collect message words
            if (state == S_MSG_COLLECT) begin
                if (msg_ready && msg_valid) begin
                    msg_buf[32*msg_count +: 32] <= msg_word;
                    msg_count <= msg_count + 1;
                    if (msg_last)
                        msg_buf_has_last <= 1'b1;
                end
            end

            // shift/decrement only when SHA streamer really accepted a word
            if (sha_word_accepted) begin
                send_buf <= (send_buf >> 32);
                if (send_words_left != 0)
                    send_words_left <= send_words_left - 1;
            end

            // reset block_started whenever we enter a LOAD state
            if (state != nstate) begin
                if (nstate == S_INNER_IPAD_LOAD ||
                    nstate == S_MSG_BLOCK_LOAD  ||
                    nstate == S_OUTER_OPAD_LOAD ||
                    nstate == S_OUTER_INNER_LOAD)
                    block_started <= 1'b0;
            end

            // latch block_started once we pulse start_block
            if (sha_start_block)
                block_started <= 1'b1;

            // LOAD actions
            if (state == S_INNER_IPAD_LOAD) begin
                send_buf        <= key_xor_ipad;
                send_words_left <= RATE_WORDS;
                send_last_flag  <= 1'b0;
            end

            if (state == S_MSG_BLOCK_LOAD) begin
                send_buf        <= msg_buf;
                send_words_left <= msg_count;
                send_last_flag  <= msg_buf_has_last;

                // clear collector for next block
                msg_buf          <= 0;
                msg_count        <= 0;
                msg_buf_has_last <= 0;
            end

            if (state == S_OUTER_OPAD_LOAD) begin
                send_buf        <= key_xor_opad;
                send_words_left <= RATE_WORDS;
                send_last_flag  <= 1'b0;
            end

            if (state == S_OUTER_INNER_LOAD) begin
                // inner_hash is 512 bits = 16 words; pad lower 64 bits to make 576
                send_buf        <= {inner_hash, 64'b0};
                send_words_left <= 6'd16;
                send_last_flag  <= 1'b1;
            end
        end
    end

    // -------------------------
    // Combinational outputs + next state
    // -------------------------
    always @(*) begin
        // defaults
        nstate = state;

        done = 1'b0;

        mode_puf   = 1'b0;
        mode_block = 1'b0;

        sha_start_puf = 1'b0;
        sha_puf_data  = puf_input;

        sha_start_block      = 1'b0;
        sha_block_word       = send_buf[31:0];
        sha_block_word_valid = 1'b0;
        sha_block_last       = 1'b0;
        sha_words_in_block   = RATE_WORDS;

        msg_ready = 1'b0;

        case (state)

            S_IDLE: begin
                if (start_puf)
                    nstate = S_PUF_START;
                else if (start_hmac)
                    nstate = S_INNER_IPAD_LOAD;
            end

            // -------------------------
            // PUF = SHA3(puf_input_704)
            // -------------------------
            S_PUF_START: begin
                mode_puf      = 1'b1;
                sha_puf_data  = puf_input;
                sha_start_puf = 1'b1;
                nstate        = S_PUF_WAIT;
            end

            S_PUF_WAIT: begin
                mode_puf = 1'b1;
                if (sha_out_ready)
                    nstate = S_DONE;
            end

            // -------------------------
            // INNER: send (K^ipad) block
            // -------------------------
            S_INNER_IPAD_LOAD: begin
                // go to send immediately
                nstate = S_INNER_IPAD_SEND;
            end

            S_INNER_IPAD_SEND: begin
                mode_block = 1'b1;

                // one-shot block start
                if (!block_started && !sha_busy && !sha_buffer_full)
                    sha_start_block = 1'b1;

                sha_words_in_block = RATE_WORDS;

                // drive words only when the keccak_top is in streaming busy mode
                if (sha_busy && (send_words_left != 0) && !sha_buffer_full) begin
                    sha_block_word_valid = 1'b1;
                    sha_block_last       = 1'b0; // ipad block never last
                end

                if (send_words_left == 0)
                    nstate = S_MSG_COLLECT;
            end

            // -------------------------
            // Collect message words (up to 18)
            // -------------------------
            S_MSG_COLLECT: begin
                msg_ready = (msg_count < RATE_WORDS);

                // send when full block OR msg_last seen (and at least 1 word)
                if ((msg_count == RATE_WORDS) || (msg_buf_has_last && (msg_count != 0)))
                    nstate = S_MSG_BLOCK_LOAD;
            end

            S_MSG_BLOCK_LOAD: begin
                nstate = S_MSG_BLOCK_SEND;
            end

            S_MSG_BLOCK_SEND: begin
                mode_block = 1'b1;

                // one-shot start
                if (!block_started && !sha_busy && !sha_buffer_full)
                    sha_start_block = 1'b1;

                sha_words_in_block = send_words_left;

                if (sha_busy && (send_words_left != 0) && !sha_buffer_full) begin
                    sha_block_word_valid = 1'b1;
                    // only assert last on FINAL word of FINAL block
                    if ((send_words_left == 1) && send_last_flag)
                        sha_block_last = 1'b1;
                    else
                        sha_block_last = 1'b0;
                end

                if (send_words_left == 0) begin
                    if (send_last_flag)
                        nstate = S_INNER_WAIT;
                    else
                        nstate = S_MSG_COLLECT;
                end
            end

            S_INNER_WAIT: begin
                mode_block = 1'b1;
                if (sha_out_ready)
                    nstate = S_OUTER_OPAD_LOAD;
            end

            // -------------------------
            // OUTER: send (K^opad) block
            // -------------------------
            S_OUTER_OPAD_LOAD: begin
                nstate = S_OUTER_OPAD_SEND;
            end

            S_OUTER_OPAD_SEND: begin
                mode_block = 1'b1;

                if (!block_started && !sha_busy && !sha_buffer_full)
                    sha_start_block = 1'b1;

                sha_words_in_block = RATE_WORDS;

                if (sha_busy && (send_words_left != 0) && !sha_buffer_full) begin
                    sha_block_word_valid = 1'b1;
                    sha_block_last       = 1'b0;
                end

                if (send_words_left == 0)
                    nstate = S_OUTER_INNER_LOAD;
            end

            // send inner_hash block (16 words), mark last
            S_OUTER_INNER_LOAD: begin
                nstate = S_OUTER_INNER_SEND;
            end

            S_OUTER_INNER_SEND: begin
                mode_block = 1'b1;

                if (!block_started && !sha_busy && !sha_buffer_full)
                    sha_start_block = 1'b1;

                sha_words_in_block = 6'd16;

                if (sha_busy && (send_words_left != 0) && !sha_buffer_full) begin
                    sha_block_word_valid = 1'b1;
                    if (send_words_left == 1)
                        sha_block_last = 1'b1;
                    else
                        sha_block_last = 1'b0;
                end

                if (send_words_left == 0)
                    nstate = S_OUTER_WAIT;
            end

            S_OUTER_WAIT: begin
                mode_block = 1'b1;
                if (sha_out_ready)
                    nstate = S_DONE;
            end

            S_DONE: begin
                done   = 1'b1;
                nstate = S_IDLE;
            end

            default: begin
                nstate = S_IDLE;
            end
        endcase
    end

endmodule
