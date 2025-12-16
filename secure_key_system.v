// ============================================================================
// secure_key_system.v
// Combined Fuzzy Extractor + HMAC-SHA3-512 System
//
// Flow: PUF → Fuzzy Extractor (replicate to 704 bits) → HMAC Key Generation
// ============================================================================

module secure_key_system
#(
    parameter integer PUF_BLOCKS = 2,    // Number of 32-bit PUF blocks (2 = 64 bits)
    parameter integer FE_BLOCKS  = 22    // Fuzzy extractor blocks (22 = 704 bits)
)
(
    input  wire         clk,
    input  wire         reset,

    // ========================================
    // Control - Single unified start signal
    // ========================================
    input  wire         start_keygen,    // Start key generation process

    // ========================================
    // PUF Interface (exposed from fuzzy extractor)
    // ========================================
    output wire         puf_read_req,
    input  wire [PUF_BLOCKS*32-1:0] puf_data,     // Raw PUF response (64 bits)
    input  wire         puf_valid,

    // ========================================
    // TRNG Interface (exposed from fuzzy extractor)
    // ========================================
    output wire         trng_req,
    input  wire [FE_BLOCKS*6-1:0] trng_data,     // Random bits for RM encoding (132 bits)
    input  wire         trng_valid,

    // ========================================
    // HMAC Message Interface
    // ========================================
    input  wire         start_hmac,
    input  wire [31:0]  msg_word,
    input  wire         msg_valid,
    input  wire         msg_last,
    output wire         msg_ready,

    // ========================================
    // Outputs
    // ========================================
    output wire [FE_BLOCKS*32-1:0] helper_data,  // Helper data (store in NVM)
    output wire         helper_data_valid,       // Helper data is ready

    output wire [511:0] puf_key,                 // Derived PUF key (512 bits)
    output wire         puf_key_valid,           // PUF key is ready

    output wire [511:0] hmac_value,              // HMAC output
    output wire         hmac_done                // HMAC operation complete
);

    // ========================================================================
    // Internal Signals
    // ========================================================================

    // Fuzzy Extractor signals
    reg                     fe_enable;
    wire [FE_BLOCKS*32-1:0] fe_rprime;           // Replicated PUF data (704 bits)
    wire                    fe_complete;

    // HMAC top signals
    reg                     start_puf_hash;      // Trigger PUF key generation
    reg  [703:0]            puf_input_to_hmac;   // 704-bit input from fuzzy extractor
    wire                    puf_hash_done;       // Done signal from HMAC module

    // FSM state machine
    localparam [2:0] S_IDLE          = 3'd0,
                     S_FE_REQUEST    = 3'd1,
                     S_FE_WAIT       = 3'd2,
                     S_HASH_PUF      = 3'd3,
                     S_WAIT_HASH     = 3'd4,
                     S_READY         = 3'd5;

    reg [2:0] state, next_state;

    // Output status registers
    reg helper_data_valid_r;
    reg puf_key_valid_r;

    assign helper_data_valid = helper_data_valid_r;
    assign puf_key_valid = puf_key_valid_r;

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

        // PUF interface (exposed to top-level)
        .puf_read_req(puf_read_req),
        .puf_data(puf_data),
        .puf_valid(puf_valid),

        // TRNG interface (exposed to top-level)
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
        .start_puf(start_puf_hash),      // Generate key from PUF data
        .start_hmac(start_hmac),         // Start HMAC operation

        // PUF input (704 bits from fuzzy extractor)
        .puf_input(puf_input_to_hmac),

        // Message interface
        .msg_word(msg_word),
        .msg_valid(msg_valid),
        .msg_last(msg_last),
        .msg_ready(msg_ready),

        // Outputs
        .puf_key(puf_key),
        .hmac_value(hmac_value),
        .done(puf_hash_done)
    );

    assign hmac_done = puf_hash_done;  // HMAC done is same as HMAC module done

    // ========================================================================
    // FSM: Sequential Logic
    // ========================================================================
    always @(posedge clk) begin
        if (reset)
            state <= S_IDLE;
        else
            state <= next_state;
    end

    // ========================================================================
    // FSM: Next State Logic
    // ========================================================================
    always @(*) begin
        next_state = state;

        case (state)
            S_IDLE: begin
                // Start key generation when requested
                if (start_keygen)
                    next_state = S_FE_REQUEST;
            end

            S_FE_REQUEST: begin
                // Enable fuzzy extractor
                next_state = S_FE_WAIT;
            end

            S_FE_WAIT: begin
                // Wait for fuzzy extractor to complete
                if (fe_complete)
                    next_state = S_HASH_PUF;
            end

            S_HASH_PUF: begin
                // Start PUF hashing
                next_state = S_WAIT_HASH;
            end

            S_WAIT_HASH: begin
                // Wait for hash to complete
                if (puf_hash_done)
                    next_state = S_READY;
            end

            S_READY: begin
                // System ready for HMAC operations
                // Stay here until new key generation requested
                if (start_keygen)
                    next_state = S_FE_REQUEST;
            end

            default: next_state = S_IDLE;
        endcase
    end

    // ========================================================================
    // FSM: Output Logic
    // ========================================================================
    always @(posedge clk) begin
        if (reset) begin
            fe_enable          <= 1'b0;
            start_puf_hash     <= 1'b0;
            puf_input_to_hmac  <= 704'b0;
            helper_data_valid_r <= 1'b0;
            puf_key_valid_r    <= 1'b0;
        end else begin
            // Default: clear one-shot signals
            fe_enable      <= 1'b0;
            start_puf_hash <= 1'b0;

            case (state)
                S_IDLE: begin
                    // Clear valid flags when starting new key generation
                    if (start_keygen) begin
                        helper_data_valid_r <= 1'b0;
                        puf_key_valid_r    <= 1'b0;
                    end
                end

                S_FE_REQUEST: begin
                    // Enable fuzzy extractor
                    fe_enable <= 1'b1;
                end

                S_FE_WAIT: begin
                    // Wait for completion
                    if (fe_complete) begin
                        // Latch rprime output for HMAC
                        puf_input_to_hmac <= fe_rprime;
                        // Mark helper data as valid
                        helper_data_valid_r <= 1'b1;
                    end
                end

                S_HASH_PUF: begin
                    // Start PUF key hashing with rprime data
                    start_puf_hash <= 1'b1;
                end

                S_WAIT_HASH: begin
                    // Wait for hash completion
                    if (puf_hash_done) begin
                        puf_key_valid_r <= 1'b1;
                    end
                end

                S_READY: begin
                    // System ready - maintain valid flags
                    // User can now perform HMAC operations
                end

                default: begin
                    // Reset everything
                end
            endcase
        end
    end

endmodule


// ============================================================================
// USAGE NOTES:
// ============================================================================
//
// 1. KEY GENERATION FLOW:
//    - Assert start_keygen
//    - System automatically:
//      a) Requests PUF data via puf_read_req
//      b) Requests TRNG data via trng_req
//      c) Fuzzy extractor replicates 64-bit PUF → 704-bit rprime
//      d) Generates helper_data (output, can be stored)
//      e) Hashes rprime → 512-bit puf_key
//    - When puf_key_valid goes high, key is ready
//
// 2. HMAC OPERATIONS (after key is ready):
//    - Assert start_hmac
//    - Send message via msg_word/msg_valid/msg_last
//    - HMAC output appears on hmac_value when hmac_done pulses
//
// 3. HELPER DATA:
//    - helper_data output contains RM-encoded data
//    - helper_data_valid indicates it's ready to store
//    - Store this in non-volatile memory for future reconstruction
//    - (Reconstruction not implemented yet - would need decoder)
//
// 4. TIMING:
//    - Key generation takes ~500-1000 cycles
//    - HMAC operation timing depends on message length
//
// ============================================================================
