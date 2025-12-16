// -------------------------------------------------------
// hmac_top.v
// Wrapper: hmac_controller + keccak_top
// -------------------------------------------------------
module hmac_top(
    input               clk,
    input               reset,

    input               start_puf,
    input               start_hmac,

    input      [703:0]   puf_input,

    // 32-bit message stream into HMAC
    input      [31:0]    msg_word,
    input               msg_valid,
    input               msg_last,
    output              msg_ready,

    output     [511:0]   puf_key,
    output     [511:0]   hmac_value,
    output              done
);

    wire mode_puf, mode_block;

    wire        sha_start_puf;
    wire [703:0] sha_puf_data;

    wire        sha_start_block;
    wire [31:0] sha_block_word;
    wire        sha_block_word_valid;
    wire        sha_block_last;
    wire [5:0]  sha_words_in_block;

    wire [511:0] sha_out;
    wire         sha_out_ready;
    wire         sha_busy;
    wire         sha_buffer_full;

    hmac_controller u_ctrl(
        .clk(clk),
        .reset(reset),

        .start_puf(start_puf),
        .start_hmac(start_hmac),

        .puf_input(puf_input),

        .msg_word(msg_word),
        .msg_valid(msg_valid),
        .msg_last(msg_last),
        .msg_ready(msg_ready),

        .puf_key_out(puf_key),
        .hmac_out(hmac_value),
        .done(done),

        .mode_puf(mode_puf),
        .mode_block(mode_block),

        .sha_start_puf(sha_start_puf),
        .sha_puf_data(sha_puf_data),

        .sha_start_block(sha_start_block),
        .sha_block_word(sha_block_word),
        .sha_block_word_valid(sha_block_word_valid),
        .sha_block_last(sha_block_last),
        .sha_words_in_block(sha_words_in_block),

        .sha_out(sha_out),
        .sha_out_ready(sha_out_ready),
        .sha_busy(sha_busy),
        .sha_buffer_full(sha_buffer_full)
    );

    keccak_top u_sha3(
        .clk(clk),
        .reset(reset),

        .mode_puf(mode_puf),
        .mode_block(mode_block),

        .start_puf(sha_start_puf),
        .data_in(sha_puf_data),

        .start_block(sha_start_block),
        .block_word(sha_block_word),
        .block_word_valid(sha_block_word_valid),
        .block_last(sha_block_last),
        .words_in_block(sha_words_in_block),

        .busy(sha_busy),
        .buffer_full(sha_buffer_full),
        .out(sha_out),
        .out_ready(sha_out_ready)
    );

endmodule
