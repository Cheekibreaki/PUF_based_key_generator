`timescale 1ns/1ps

module hmac_tb;

  reg clk, reset;
  reg start_puf, start_hmac;

  reg [703:0] puf_input;

  reg [31:0] msg_word;
  reg        msg_valid;
  reg        msg_last;
  wire       msg_ready;

  wire [511:0] puf_key;
  wire [511:0] hmac_value;
  wire         done;

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

  // 100 MHz
  initial begin clk = 1'b0; forever #5 clk = ~clk; end

  // one-cycle pulse
  task pulse(input is_puf);
    begin
      @(posedge clk);
      start_puf  <= is_puf;
      start_hmac <= ~is_puf;
      @(posedge clk);
      start_puf  <= 1'b0;
      start_hmac <= 1'b0;
    end
  endtask

  // wait done rising edge with timeout
  task wait_done_edge;
    integer cyc;
    reg done_d;
    begin
      done_d = done;
      for (cyc = 0; cyc < 500000; cyc = cyc + 1) begin
        @(posedge clk);
        if (done && !done_d) begin
          @(posedge clk); // let outputs settle
          disable wait_done_edge;
        end
        done_d = done;
      end
      $display("TIMEOUT: waited 500000 cycles for done pulse.");
      $stop;
    end
  endtask

  task send_word(input [31:0] w, input last);
    begin
      while (!msg_ready) @(posedge clk);
      msg_word  <= w;
      msg_valid <= 1'b1;
      msg_last  <= last;
      @(posedge clk);
      msg_valid <= 1'b0;
      msg_last  <= 1'b0;
      msg_word  <= 32'b0;
    end
  endtask

  initial begin
    // init
    reset = 1'b1;
    start_puf = 0;
    start_hmac = 0;

    puf_input = 0;
    msg_word  = 0;
    msg_valid = 0;
    msg_last  = 0;

    repeat (10) @(posedge clk);
    reset = 1'b0;

    // -------------------------
    // Test 1: PUF
    // -------------------------
    $display("\n=== Test Case 1: Generate PUF Key ===");
    puf_input = 704'h0123_4567_89AB_CDEF_0011_2233_4455_6677_8899_AABB_CCDD_EEFF_0123_4567_89AB_CDEF_0011_2233_4455_6677_8899_AABB_CCDD_EEFF_0123_4567_89AB_CDEF_0011_2233;

    pulse(1'b1);      // start_puf
    wait_done_edge();

    $display("PUF key  = %h", puf_key);

    // -------------------------
    // Test 2: MAC = SHA3( (K^ipad)||msg )
    // msg = 3 words
    // -------------------------
    $display("\n=== Test Case 2: MAC (3 words) ===");
    pulse(1'b0);      // start_hmac

    send_word(32'hDEADBEEF, 1'b0);
    send_word(32'hCAFEBABE, 1'b0);
    send_word(32'h00000011, 1'b1);

    wait_done_edge();

    $display("MAC      = %h", hmac_value);

    $display("\nAll tests finished.\n");
    $stop;
  end

endmodule
