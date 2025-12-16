`timescale 1ns/1ps

// ============================================================================
// DEBUG Testbench for secure_key_system
// Adds FSM state monitoring and detailed cycle-by-cycle tracing
// ============================================================================

module secure_key_system_tb_debug;

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

    integer cycle_count;

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
    // Debug Monitors
    // ========================================

    // Monitor main FSM state
    wire [2:0] main_fsm_state = dut.state;

    // Monitor HMAC controller state
    wire [4:0] hmac_ctrl_state = dut.hmac.u_ctrl.state;

    // Monitor SHA3 signals
    wire sha_init = dut.hmac.sha_init;
    wire mode_puf = dut.hmac.mode_puf;
    wire mode_block = dut.hmac.mode_block;
    wire sha_busy = dut.hmac.sha_busy;
    wire sha_out_ready = dut.hmac.sha_out_ready;

    // State name decoder for main FSM
    function [127:0] main_state_name;
        input [2:0] state;
        begin
            case (state)
                3'd0: main_state_name = "IDLE";
                3'd1: main_state_name = "FE_REQUEST";
                3'd2: main_state_name = "FE_WAIT";
                3'd3: main_state_name = "HASH_PUF";
                3'd4: main_state_name = "WAIT_HASH";
                3'd5: main_state_name = "READY";
                default: main_state_name = "UNKNOWN";
            endcase
        end
    endfunction

    // State name decoder for HMAC controller
    function [127:0] hmac_state_name;
        input [4:0] state;
        begin
            case (state)
                5'd0: hmac_state_name = "IDLE";
                5'd1: hmac_state_name = "PUF_INIT";
                5'd2: hmac_state_name = "PUF_START";
                5'd3: hmac_state_name = "PUF_WAIT";
                5'd4: hmac_state_name = "MAC_INIT";
                5'd5: hmac_state_name = "IPAD_LOAD";
                5'd6: hmac_state_name = "IPAD_SEND";
                5'd7: hmac_state_name = "MSG_COLLECT";
                5'd8: hmac_state_name = "MSG_LOAD";
                5'd9: hmac_state_name = "MSG_SEND";
                5'd10: hmac_state_name = "MAC_WAIT";
                5'd31: hmac_state_name = "DONE";
                default: hmac_state_name = "UNKNOWN";
            endcase
        end
    endfunction

    // Cycle counter
    always @(posedge clk) begin
        if (reset)
            cycle_count <= 0;
        else
            cycle_count <= cycle_count + 1;
    end

    // State change monitor
    reg [2:0] main_fsm_state_prev;
    reg [4:0] hmac_ctrl_state_prev;

    always @(posedge clk) begin
        if (!reset) begin
            if (main_fsm_state !== main_fsm_state_prev) begin
                $display("[%0t ns, Cycle %0d] Main FSM: %0s -> %0s",
                    $time, cycle_count,
                    main_state_name(main_fsm_state_prev),
                    main_state_name(main_fsm_state));
            end

            if (hmac_ctrl_state !== hmac_ctrl_state_prev) begin
                $display("[%0t ns, Cycle %0d] HMAC Controller: %0s -> %0s",
                    $time, cycle_count,
                    hmac_state_name(hmac_ctrl_state_prev),
                    hmac_state_name(hmac_ctrl_state));
            end

            main_fsm_state_prev <= main_fsm_state;
            hmac_ctrl_state_prev <= hmac_ctrl_state;
        end
    end

    // Signal monitor
    always @(posedge clk) begin
        if (!reset) begin
            if (sha_init)
                $display("[%0t ns, Cycle %0d] SHA_INIT pulsed", $time, cycle_count);
            if (start_hmac)
                $display("[%0t ns, Cycle %0d] START_HMAC asserted", $time, cycle_count);
            if (hmac_done)
                $display("[%0t ns, Cycle %0d] HMAC_DONE pulsed", $time, cycle_count);
            if (sha_out_ready)
                $display("[%0t ns, Cycle %0d] SHA_OUT_READY (hash complete)", $time, cycle_count);
            if (msg_valid && msg_ready)
                $display("[%0t ns, Cycle %0d] Message word sent: 0x%08h, last=%b",
                    $time, cycle_count, msg_word, msg_last);
        end
    end

    // ========================================
    // Clock Generation: 100 MHz
    // ========================================
    initial begin
        clk = 0;
        forever #5 clk = ~clk;
    end

    // ========================================
    // PUF Simulator
    // ========================================
    always @(posedge clk) begin
        if (reset) begin
            puf_data <= 0;
            puf_valid <= 0;
        end else begin
            if (puf_read_req && !puf_valid) begin
                repeat(2) @(posedge clk);
                puf_data <= {$random, $random};
                puf_valid <= 1'b1;
                @(posedge clk);
                puf_valid <= 1'b0;
            end
        end
    end

    // ========================================
    // TRNG Simulator
    // ========================================
    always @(posedge clk) begin
        if (reset) begin
            trng_data <= 0;
            trng_valid <= 0;
        end else begin
            if (trng_req && !trng_valid) begin
                repeat(2) @(posedge clk);
                trng_data <= {$random, $random, $random, $random, $random};
                trng_valid <= 1'b1;
                @(posedge clk);
                trng_valid <= 1'b0;
            end
        end
    end

    // ========================================
    // Test Sequence
    // ========================================
    initial begin
        $display("\n========================================");
        $display("  DEBUG Testbench - Secure Key System");
        $display("========================================\n");

        // Reset
        reset = 1'b1;
        start_keygen = 1'b0;
        start_hmac = 1'b0;
        msg_word = 32'b0;
        msg_valid = 1'b0;
        msg_last = 1'b0;

        repeat(10) @(posedge clk);
        reset = 1'b0;
        repeat(2) @(posedge clk);

        $display("\n=== TEST: Key Generation ===\n");
        @(posedge clk);
        start_keygen <= 1'b1;
        @(posedge clk);
        start_keygen <= 1'b0;

        // Wait for key generation
        wait(puf_key_valid);
        repeat(5) @(posedge clk);

        $display("\n=== PUF Key Generated ===");
        $display("PUF Key = %h", puf_key);
        $display("Cycle count = %0d\n", cycle_count);

        $display("\n=== TEST: HMAC Single Word ===\n");
        @(posedge clk);
        start_hmac <= 1'b1;
        @(posedge clk);
        start_hmac <= 1'b0;

        // Wait for msg_ready
        wait(msg_ready);
        @(posedge clk);

        msg_word <= 32'h12345678;
        msg_valid <= 1'b1;
        msg_last <= 1'b1;
        @(posedge clk);
        msg_valid <= 1'b0;
        msg_last <= 1'b0;

        // Wait for completion
        wait(hmac_done);
        repeat(5) @(posedge clk);

        $display("\n=== HMAC Result ===");
        $display("HMAC Value = %h", hmac_value);
        $display("Total cycles for HMAC = %0d\n", cycle_count);

        $display("\n=== TEST: HMAC Multi-Word ===\n");
        @(posedge clk);
        start_hmac <= 1'b1;
        @(posedge clk);
        start_hmac <= 1'b0;

        // Send first word
        wait(msg_ready);
        @(posedge clk);
        msg_word <= 32'hDEADBEEF;
        msg_valid <= 1'b1;
        msg_last <= 1'b0;
        @(posedge clk);
        msg_valid <= 1'b0;

        // Send second word
        wait(msg_ready);
        @(posedge clk);
        msg_word <= 32'hCAFEBABE;
        msg_valid <= 1'b1;
        msg_last <= 1'b1;
        @(posedge clk);
        msg_valid <= 1'b0;
        msg_last <= 1'b0;

        // Wait for completion
        wait(hmac_done);
        repeat(5) @(posedge clk);

        $display("\n=== HMAC Result ===");
        $display("HMAC Value = %h", hmac_value);

        repeat(20) @(posedge clk);
        $display("\n=== Test Complete ===\n");
        $finish;
    end

    // ========================================
    // Waveform Dump
    // ========================================
    initial begin
        $dumpfile("secure_key_system_tb_debug.vcd");
        $dumpvars(0, secure_key_system_tb_debug);
    end

    // ========================================
    // Timeout Watchdog
    // ========================================
    initial begin
        #100000000; // 100ms
        $display("\n[ERROR] Global timeout reached!\n");
        $finish;
    end

endmodule
