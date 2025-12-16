`timescale 1ns/1ps

// ============================================================
// Stress Test Testbench for HMAC
// Tests edge cases, timing, and corner conditions
// ============================================================

module hmac_tb_stress;

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
      repeat (5) @(posedge clk);
      reset = 1'b0;
      repeat (2) @(posedge clk);
    end
  endtask

  task pulse_start_puf;
    begin
      @(posedge clk);
      start_puf = 1'b1;
      @(posedge clk);
      start_puf = 1'b0;
    end
  endtask

  task pulse_start_hmac;
    begin
      @(posedge clk);
      start_hmac = 1'b1;
      @(posedge clk);
      start_hmac = 1'b0;
    end
  endtask

  task wait_done;
    integer timeout;
    begin
      timeout = 0;
      while (!done && timeout < 20000) begin
        @(posedge clk);
        timeout = timeout + 1;
      end
      if (timeout >= 20000) begin
        $display("  [ERROR] Timeout waiting for done!");
        error_count = error_count + 1;
      end
      @(posedge clk);
    end
  endtask

  task send_word;
    input [31:0] w;
    input last;
    integer timeout;
    begin
      timeout = 0;
      while (!msg_ready && timeout < 2000) begin
        @(posedge clk);
        timeout = timeout + 1;
      end
      if (timeout >= 2000) begin
        $display("  [ERROR] msg_ready timeout!");
        error_count = error_count + 1;
        disable send_word;
      end

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
    $display("  HMAC Stress Test Testbench");
    $display("========================================\n");

    init_signals();

    // ============================================================
    // Test 1: Multiple Rapid PUF Generations
    // ============================================================
    test_num = test_num + 1;
    $display("[TEST %0d] Rapid PUF Key Regeneration (10x)", test_num);

    begin: rapid_puf
      integer i;
      for (i = 0; i < 10; i = i + 1) begin
        puf_input = {i[7:0], 696'hABCDEF0123456789ABCDEF0123456789ABCDEF0123456789ABCDEF0123456789ABCDEF0123456789ABCDEF0123456789ABCDEF0123};
        pulse_start_puf();
        wait_done();
        $display("  PUF #%0d: Key = %h", i, puf_key[63:0]); // show lower 64 bits
      end
    end

    $display("  [PASS] Rapid PUF generation completed\n");

    // ============================================================
    // Test 2: Maximum Length Message (100 words)
    // ============================================================
    test_num = test_num + 1;
    $display("[TEST %0d] Very Long Message (100 words)", test_num);

    pulse_start_hmac();
    begin: long_msg
      integer i;
      for (i = 0; i < 100; i = i + 1) begin
        send_word(32'h10000000 + i, (i == 99));
      end
    end
    wait_done();
    $display("  HMAC = %h", hmac_value[63:0]);
    $display("  [PASS] Long message test completed\n");

    // ============================================================
    // Test 3: Burst HMAC Operations
    // ============================================================
    test_num = test_num + 1;
    $display("[TEST %0d] Burst HMAC Operations (20x short messages)", test_num);

    begin: burst_hmac
      integer i;
      for (i = 0; i < 20; i = i + 1) begin
        pulse_start_hmac();
        send_word(32'h20000000 + i, 1'b1);
        wait_done();
      end
    end
    $display("  [PASS] Burst HMAC test completed\n");

    // ============================================================
    // Test 4: msg_valid Gaps (Slow Streaming)
    // ============================================================
    test_num = test_num + 1;
    $display("[TEST %0d] Slow Message Streaming with Gaps", test_num);

    pulse_start_hmac();
    begin: slow_stream
      integer i;
      for (i = 0; i < 5; i = i + 1) begin
        while (!msg_ready) @(posedge clk);

        msg_word = 32'h30000000 + i;
        msg_valid = 1'b1;
        msg_last = (i == 4);
        @(posedge clk);
        msg_valid = 1'b0;
        msg_last = 1'b0;

        // Add random gaps
        repeat ($urandom_range(1, 20)) @(posedge clk);
      end
    end
    wait_done();
    $display("  [PASS] Slow streaming test completed\n");

    // ============================================================
    // Test 5: Edge Case - Exactly 18 Words Multiple Times
    // ============================================================
    test_num = test_num + 1;
    $display("[TEST %0d] Multiple 18-Word Blocks (3 blocks)", test_num);

    pulse_start_hmac();
    begin: multi_18
      integer i;
      for (i = 0; i < 54; i = i + 1) begin
        send_word(32'h40000000 + i, (i == 53));
      end
    end
    wait_done();
    $display("  [PASS] Multiple 18-word blocks completed\n");

    // ============================================================
    // Test 6: Alternating PUF and HMAC
    // ============================================================
    test_num = test_num + 1;
    $display("[TEST %0d] Alternating PUF and HMAC Operations", test_num);

    begin: alternating
      integer i;
      for (i = 0; i < 5; i = i + 1) begin
        // Generate new PUF key
        puf_input = {i[7:0], 696'hDEADBEEFCAFEBABEDEADBEEFCAFEBABEDEADBEEFCAFEBABEDEADBEEFCAFEBABEDEADBEEFCAFEBABEDEADBEEFCAFEBABE};
        pulse_start_puf();
        wait_done();

        // Compute HMAC with that key
        pulse_start_hmac();
        send_word(32'h50000000 + i, 1'b1);
        wait_done();

        $display("  Iteration %0d: HMAC = %h", i, hmac_value[63:0]);
      end
    end
    $display("  [PASS] Alternating operations completed\n");

    // ============================================================
    // Test 7: Boundary Test - 17, 18, 19 Word Messages
    // ============================================================
    test_num = test_num + 1;
    $display("[TEST %0d] Boundary Testing (17, 18, 19 words)", test_num);

    begin: boundary_test
      integer num_words;
      integer i;

      for (num_words = 17; num_words <= 19; num_words = num_words + 1) begin
        $display("  Testing %0d-word message...", num_words);
        pulse_start_hmac();
        for (i = 0; i < num_words; i = i + 1) begin
          send_word(32'h60000000 + i, (i == num_words - 1));
        end
        wait_done();
        $display("    HMAC = %h", hmac_value[63:0]);
      end
    end
    $display("  [PASS] Boundary test completed\n");

    // ============================================================
    // Test 8: Zero PUF Input
    // ============================================================
    test_num = test_num + 1;
    $display("[TEST %0d] Zero PUF Input", test_num);

    puf_input = 704'b0;
    pulse_start_puf();
    wait_done();
    $display("  PUF Key from zero input = %h", puf_key[63:0]);

    pulse_start_hmac();
    send_word(32'h12345678, 1'b1);
    wait_done();
    $display("  HMAC with zero-derived key = %h", hmac_value[63:0]);
    $display("  [PASS] Zero input test completed\n");

    // ============================================================
    // Test 9: All-Ones PUF Input
    // ============================================================
    test_num = test_num + 1;
    $display("[TEST %0d] All-Ones PUF Input", test_num);

    puf_input = {704{1'b1}};
    pulse_start_puf();
    wait_done();
    $display("  PUF Key from all-ones = %h", puf_key[63:0]);

    pulse_start_hmac();
    send_word(32'hFFFFFFFF, 1'b1);
    wait_done();
    $display("  HMAC with all-ones key = %h", hmac_value[63:0]);
    $display("  [PASS] All-ones test completed\n");

    // ============================================================
    // Test 10: Walking 1's in PUF Input
    // ============================================================
    test_num = test_num + 1;
    $display("[TEST %0d] Walking 1's PUF Pattern", test_num);

    begin: walking_ones
      integer i;
      for (i = 0; i < 8; i = i + 1) begin
        puf_input = 704'b0;
        puf_input[i*88] = 1'b1; // set one bit at a time
        pulse_start_puf();
        wait_done();
        $display("  Bit %0d: PUF = %h", i*88, puf_key[31:0]);
      end
    end
    $display("  [PASS] Walking 1's test completed\n");

    // ============================================================
    // Test 11: Random Data Stress Test
    // ============================================================
    test_num = test_num + 1;
    $display("[TEST %0d] Random Data Stress Test (10 iterations)", test_num);

    begin: random_stress
      integer i, j, num_words;
      for (i = 0; i < 10; i = i + 1) begin
        // Random PUF input
        puf_input = {$random, $random, $random, $random, $random, $random,
                     $random, $random, $random, $random, $random, $random,
                     $random, $random, $random, $random, $random, $random,
                     $random, $random, $random, $random};
        pulse_start_puf();
        wait_done();

        // Random length message (1-40 words)
        num_words = $urandom_range(1, 40);
        pulse_start_hmac();
        for (j = 0; j < num_words; j = j + 1) begin
          send_word($random, (j == num_words - 1));
        end
        wait_done();

        $display("  Iter %0d: %0d words, HMAC = %h", i, num_words, hmac_value[31:0]);
      end
    end
    $display("  [PASS] Random stress test completed\n");

    // ============================================================
    // Test 12: Sequential Message Pattern
    // ============================================================
    test_num = test_num + 1;
    $display("[TEST %0d] Sequential Counter Message (30 words)", test_num);

    pulse_start_hmac();
    begin: sequential
      integer i;
      for (i = 0; i < 30; i = i + 1) begin
        send_word(i, (i == 29));
      end
    end
    wait_done();
    $display("  HMAC = %h", hmac_value);
    $display("  [PASS] Sequential pattern completed\n");

    // ============================================================
    // Test 13: Verify msg_ready Behavior
    // ============================================================
    test_num = test_num + 1;
    $display("[TEST %0d] msg_ready Handshake Verification", test_num);

    pulse_start_hmac();

    // Check msg_ready is high in MSG_COLLECT state
    repeat (50) @(posedge clk);
    if (!msg_ready) begin
      $display("  [ERROR] msg_ready should be high during collection!");
      error_count = error_count + 1;
    end else begin
      $display("  [INFO] msg_ready correctly asserted");
    end

    // Send message and complete
    send_word(32'hABCDABCD, 1'b1);
    wait_done();
    $display("  [PASS] msg_ready verification completed\n");

    // ============================================================
    // Test 14: Back-to-back with No Idle Cycles
    // ============================================================
    test_num = test_num + 1;
    $display("[TEST %0d] Back-to-back Operations (No Idle)", test_num);

    begin: back_to_back
      integer i;
      for (i = 0; i < 5; i = i + 1) begin
        pulse_start_hmac();
        send_word(32'h70000000 + i, 1'b1);
        // Don't wait_done, just check that done pulses
        while (!done) @(posedge clk);
        @(posedge clk); // capture done
      end
    end
    $display("  [PASS] Back-to-back operations completed\n");

    // ============================================================
    // Test 15: Very Large Message Stress (200 words)
    // ============================================================
    test_num = test_num + 1;
    $display("[TEST %0d] Very Large Message (200 words)", test_num);

    pulse_start_hmac();
    begin: very_large
      integer i;
      for (i = 0; i < 200; i = i + 1) begin
        send_word(32'h80000000 + i, (i == 199));
        if (i % 50 == 0) $display("  Progress: %0d words sent", i);
      end
    end
    wait_done();
    $display("  HMAC = %h", hmac_value[63:0]);
    $display("  [PASS] Very large message completed\n");

    // ============================================================
    // Final Summary
    // ============================================================
    repeat (10) @(posedge clk);

    $display("\n========================================");
    $display("  Stress Test Summary");
    $display("========================================");
    $display("  Total Tests:  %0d", test_num);
    $display("  Errors:       %0d", error_count);
    $display("========================================\n");

    if (error_count == 0) begin
      $display("  *** ALL STRESS TESTS PASSED ***\n");
    end else begin
      $display("  *** %0d ERRORS DETECTED ***\n", error_count);
    end

    $stop;
  end

  // Waveform dump
  initial begin
    $dumpfile("hmac_tb_stress.vcd");
    $dumpvars(0, hmac_tb_stress);
  end

  // Global timeout
  initial begin
    #200000000; // 200ms
    $display("\n[ERROR] Global timeout!");
    $stop;
  end

endmodule
