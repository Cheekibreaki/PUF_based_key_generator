`timescale 1ns/1ps

// ============================================================================
// Testbench for secure_key_system with NEW PUF protocol
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

module secure_key_system_tb_new;

    // ========================================
    // Parameters
    // ========================================
    localparam PUF_BLOCKS = 2;
    localparam FE_BLOCKS = 22;
    localparam PUF_BITS = PUF_BLOCKS * 32;     // 64 bits
    localparam PUF_BYTES = PUF_BITS / 8;       // 8 bytes
    localparam TRNG_WIDTH = FE_BLOCKS * 6;     // 132 bits
    localparam HELPER_WIDTH = FE_BLOCKS * 32;  // 704 bits

    // ========================================
    // Signals
    // ========================================
    reg clk;
    reg reset;

    // Control
    reg start_keygen;

    // PUF interface - NEW PROTOCOL
    wire puf_clk;
    wire puf_enable;
    wire [$clog2(PUF_BYTES)-1:0] puf_addr;
    reg [7:0] puf_data;

    // TRNG interface - NEW PROTOCOL
    wire trng_clk;
    wire trng_enable;
    reg  trng_data;

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

    // PUF simulation memory
    reg [7:0] puf_memory [0:PUF_BYTES-1];
    integer puf_init_i;

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

        .puf_clk(puf_clk),
        .puf_enable(puf_enable),
        .puf_addr(puf_addr),
        .puf_data(puf_data),

        .trng_clk(trng_clk),
        .trng_enable(trng_enable),
        .trng_data(trng_data),

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
    // PUF Simulator - Responds to clocked read protocol
    // ========================================
    always @(posedge puf_clk) begin
        if (puf_enable) begin
            // On rising edge of puf_clk, provide data at current address
            if (puf_addr < PUF_BYTES) begin
                puf_data <= puf_memory[puf_addr];
            end else begin
                puf_data <= 8'h00;
            end
        end
    end

    // Initialize PUF memory with random values
    initial begin
        for (puf_init_i = 0; puf_init_i < PUF_BYTES; puf_init_i = puf_init_i + 1) begin
            puf_memory[puf_init_i] = $random & 8'hFF;
        end
    end

    // ========================================
    // TRNG Simulator - Responds to clocked read protocol
    // Returns 1 random bit per clock cycle
    // ========================================
    always @(posedge trng_clk) begin
        if (trng_enable) begin
            // On rising edge of trng_clk, provide random 1-bit data
            trng_data <= $random & 1'b1;
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
            puf_data = 8'b0;

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
                $display("  [INFO] PUF Key = %h", puf_key[127:0]);
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
                $display("  [INFO] HMAC = %h", hmac_value[127:0]);
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
        $display("  Secure Key System Testbench (NEW PUF)");
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
        $dumpfile("secure_key_system_tb_new.vcd");
        $dumpvars(0, secure_key_system_tb_new);
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
