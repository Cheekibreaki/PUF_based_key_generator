// ============================================================================
// secure_key_system.v
// Combined Fuzzy Extractor + HMAC-SHA3-512 System
//
// This module integrates:
// 1. Fuzzy Extractor (device_rfe_gen) - Generates helper data from PUF
// 2. HMAC-SHA3-512 (hmac_top) - Uses PUF output as cryptographic key
//
// The PUF data flows through the fuzzy extractor first, then the extracted
// stable bits are used as the key for HMAC operations.
// ============================================================================

module secure_key_system
#(
    parameter integer PUF_BLOCKS = 2,    // Number of 32-bit PUF blocks
    parameter integer FE_BLOCKS  = 22    // Fuzzy extractor blocks (22 for 704 bits)
)
(
    input  wire         clk,
    input  wire         reset,

    // ========================================
    // Control Signals
    // ========================================
    input  wire         start_enrollment,    // Start enrollment (generate helper data)
    input  wire         start_reconstruction, // Start reconstruction (recover key from noisy PUF)
    input  wire         start_hmac,          // Start HMAC computation

    // ========================================
    // PUF Interface
    // ========================================
    output wire         puf_read_req,
    input  wire [PUF_BLOCKS*32-1:0] puf_data,     // Raw PUF response (64 bits for PUF_BLOCKS=2)
    input  wire         puf_valid,

    // ========================================
    // TRNG Interface (for enrollment only)
    // ========================================
    output wire         trng_req,
    input  wire [FE_BLOCKS*6-1:0] trng_data,     // Random bits for RM encoding (132 bits)
    input  wire         trng_valid,

    // ========================================
    // HMAC Message Interface
    // ========================================
    input  wire [31:0]  msg_word,
    input  wire         msg_valid,
    input  wire         msg_last,
    output wire         msg_ready,

    // ========================================
    // Outputs
    // ========================================
    output wire [FE_BLOCKS*32-1:0] helper_data,  // Helper data (store in NVM during enrollment)
    output wire         enrollment_done,         // Enrollment complete

    output wire [511:0] puf_key,                 // Reconstructed/Extracted PUF key (512 bits)
    output wire [511:0] hmac_value,              // HMAC output
    output wire         done                      // Operation complete
);

    // ========================================================================
    // Internal Signals
    // ========================================================================

    // Fuzzy Extractor signals
    wire                    fe_enable;
    wire [FE_BLOCKS*32-1:0] fe_rprime;           // Replicated PUF data (704 bits)
    wire                    fe_complete;

    // PUF key generation control
    reg                     puf_key_valid;
    reg  [703:0]            puf_input_reg;       // 704-bit input to SHA3
    reg                     start_puf_gen;

    // Mode selection
    wire                    enrollment_mode;
    wire                    reconstruction_mode;

    // Internal state machine
    localparam [2:0] S_IDLE          = 3'd0,
                     S_ENROLLMENT    = 3'd1,
                     S_WAIT_FE       = 3'd2,
                     S_PUF_HASH      = 3'd3,
                     S_WAIT_PUF      = 3'd4,
                     S_READY         = 3'd5;

    reg [2:0] state, next_state;

    // ========================================================================
    // Fuzzy Extractor Instance
    // ========================================================================
    device_rfe_gen #(
        .PUF_BLOCKS(PUF_BLOCKS),
        .BLOCKS(FE_BLOCKS),
        .N(32),
        .K(6)
    ) fuzzy_extractor (
        .clk(clk),
        .rst_n(~reset),
        .enable(fe_enable),

        // PUF interface
        .puf_read_req(puf_read_req),
        .puf_data(puf_data),
        .puf_valid(puf_valid),

        // TRNG interface
        .trng_req(trng_req),
        .trng_data(trng_data),
        .trng_valid(trng_valid),

        // Outputs
        .rprime(fe_rprime),              // Replicated PUF data (704 bits)
        .helper_data(helper_data),       // Helper data for storage
        .complete(fe_complete)
    );

    // ========================================================================
    // HMAC-SHA3-512 Instance
    // ========================================================================
    hmac_top hmac (
        .clk(clk),
        .reset(reset),

        // Control
        .start_puf(start_puf_gen),       // Generate key from PUF data
        .start_hmac(start_hmac),

        // PUF input (704 bits from fuzzy extractor)
        .puf_input(puf_input_reg),

        // Message interface
        .msg_word(msg_word),
        .msg_valid(msg_valid),
        .msg_last(msg_last),
        .msg_ready(msg_ready),

        // Outputs
        .puf_key(puf_key),
        .hmac_value(hmac_value),
        .done(done)
    );

    // ========================================================================
    // Control Logic
    // ========================================================================

    assign enrollment_mode     = start_enrollment;
    assign reconstruction_mode = start_reconstruction;
    assign fe_enable           = (state == S_ENROLLMENT);
    assign enrollment_done     = (state == S_READY) && enrollment_mode;

    // State machine: Sequential
    always @(posedge clk) begin
        if (reset)
            state <= S_IDLE;
        else
            state <= next_state;
    end

    // State machine: Next state logic
    always @(*) begin
        next_state = state;

        case (state)
            S_IDLE: begin
                if (start_enrollment || start_reconstruction)
                    next_state = S_ENROLLMENT;
            end

            S_ENROLLMENT: begin
                // Wait for fuzzy extractor to request PUF/TRNG
                if (fe_enable)
                    next_state = S_WAIT_FE;
            end

            S_WAIT_FE: begin
                // Wait for fuzzy extractor to complete
                if (fe_complete)
                    next_state = S_PUF_HASH;
            end

            S_PUF_HASH: begin
                // Start PUF key generation via SHA3
                next_state = S_WAIT_PUF;
            end

            S_WAIT_PUF: begin
                // Wait for PUF key generation to complete
                if (done)
                    next_state = S_READY;
            end

            S_READY: begin
                // System ready - can accept HMAC operations
                // Stay here until reset or new enrollment
                if (start_enrollment || start_reconstruction)
                    next_state = S_ENROLLMENT;
            end

            default: next_state = S_IDLE;
        endcase
    end

    // Latch PUF data and generate key
    always @(posedge clk) begin
        if (reset) begin
            puf_input_reg  <= 704'b0;
            start_puf_gen  <= 1'b0;
            puf_key_valid  <= 1'b0;
        end else begin
            start_puf_gen <= 1'b0;  // Default: one-shot pulse

            // When FE completes, latch the rprime data
            if (state == S_WAIT_FE && fe_complete) begin
                puf_input_reg <= fe_rprime;  // 704 bits
            end

            // Start PUF key hashing
            if (state == S_PUF_HASH) begin
                start_puf_gen <= 1'b1;
            end

            // Mark key as valid when hash completes
            if (state == S_WAIT_PUF && done) begin
                puf_key_valid <= 1'b1;
            end

            // Clear valid flag on new enrollment
            if (start_enrollment || start_reconstruction) begin
                puf_key_valid <= 1'b0;
            end
        end
    end

