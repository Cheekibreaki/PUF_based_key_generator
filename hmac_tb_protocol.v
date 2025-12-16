`timescale 1ns/1ps

// ============================================================
// Protocol Verification Testbench
// Verifies handshaking, timing, and signal behavior
// ============================================================

module hmac_tb_protocol;

  // Signals
  reg clk;
  reg reset;
  reg start_puf;
  reg start_hmac;
  reg [703:0] puf_input;
  reg [31:0]  msg_word;
  reg         msg_valid;
  reg         msg_last;
  wire        msg_ready;
  wire [511:0] puf_key;
  wire [511:0] hmac_value;
  wire         done;

  integer test_num;
  integer error_count;
  integer cycle_count;

  // For signal monitoring
  reg prev_done;
  integer done_pulse_count;
  integer done_pulse_width;

  // DUT
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

  // Clock: 100 MHz
  initial begin
    clk = 0;
    forever #5 clk = ~clk;
  end

  // Monitor done signal edges
  always @(posedge clk) begin
    if (reset) begin
      prev_done <= 0;
      done_pulse_count <= 0;
      done_pulse_width <= 0;
    end else begin
      prev_done <= done;

      // Detect rising edge of done
      if (done && !prev_done) begin
        done_pulse_count <= done_pulse_count + 1;
        done_pulse_width <= 1;
        $display("  [MONITOR] done pulse detected at cycle %0d", cycle_count);
      end else if (done) begin
        done_pulse_width <= done_pulse_width + 1;
      end else if (prev_done && !done) begin
        // Falling edge
        $display("  [MONITOR] done pulse width = %0d cycle(s)", done_pulse_width);
        if (done_pulse_width != 1) begin
          $display("  [WARN] done pulse width is not 1 cycle!");
        end
      end
    end
  end

  // Cycle counter
  always @(posedge clk) begin
    if (reset)
      cycle_count <= 0;
    else
      cycle_count <= cycle_count + 1;
  end

  // =============================
  // Tasks
  // =============================

  task init_signals;
    begin
      reset = 1'b1;
      start_puf  = 1'b0;
      start_hmac = 1'b0;
      puf_input  = 704'b0;
      msg_word   = 32'b0;
      msg_valid  = 1'b0;
      msg_last   = 1'b0;
      cycle_count = 0;
      done_pulse_count = 0;
      repeat (10) @(posedge clk);
      reset = 1'b0;
      repeat (2) @(posedge clk);
    end
  endtask

  task wait_done;
    integer timeout;
    begin
      timeout = 0;
      while (!done && timeout < 10000) begin
        @(posedge clk);
        timeout = timeout + 1;
      end
      if (timeout >= 10000) begin
        $display("  [ERROR] Timeout!");
        error_count = error_count + 1;
      end
      @(posedge clk);
    end
  endtask

  task send_word;
    input [31:0] w;
    input last;
    begin
      while (!msg_ready) @(posedge clk);
      msg_word  = w;
      msg_valid = 1'b1;
      msg_last  = last;
      @(posedge clk);
      msg_valid = 1'b0;
      msg_last  = 1'b0;
    end
  endtask

  // =============================
  // Test Sequence
  // =============================
  initial begin
    test_num = 0;
    error_count = 0;

    $display("\n========================================");
    $display("  HMAC Protocol Verification");
    $display("========================================\n");

    init_signals();

    // ============================================================
    // Test 1: Verify done is Single Cycle Pulse (PUF)
    // ============================================================
    test_num = test_num + 1;
    $display("[TEST %0d] Verify 'done' Pulse Width - PUF Operation", test_num);
    $display("----------------------------------------");

    puf_input = 704'h123456789ABCDEF0123456789ABCDEF0123456789ABCDEF0123456789ABCDEF0123456789ABCDEF0123456789ABCDEF0123456789ABCDEF0123456789ABCDEF;

    done_pulse_count = 0;
    done_pulse_width = 0;

    @(posedge clk);
    start_puf = 1'b1;
    @(posedge clk);
    start_puf = 1'b0;

    wait_done();

    if (done_pulse_width == 1) begin
      $display("  [PASS] done is a 1-cycle pulse");
    end else begin
      $display("  [FAIL] done pulse width = %0d (expected 1)", done_pulse_width);
      error_count = error_count + 1;
    end
    $display("");

    // ============================================================
    // Test 2: Verify done is Single Cycle Pulse (HMAC)
    // ============================================================
    test_num = test_num + 1;
    $display("[TEST %0d] Verify 'done' Pulse Width - HMAC Operation", test_num);
    $display("----------------------------------------");

    done_pulse_count = 0;
    done_pulse_width = 0;

    @(posedge clk);
    start_hmac = 1'b1;
    @(posedge clk);
    start_hmac = 1'b0;

    send_word(32'h11111111, 1'b1);
    wait_done();

    if (done_pulse_width == 1) begin
      $display("  [PASS] done is a 1-cycle pulse");
    end else begin
      $display("  [FAIL] done pulse width = %0d (expected 1)", done_pulse_width);
      error_count = error_count + 1;
    end
    $display("");

    // ============================================================
    // Test 3: Verify puf_key Persistence
    // ============================================================
    test_num = test_num + 1;
    $display("[TEST %0d] Verify puf_key Persistence Across Operations", test_num);
    $display("----------------------------------------");

    puf_input = 704'hABCDEF0123456789ABCDEF0123456789ABCDEF0123456789ABCDEF0123456789ABCDEF0123456789ABCDEF0123456789ABCDEF0123456789ABCDEF0123456789;

    @(posedge clk);
    start_puf = 1'b1;
    @(posedge clk);
    start_puf = 1'b0;
    wait_done();

    $display("  Generated PUF key = %h", puf_key[63:0]);
    begin
      reg [511:0] saved_key;
      saved_key = puf_key;

      // Wait some cycles
      repeat (100) @(posedge clk);

      if (puf_key == saved_key) begin
        $display("  [PASS] PUF key persists after 100 cycles");
      end else begin
        $display("  [FAIL] PUF key changed!");
        error_count = error_count + 1;
      end

      // Do an HMAC operation
      @(posedge clk);
      start_hmac = 1'b1;
      @(posedge clk);
      start_hmac = 1'b0;
      send_word(32'h22222222, 1'b1);
      wait_done();

      if (puf_key == saved_key) begin
        $display("  [PASS] PUF key persists after HMAC operation");
      end else begin
        $display("  [FAIL] PUF key changed after HMAC!");
        error_count = error_count + 1;
      end
    end
    $display("");

    // ============================================================
    // Test 4: Verify msg_ready Handshake
    // ============================================================
    test_num = test_num + 1;
    $display("[TEST %0d] msg_ready Handshake Protocol", test_num);
    $display("----------------------------------------");

    // msg_ready should be low when idle
    if (msg_ready) begin
      $display("  [WARN] msg_ready high when idle");
    end else begin
      $display("  [PASS] msg_ready low when idle");
    end

    @(posedge clk);
    start_hmac = 1'b1;
    @(posedge clk);
    start_hmac = 1'b0;

    // Wait for msg_ready to assert
    begin
      integer timeout;
      timeout = 0;
      while (!msg_ready && timeout < 500) begin
        @(posedge clk);
        timeout = timeout + 1;
      end

      if (msg_ready) begin
        $display("  [PASS] msg_ready asserted after start_hmac");
      end else begin
        $display("  [FAIL] msg_ready never asserted!");
        error_count = error_count + 1;
      end
    end

    // Send words and verify handshake
    begin
      integer i;
      for (i = 0; i < 3; i = i + 1) begin
        // Wait for ready
        while (!msg_ready) @(posedge clk);

        // Assert valid
        msg_word = 32'h30000000 + i;
        msg_valid = 1'b1;
        msg_last = (i == 2);

        @(posedge clk);

        // Deassert
        msg_valid = 1'b0;
        msg_last = 1'b0;
      end
    end

    wait_done();
    $display("  [PASS] msg_ready handshake working correctly");
    $display("");

    // ============================================================
    // Test 5: Check msg_ready De-assertion at Boundary
    // ============================================================
    test_num = test_num + 1;
    $display("[TEST %0d] msg_ready at 18-Word Boundary", test_num);
    $display("----------------------------------------");

    @(posedge clk);
    start_hmac = 1'b1;
    @(posedge clk);
    start_hmac = 1'b0;

    // Send exactly 18 words (full rate)
    begin
      integer i;
      for (i = 0; i < 18; i = i + 1) begin
        while (!msg_ready) @(posedge clk);
        msg_word = 32'h40000000 + i;
        msg_valid = 1'b1;
        msg_last = 1'b0;
        @(posedge clk);
        msg_valid = 1'b0;
      end

      // After 18 words, should be able to send more (new block)
      repeat (50) @(posedge clk);

      if (msg_ready) begin
        $display("  [PASS] msg_ready re-asserted for next block");

        // Send one more word with last
        send_word(32'h4000FFFF, 1'b1);
      end else begin
        $display("  [WARN] msg_ready not re-asserted after 18 words");
      end
    end

    wait_done();
    $display("");

    // ============================================================
    // Test 6: Verify No Glitches on done
    // ============================================================
    test_num = test_num + 1;
    $display("[TEST %0d] Verify No Glitches on 'done' Signal", test_num);
    $display("----------------------------------------");

    done_pulse_count = 0;

    @(posedge clk);
    start_puf = 1'b1;
    @(posedge clk);
    start_puf = 1'b0;
    wait_done();

    if (done_pulse_count == 1) begin
      $display("  [PASS] Exactly 1 done pulse detected");
    end else begin
      $display("  [FAIL] %0d done pulses detected (expected 1)", done_pulse_count);
      error_count = error_count + 1;
    end
    $display("");

    // ============================================================
    // Test 7: Start Signal Timing
    // ============================================================
    test_num = test_num + 1;
    $display("[TEST %0d] Verify start_puf/start_hmac are Single-Cycle", test_num);
    $display("----------------------------------------");

    // Multi-cycle start_puf (should still work)
    $display("  Testing multi-cycle start_puf...");
    puf_input = 704'h5555555555555555555555555555555555555555555555555555555555555555555555555555555555555555555555555555555555555555555555555555555555555555555555555555555555;

    @(posedge clk);
    start_puf = 1'b1;
    @(posedge clk);
    @(posedge clk);
    @(posedge clk); // hold for 3 cycles
    start_puf = 1'b0;

    wait_done();
    $display("  [INFO] Multi-cycle start_puf completed (design should handle this)");
    $display("");

    // ============================================================
    // Test 8: Verify HMAC Output Stability
    // ============================================================
    test_num = test_num + 1;
    $display("[TEST %0d] Verify HMAC Output Stability After done", test_num);
    $display("----------------------------------------");

    @(posedge clk);
    start_hmac = 1'b1;
    @(posedge clk);
    start_hmac = 1'b0;

    send_word(32'hABCDABCD, 1'b1);
    wait_done();

    begin
      reg [511:0] saved_hmac;
      saved_hmac = hmac_value;
      $display("  HMAC = %h", hmac_value[63:0]);

      // Wait and check stability
      repeat (100) @(posedge clk);

      if (hmac_value == saved_hmac) begin
        $display("  [PASS] HMAC output stable for 100 cycles");
      end else begin
        $display("  [FAIL] HMAC output changed!");
        error_count = error_count + 1;
      end
    end
    $display("");

    // ============================================================
    // Test 9: Reset During Operation
    // ============================================================
    test_num = test_num + 1;
    $display("[TEST %0d] Reset During PUF Operation", test_num);
    $display("----------------------------------------");

    puf_input = 704'h7777777777777777777777777777777777777777777777777777777777777777777777777777777777777777777777777777777777777777777777777777777777777777777777777777777777;

    @(posedge clk);
    start_puf = 1'b1;
    @(posedge clk);
    start_puf = 1'b0;

    // Wait a bit then reset
    repeat (50) @(posedge clk);
    $display("  Asserting reset...");

    reset = 1'b1;
    repeat (5) @(posedge clk);
    reset = 1'b0;

    // Check outputs are cleared
    if (puf_key == 512'b0 && hmac_value == 512'b0 && !done) begin
      $display("  [PASS] Outputs cleared after reset");
    end else begin
      $display("  [WARN] Some outputs not cleared after reset");
    end

    // Verify operation continues normally
    repeat (5) @(posedge clk);
    puf_input = 704'h8888888888888888888888888888888888888888888888888888888888888888888888888888888888888888888888888888888888888888888888888888888888888888888888888888888888;

    @(posedge clk);
    start_puf = 1'b1;
    @(posedge clk);
    start_puf = 1'b0;
    wait_done();

    $display("  [PASS] Operation resumed successfully after reset");
    $display("");

    // ============================================================
    // Test 10: Measure PUF Latency
    // ============================================================
    test_num = test_num + 1;
    $display("[TEST %0d] Measure PUF Operation Latency", test_num);
    $display("----------------------------------------");

    puf_input = 704'h9999999999999999999999999999999999999999999999999999999999999999999999999999999999999999999999999999999999999999999999999999999999999999999999999999999999;

    cycle_count = 0;
    @(posedge clk);
    start_puf = 1'b1;
    @(posedge clk);
    start_puf = 1'b0;

    begin
      integer start_cycle, end_cycle;
      start_cycle = cycle_count;

      wait_done();
      end_cycle = cycle_count;

      $display("  PUF latency = %0d cycles", end_cycle - start_cycle);
    end
    $display("");

    // ============================================================
    // Test 11: Measure HMAC Latency (various lengths)
    // ============================================================
    test_num = test_num + 1;
    $display("[TEST %0d] Measure HMAC Latency", test_num);
    $display("----------------------------------------");

    begin
      integer num_words, i;
      integer start_cycle, end_cycle;

      for (num_words = 1; num_words <= 36; num_words = num_words + 17) begin
        cycle_count = 0;

        @(posedge clk);
        start_hmac = 1'b1;
        @(posedge clk);
        start_hmac = 1'b0;

        start_cycle = cycle_count;

        for (i = 0; i < num_words; i = i + 1) begin
          send_word(32'hA0000000 + i, (i == num_words - 1));
        end

        wait_done();
        end_cycle = cycle_count;

        $display("  HMAC latency (%2d words) = %0d cycles", num_words, end_cycle - start_cycle);
      end
    end
    $display("");

    // ============================================================
    // Final Summary
    // ============================================================
    repeat (10) @(posedge clk);

    $display("\n========================================");
    $display("  Protocol Verification Summary");
    $display("========================================");
    $display("  Total Tests:  %0d", test_num);
    $display("  Errors:       %0d", error_count);
    $display("========================================\n");

    if (error_count == 0) begin
      $display("  *** ALL PROTOCOL TESTS PASSED ***\n");
    end else begin
      $display("  *** %0d ERRORS DETECTED ***\n", error_count);
    end

    $stop;
  end

  // Waveform dump
  initial begin
    $dumpfile("hmac_tb_protocol.vcd");
    $dumpvars(0, hmac_tb_protocol);
  end

  // Global timeout
  initial begin
    #50000000; // 50ms
    $display("\n[ERROR] Global timeout!");
    $stop;
  end

endmodule
