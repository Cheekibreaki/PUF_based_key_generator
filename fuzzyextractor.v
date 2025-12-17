`timescale 1ns/10ps

// -----------------------------------------------------------------------------
// DEVICE_RFE_GEN (Modified with PUF replication and rprime output)
// - PUF_BLOCKS: number of N-bit blocks from PUF (can be less than BLOCKS)
// - BLOCKS: number of RM encoding blocks needed
// - PUF data is replicated/cycled to fill all BLOCKS
// -----------------------------------------------------------------------------
module device_rfe_gen
#(
    parameter integer PUF_BLOCKS = 2,   // Number of N-bit blocks from PUF (each block is N bits)
    parameter integer BLOCKS     = 22,   // Number of RM encoding blocks
    parameter integer N          = 32,  // fixed at 32 for RM(1,5)
    parameter integer K          = 6    // fixed at 6  for RM(1,5)
)
(
    input  wire                       clk,
    input  wire                       rst_n,
    input  wire                       enable,      // Enable signal to start processing

    // PUF Interface - NEW PROTOCOL
    // Read PUF_BLOCKS*N bits total, 8 bits at a time
    output reg                        puf_clk,     // Clock for PUF
    output reg                        puf_enable,  // Enable signal for PUF
    output reg  [$clog2((PUF_BLOCKS*N)/8)-1:0] puf_addr,  // Address (byte address)
    input  wire [7:0]                 puf_data,    // 8-bit data from PUF

    // TRNG Interface - NEW PROTOCOL
    // Read 1 bit per cycle for BLOCKS cycles, replicate each bit K times
    output reg                        trng_clk,      // Clock for TRNG
    output reg                        trng_enable,   // Enable signal for TRNG
    input  wire                       trng_data,     // 1-bit data from TRNG

    // Outputs
    output reg  [BLOCKS*N-1:0]        rprime,      // NEW: Replicated PUF data output
    output reg  [BLOCKS*N-1:0]        helper_data, // H = R' XOR Enc_RM(x)
    output reg                        complete     // Complete pulse signal
);

    // Latches for inputs
    reg [PUF_BLOCKS*N-1:0] puf_raw_reg;      // Raw PUF data as received
    reg [BLOCKS*N-1:0]     rprime_reg;       // Replicated PUF data (internal)
    reg [BLOCKS*K-1:0]     x_reg;
    reg                    have_puf;
    reg                    have_trng;

    // PUF reading state machine
    localparam PUF_BYTES = (PUF_BLOCKS * N) / 8;  // Total bytes to read from PUF
    reg [$clog2(PUF_BYTES):0] puf_byte_count;     // Current byte being read
    reg                       puf_read_state;     // 0=wait, 1=reading

    // TRNG reading state machine
    reg [$clog2(BLOCKS):0]    trng_bit_count;     // Current bit being read (0 to BLOCKS-1)
    reg                       trng_read_state;    // 0=wait, 1=reading

    // Edge detection for enable signal
    reg                    enable_d;
    wire                   enable_rising;

    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) enable_d <= 1'b0;
        else        enable_d <= enable;
    end
    assign enable_rising = enable & ~enable_d;

    // -----------------------------------------------------------------------------
    // PUF Replication Logic
    // Replicate PUF_BLOCKS of data to fill BLOCKS
    // -----------------------------------------------------------------------------
    integer rep_idx;
    always @(*) begin
        for (rep_idx = 0; rep_idx < BLOCKS; rep_idx = rep_idx + 1) begin
            // Use modulo to cycle through available PUF blocks
            rprime_reg[rep_idx*N +: N] = puf_raw_reg[(rep_idx % PUF_BLOCKS)*N +: N];
        end
    end

    // Combinational helper (built from replicated PUF data)
    wire [BLOCKS*N-1:0] helper_data_w;

    // -----------------------------------------------------------------------------
    // Generate helper_data_w block-by-block with cell instantiations
    // -----------------------------------------------------------------------------
    genvar b;
    generate
        for (b = 0; b < BLOCKS; b = b + 1) begin : g_block
            wire [K-1:0]  xb;
            wire [N-1:0]  Rb;
            wire [N-1:0]  cw;
            wire [N-1:0]  Hb;

            // Extract K-bit info and N-bit PUF block (from replicated data)
            assign xb = x_reg     [(b*K) +: K];
            assign Rb = rprime_reg[(b*N) +: N];

            // Instantiate RM encoder for this block
            rm_encoder #(.N(N), .K(K)) encoder (
                .a(xb),
                .codeword(cw)
            );

            // XOR gates: Hb = Rb XOR cw
            genvar i;
            for (i = 0; i < N; i = i + 1) begin : gen_block_xor
                CKXOR2D0 xor_helper (
                    .A1(Rb[i]),
                    .A2(cw[i]),
                    .Z(Hb[i])
                );
            end

            assign helper_data_w[(b*N) +: N] = Hb;
        end
    endgenerate

    // -----------------------------------------------------------------------------
    // Simple handshake + latching FSM (five phases)
    // -----------------------------------------------------------------------------
    localparam [2:0] S_IDLE      = 3'd0,
                     S_PUF_READ  = 3'd1,
                     S_TRNG_READ = 3'd2,
                     S_OUT       = 3'd3;

    reg [2:0] state, next_state;

    // State register
    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) state <= S_IDLE;
        else        state <= next_state;
    end

    // Next-state logic
    always @(*) begin
        case (state)
            S_IDLE:      next_state = (enable_rising ? S_PUF_READ : S_IDLE);
            S_PUF_READ:  next_state = (have_puf ? S_TRNG_READ : S_PUF_READ);
            S_TRNG_READ: next_state = (have_trng ? S_OUT : S_TRNG_READ);
            S_OUT:       next_state = S_IDLE;
            default:     next_state = S_IDLE;
        endcase
    end

    // Outputs and latches
    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            puf_clk        <= 1'b0;
            puf_enable     <= 1'b0;
            // puf_addr is now controlled by separate always @(posedge puf_clk) block
            puf_byte_count <= {($clog2(PUF_BYTES)+1){1'b0}};
            puf_read_state <= 1'b0;
            trng_clk       <= 1'b0;
            trng_enable    <= 1'b0;
            trng_bit_count <= {($clog2(BLOCKS)+1){1'b0}};
            trng_read_state<= 1'b0;
            puf_raw_reg    <= {(PUF_BLOCKS*N){1'b0}};
            x_reg          <= {(BLOCKS*K){1'b0}};
            have_puf       <= 1'b0;
            have_trng      <= 1'b0;
            rprime         <= {(BLOCKS*N){1'b0}};      // Initialize rprime output
            helper_data    <= {(BLOCKS*N){1'b0}};
            complete       <= 1'b0;
        end else begin
            // defaults
            complete     <= 1'b0;

            case (state)
                S_IDLE: begin
                    have_puf       <= 1'b0;
                    have_trng      <= 1'b0;
                    puf_enable     <= 1'b0;
                    puf_clk        <= 1'b0;
                    // puf_addr is now controlled by separate always @(posedge puf_clk) block
                    puf_byte_count <= {($clog2(PUF_BYTES)+1){1'b0}};
                    puf_read_state <= 1'b0;
                    trng_enable    <= 1'b0;
                    trng_clk       <= 1'b0;
                    trng_bit_count <= {($clog2(BLOCKS)+1){1'b0}};
                    trng_read_state<= 1'b0;

                    if (enable_rising) begin
                        // Start PUF reading on next state
                    end
                end

                S_PUF_READ: begin
                    // PUF reading protocol:
                    // Toggle puf_clk every main clock cycle
                    // Separate always block handles addr increment on puf_clk rising edge
                    // Data capture happens on puf_clk falling edge

                    if (!puf_read_state) begin
                        // First cycle: initialize
                        puf_enable     <= 1'b1;
                        puf_clk        <= 1'b0;
                        puf_read_state <= 1'b1;
                        puf_byte_count <= {($clog2(PUF_BYTES)+1){1'b0}};
                    end else begin
                        // Toggle clock every main clock cycle
                        puf_clk <= ~puf_clk;

                        // On falling edge of puf_clk: capture data
                        if (puf_clk) begin
                            // puf_clk is currently high, about to go low (falling edge)
                            puf_raw_reg[puf_byte_count*8 +: 8] <= puf_data;
                            puf_byte_count <= puf_byte_count + 1;

                            // Check if we've read all bytes
                            if (puf_byte_count >= (PUF_BYTES - 1)) begin
                                have_puf    <= 1'b1;
                                puf_enable  <= 1'b0;
                            end
                        end
                    end
                end

                S_TRNG_READ: begin
                    // TRNG reading protocol:
                    // Cycle 0: Assert trng_enable, trng_clk=0
                    // Cycle 1: trng_clk=1, read 1 bit on rising edge
                    // Replicate each bit K times in x_reg
                    // Repeat for BLOCKS cycles

                    if (!trng_read_state) begin
                        // First cycle after entering state: assert enable, clock low
                        trng_enable     <= 1'b1;
                        trng_clk        <= 1'b0;
                        trng_read_state <= 1'b1;
                    end else begin
                        // Reading cycles: toggle clock and capture data
                        if (!trng_clk) begin
                            // Clock was low, make it high (data will be ready on rising edge)
                            trng_clk <= 1'b1;
                        end else begin
                            // Clock was high, now on this rising edge we capture data
                            // Read 1 bit and replicate it K=6 times in x_reg
                            // Each TRNG bit occupies 6 consecutive bits in x_reg
                            x_reg[trng_bit_count*6 + 0] <= trng_data;
                            x_reg[trng_bit_count*6 + 1] <= trng_data;
                            x_reg[trng_bit_count*6 + 2] <= trng_data;
                            x_reg[trng_bit_count*6 + 3] <= trng_data;
                            x_reg[trng_bit_count*6 + 4] <= trng_data;
                            x_reg[trng_bit_count*6 + 5] <= trng_data;

                            // Prepare for next bit
                            trng_clk <= 1'b0;
                            trng_bit_count <= trng_bit_count + 1;

                            // Check if we've read all bits
                            if (trng_bit_count == (BLOCKS - 1)) begin
                                have_trng    <= 1'b1;
                                trng_enable  <= 1'b0;
                            end
                        end
                    end
                end

                S_OUT: begin
                    // Latch both rprime and helper_data as registered outputs
                    rprime      <= rprime_reg;     // Output the replicated PUF data
                    helper_data <= helper_data_w;   // Output the helper data
                    complete    <= 1'b1;
                end

                default: ; // no-op
            endcase
        end
    end

    // -----------------------------------------------------------------------------
    // PUF Address Increment Logic (synchronized to puf_clk rising edge)
    // -----------------------------------------------------------------------------
    // Address increments AFTER each read, so:
    // - 1st rising edge: read addr 0, then increment to 1
    // - 2nd rising edge: read addr 1, then increment to 2
    // - ...
    // - 8th rising edge: read addr 7, then increment (but capped at 7)
    always @(posedge puf_clk or negedge rst_n) begin
        if (!rst_n) begin
            puf_addr <= {($clog2(PUF_BYTES)){1'b0}};
        end else begin
            if (puf_enable && puf_addr < (PUF_BYTES - 1)) begin
                // Increment address after each read
                // This happens on rising edge, so PUF sees current addr,
                // then we increment for next cycle
                puf_addr <= puf_addr + 1;
            end
        end
    end

endmodule

// Reed-Muller encoder remains unchanged
module rm_encoder
#(
    parameter integer N = 32,  
    parameter integer K = 6    
)
(
    input  [K-1:0] a,          
    output [N-1:0] codeword    
);
    genvar u;
    generate
        for (u = 0; u < N; u = u + 1) begin : gen_codeword
            wire [K-2:0] v;        
            wire [K-2:0] and_out;  
            wire [K-1:0] xor_tmp;  
            
            assign v = u[K-2:0];
            
            genvar j;
            for (j = 0; j < K-1; j = j + 1) begin : gen_and
                AN2D0 and_gate (.A1(a[j+1]), .A2(v[j]), .Z(and_out[j]));
            end
            
            CKXOR2D0 xor_gate_0 (.A1(a[0]), .A2(and_out[0]), .Z(xor_tmp[0]));
            
            for (j = 1; j < K-1; j = j + 1) begin : gen_xor
                CKXOR2D0 xor_gate (.A1(xor_tmp[j-1]), .A2(and_out[j]), .Z(xor_tmp[j]));
            end
            
            assign codeword[u] = xor_tmp[K-2];
        end
    endgenerate
endmodule