// -----------------------------------------------------------------------------
// keccak_top.v
// PUF mode (704-bit) and block mode (stream of 32-bit words)
// Adds hash_init: 1-cycle reset of sponge for starting a NEW message.
// -----------------------------------------------------------------------------
module keccak_top (
    input           clk,
    input           reset,

    // NEW: reset sponge for a NEW message (1-cycle pulse)
    input           sha_init,

    input           mode_puf,
    input           mode_block,

    // PUF input
    input           start_puf,
    input  [703:0]  data_in,

    // Block input
    input           start_block,
    input  [31:0]   block_word,
    input           block_word_valid,
    input           block_last,
    input  [5:0]    words_in_block,

    output          busy,
    output          buffer_full,
    output [511:0]  out,
    output          out_ready
);
    localparam TOTAL_BITS  = 704;
    localparam TOTAL_BYTES = TOTAL_BITS/8;
    localparam NUM_WORDS   = (TOTAL_BYTES + 3) / 4; // 22

    reg [703:0] puf_buffer;
    reg [5:0]   puf_words_left;

    reg [5:0]   blk_words_left;

    reg         busy_r;
    reg [31:0]  ke_in;
    reg         ke_in_ready;
    reg         ke_is_last;

    wire [1:0]  ke_byte_num = 2'b11;

    assign busy = busy_r;

    // IMPORTANT:
    // sha_init resets the sponge state for a fresh hash computation.
    keccak keccak_inst (
        .clk(clk),
        .reset(reset | sha_init),
        .in(ke_in),
        .in_ready(ke_in_ready),
        .is_last(ke_is_last),
        .byte_num(ke_byte_num),
        .buffer_full(buffer_full),
        .out(out),
        .out_ready(out_ready)
    );

    always @(posedge clk) begin
        if (reset | sha_init) begin
            puf_buffer     <= 0;
            puf_words_left <= 0;
            blk_words_left <= 0;

            ke_in       <= 0;
            ke_in_ready <= 0;
            ke_is_last  <= 0;

            busy_r      <= 0;
        end else begin
            ke_in_ready <= 0;
            ke_is_last  <= 0;

            // -------------------------
            // PUF MODE (704-bit)
            // -------------------------
            // Use else-if to prevent race condition between modes
            if (mode_puf && !mode_block) begin
                if (start_puf && !busy_r) begin
                    puf_buffer     <= data_in;
                    puf_words_left <= NUM_WORDS; // 22
                    busy_r         <= 1'b1;
                end

                if (busy_r && (puf_words_left != 0) && !buffer_full) begin
                    ke_in       <= puf_buffer[31:0];
                    ke_in_ready <= 1'b1;

                    if (puf_words_left == 1)
                        ke_is_last <= 1'b1;

                    puf_buffer     <= (puf_buffer >> 32);
                    puf_words_left <= puf_words_left - 1;

                    if (puf_words_left == 1)
                        busy_r <= 1'b0;
                end
            end
            // -------------------------
            // BLOCK MODE (stream)
            // -------------------------
            else if (mode_block && !mode_puf) begin
                if (start_block && !busy_r && !buffer_full) begin
                    blk_words_left <= words_in_block;
                    busy_r         <= 1'b1;
                end

                if (busy_r && block_word_valid && !buffer_full) begin
                    ke_in       <= block_word;
                    ke_in_ready <= 1'b1;

                    if (blk_words_left == 1)
                        ke_is_last <= block_last;

                    blk_words_left <= blk_words_left - 1;

                    if (blk_words_left == 1)
                        busy_r <= 1'b0;
                end
            end
        end
    end

endmodule
