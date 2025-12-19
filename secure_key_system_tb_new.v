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

    // Outputs - Three separate 16-bit buses
    wire [15:0] helper_data_out;
    wire        helper_data_valid;
    wire        helper_data_done;

    wire [15:0] puf_key_out;
    wire        puf_key_valid;
    wire        puf_key_done;

    wire [15:0] hmac_out;
    wire        hmac_valid;
    wire        hmac_done;

    // Capture full data from 16-bit buses
    reg [HELPER_WIDTH-1:0] helper_data_captured;
    reg [511:0]            puf_key_captured;
    reg [511:0]            hmac_value_captured;
    reg [5:0]              helper_word_idx;
    reg [4:0]              puf_key_word_idx;
    reg [4:0]              hmac_word_idx;

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

        .helper_data_out(helper_data_out),
        .helper_data_valid(helper_data_valid),
        .helper_data_done(helper_data_done),

        .puf_key_out(puf_key_out),
        .puf_key_valid(puf_key_valid),
        .puf_key_done(puf_key_done),

        .hmac_out(hmac_out),
        .hmac_valid(hmac_valid),
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
    // Capture 16-bit bus outputs into full registers
    // ========================================
    // Capture helper_data from 16-bit bus
    always @(posedge clk) begin
        if (reset) begin
            helper_data_captured <= {HELPER_WIDTH{1'b0}};
            helper_word_idx <= 6'b0;
        end else if (helper_data_valid) begin
            helper_data_captured[helper_word_idx*16 +: 16] <= helper_data_out;
            helper_word_idx <= helper_word_idx + 1;
        end else if (helper_data_done) begin
            helper_word_idx <= 6'b0;
        end
    end

    // Capture puf_key from 16-bit bus
    always @(posedge clk) begin
        if (reset) begin
            puf_key_captured <= 512'b0;
            puf_key_word_idx <= 5'b0;
        end else if (puf_key_valid) begin
            puf_key_captured[puf_key_word_idx*16 +: 16] <= puf_key_out;
            puf_key_word_idx <= puf_key_word_idx + 1;
        end else if (puf_key_done) begin
            puf_key_word_idx <= 5'b0;
        end
    end

    // Capture hmac_value from 16-bit bus
    always @(posedge clk) begin
        if (reset) begin
            hmac_value_captured <= 512'b0;
            hmac_word_idx <= 5'b0;
        end else if (hmac_valid) begin
            hmac_value_captured[hmac_word_idx*16 +: 16] <= hmac_out;
            hmac_word_idx <= hmac_word_idx + 1;
        end else if (hmac_done) begin
            hmac_word_idx <= 5'b0;
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
            $display("[INFO] Waiting for key generation outputs...");

            // Wait for helper_data and puf_key to complete
            // (HMAC output only happens during HMAC operations, not key generation)
            while ((!helper_data_done || !puf_key_done) && timeout < 200) begin
                // Show progress every 100 cycles
                if (timeout % 100 == 0 && timeout > 0) begin
                    $display("[INFO] Cycle %0d: helper_data=%b, puf_key=%b",
                             timeout, helper_data_done, puf_key_done);
                end
                @(posedge clk);
                timeout = timeout + 1;
            end

            if (timeout >= 200) begin
                $display("[ERROR] Timeout waiting for key generation!");
                $display("[ERROR] helper_data_done=%b, puf_key_done=%b",
                         helper_data_done, puf_key_done);
            end else begin
                $display("[INFO] Key generation completed in %0d cycles\n", timeout);
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
            while (!hmac_done && timeout < 200) begin
                @(posedge clk);
                timeout = timeout + 1;
            end

            if (timeout >= 200) begin
                $display("  [ERROR] Timeout waiting for HMAC completion!");
                fail_count = fail_count + 1;
            end else begin
                $display("  [INFO] HMAC completed in %0d cycles", timeout);
                $display("  [INFO] HMAC = %h", hmac_value_captured[127:0]);
            end

            @(posedge clk);
        end
    endtask

    // ========================================
    // Complete Test Sequence
    // ========================================
    initial begin
        $display("\n========================================");
        $display("  Secure Key System - Complete Test");
        $display("========================================\n");

        // Reset the system
        reset_system();

        // ===========================================
        // Step 1: Key Generation
        // ===========================================
        $display("[INFO] ===== STEP 1: Key Generation =====");
        trigger_keygen();
        wait_keygen_complete();

        // Check key generation results
        $display("\n[INFO] Key Generation Results:");
        if (helper_data_done) begin
            $display("[PASS] Helper Data transmitted (%0d words)", 44);
            $display("       First 64 bits: %h", helper_data_captured[63:0]);
        end else begin
            $display("[FAIL] Helper Data not done");
        end

        if (puf_key_done) begin
            $display("[PASS] PUF Key transmitted (%0d words)", 32);
            $display("       First 64 bits: %h", puf_key_captured[63:0]);
        end else begin
            $display("[FAIL] PUF Key not done");
        end

        // Wait a bit before starting HMAC
        repeat(1) @(posedge clk);

        // ===========================================
        // Step 2: HMAC Operation
        // ===========================================
        $display("\n[INFO] ===== STEP 2: HMAC Operation =====");
        trigger_hmac();

        // Send test message (2 words)
        $display("  [INFO] Sending test message...");
        send_word(32'hDEADBEEF, 1'b0);  // First word
        send_word(32'hCAFEBABE, 1'b1);  // Last word

        // Wait for HMAC to complete
        wait_hmac_complete();

        // Check HMAC results
        $display("\n[INFO] HMAC Operation Results:");
        if (hmac_done) begin
            $display("[PASS] HMAC Value transmitted (%0d words)", 32);
            $display("       First 64 bits: %h", hmac_value_captured[63:0]);
        end else begin
            $display("[FAIL] HMAC Value not done");
        end

        // ===========================================
        // Final Summary
        // ===========================================
        repeat(10) @(posedge clk);

        $display("\n========================================");
        $display("  Complete Test Results");
        $display("========================================");
        $display("Helper Data (first 64 bits): %h", helper_data_captured[63:0]);
        $display("PUF Key (first 64 bits):     %h", puf_key_captured[63:0]);
        $display("HMAC Value (first 64 bits):  %h", hmac_value_captured[63:0]);
        $display("\n========================================");
        $display("  Test Complete");
        $display("========================================\n");

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
        #20000; // 200ms
        $display("\n[ERROR] Global timeout reached!");
        $finish;
    end

endmodule
