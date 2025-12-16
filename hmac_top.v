// -------------------------------------------------------
// hmac_top.v
// Wrapper: hmac_controller + keccak_top
// -------------------------------------------------------
module hmac_top(
    input               clk,
    input               reset,

    input               start_puf,
    input               start_hmac,

    input      [703:0]  puf_input,

    input      [31:0]   msg_word,
    input               msg_valid,
    input               msg_last,
    output              msg_ready,

    output     [511:0]  puf_key,
    output     [511:0]  hmac_value,
    output              done
);

    wire sha_init;

    wire mode_puf, mode_block;

    wire start_puf_o;
    wire [703:0] puf_data_o;

    wire start_block_o;
    wire [31:0]  block_word_o;
    wire         block_word_valid_o;
    wire         block_last_o;
    wire [5:0]   words_in_block_o;

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

        .sha_init(sha_init),

        .mode_puf(mode_puf),
        .mode_block(mode_block),

        .start_puf_o(start_puf_o),
        .puf_data_o(puf_data_o),

        .start_block_o(start_block_o),
        .block_word_o(block_word_o),
        .block_word_valid_o(block_word_valid_o),
        .block_last_o(block_last_o),
        .words_in_block_o(words_in_block_o),

        .sha_out(sha_out),
        .sha_out_ready(sha_out_ready),
        .sha_busy(sha_busy),
        .sha_buffer_full(sha_buffer_full)
    );

    keccak_top u_sha3(
        .clk(clk),
        .reset(reset),

        .sha_init(sha_init),

        .mode_puf(mode_puf),
        .mode_block(mode_block),

        .start_puf(start_puf_o),
        .data_in(puf_data_o),

        .start_block(start_block_o),
        .block_word(block_word_o),
        .block_word_valid(block_word_valid_o),
        .block_last(block_last_o),
        .words_in_block(words_in_block_o),

        .busy(sha_busy),
        .buffer_full(sha_buffer_full),
        .out(sha_out),
        .out_ready(sha_out_ready)
    );

endmodule
