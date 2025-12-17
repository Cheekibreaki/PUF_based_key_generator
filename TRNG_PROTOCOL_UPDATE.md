# TRNG Interface Protocol Update

## Overview

The TRNG (True Random Number Generator) interface has been updated to use a clocked serial read protocol that reads 1 bit per cycle for FE_BLOCKS cycles, with each bit replicated K=6 times.

## New TRNG Interface

### Port Changes

**Old Interface:**
```verilog
output reg                 trng_req,
input  wire [BLOCKS*K-1:0] trng_data,    // All 132 bits at once (22*6)
input  wire                trng_valid
```

**New Interface:**
```verilog
output reg                 trng_clk,      // Clock for TRNG
output reg                 trng_enable,   // Enable signal for TRNG
input  wire                trng_data      // 1-bit data input
```

Where:
- `BLOCKS = 22` (FE_BLOCKS parameter)
- `K = 6` (Reed-Muller encoding parameter)
- Total bits needed: `BLOCKS * K = 132 bits`
- Bits read from TRNG: `BLOCKS = 22 bits` (1 bit per block)
- Each bit replicated: `K = 6 times`

## Read Protocol Timing

The TRNG read protocol operates as follows:

```
Cycle 0:  trng_enable = 1, trng_clk = 0
Cycle 1:  trng_clk = 0→1 (rising edge)
          On rising edge: trng_data outputs bit[0]
Cycle 2:  Capture bit[0], replicate 6 times into x_reg[5:0]
          trng_clk = 1→0
Cycle 3:  trng_clk = 0→1 (rising edge)
          On rising edge: trng_data outputs bit[1]
Cycle 4:  Capture bit[1], replicate 6 times into x_reg[11:6]
          trng_clk = 1→0
...
Continue for BLOCKS=22 cycles total
```

### Detailed Sequence

1. **Cycle 0 (Entry to S_TRNG_READ state):**
   - Assert `trng_enable = 1`
   - Set `trng_clk = 0`
   - Set internal `trng_read_state = 1`

2. **For each bit (2 cycles per bit):**

   **First cycle (clock low → high):**
   - `trng_clk` transitions from 0 → 1
   - TRNG responds to rising edge by outputting 1 random bit

   **Second cycle (capture and replicate):**
   - Capture `trng_data` (1 bit)
   - Replicate this bit K=6 times:
     ```verilog
     for (k_idx = 0; k_idx < K; k_idx = k_idx + 1)
         x_reg[trng_bit_count*K + k_idx] <= trng_data;
     ```
   - Set `trng_clk = 0` (prepare for next bit)
   - Increment `trng_bit_count`

3. **Completion:**
   - When `trng_bit_count == (BLOCKS - 1)`, set `have_trng = 1`
   - Deassert `trng_enable = 0`
   - Transition to next state

## Bit Replication Example

For `BLOCKS=22` and `K=6`:

| TRNG Bit Index | TRNG Bit Value | x_reg Bit Range | x_reg Value |
|----------------|----------------|-----------------|-------------|
| 0 | 1 | [5:0] | 6'b111111 |
| 1 | 0 | [11:6] | 6'b000000 |
| 2 | 1 | [17:12] | 6'b111111 |
| ... | ... | ... | ... |
| 21 | 0 | [131:126] | 6'b000000 |

Each TRNG bit is read once and then replicated 6 times in consecutive bit positions of `x_reg`.

## FSM Changes

### Updated States

```verilog
localparam [2:0] S_IDLE      = 3'd0,  // Idle, waiting for enable
                 S_PUF_READ  = 3'd1,  // Reading from PUF byte-by-byte
                 S_TRNG_READ = 3'd2,  // Reading from TRNG bit-by-bit (RENAMED)
                 S_OUT       = 3'd3;  // Output results
```

### State Flow

```
S_IDLE → (enable rising edge) → S_PUF_READ
S_PUF_READ → (all PUF bytes read) → S_TRNG_READ
S_TRNG_READ → (all TRNG bits read) → S_OUT
S_OUT → S_IDLE
```

## File Changes

### 1. fuzzyextractor.v (device_rfe_gen module)