endmodule


// ============================================================================
// IMPORTANT NOTES:
// ============================================================================
//
// 1. ENROLLMENT FLOW (First-time setup):
//    - Assert start_enrollment
//    - Fuzzy extractor reads PUF and TRNG
//    - Helper data is generated and output on helper_data port
//    - Store helper_data in non-volatile memory
//    - PUF data is hashed to generate puf_key (512 bits)
//    - enrollment_done pulses when ready
//
// 2. RECONSTRUCTION FLOW (Subsequent boots):
//    - Assert start_reconstruction
//    - Fuzzy extractor reads noisy PUF
//    - Use stored helper_data with error correction (not shown here)
//    - Recovered PUF data is hashed to regenerate same puf_key
//    - System ready for HMAC operations
//
// 3. HMAC OPERATION:
//    - After enrollment/reconstruction completes (puf_key is valid)
//    - Assert start_hmac
//    - Send message words via msg_word/msg_valid/msg_last interface
//    - HMAC output appears on hmac_value when done pulses
//
// 4. SECURITY CONSIDERATIONS:
//    - helper_data can be stored publicly (it's not secret)
//    - puf_key should NEVER be exposed outside this module
//    - The 704-bit PUF response provides ~512 bits of entropy after hashing
//    - Reed-Muller codes provide error correction for noisy PUF responses
//
// ============================================================================
