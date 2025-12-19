`timescale 1ns/1ps

// ============================================================================
// Testbench for keccak_top with HARDCODED test vectors
// Tests both PUF mode (704-bit) and Block mode (32-bit word stream)
// ============================================================================
module keccak_top_tb;

    // ========================================
    // Signals
    // ========================================
    reg         clk;
    reg         reset;
    reg         sha_init;

    // Mode selection
    reg         mode_puf;
    reg         mode_block;

    // PUF mode interface
    reg         start_puf;
    reg [703:0] data_in;

    // Block mode interface
    reg         start_block;
    reg [31:0]  block_word;
    reg         block_word_valid;
    reg         block_last;
    reg [5:0]   words_in_block;

    // Outputs
    wire        busy;
    wire        buffer_full;
    wire [511:0] out;
    wire        out_ready;

    // Test tracking
    integer test_num;
    integer pass_count;
    integer fail_count;

    // ========================================
    // DUT Instantiation
    // ========================================
    keccak_top dut (
        .clk(clk),
        .reset(reset),
        .sha_init(sha_init),
        .mode_puf(mode_puf),
        .mode_block(mode_block),
        .start_puf(start_puf),
        .data_in(data_in),
        .start_block(start_block),
        .block_word(block_word),
        .block_word_valid(block_word_valid),
        .block_last(block_last),
        .words_in_block(words_in_block),
        .busy(busy),
        .buffer_full(buffer_full),
        .out(out),
        .out_ready(out_ready)
    );

    // ========================================
    // Clock Generation: 100 MHz
    // ========================================
    initial begin
        clk = 0;
        forever #5 clk = ~clk;
    end

    // ========================================
    // Tasks
    // ========================================

    // Reset task
    task reset_system;
        begin
            reset = 1'b1;
            sha_init = 1'b0;
            mode_puf = 1'b0;
            mode_block = 1'b0;
            start_puf = 1'b0;
            data_in = 704'b0;
            start_block = 1'b0;
            block_word = 32'b0;
            block_word_valid = 1'b0;
            block_last = 1'b0;
            words_in_block = 6'b0;

            repeat(10) @(posedge clk);
            reset = 1'b0;
            repeat(2) @(posedge clk);
            $display("  [INFO] System reset completed");
        end
    endtask

    // Initialize hash (pulse sha_init)
    task init_hash;
        begin
            @(posedge clk);
            sha_init <= 1'b1;
            @(posedge clk);
            sha_init <= 1'b0;
            $display("  [INFO] SHA3 sponge initialized");
        end
    endtask

    // Test PUF mode
    task test_puf_mode;
        input [703:0] puf_data;
        integer timeout;
        begin
            $display("\n[TEST] PUF Mode: Hashing 704-bit data");

            // Initialize hash
            init_hash();

            // Start PUF mode
            @(posedge clk);
            mode_puf <= 1'b1;
            start_puf <= 1'b1;
            data_in <= puf_data;
            @(posedge clk);
            start_puf <= 1'b0;

            // Wait for completion
            timeout = 0;
            while (!out_ready && timeout < 5000) begin
                @(posedge clk);
                timeout = timeout + 1;
            end

            if (timeout >= 5000) begin
                $display("  [FAIL] Timeout waiting for PUF mode result");
                fail_count = fail_count + 1;
            end else begin
                $display("  [PASS] PUF mode completed in %0d cycles", timeout);
                $display("  [INFO] Output (512 bits):");
                $display("         %h", out);
                $display("         First 64 bits: %h", out[63:0]);
                pass_count = pass_count + 1;
            end

            // Cleanup
            @(posedge clk);
            mode_puf <= 1'b0;
            @(posedge clk);
        end
    endtask

    // Test Block mode
    task test_block_mode;
        input [31:0] word0, word1, word2, word3;
        input [5:0] num_words;
        integer timeout;
        integer i;
        begin
            $display("\n[TEST] Block Mode: Hashing %0d words", num_words);

            // Initialize hash
            init_hash();

            // Start block mode
            @(posedge clk);
            mode_block <= 1'b1;
            start_block <= 1'b1;
            words_in_block <= num_words;
            @(posedge clk);
            start_block <= 1'b0;

            // Send words
            if (num_words >= 1) begin
                while (buffer_full) @(posedge clk);
                block_word <= word0;
                block_word_valid <= 1'b1;
                block_last <= (num_words == 1) ? 1'b1 : 1'b0;
                @(posedge clk);
            end

            if (num_words >= 2) begin
                while (buffer_full) @(posedge clk);
                block_word <= word1;
                block_word_valid <= 1'b1;
                block_last <= (num_words == 2) ? 1'b1 : 1'b0;
                @(posedge clk);
            end

            if (num_words >= 3) begin
                while (buffer_full) @(posedge clk);
                block_word <= word2;
                block_word_valid <= 1'b1;
                block_last <= (num_words == 3) ? 1'b1 : 1'b0;
                @(posedge clk);
            end

            if (num_words >= 4) begin
                while (buffer_full) @(posedge clk);
                block_word <= word3;
                block_word_valid <= 1'b1;
                block_last <= 1'b1;
                @(posedge clk);
            end

            block_word_valid <= 1'b0;
            block_last <= 1'b0;

            // Wait for completion
            timeout = 0;
            while (!out_ready && timeout < 5000) begin
                @(posedge clk);
                timeout = timeout + 1;
            end

            if (timeout >= 5000) begin
                $display("  [FAIL] Timeout waiting for Block mode result");
                fail_count = fail_count + 1;
            end else begin
                $display("  [PASS] Block mode completed in %0d cycles", timeout);
                $display("  [INFO] Output (512 bits):");
                $display("         %h", out);
                $display("         First 64 bits: %h", out[63:0]);
                pass_count = pass_count + 1;
            end

            // Cleanup
            @(posedge clk);
            mode_block <= 1'b0;
            @(posedge clk);
        end
    endtask

    // ========================================
    // Test Sequence
    // ========================================
    initial begin
        $display("\n========================================");
        $display("  Keccak Top Testbench");
        $display("========================================\n");

        test_num = 0;
        pass_count = 0;
        fail_count = 0;

        // Reset
        reset_system();

        // ===========================================
        // Test 1: PUF Mode with hardcoded 704-bit data
        // ===========================================
        test_num = test_num + 1;
        $display("\n[TEST %0d] ===== PUF Mode Test =====", test_num);

        // Hardcoded 704-bit input (all 0xAA pattern)
        test_puf_mode(704'hAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAA);

        repeat(20) @(posedge clk);

        // ===========================================
        // Test 2: PUF Mode with different pattern
        // ===========================================
        test_num = test_num + 1;
        $display("\n[TEST %0d] ===== PUF Mode Test (Pattern 2) =====", test_num);

        // Hardcoded 704-bit input (0x0123456789ABCDEF pattern repeated)
        test_puf_mode(704'h0123456789ABCDEF0123456789ABCDEF0123456789ABCDEF0123456789ABCDEF0123456789ABCDEF0123456789ABCDEF0123456789ABCDEF0123456789ABCDEF0123456789ABCDEF0123456789ABCDEF0123456789ABCDEF0123456789ABCD);

        repeat(20) @(posedge clk);

        // ===========================================
        // Test 3: Block Mode with 2 words
        // ===========================================
        test_num = test_num + 1;
        $display("\n[TEST %0d] ===== Block Mode Test (2 words) =====", test_num);

        // Hardcoded message: [0xDEADBEEF, 0xCAFEBABE]
        test_block_mode(32'hDEADBEEF, 32'hCAFEBABE, 32'h0, 32'h0, 6'd2);

        repeat(20) @(posedge clk);

        // ===========================================
        // Test 4: Block Mode with 4 words
        // ===========================================
        test_num = test_num + 1;
        $display("\n[TEST %0d] ===== Block Mode Test (4 words) =====", test_num);

        // Hardcoded message: [0x01234567, 0x89ABCDEF, 0xFEDCBA98, 0x76543210]
        test_block_mode(32'h01234567, 32'h89ABCDEF, 32'hFEDCBA98, 32'h76543210, 6'd4);

        repeat(20) @(posedge clk);

        // ===========================================
        // Test 5: Block Mode with 1 word
        // ===========================================
        test_num = test_num + 1;
        $display("\n[TEST %0d] ===== Block Mode Test (1 word) =====", test_num);

        // Hardcoded message: [0x12345678]
        test_block_mode(32'h12345678, 32'h0, 32'h0, 32'h0, 6'd1);

        repeat(20) @(posedge clk);

        // ===========================================
        // Final Summary
        // ===========================================
        $display("\n========================================");
        $display("  Test Summary");
        $display("========================================");
        $display("  Total Tests: %0d", test_num);
        $display("  Passed:      %0d", pass_count);
        $display("  Failed:      %0d", fail_count);
        $display("========================================\n");

        if (fail_count == 0)
            $display("  ALL TESTS PASSED!");
        else
            $display("  SOME TESTS FAILED!");

        $display("\n");
        $finish;
    end

    // ========================================
    // Waveform Dump
    // ========================================
    initial begin
        $dumpfile("keccak_top_tb.vcd");
        $dumpvars(0, keccak_top_tb);
    end

    // ========================================
    // Timeout Watchdog
    // ========================================
    initial begin
        #500000; // 500us
        $display("\n[ERROR] Global timeout reached!");
        $finish;
    end

endmodule
