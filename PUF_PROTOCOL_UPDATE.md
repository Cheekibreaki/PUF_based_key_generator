# PUF Interface Protocol Update

## Overview

The fuzzy extractor module has been updated to use a new PUF read protocol that reads data byte-by-byte using a clocked interface instead of the previous simple valid/data handshake.

## New PUF Interface

### Port Changes

**Old Interface:**
```verilog
output reg                        puf_read_req,
input  wire [PUF_BLOCKS*N-1:0]   puf_data,     // All bits at once
input  wire                       puf_valid
```

**New Interface:**
```verilog
output reg                        puf_clk,      // Clock for PUF
output reg                        puf_enable,   // Enable signal for PUF
output reg  [$clog2(PUF_BYTES)-1:0] puf_addr,   // Byte address (0 to PUF_BYTES-1)
input  wire [7:0]                 puf_data      // 8-bit data input
```

Where `PUF_BYTES = (PUF_BLOCKS * N) / 8`
- For PUF_BLOCKS=2, N=32: PUF_BYTES = 64/8 = 8 bytes
- Address width = $clog2(8) = 3 bits

## Read Protocol Timing

The PUF read protocol operates as follows:

```
Cycle 0:  puf_enable = 1, puf_addr = 0, puf_clk = 0
Cycle 1:  puf_clk = 0→1 (rising edge)
          On rising edge: puf_data outputs byte[0]
Cycle 2:  puf_clk = 1, capture data into puf_raw_reg[7:0]
          puf_clk = 1→0, puf_addr = 1
Cycle 3:  puf_clk = 0→1 (rising edge)
          On rising edge: puf_data outputs byte[1]
Cycle 4:  puf_clk = 1, capture data into puf_raw_reg[15:8]
          puf_clk = 1→0, puf_addr = 2
...
Continue until all PUF_BYTES are read
```

### Detailed Sequence

1. **Cycle 0 (Entry to S_PUF_READ state):**
   - Assert `puf_enable = 1`
   - Set `puf_addr = 0`
   - Set `puf_clk = 0`
   - Set internal `puf_read_state = 1`

2. **For each byte (2 cycles per byte):**

   **First cycle (clock low → high):**
   - `puf_clk` transitions from 0 → 1
   - PUF responds to rising edge by outputting data at current address

   **Second cycle (capture and advance):**
   - Capture `puf_data` into `puf_raw_reg[byte_count*8 +: 8]`
   - Set `puf_clk = 0` (prepare for next byte)
   - Increment `puf_byte_count`
   - Increment `puf_addr`

3. **Completion:**
   - When `puf_byte_count == (PUF_BYTES - 1)`, set `have_puf = 1`
   - Deassert `puf_enable = 0`
   - Transition to next state

## FSM Changes

### New States

```verilog
localparam [2:0] S_IDLE     = 3'd0,  // Idle, waiting for enable
                 S_PUF_READ = 3'd1,  // NEW: Reading from PUF byte-by-byte
                 S_REQ_TRNG = 3'd2,  // Request TRNG data
                 S_OUT      = 3'd3;  // Output results
```

### State Flow

```
S_IDLE → (enable rising edge) → S_PUF_READ
S_PUF_READ → (all bytes read) → S_REQ_TRNG
S_REQ_TRNG → (TRNG valid) → S_OUT
S_OUT → S_IDLE
```

## File Changes

### 1. fuzzyextractor.v (device_rfe_gen module)

