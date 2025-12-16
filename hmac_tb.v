`timescale 1ns/1ps

module hmac_tb;

  // clock/reset
  reg clk;
  reg reset;

  // control
  reg start_puf;
  reg start_hmac;

  // inputs
  reg [703:0] puf_input;

  reg [31:0]  msg_word;
  reg         msg_valid;
  reg         msg_last;
  wire        msg_ready;

  // outputs
  wire [511:0] puf_key;
  wire [511:0] hmac_value;
  wire         done;

  // -----------------------------
  // DUT
  // -----------------------------
  hmac_top dut (
    .clk(clk),
    .reset(reset),

    .start_puf(start_puf),
    .start_hmac(start_hmac),

    .puf_input(puf_input),

    .msg_word(msg_word),
    .msg_valid(msg_valid),
    .msg_last(msg_last),
    .msg_ready(msg_ready),

    .puf_key(puf_key),
    .hmac_value(hmac_value),
    .done(done)
  );

  // -----------------------------
  // Clock: 100 MHz
  // -----------------------------
  initial begin
    clk = 0;
    forever #5 clk = ~clk;
  end

  // -----------------------------
  // Tasks
  // -----------------------------
  task pulse_start_puf;
    begin
      start_puf  = 1'b1;
      start_hmac = 1'b0;
      @(posedge clk);
      start_puf  = 1'b0;
      start_hmac = 1'b0;
    end
  endtask

  task pulse_start_hmac;
    begin
      start_puf  = 1'b0;
      start_hmac = 1'b1;
      @(posedge clk);
      start_puf  = 1'b0;
      start_hmac = 1'b0;
    end
  endtask

  task wait_done;
    begin
      while (!done) @(posedge clk);
      // done may be a 1-cycle pulse; give one more cycle for stability
      @(posedge clk);
    end
  endtask

  task send_msg_word;
    input [31:0] w;
    input        last;
    begin
      // wait until controller is ready
      while (!msg_ready) @(posedge clk);

      msg_word  = w;
      msg_valid = 1'b1;
      msg_last  = last;

      @(posedge clk);

      // deassert
      msg_valid = 1'b0;
      msg_last  = 1'b0;
      msg_word  = 32'b0;
    end
  endtask

  // -----------------------------
  // Test sequence
  // -----------------------------
  initial begin
    // init
    reset      = 1'b1;
    start_puf  = 1'b0;
    start_hmac = 1'b0;

    puf_input  = 704'b0;

    msg_word   = 32'b0;
    msg_valid  = 1'b0;
    msg_last   = 1'b0;

    // release reset
    repeat (5) @(posedge clk);
    reset = 1'b0;

    // ============================================================
    // Test case 1: Generate PUF Key
    // ============================================================
    $display("\n===Test Case 1: Generate PUF Key ===");

    // Example 704-bit input
    puf_input = 704'h0123_4567_89AB_CDEF_0011_2233_4455_6677_8899_AABB_CCDD_EEFF_0123_4567_89AB_CDEF_0011_2233_4455_6677_8899_AABB_CCDD_EEFF_0123_4567_89AB_CDEF_0011_2233;

    pulse_start_puf();
    wait_done();

    $display("PUF key  = %h", puf_key);

    // ============================================================
    // Test case 2: HMAC with 3*32-bit message stream
    // ============================================================
    $display("\n=== Test Case 2: HMAC (3 words) ===");

    pulse_start_hmac();

    // send 3 words, last asserted on final word
    send_msg_word(32'hDEADBEEF, 1'b0);
    send_msg_word(32'hCAFEBABE, 1'b0);
    send_msg_word(32'h00000011, 1'b1);

    wait_done();

    $display("HMAC     = %h", hmac_value);

    $display("\nAll tests finished.\n");
    $stop;
  end

endmodule
