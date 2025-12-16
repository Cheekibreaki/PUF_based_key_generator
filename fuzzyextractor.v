`timescale 1ns/10ps

// -----------------------------------------------------------------------------
// DEVICE_RFE_GEN (Modified with PUF replication and rprime output)
// - PUF_BLOCKS: number of N-bit blocks from PUF (can be less than BLOCKS)
// - BLOCKS: number of RM encoding blocks needed
// - PUF data is replicated/cycled to fill all BLOCKS
// -----------------------------------------------------------------------------
module device_rfe_gen
#(
    parameter integer PUF_BLOCKS = 2,   // Number of N-bit blocks from PUF
    parameter integer BLOCKS     = 22,   // Number of RM encoding blocks
    parameter integer N          = 32,  // fixed at 32 for RM(1,5)
    parameter integer K          = 6    // fixed at 6  for RM(1,5)
)
(
    input  wire                       clk,
    input  wire                       rst_n,
    input  wire                       enable,      // Enable signal to start processing

    // PUF Interface (now takes PUF_BLOCKS*N bits instead of BLOCKS*N)
    output reg                        puf_read_req,
    input  wire [PUF_BLOCKS*N-1:0]   puf_data,    // R' (PUF response) - reduced size
    input  wire                       puf_valid,

    // TRNG Interface (still BLOCKS*K bits)
    output reg                        trng_req,
    input  wire [BLOCKS*K-1:0]        trng_data,   // x (TRNG bits)
    input  wire                       trng_valid,

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
    // Simple handshake + latching FSM (three phases)
    // -----------------------------------------------------------------------------
    localparam [1:0] S_IDLE = 2'd0,
                     S_REQ  = 2'd1,
                     S_OUT  = 2'd2;

    reg [1:0] state, next_state;

    // State register
    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) state <= S_IDLE;
        else        state <= next_state;
    end

    // Next-state logic
    always @(*) begin
        case (state)
            S_IDLE: next_state = (enable_rising ? S_REQ : S_IDLE);
            S_REQ : next_state = (have_puf && have_trng) ? S_OUT : S_REQ;
            S_OUT : next_state = S_IDLE;
            default: next_state = S_IDLE;
        endcase
    end

    // Outputs and latches
    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            puf_read_req  <= 1'b0;
            trng_req      <= 1'b0;
            puf_raw_reg   <= {(PUF_BLOCKS*N){1'b0}};
            x_reg         <= {(BLOCKS*K){1'b0}};
            have_puf      <= 1'b0;
            have_trng     <= 1'b0;
            rprime        <= {(BLOCKS*N){1'b0}};      // Initialize rprime output
            helper_data   <= {(BLOCKS*N){1'b0}};
            complete      <= 1'b0;
        end else begin
            // defaults
            puf_read_req <= 1'b0;
            trng_req     <= 1'b0;
            complete     <= 1'b0;

            case (state)
                S_IDLE: begin
                    have_puf  <= 1'b0;
                    have_trng <= 1'b0;
                    if (enable_rising) begin
                        puf_read_req <= 1'b1;
                        trng_req     <= 1'b1;
                    end
                end

                S_REQ: begin
                    // keep requesting until each arrives
                    if (!have_puf)  puf_read_req <= 1'b1;
                    if (!have_trng) trng_req     <= 1'b1;

                    if (puf_valid) begin
                        puf_raw_reg <= puf_data;  // Store raw PUF data
                        have_puf    <= 1'b1;
                    end
                    if (trng_valid) begin
                        x_reg     <= trng_data;
                        have_trng <= 1'b1;
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