**Location:** [fuzzyextractor.v:9-37](fuzzyextractor.v#L9-L37)

- Updated module ports to use new PUF interface
- Added PUF byte-by-byte reading logic
- Changed FSM from 2-bit (3 states) to 3-bit (4 states)
- Implemented clock generation and address sequencing

**Key Implementation:** [fuzzyextractor.v:174-209](fuzzyextractor.v#L174-L209)
```verilog
S_PUF_READ: begin
    if (!puf_read_state) begin
        // Initialize: assert enable, set addr=0, clock low
        puf_enable     <= 1'b1;
        puf_addr       <= puf_byte_count[$clog2(PUF_BYTES)-1:0];
        puf_clk        <= 1'b0;
        puf_read_state <= 1'b1;
    end else begin
        // Toggle clock and capture data
        if (!puf_clk) begin
            puf_clk <= 1'b1;  // Rising edge
        end else begin
            // Capture on this rising edge
            puf_raw_reg[puf_byte_count*8 +: 8] <= puf_data;
            puf_clk <= 1'b0;
            puf_byte_count <= puf_byte_count + 1;
            puf_addr <= puf_addr + 1;

            if (puf_byte_count == (PUF_BYTES - 1)) begin
                have_puf <= 1'b1;
                puf_enable <= 1'b0;
            end
        end
    end
end
```

### 2. secure_key_system.v

**Location:** [secure_key_system.v:23-28](secure_key_system.v#L23-L28)

Updated top-level PUF interface:
```verilog
output wire                         puf_clk,
output wire                         puf_enable,
output wire [$clog2((PUF_BLOCKS*32)/8)-1:0] puf_addr,
input  wire [7:0]                   puf_data
```

**Location:** [secure_key_system.v:103-107](secure_key_system.v#L103-L107)

Updated fuzzy extractor instantiation to connect new PUF ports.

### 3. secure_key_system_tb_new.v (NEW FILE)

Created new testbench with PUF memory simulation:

**PUF Memory Simulator:** [secure_key_system_tb_new.v:117-126](secure_key_system_tb_new.v#L117-L126)
```verilog
// Simulates PUF memory responding to clocked read protocol
always @(posedge puf_clk) begin
    if (puf_enable) begin
        if (puf_addr < PUF_BYTES) begin
            puf_data <= puf_memory[puf_addr];
        end else begin
            puf_data <= 8'h00;
        end
    end
end
```

The PUF memory is initialized with random values at simulation start.

## Testbench Usage

### Old Testbench (obsolete)
```bash
# DO NOT USE - uses old PUF protocol
vlog secure_key_system_tb.v ...
```

### New Testbench
```bash
vlog secure_key_system_tb_new.v secure_key_system.v fuzzyextractor.v hmac_top.v hmac_controller.v keccak_top.v keccak.v f_permutation.v round.v rconst.v padder.v padder1.v
vsim -c secure_key_system_tb_new -do "run -all; quit"
```

## Timing Analysis

### Read Latency

For PUF_BLOCKS=2 (8 bytes):
- Entry cycle: 1 cycle
- Per byte: 2 cycles × 8 bytes = 16 cycles
- **Total PUF read time: ~17 cycles**

This is significantly faster than waiting for external handshaking.

### Total Key Generation Time

1. PUF read: ~17 cycles
2. TRNG request/response: ~3 cycles
3. RM encoding + XOR (combinational): 0 cycles
4. PUF hash (SHA3-512): ~500 cycles
5. FSM overhead: ~5 cycles

**Expected total: ~525 cycles** (vs previous ~83 cycles suggests previous implementation had issues)

## Benefits

1. **Deterministic timing** - No waiting for external valid signals
2. **Memory-like interface** - Standard byte-addressable read protocol
3. **Smaller PUF interface** - Only 8 data bits instead of 64
4. **Parameterizable** - Address width automatically adjusts to PUF size
5. **Realistic** - More closely models actual SRAM PUF read protocols

## Migration Notes

### For existing designs using the old protocol:

1. **Update top-level ports** to use new 4-wire PUF interface
2. **Replace PUF simulator** with clocked memory model
3. **Use new testbench** `secure_key_system_tb_new.v`
4. **No changes needed** to HMAC or other modules - only fuzzy extractor affected

### Signal Mapping

| Old Signal | New Signal | Notes |
|------------|------------|-------|
| `puf_read_req` | `puf_enable` | Now stays high during entire read |
| `puf_data[63:0]` | `puf_data[7:0]` | Only 8 bits, read byte-by-byte |
| `puf_valid` | (removed) | No handshake, synchronous read |
| - | `puf_clk` | NEW: Clock for PUF |
| - | `puf_addr[2:0]` | NEW: Byte address (width varies) |

## Known Limitations

1. **No error checking** - Assumes PUF always provides valid data
2. **Fixed 8-bit width** - Cannot be parameterized (could be future enhancement)
3. **Sequential reads only** - Cannot read random access (address increments)
4. **No burst mode** - Could optimize by reading multiple bytes per cycle

## Future Enhancements

1. Add error/valid signaling from PUF
2. Support configurable data width (4, 8, 16, 32 bits)
3. Add burst read mode for faster throughput
4. Implement retry logic for PUF read failures
5. Add CRC/parity checking on PUF data
