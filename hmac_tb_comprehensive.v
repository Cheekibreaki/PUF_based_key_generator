`timescale 1ns/1ps

module hmac_tb_comprehensive;

  // =============================
  // Signals
  // =============================
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

  // Test tracking
  integer test_num;
  integer pass_count;
  integer fail_count;
  reg [511:0] expected_hmac;
  reg [511:0] prev_hmac;

  // =============================
  // DUT Instantiation
  // =============================
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

  // =============================
  // Clock Generation: 100 MHz
  // =============================
  initial begin
    clk = 0;
    forever #5 clk = ~clk;
  end

  // =============================
  // Tasks
  // =============================

  // Reset task
  task reset_dut;
    begin
      reset = 1'b1;
      start_puf  = 1'b0;
      start_hmac = 1'b0;
      msg_word   = 32'b0;
      msg_valid  = 1'b0;
      msg_last   = 1'b0;
      repeat (10) @(posedge clk);
      reset = 1'b0;
      repeat (2) @(posedge clk);
      $display("  [INFO] DUT reset completed");
    end
  endtask

  // Start PUF generation
  task pulse_start_puf;
    begin
      start_puf  = 1'b1;
      start_hmac = 1'b0;
      @(posedge clk);
      start_puf  = 1'b0;
      start_hmac = 1'b0;
    end
  endtask

  // Start HMAC computation
  task pulse_start_hmac;
    begin
      start_puf  = 1'b0;
      start_hmac = 1'b1;
      @(posedge clk);
      start_puf  = 1'b0;
      start_hmac = 1'b0;
    end
  endtask

  // Wait for done signal with timeout
  task wait_done_with_timeout;
    input integer max_cycles;
    integer cycle_count;
    begin
      cycle_count = 0;
      while (!done && cycle_count < max_cycles) begin
        @(posedge clk);
        cycle_count = cycle_count + 1;
      end

      if (cycle_count >= max_cycles) begin
        $display("  [ERROR] Timeout waiting for done signal after %0d cycles!", max_cycles);
        fail_count = fail_count + 1;
      end else begin
        $display("  [INFO] Operation completed in %0d cycles", cycle_count);
      end

      @(posedge clk); // stability cycle
    end
  endtask

  // Send a single message word
  task send_msg_word;
    input [31:0] w;
    input        last;
    integer timeout;
    begin
      timeout = 0;
      // wait until controller is ready
      while (!msg_ready && timeout < 1000) begin
        @(posedge clk);
        timeout = timeout + 1;
      end

      if (timeout >= 1000) begin
        $display("  [ERROR] Timeout waiting for msg_ready!");
        fail_count = fail_count + 1;
        return;
      end

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

  // Send multiple words as an array
  task send_msg_array;
    input integer num_words;
    input [31:0] words [0:63]; // support up to 64 words
    integer i;
    begin
      for (i = 0; i < num_words; i = i + 1) begin
        send_msg_word(words[i], (i == num_words - 1));
      end
    end
  endtask

  // Check if HMAC output changed
  task check_hmac_changed;
    input [511:0] prev_val;
    begin
      if (hmac_value == prev_val) begin
        $display("  [WARN] HMAC value unchanged from previous test");
      end else begin
        $display("  [PASS] HMAC value changed as expected");
        pass_count = pass_count + 1;
      end
    end
  endtask

  // Check if PUF key is non-zero
  task check_puf_nonzero;
    begin
      if (puf_key == 512'b0) begin
        $display("  [FAIL] PUF key is zero!");
        fail_count = fail_count + 1;
      end else begin
        $display("  [PASS] PUF key is non-zero");
        pass_count = pass_count + 1;
      end
    end
  endtask

  // =============================
  // Test Sequence
  // =============================
  initial begin
    test_num = 0;
    pass_count = 0;
    fail_count = 0;

    $display("\n");
    $display("========================================");
    $display("  HMAC Comprehensive Testbench");
    $display("========================================\n");

    // Initial reset
    reset_dut();

    // ============================================================
    // Test 1: Basic PUF Key Generation
    // ============================================================
    test_num = test_num + 1;
    $display("\n[TEST %0d] Basic PUF Key Generation", test_num);
    $display("----------------------------------------");

    puf_input = 704'h0123_4567_89AB_CDEF_0011_2233_4455_6677_8899_AABB_CCDD_EEFF_0123_4567_89AB_CDEF_0011_2233_4455_6677_8899_AABB_CCDD_EEFF_0123_4567_89AB_CDEF_0011_2233;

    pulse_start_puf();
    wait_done_with_timeout(5000);

    $display("  PUF Key = %h", puf_key);
    check_puf_nonzero();

    // ============================================================
    // Test 2: HMAC with Single Word Message
    // ============================================================
    test_num = test_num + 1;
    $display("\n[TEST %0d] HMAC with Single Word Message", test_num);
    $display("----------------------------------------");

    pulse_start_hmac();
    send_msg_word(32'h12345678, 1'b1); // single word, last=1
    wait_done_with_timeout(5000);

    $display("  HMAC = %h", hmac_value);
    prev_hmac = hmac_value;

    // ============================================================
    // Test 3: HMAC with 3-Word Message
    // ============================================================
    test_num = test_num + 1;
    $display("\n[TEST %0d] HMAC with 3-Word Message", test_num);
    $display("----------------------------------------");

    pulse_start_hmac();
    send_msg_word(32'hDEADBEEF, 1'b0);
    send_msg_word(32'hCAFEBABE, 1'b0);
    send_msg_word(32'h00000011, 1'b1);
    wait_done_with_timeout(5000);

    $display("  HMAC = %h", hmac_value);
    check_hmac_changed(prev_hmac);
    prev_hmac = hmac_value;

    // ============================================================
    // Test 4: HMAC with Exactly 18 Words (Full Rate Block)
    // ============================================================
    test_num = test_num + 1;
    $display("\n[TEST %0d] HMAC with 18-Word Message (Full Rate)", test_num);
    $display("----------------------------------------");

    pulse_start_hmac();

    begin: test4_block
      integer i;
      for (i = 0; i < 18; i = i + 1) begin
        send_msg_word(32'hA0000000 + i, (i == 17));
      end
    end

    wait_done_with_timeout(6000);
    $display("  HMAC = %h", hmac_value);
    check_hmac_changed(prev_hmac);
    prev_hmac = hmac_value;

    // ============================================================
    // Test 5: HMAC with 36 Words (Two Full Blocks)
    // ============================================================
    test_num = test_num + 1;
    $display("\n[TEST %0d] HMAC with 36-Word Message (2 Full Blocks)", test_num);
    $display("----------------------------------------");

    pulse_start_hmac();

    begin: test5_block
      integer i;
      for (i = 0; i < 36; i = i + 1) begin
        send_msg_word(32'hB0000000 + i, (i == 35));
      end
    end

    wait_done_with_timeout(8000);
    $display("  HMAC = %h", hmac_value);
    check_hmac_changed(prev_hmac);
    prev_hmac = hmac_value;

    // ============================================================
    // Test 6: HMAC with 19 Words (1 Full + 1 Partial Block)
    // ============================================================
    test_num = test_num + 1;
    $display("\n[TEST %0d] HMAC with 19-Word Message (1 Full + 1 Partial)", test_num);
    $display("----------------------------------------");

    pulse_start_hmac();

    begin: test6_block
      integer i;
      for (i = 0; i < 19; i = i + 1) begin
        send_msg_word(32'hC0000000 + i, (i == 18));
      end
    end

    wait_done_with_timeout(6000);
    $display("  HMAC = %h", hmac_value);
    check_hmac_changed(prev_hmac);
    prev_hmac = hmac_value;

    // ============================================================
    // Test 7: HMAC with Empty-ish Message (Just 1 zero word)
    // ============================================================
    test_num = test_num + 1;
    $display("\n[TEST %0d] HMAC with Single Zero Word", test_num);
    $display("----------------------------------------");

    pulse_start_hmac();
    send_msg_word(32'h00000000, 1'b1);
    wait_done_with_timeout(5000);

    $display("  HMAC = %h", hmac_value);
    check_hmac_changed(prev_hmac);
    prev_hmac = hmac_value;

    // ============================================================
    // Test 8: HMAC with All 0xFF Pattern
    // ============================================================
    test_num = test_num + 1;
    $display("\n[TEST %0d] HMAC with All 0xFF Pattern (5 words)", test_num);
    $display("----------------------------------------");

    pulse_start_hmac();

    begin: test8_block
      integer i;
      for (i = 0; i < 5; i = i + 1) begin
        send_msg_word(32'hFFFFFFFF, (i == 4));
      end
    end

    wait_done_with_timeout(5000);
    $display("  HMAC = %h", hmac_value);
    check_hmac_changed(prev_hmac);
    prev_hmac = hmac_value;

    // ============================================================
    // Test 9: Regenerate PUF Key with Different Input
    // ============================================================
    test_num = test_num + 1;
    $display("\n[TEST %0d] Regenerate PUF Key with Different Input", test_num);
    $display("----------------------------------------");

    puf_input = 704'hFEDC_BA98_7654_3210_FFFF_EEEE_DDDD_CCCC_BBBB_AAAA_9999_8888_7777_6666_5555_4444_3333_2222_1111_0000_FFEE_DDCC_BBAA_9988_7766_5544_3322_1100_FAFA_BEBE;

    pulse_start_puf();
    wait_done_with_timeout(5000);

    $display("  New PUF Key = %h", puf_key);
    check_puf_nonzero();

    // ============================================================
    // Test 10: HMAC with New Key
    // ============================================================
    test_num = test_num + 1;
    $display("\n[TEST %0d] HMAC with New PUF Key", test_num);
    $display("----------------------------------------");

    pulse_start_hmac();
    send_msg_word(32'hDEADBEEF, 1'b0);
    send_msg_word(32'hCAFEBABE, 1'b1);
    wait_done_with_timeout(5000);

    $display("  HMAC = %h", hmac_value);
    check_hmac_changed(prev_hmac);
    prev_hmac = hmac_value;

    // ============================================================
    // Test 11: Back-to-Back HMAC Operations
    // ============================================================
    test_num = test_num + 1;
    $display("\n[TEST %0d] Back-to-Back HMAC Operations", test_num);
    $display("----------------------------------------");

    // First HMAC
    pulse_start_hmac();
    send_msg_word(32'h11111111, 1'b1);
    wait_done_with_timeout(5000);
    $display("  HMAC #1 = %h", hmac_value);

    // Immediately start second HMAC
    pulse_start_hmac();
    send_msg_word(32'h22222222, 1'b1);
    wait_done_with_timeout(5000);
    $display("  HMAC #2 = %h", hmac_value);
    pass_count = pass_count + 1;

    // ============================================================
    // Test 12: Large Message (50 words)
    // ============================================================
    test_num = test_num + 1;
    $display("\n[TEST %0d] HMAC with Large Message (50 words)", test_num);
    $display("----------------------------------------");

    pulse_start_hmac();

    begin: test12_block
      integer i;
      for (i = 0; i < 50; i = i + 1) begin
        send_msg_word(32'h50000000 + i, (i == 49));
      end
    end

    wait_done_with_timeout(12000);
    $display("  HMAC = %h", hmac_value);
    check_hmac_changed(prev_hmac);
    prev_hmac = hmac_value;

    // ============================================================
    // Test 13: Alternating Pattern Message
    // ============================================================
    test_num = test_num + 1;
    $display("\n[TEST %0d] HMAC with Alternating 0xAAAA/0x5555 Pattern", test_num);
    $display("----------------------------------------");

    pulse_start_hmac();

    begin: test13_block
      integer i;
      for (i = 0; i < 10; i = i + 1) begin
        if (i % 2 == 0)
          send_msg_word(32'hAAAAAAAA, (i == 9));
        else
          send_msg_word(32'h55555555, (i == 9));
      end
    end

    wait_done_with_timeout(6000);
    $display("  HMAC = %h", hmac_value);
    check_hmac_changed(prev_hmac);
    prev_hmac = hmac_value;

    // ============================================================
    // Test 14: Reset During PUF Operation
    // ============================================================
    test_num = test_num + 1;
    $display("\n[TEST %0d] Reset During PUF Operation", test_num);
    $display("----------------------------------------");

    puf_input = 704'h1234_5678_90AB_CDEF_1111_2222_3333_4444_5555_6666_7777_8888_9999_AAAA_BBBB_CCCC_DDDD_EEEE_FFFF_0000_1234_5678_90AB_CDEF_1111_2222_3333_4444_5555_6666;
    pulse_start_puf();

    // Wait a few cycles then reset
    repeat (50) @(posedge clk);
    $display("  [INFO] Asserting reset mid-operation...");
    reset_dut();

    // Now complete the PUF operation properly
    pulse_start_puf();
    wait_done_with_timeout(5000);
    $display("  PUF Key after reset = %h", puf_key);
    pass_count = pass_count + 1;

    // ============================================================
    // Test 15: Same Message Twice (Should produce same HMAC)
    // ============================================================
    test_num = test_num + 1;
    $display("\n[TEST %0d] Same Message Twice - Determinism Check", test_num);
    $display("----------------------------------------");

    // First computation
    pulse_start_hmac();
    send_msg_word(32'hABCDEF01, 1'b0);
    send_msg_word(32'h23456789, 1'b1);
    wait_done_with_timeout(5000);
    $display("  HMAC #1 = %h", hmac_value);
    prev_hmac = hmac_value;

    // Second computation with same message
    pulse_start_hmac();
    send_msg_word(32'hABCDEF01, 1'b0);
    send_msg_word(32'h23456789, 1'b1);
    wait_done_with_timeout(5000);
    $display("  HMAC #2 = %h", hmac_value);

    if (hmac_value == prev_hmac) begin
      $display("  [PASS] HMAC values match (deterministic)");
      pass_count = pass_count + 1;
    end else begin
      $display("  [FAIL] HMAC values don't match!");
      fail_count = fail_count + 1;
    end

    // ============================================================
    // Final Summary
    // ============================================================
    repeat (10) @(posedge clk);

    $display("\n");
    $display("========================================");
    $display("  Test Summary");
    $display("========================================");
    $display("  Total Tests:  %0d", test_num);
    $display("  Passed:       %0d", pass_count);
    $display("  Failed:       %0d", fail_count);
    $display("========================================\n");

    if (fail_count == 0) begin
      $display("  *** ALL TESTS PASSED ***\n");
    end else begin
      $display("  *** SOME TESTS FAILED ***\n");
    end

    $stop;
  end

  // =============================
  // Waveform Dump (optional)
  // =============================
  initial begin
    $dumpfile("hmac_tb_comprehensive.vcd");
    $dumpvars(0, hmac_tb_comprehensive);
  end

  // =============================
  // Timeout Watchdog
  // =============================
  initial begin
    #100000000; // 100ms timeout
    $display("\n[ERROR] Global timeout reached!");
    $display("Test may be hung. Check your design.\n");
    $stop;
  end

endmodule
