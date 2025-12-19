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
    // PUF Interface (exposed from fuzzy extractor) - NEW PROTOCOL
    // ========================================
    output wire                         puf_clk,     // Clock for PUF
    output wire                         puf_enable,  // Enable signal for PUF
    output wire [$clog2((PUF_BLOCKS*32)/8)-1:0] puf_addr,    // Byte address
    input  wire [7:0]                   puf_data,    // 8-bit data from PUF

    // ========================================
    // TRNG Interface (exposed from fuzzy extractor) - NEW PROTOCOL
    // ========================================
    output wire         trng_clk,      // Clock for TRNG
    output wire         trng_enable,   // Enable signal for TRNG
    input  wire         trng_data,     // 1-bit data from TRNG

    // ========================================
    // HMAC Message Interface
    // ========================================
    input  wire         start_hmac,
    input  wire [31:0]  msg_word,
    input  wire         msg_valid,
    input  wire         msg_last,
    output wire         msg_ready,

    // ========================================
    // Outputs - Three separate 16-bit buses
    // ========================================
    // Helper Data bus (704 bits over 44 words)
    output reg  [15:0]  helper_data_out,
    output reg          helper_data_valid,
    output reg          helper_data_done,

    // PUF Key bus (512 bits over 32 words)
    output reg  [15:0]  puf_key_out,
    output reg          puf_key_valid,
    output reg          puf_key_done,

    // HMAC Value bus (512 bits over 32 words)
    output reg  [15:0]  hmac_out,
    output reg          hmac_valid,
    output reg          hmac_done
);

    // ========================================================================
    // Internal Signals
    // ========================================================================

    // Fuzzy Extractor signals
    reg                     fe_enable;
    wire [FE_BLOCKS*32-1:0] fe_rprime;           // Replicated PUF data (704 bits)
    wire [FE_BLOCKS*32-1:0] helper_data_internal; // Helper data from fuzzy extractor
    wire                    fe_complete;

    // HMAC top signals
    reg                     start_puf_hash;      // Trigger PUF key generation
    reg  [703:0]            puf_input_to_hmac;   // 704-bit input from fuzzy extractor
    wire [511:0]            puf_key_internal;    // PUF key from HMAC
    wire [511:0]            hmac_value_internal; // HMAC output
    wire                    puf_hash_done;       // Done signal from HMAC module

    // Internal storage for outputs
    reg [FE_BLOCKS*32-1:0]  helper_data_reg;     // 704 bits
    reg [511:0]             puf_key_reg;         // 512 bits
    reg [511:0]             hmac_value_reg;      // 512 bits

    // Separate word counters for each 16-bit bus
    reg [5:0]  helper_word_count;  // 0-43 (44 words for 704 bits)
    reg [4:0]  puf_key_word_count; // 0-31 (32 words for 512 bits)
    reg [4:0]  hmac_word_count;    // 0-31 (32 words for 512 bits)

    // Serialization active flags
    reg        helper_serializing;
    reg        puf_key_serializing;
    reg        hmac_serializing;

    // Track if we're doing HMAC operation vs key generation
    reg        hmac_operation_active;

    // FSM state machine
    localparam [2:0] S_IDLE          = 3'd0,
                     S_FE_REQUEST    = 3'd1,
                     S_FE_WAIT       = 3'd2,
                     S_HASH_PUF      = 3'd3,
                     S_WAIT_HASH     = 3'd4,
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

        // PUF interface (NEW PROTOCOL - exposed to top-level)
        .puf_clk(puf_clk),
        .puf_enable(puf_enable),
        .puf_addr(puf_addr),
        .puf_data(puf_data),

        // TRNG interface (NEW PROTOCOL - exposed to top-level)
        .trng_clk(trng_clk),
        .trng_enable(trng_enable),
        .trng_data(trng_data),

        // Outputs
        .rprime(fe_rprime),                    // Replicated PUF data (704 bits)
        .helper_data(helper_data_internal),    // Helper data for storage
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
        .puf_key(puf_key_internal),
        .hmac_value(hmac_value_internal),
        .done(puf_hash_done)
    );

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
            fe_enable            <= 1'b0;
            start_puf_hash       <= 1'b0;
            puf_input_to_hmac    <= 704'b0;
            hmac_operation_active<= 1'b0;
        end else begin
            // Default: clear one-shot signals
            fe_enable      <= 1'b0;
            start_puf_hash <= 1'b0;

            // Track HMAC operations
            if (start_hmac) begin
                hmac_operation_active <= 1'b1;
            end else if (puf_hash_done && hmac_operation_active) begin
                hmac_operation_active <= 1'b0;
            end

            case (state)
                S_IDLE: begin
                    // Ready for new key generation
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
                        // Latch helper data for 16-bit bus serialization
                        helper_data_reg <= helper_data_internal;
                    end
                end

                S_HASH_PUF: begin
                    // Start PUF key hashing with rprime data
                    start_puf_hash <= 1'b1;
                end

                S_WAIT_HASH: begin
                    // Wait for hash completion
                    // Data latching now happens in serialization blocks
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

    // ========================================================================
    // Helper Data 16-bit Output Serialization
    // ========================================================================
    always @(posedge clk) begin
        if (reset) begin
            helper_data_out     <= 16'b0;
            helper_data_valid   <= 1'b0;
            helper_data_done    <= 1'b0;
            helper_word_count   <= 6'b0;
            helper_serializing  <= 1'b0;
        end else begin
            // Start serialization when data is latched and not already done
            if (fe_complete && !helper_serializing && !helper_data_done) begin
                helper_serializing <= 1'b1;
                helper_word_count  <= 6'b0;
            end

            // Serialize data
            if (helper_serializing) begin
                helper_data_valid <= 1'b1;
                helper_data_out   <= helper_data_reg[helper_word_count*16 +: 16];
                helper_word_count <= helper_word_count + 1;

                if (helper_word_count >= 6'd43) begin  // 44 words (0-43)
                    helper_data_done    <= 1'b1;
                    helper_data_valid   <= 1'b0;
                    helper_serializing  <= 1'b0;
                end
            end

            // Reset when new key generation starts
            if (!fe_complete && helper_data_done) begin
                helper_data_done <= 1'b0;
            end
        end
    end

    // ========================================================================
    // PUF Key 16-bit Output Serialization
    // ========================================================================
    always @(posedge clk) begin
        if (reset) begin
            puf_key_out         <= 16'b0;
            puf_key_valid       <= 1'b0;
            puf_key_done        <= 1'b0;
            puf_key_word_count  <= 5'b0;
            puf_key_serializing <= 1'b0;
            puf_key_reg         <= 512'b0;
        end else begin
            // Latch data when puf_hash_done pulses
            if (puf_hash_done && !puf_key_serializing && !puf_key_done) begin
                puf_key_reg         <= puf_key_internal;
                puf_key_serializing <= 1'b1;
                puf_key_word_count  <= 5'b0;
            end
            // Serialize data (starts the cycle AFTER latching)
            else if (puf_key_serializing) begin
                puf_key_valid     <= 1'b1;
                puf_key_out       <= puf_key_reg[puf_key_word_count*16 +: 16];
                puf_key_word_count<= puf_key_word_count + 1;

                if (puf_key_word_count >= 5'd31) begin  // 32 words (0-31)
                    puf_key_done        <= 1'b1;
                    puf_key_valid       <= 1'b0;
                    puf_key_serializing <= 1'b0;
                end
            end

            // Reset when new key generation starts (start_keygen or reset)
            if (state == S_IDLE && puf_key_done) begin
                puf_key_done <= 1'b0;
            end
        end
    end

    // ========================================================================
    // HMAC Value 16-bit Output Serialization
    // ========================================================================
    always @(posedge clk) begin
        if (reset) begin
            hmac_out          <= 16'b0;
            hmac_valid        <= 1'b0;
            hmac_done         <= 1'b0;
            hmac_word_count   <= 5'b0;
            hmac_serializing  <= 1'b0;
            hmac_value_reg    <= 512'b0;
        end else begin
            // Latch data when puf_hash_done pulses AND it's an HMAC operation
            if (puf_hash_done && hmac_operation_active && !hmac_serializing && !hmac_done) begin
                hmac_value_reg   <= hmac_value_internal;
                hmac_serializing <= 1'b1;
                hmac_word_count  <= 5'b0;
            end
            // Serialize data (starts the cycle AFTER latching)
            else if (hmac_serializing) begin
                hmac_valid     <= 1'b1;
                hmac_out       <= hmac_value_reg[hmac_word_count*16 +: 16];
                hmac_word_count<= hmac_word_count + 1;

                if (hmac_word_count >= 5'd31) begin  // 32 words (0-31)
                    hmac_done        <= 1'b1;
                    hmac_valid       <= 1'b0;
                    hmac_serializing <= 1'b0;
                end
            end

            // Reset when new key generation starts
            if (state == S_IDLE && hmac_done) begin
                hmac_done <= 1'b0;
            end
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
