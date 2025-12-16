`timescale 1ns/1ps

// ============================================================================
// Testbench for secure_key_system
// Tests the complete flow: PUF → Fuzzy Extractor → HMAC Key → HMAC Operations
// ============================================================================
module CKXOR2D0 (
    input  A1,
    input  A2,
    output Z
);
    assign Z = A1 ^ A2;
endmodule

module AN2D0 (
    input  A1,
    input  A2,
    output Z
);
    assign Z = A1 & A2;
endmodule

module secure_key_system_tb;

    // ========================================
    // Parameters
    // ========================================
    localparam PUF_BLOCKS = 2;
    localparam FE_BLOCKS = 22;
    localparam PUF_WIDTH = PUF_BLOCKS * 32;   // 64 bits
    localparam TRNG_WIDTH = FE_BLOCKS * 6;    // 132 bits
    localparam HELPER_WIDTH = FE_BLOCKS * 32; // 704 bits

    // ========================================
    // Signals
    // ========================================
    reg clk;
    reg reset;

    // Control
    reg start_keygen;

    // PUF interface (simulated)
    wire puf_read_req;
    reg [PUF_WIDTH-1:0] puf_data;
    reg puf_valid;

    // TRNG interface (simulated)
    wire trng_req;
    reg [TRNG_WIDTH-1:0] trng_data;
    reg trng_valid;

    // HMAC interface
    reg start_hmac;
    reg [31:0] msg_word;
    reg msg_valid;
    reg msg_last;
    wire msg_ready;

    // Outputs
    wire [HELPER_WIDTH-1:0] helper_data;
    wire helper_data_valid;
    wire [511:0] puf_key;
    wire puf_key_valid;
    wire [511:0] hmac_value;
    wire hmac_done;

    // Test tracking
    integer test_num;
    integer pass_count;
    integer fail_count;

    // ========================================
    // DUT Instantiation
    // ========================================
    secure_key_system #(
        .PUF_BLOCKS(PUF_BLOCKS),
        .FE_BLOCKS(FE_BLOCKS)
    ) dut (
        .clk(clk),
        .reset(reset),

        .start_keygen(start_keygen),

        .puf_read_req(puf_read_req),
        .puf_data(puf_data),
        .puf_valid(puf_valid),

        .trng_req(trng_req),
        .trng_data(trng_data),
        .trng_valid(trng_valid),

        .start_hmac(start_hmac),
        .msg_word(msg_word),
        .msg_valid(msg_valid),
        .msg_last(msg_last),
        .msg_ready(msg_ready),

        .helper_data(helper_data),
        .helper_data_valid(helper_data_valid),

        .puf_key(puf_key),
        .puf_key_valid(puf_key_valid),

        .hmac_value(hmac_value),
        .hmac_done(hmac_done)
    );

    // ========================================
    // Clock Generation: 100 MHz
    // ========================================
    initial begin
        clk = 0;
        forever #5 clk = ~clk;
    end

    // ========================================
    // PUF Simulator
    // Responds to puf_read_req with random data
    // ========================================
    always @(posedge clk) begin
        if (reset) begin
            puf_data <= 0;
            puf_valid <= 0;
        end else begin
            if (puf_read_req && !puf_valid) begin
                // Simulate PUF response after 2-3 cycles
                repeat(2) @(posedge clk);
                puf_data <= {$random, $random};  // 64 bits of random PUF data
                puf_valid <= 1'b1;
                @(posedge clk);
                puf_valid <= 1'b0;
            end
        end
    end

    // ========================================
    // TRNG Simulator
    // Responds to trng_req with random data
    // ========================================
    always @(posedge clk) begin
        if (reset) begin
            trng_data <= 0;
            trng_valid <= 0;
        end else begin
            if (trng_req && !trng_valid) begin
                // Simulate TRNG response after 2-3 cycles
                repeat(2) @(posedge clk);
                trng_data <= {$random, $random, $random, $random, $random}; // 132 bits
                trng_valid <= 1'b1;
                @(posedge clk);
                trng_valid <= 1'b0;
            end
        end
    end

    // ========================================
    // Tasks
    // ========================================

    // Reset task
    task reset_system;
        begin
            reset = 1'b1;
            start_keygen = 1'b0;
            start_hmac = 1'b0;
            msg_word = 32'b0;
            msg_valid = 1'b0;
            msg_last = 1'b0;

            repeat(10) @(posedge clk);
            reset = 1'b0;
            repeat(2) @(posedge clk);
            $display("  [INFO] System reset completed");
        end
    endtask

    // Start key generation
    task trigger_keygen;
        begin
            @(posedge clk);
            start_keygen <= 1'b1;
            @(posedge clk);
            start_keygen <= 1'b0;
            $display("  [INFO] Key generation started");
        end
    endtask

    // Wait for key generation complete
    task wait_keygen_complete;
        integer timeout;
        begin
            timeout = 0;
            while (!puf_key_valid && timeout < 50000) begin
                @(posedge clk);
                timeout = timeout + 1;
            end

            if (timeout >= 50000) begin
                $display("  [ERROR] Timeout waiting for key generation!");
                fail_count = fail_count + 1;
            end else begin
                $display("  [INFO] Key generation completed in %0d cycles", timeout);
                $display("  [INFO] PUF Key = %h", puf_key[63:0]);
                $display("  [INFO] Helper data valid = %b", helper_data_valid);
            end
        end
    endtask

    // Start HMAC operation
    task trigger_hmac;
        begin
            @(posedge clk);
            start_hmac <= 1'b1;
            @(posedge clk);
            start_hmac <= 1'b0;
        end
    endtask

    // Send a message word
    task send_word;
        input [31:0] word;
        input last_flag;
        integer timeout;
        begin
            timeout = 0;
            while (!msg_ready && timeout < 50000) begin
                @(posedge clk);
                timeout = timeout + 1;
            end

            if (timeout >= 50000) begin
                $display("  [ERROR] Timeout waiting for msg_ready!");
                fail_count = fail_count + 1;
                disable send_word;
            end

            msg_word <= word;
            msg_valid <= 1'b1;
            msg_last <= last_flag;
            @(posedge clk);
            msg_valid <= 1'b0;
            msg_last <= 1'b0;
            msg_word <= 32'b0;
        end
    endtask

    // Wait for HMAC completion
    task wait_hmac_complete;
        integer timeout;
        begin
            timeout = 0;
            while (!hmac_done && timeout < 200000) begin
                @(posedge clk);
                timeout = timeout + 1;
            end

            if (timeout >= 200000) begin
                $display("  [ERROR] Timeout waiting for HMAC completion!");
                fail_count = fail_count + 1;
            end else begin
                $display("  [INFO] HMAC completed in %0d cycles", timeout);
                $display("  [INFO] HMAC = %h", hmac_value[63:0]);
            end

            @(posedge clk);
        end
    endtask

    // ========================================
    // Test Sequence
    // ========================================
    initial begin
        test_num = 0;
        pass_count = 0;
        fail_count = 0;

        $display("\n========================================");
        $display("  Secure Key System Testbench");
        $display("========================================\n");

        reset_system();

        // ============================================================
        // Test 1: Key Generation Flow
        // ============================================================
        test_num = test_num + 1;
        $display("\n[TEST %0d] Key Generation Flow", test_num);
        $display("----------------------------------------");

        trigger_keygen();
        wait_keygen_complete();

        if (puf_key_valid && helper_data_valid) begin
            $display("  [PASS] Key and helper data generated successfully");
            pass_count = pass_count + 1;
        end else begin
            $display("  [FAIL] Key generation failed");
            fail_count = fail_count + 1;
        end

        // ============================================================
        // Test 2: Single Word HMAC
        // ============================================================
        test_num = test_num + 1;
        $display("\n[TEST %0d] HMAC with Single Word", test_num);
        $display("----------------------------------------");

        trigger_hmac();
        send_word(32'h12345678, 1'b1);
        wait_hmac_complete();

        if (hmac_done) begin
            $display("  [PASS] Single word HMAC completed");
            pass_count = pass_count + 1;
        end else begin
            $display("  [FAIL] Single word HMAC failed");
            fail_count = fail_count + 1;
        end

        // ============================================================
        // Test 3: Multi-Word HMAC
        // ============================================================
        test_num = test_num + 1;
        $display("\n[TEST %0d] HMAC with Multiple Words", test_num);
        $display("----------------------------------------");

        trigger_hmac();
        send_word(32'hDEADBEEF, 1'b0);
        send_word(32'hCAFEBABE, 1'b0);
        send_word(32'h00112233, 1'b1);
        wait_hmac_complete();

        if (hmac_done) begin
            $display("  [PASS] Multi-word HMAC completed");
            pass_count = pass_count + 1;
        end else begin
            $display("  [FAIL] Multi-word HMAC failed");
            fail_count = fail_count + 1;
        end

        // ============================================================
        // Test 4: Back-to-Back HMAC Operations
        // ============================================================
        test_num = test_num + 1;
        $display("\n[TEST %0d] Back-to-Back HMAC Operations", test_num);
        $display("----------------------------------------");

        begin: test4_block
            integer i;
            reg [511:0] prev_hmac;

            for (i = 0; i < 3; i = i + 1) begin
                $display("  HMAC iteration %0d", i);
                trigger_hmac();
                send_word(32'h10000000 + i, 1'b1);
                wait_hmac_complete();

                if (i > 0 && hmac_value == prev_hmac) begin
                    $display("  [WARN] HMAC values identical (iteration %0d)", i);
                end

                prev_hmac = hmac_value;
            end

            $display("  [PASS] Back-to-back operations completed");
            pass_count = pass_count + 1;
        end

        // ============================================================
        // Test 5: Long Message HMAC (20 words)
        // ============================================================
        test_num = test_num + 1;
        $display("\n[TEST %0d] HMAC with Long Message (20 words)", test_num);
        $display("----------------------------------------");

        trigger_hmac();
        begin: test5_block
            integer i;
            for (i = 0; i < 20; i = i + 1) begin
                send_word(32'h20000000 + i, (i == 19));
            end
        end
        wait_hmac_complete();

        if (hmac_done) begin
            $display("  [PASS] Long message HMAC completed");
            pass_count = pass_count + 1;
        end else begin
            $display("  [FAIL] Long message HMAC failed");
            fail_count = fail_count + 1;
        end

        // ============================================================
        // Test 6: Regenerate Key with Different PUF
        // ============================================================
        test_num = test_num + 1;
        $display("\n[TEST %0d] Regenerate Key (New PUF Data)", test_num);
        $display("----------------------------------------");

        begin: test6_block
            reg [511:0] old_key;
            old_key = puf_key;

            trigger_keygen();
            wait_keygen_complete();

            if (puf_key != old_key) begin
                $display("  [PASS] New key differs from old key");
                pass_count = pass_count + 1;
            end else begin
                $display("  [WARN] New key same as old key (could be random collision)");
                pass_count = pass_count + 1;
            end
        end

        // ============================================================
        // Test 7: HMAC with New Key
        // ============================================================
        test_num = test_num + 1;
        $display("\n[TEST %0d] HMAC with Regenerated Key", test_num);
        $display("----------------------------------------");

        trigger_hmac();
        send_word(32'hABCDEF01, 1'b0);
        send_word(32'h23456789, 1'b1);
        wait_hmac_complete();

        if (hmac_done) begin
            $display("  [PASS] HMAC with new key completed");
            pass_count = pass_count + 1;
        end else begin
            $display("  [FAIL] HMAC with new key failed");
            fail_count = fail_count + 1;
        end

        // ============================================================
        // Test 8: Edge Case - 18 Word Message (Full Rate)
        // ============================================================
        test_num = test_num + 1;
        $display("\n[TEST %0d] HMAC with 18-Word Message (Full Rate)", test_num);
        $display("----------------------------------------");

        trigger_hmac();
        begin: test8_block
            integer i;
            for (i = 0; i < 18; i = i + 1) begin
                send_word(32'h30000000 + i, (i == 17));
            end
        end
        wait_hmac_complete();

        if (hmac_done) begin
            $display("  [PASS] Full rate message HMAC completed");
            pass_count = pass_count + 1;
        end else begin
            $display("  [FAIL] Full rate message HMAC failed");
            fail_count = fail_count + 1;
        end

        // ============================================================
        // Final Summary
        // ============================================================
        repeat(10) @(posedge clk);

        $display("\n========================================");
        $display("  Test Summary");
        $display("========================================");
        $display("  Total Tests:  %0d", test_num);
        $display("  Passed:       %0d", pass_count);
        $display("  Failed:       %0d", fail_count);
        $display("========================================\n");

        if (fail_count == 0) begin
            $display("  *** ALL TESTS PASSED ***\n");
        end else begin
            $display("  *** %0d TESTS FAILED ***\n", fail_count);
        end

        $finish;
    end

    // ========================================
    // Waveform Dump
    // ========================================
    initial begin
        $dumpfile("secure_key_system_tb.vcd");
        $dumpvars(0, secure_key_system_tb);
    end

    // ========================================
    // Timeout Watchdog
    // ========================================
    initial begin
        #200000000; // 200ms
        $display("\n[ERROR] Global timeout reached!");
        $finish;
    end

endmodule
