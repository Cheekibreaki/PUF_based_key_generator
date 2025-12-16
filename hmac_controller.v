// -------------------------------------------------------
// hmac_controller.v
// Simplified: TAG = SHA3_512( (K^ipad) || message_stream )
// -------------------------------------------------------
module hmac_controller(
    input               clk,
    input               reset,

    input               start_puf,
    input               start_hmac,

    input      [703:0]  puf_input,

    // 32-bit message stream
    input      [31:0]   msg_word,
    input               msg_valid,
    input               msg_last,
    output reg          msg_ready,

    // results
    output reg [511:0]  puf_key_out,
    output reg [511:0]  hmac_out,
    output reg          done,

    // keccak_top control
    output reg          sha_init,
    output reg          mode_puf,
    output reg          mode_block,

    // PUF path
    output reg          start_puf_o,
    output reg [703:0]  puf_data_o,

    // block streaming path
    output reg          start_block_o,
    output reg [31:0]   block_word_o,
    output reg          block_word_valid_o,
    output reg          block_last_o,
    output reg [5:0]    words_in_block_o,

    // feedback from keccak_top
    input      [511:0]  sha_out,
    input               sha_out_ready,
    input               sha_busy,
    input               sha_buffer_full
);
    localparam RATE_WORDS = 18;

    // ipad constant (576-bit)
    wire [575:0] IPAD = {72{8'h36}};

    // pad key to 576
    wire [575:0] key_padded   = {puf_key_out, 64'b0};
    wire [575:0] key_xor_ipad = key_padded ^ IPAD;

    // sending buffer for ONE block (up to 18 words)
    reg  [575:0] send_buf;
    reg  [5:0]   send_words_left;
    reg          send_block_last;     // whether THIS block is last of whole message

    // message buffer (up to 18 words)
    reg  [575:0] msg_buf;
    reg  [5:0]   msg_count;
    reg          msg_buf_has_last;

    // one-shot start_block per block
    reg          blk_started;

    // states (plain Verilog)
    localparam S_IDLE          = 5'd0;

    localparam S_PUF_INIT      = 5'd1;
    localparam S_PUF_START     = 5'd2;
    localparam S_PUF_WAIT      = 5'd3;

    localparam S_MAC_INIT      = 5'd4;

    localparam S_IPAD_LOAD     = 5'd5;
    localparam S_IPAD_SEND     = 5'd6;

    localparam S_MSG_COLLECT   = 5'd7;
    localparam S_MSG_LOAD      = 5'd8;
    localparam S_MSG_SEND      = 5'd9;

    localparam S_MAC_WAIT      = 5'd10;

    localparam S_DONE          = 5'd31;

    reg [4:0] state, nstate;

    // accepted by keccak_top when it is busy and not full
    wire accept_word = (sha_busy && block_word_valid_o && !sha_buffer_full);

    // -------------------------------------------------------------------------
    // Sequential
    // -------------------------------------------------------------------------
    always @(posedge clk) begin
        if (reset) begin
            state <= S_IDLE;

            puf_key_out <= 0;
            hmac_out    <= 0;

            send_buf         <= 0;
            send_words_left  <= 0;
            send_block_last  <= 0;

            msg_buf          <= 0;
            msg_count        <= 0;
            msg_buf_has_last <= 0;

            blk_started <= 0;
        end else begin
            state <= nstate;

            // latch digests
            if (state == S_PUF_WAIT && sha_out_ready)
                puf_key_out <= sha_out;

            if (state == S_MAC_WAIT && sha_out_ready)
                hmac_out <= sha_out;

            // message collection
            if (state == S_MSG_COLLECT) begin
                if (msg_ready && msg_valid) begin
                    msg_buf[32*msg_count +: 32] <= msg_word;
                    msg_count <= msg_count + 1;
                    if (msg_last)
                        msg_buf_has_last <= 1'b1;
                end
            end

            // shift send buffer only when accepted
            if (accept_word) begin
                send_buf <= (send_buf >> 32);
                if (send_words_left != 0)
                    send_words_left <= send_words_left - 1;
            end

            // clear blk_started when entering a load state
            if (state != nstate) begin
                if (nstate == S_IPAD_LOAD || nstate == S_MSG_LOAD)
                    blk_started <= 1'b0;
            end
            if (start_block_o)
                blk_started <= 1'b1;

            // LOAD ipad block
            if (state == S_IPAD_LOAD) begin
                send_buf        <= key_xor_ipad;
                send_words_left <= RATE_WORDS; // 18
                send_block_last <= 1'b0;       // never last yet (msg follows)
            end

            // LOAD message chunk
            if (state == S_MSG_LOAD) begin
                send_buf        <= msg_buf;
                send_words_left <= msg_count;         // 1..18
                send_block_last <= msg_buf_has_last;  // last only if last seen in this chunk

                // clear msg buffer for next chunk
                msg_buf          <= 0;
                msg_count        <= 0;
                msg_buf_has_last <= 0;
            end
        end
    end

    // -------------------------------------------------------------------------
    // Combinational outputs + next state
    // -------------------------------------------------------------------------
    always @(*) begin
        nstate = state;

        done = 1'b0;

        // defaults
        sha_init = 1'b0;

        mode_puf   = 1'b0;
        mode_block = 1'b0;

        start_puf_o = 1'b0;
        puf_data_o  = puf_input;

        start_block_o       = 1'b0;
        block_word_o        = send_buf[31:0];
        block_word_valid_o  = 1'b0;
        block_last_o        = 1'b0;
        words_in_block_o    = RATE_WORDS;

        msg_ready = 1'b0;

        case (state)

            S_IDLE: begin
                if (start_puf)
                    nstate = S_PUF_INIT;
                else if (start_hmac)
                    nstate = S_MAC_INIT;
            end

            // -------------------------
            // PUF = SHA3(puf_input_704)
            // -------------------------
            S_PUF_INIT: begin
                sha_init = 1'b1;       // reset sponge for this message
                nstate   = S_PUF_START;
            end

            S_PUF_START: begin
                mode_puf   = 1'b1;
                start_puf_o= 1'b1;
                puf_data_o = puf_input;
                nstate     = S_PUF_WAIT;
            end

            S_PUF_WAIT: begin
                mode_puf = 1'b1;
                if (sha_out_ready)
                    nstate = S_DONE;
            end

            // -------------------------
            // MAC init: reset sponge, then send ipad block
            // -------------------------
            S_MAC_INIT: begin
                sha_init = 1'b1;
                nstate   = S_IPAD_LOAD;
            end

            S_IPAD_LOAD: begin
                nstate = S_IPAD_SEND;
            end

            S_IPAD_SEND: begin
                mode_block = 1'b1;

                // start block once
                if (!blk_started && !sha_busy && !sha_buffer_full)
                    start_block_o = 1'b1;

                words_in_block_o = RATE_WORDS;

                // push words only while sha_busy
                if (sha_busy && (send_words_left != 0) && !sha_buffer_full) begin
                    block_word_valid_o = 1'b1;
                    block_last_o       = 1'b0; // not last
                end

                if (send_words_left == 0)
                    nstate = S_MSG_COLLECT;
            end

            // -------------------------
            // Collect message words (buffer up to 18)
            // -------------------------
            S_MSG_COLLECT: begin
                msg_ready = (msg_count < RATE_WORDS);

                // if we have a full block, or we saw msg_last and have at least 1 word
                if ((msg_count == RATE_WORDS) || (msg_buf_has_last && (msg_count != 0)))
                    nstate = S_MSG_LOAD;
            end

            S_MSG_LOAD: begin
                nstate = S_MSG_SEND;
            end

            S_MSG_SEND: begin
                mode_block = 1'b1;

                if (!blk_started && !sha_busy && !sha_buffer_full)
                    start_block_o = 1'b1;

                words_in_block_o = send_words_left;

                if (sha_busy && (send_words_left != 0) && !sha_buffer_full) begin
                    block_word_valid_o = 1'b1;

                    // assert last only on final word of final message chunk
                    if ((send_words_left == 1) && send_block_last)
                        block_last_o = 1'b1;
                    else
                        block_last_o = 1'b0;
                end

                if (send_words_left == 0) begin
                    if (send_block_last)
                        nstate = S_MAC_WAIT;
                    else
                        nstate = S_MSG_COLLECT;
                end
            end

            S_MAC_WAIT: begin
                mode_block = 1'b1;
                if (sha_out_ready)
                    nstate = S_DONE;
            end

            S_DONE: begin
                done   = 1'b1;
                nstate = S_IDLE;
            end

            default: nstate = S_IDLE;

        endcase
    end

endmodule