**Location:** [fuzzyextractor.v:28-32](fuzzyextractor.v#L28-L32)

Updated TRNG interface ports:
```verilog
// TRNG Interface - NEW PROTOCOL
// Read 1 bit per cycle for BLOCKS cycles, replicate each bit K times
output reg                        trng_clk,      // Clock for TRNG
output reg                        trng_enable,   // Enable signal for TRNG
input  wire                       trng_data,     // 1-bit data from TRNG
```

**Location:** [fuzzyextractor.v:52-54](fuzzyextractor.v#L52-L54)

Added TRNG reading state machine variables:
```verilog
// TRNG reading state machine
reg [$clog2(BLOCKS):0]    trng_bit_count;     // Current bit being read (0 to BLOCKS-1)
reg                       trng_read_state;    // 0=wait, 1=reading
```

**Location:** [fuzzyextractor.v:222-259](fuzzyextractor.v#L222-L259)

Implemented S_TRNG_READ state with bit replication logic:
```verilog
S_TRNG_READ: begin
    if (!trng_read_state) begin
        trng_enable     <= 1'b1;
        trng_clk        <= 1'b0;
        trng_read_state <= 1'b1;
    end else begin
        if (!trng_clk) begin
            trng_clk <= 1'b1;  // Rising edge
        end else begin
            // Replicate 1 bit K times
            integer k_idx;
            for (k_idx = 0; k_idx < K; k_idx = k_idx + 1) begin
                x_reg[trng_bit_count*K + k_idx] <= trng_data;
            end

            trng_clk <= 1'b0;
            trng_bit_count <= trng_bit_count + 1;

            if (trng_bit_count == (BLOCKS - 1)) begin
                have_trng   <= 1'b1;
                trng_enable <= 1'b0;
            end
        end
    end
end
```

### 2. secure_key_system.v

**Location:** [secure_key_system.v:30-35](secure_key_system.v#L30-L35)

Updated top-level TRNG interface:
```verilog
// TRNG Interface (exposed from fuzzy extractor) - NEW PROTOCOL
output wire         trng_clk,      // Clock for TRNG
output wire         trng_enable,   // Enable signal for TRNG
input  wire         trng_data,     // 1-bit data from TRNG
```

**Location:** [secure_key_system.v:109-112](secure_key_system.v#L109-L112)

Updated fuzzy extractor TRNG port connections.

### 3. secure_key_system_tb_new.v

**Location:** [secure_key_system_tb_new.v:50-53](secure_key_system_tb_new.v#L50-L53)

Updated testbench TRNG signals:
```verilog
// TRNG interface - NEW PROTOCOL
wire trng_clk;
wire trng_enable;
reg  trng_data;
```

**Location:** [secure_key_system_tb_new.v:145-154](secure_key_system_tb_new.v#L145-L154)

Implemented TRNG simulator:
```verilog
// TRNG Simulator - Responds to clocked read protocol
// Returns 1 random bit per clock cycle
always @(posedge trng_clk) begin
    if (trng_enable) begin
        // On rising edge of trng_clk, provide random 1-bit data
        trng_data <= $random & 1'b1;
    end
end
```

## Timing Analysis

### Read Latency

For BLOCKS=22:
- Entry cycle: 1 cycle
- Per bit: 2 cycles × 22 bits = 44 cycles
- **Total TRNG read time: ~45 cycles**

### Total Key Generation Time

1. PUF read: ~17 cycles (8 bytes × 2 cycles + 1)
2. TRNG read: ~45 cycles (22 bits × 2 cycles + 1)
3. RM encoding + XOR (combinational): 0 cycles
4. PUF hash (SHA3-512): ~500 cycles
5. FSM overhead: ~5 cycles

**Expected total: ~567 cycles**

## Benefits of New TRNG Protocol

1. **Minimal interface** - Only 1 data bit instead of 132 bits
2. **Deterministic timing** - No waiting for external valid signals
3. **Bit replication in hardware** - Each bit replicated 6 times automatically
4. **Reduced TRNG complexity** - TRNG only needs to generate 22 bits instead of 132
5. **Power efficiency** - TRNG runs for fewer cycles (22 vs 132 bit generations)
6. **Realistic modeling** - More closely represents actual TRNG hardware behavior

## Why Replicate Each Bit K Times?

The Reed-Muller encoder expects K=6 bits per block for encoding. By reading 1 bit from TRNG and replicating it 6 times, we:

1. **Reduce TRNG load** - Only need 22 random bits instead of 132
2. **Maintain RM code structure** - Still have 6 bits per block for encoding
3. **Simplify TRNG** - TRNG generates fewer truly random bits
4. **Same helper data size** - Still produces 704-bit (22×32) helper data

This approach assumes that replicating random bits is acceptable for the fuzzy extractor's helper data generation.

## Signal Mapping

| Old Signal | New Signal | Notes |
|------------|------------|-------|
| `trng_req` | `trng_enable` | Now stays high during entire read |
| `trng_data[131:0]` | `trng_data` | Only 1 bit, read bit-by-bit |
| `trng_valid` | (removed) | No handshake, synchronous read |
| - | `trng_clk` | NEW: Clock for TRNG |

## Known Limitations

1. **No error checking** - Assumes TRNG always provides valid data
2. **Fixed replication factor** - K=6 is hardcoded (matches RM(1,5) code)
3. **Sequential reads only** - Cannot burst read multiple bits
4. **Simple replication** - All K bits are identical (may not be cryptographically ideal)

## Future Enhancements

1. Add TRNG error/valid signaling
2. Support configurable replication factor K
3. Implement TRNG health monitoring
4. Add bit diversity within K-bit groups instead of simple replication
5. Support burst/parallel bit reads for higher throughput
