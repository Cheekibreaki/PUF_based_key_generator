# Interface Updates Summary

This document summarizes all interface protocol changes made to the fuzzy extractor module.

## Overview

Both the PUF and TRNG interfaces have been updated from simple handshake protocols to clocked serial read protocols for more realistic hardware modeling and reduced interface complexity.

---

## PUF Interface Update

### Old Protocol (Parallel Handshake)
```verilog
output reg                      puf_read_req,
input  wire [PUF_BLOCKS*N-1:0] puf_data,      // 64 bits all at once
input  wire                     puf_valid
```

### New Protocol (Clocked Serial - 8 bits per cycle)
```verilog
output reg                      puf_clk,       // Clock for PUF
output reg                      puf_enable,    // Enable signal
output reg  [$clog2(PUF_BYTES)-1:0] puf_addr, // Byte address (3 bits for 8 bytes)
input  wire [7:0]              puf_data       // 8-bit data
```

### Key Changes
- **Data width**: 64 bits → 8 bits (byte-oriented)
- **Read method**: Parallel handshake → Clocked serial
- **Total cycles**: ~17 cycles to read 64 bits (8 bytes × 2 cycles + setup)
- **Address**: Added 3-bit byte address for 8-byte PUF

### Timing Diagram
```
Cycle 0: enable=1, addr=0, clk=0
Cycle 1: clk=1 (rising edge)
Cycle 2: Capture data[7:0] → puf_raw_reg[7:0], addr=1, clk=0
Cycle 3: clk=1 (rising edge)
Cycle 4: Capture data[7:0] → puf_raw_reg[15:8], addr=2, clk=0
...
Cycle 16: Final byte captured
```

---

## TRNG Interface Update

### Old Protocol (Parallel Handshake)
```verilog
output reg                 trng_req,
input  wire [BLOCKS*K-1:0] trng_data,     // 132 bits all at once (22×6)
input  wire                trng_valid
```

### New Protocol (Clocked Serial - 1 bit per cycle with replication)
```verilog
output reg                 trng_clk,       // Clock for TRNG
output reg                 trng_enable,    // Enable signal
input  wire                trng_data       // 1-bit data
```

### Key Changes
- **Data width**: 132 bits → 1 bit
- **Read method**: Parallel handshake → Clocked serial with bit replication
- **Total cycles**: ~45 cycles to read 22 bits (22 bits × 2 cycles + setup)
- **Bit replication**: Each TRNG bit replicated K=6 times in x_reg

### Timing Diagram
```
Cycle 0: enable=1, clk=0
Cycle 1: clk=1 (rising edge)
Cycle 2: Capture bit → replicate to x_reg[5:0], clk=0
Cycle 3: clk=1 (rising edge)
Cycle 4: Capture bit → replicate to x_reg[11:6], clk=0
...
Cycle 44: Final bit captured and replicated to x_reg[131:126]
```

### Bit Replication Logic
```verilog
// Each TRNG bit is replicated K=6 times
for (k_idx = 0; k_idx < K; k_idx = k_idx + 1) begin
    x_reg[trng_bit_count*K + k_idx] <= trng_data;
end
```

Example:
- TRNG outputs bit 0 = 1 → x_reg[5:0] = 6'b111111
- TRNG outputs bit 1 = 0 → x_reg[11:6] = 6'b000000
- TRNG outputs bit 2 = 1 → x_reg[17:12] = 6'b111111

---

## FSM State Updates

### Old FSM (3 states)
```verilog
S_IDLE → S_REQ → S_OUT
```

### New FSM (4 states)
```verilog
S_IDLE → S_PUF_READ → S_TRNG_READ → S_OUT
```

### State Descriptions

| State | Duration | Activity |
|-------|----------|----------|
| **S_IDLE** | 1 cycle | Wait for enable signal, initialize counters |
| **S_PUF_READ** | ~17 cycles | Read 8 bytes from PUF (2 cycles per byte) |
| **S_TRNG_READ** | ~45 cycles | Read 22 bits from TRNG (2 cycles per bit) |
| **S_OUT** | 1 cycle | Output rprime and helper_data, assert complete |

**Total fuzzy extractor latency**: ~64 cycles (vs unknown/variable in old design)

---

## Top-Level Module Changes

### secure_key_system.v

**Old PUF Interface:**
```verilog
output wire         puf_read_req,
input  wire [63:0]  puf_data,
input  wire         puf_valid,
```

**New PUF Interface:**
```verilog
output wire                         puf_clk,
output wire                         puf_enable,
output wire [$clog2(8)-1:0]        puf_addr,    // 3 bits
input  wire [7:0]                   puf_data,
```

**Old TRNG Interface:**
```verilog
output wire         trng_req,
input  wire [131:0] trng_data,
input  wire         trng_valid,
```

**New TRNG Interface:**
```verilog
output wire         trng_clk,
output wire         trng_enable,
input  wire         trng_data,
```

---

## Testbench Changes

### PUF Simulator (Memory-Based)

**Old Approach:**
```verilog
always @(posedge clk) begin
    if (puf_read_req && !puf_valid) begin
        repeat(2) @(posedge clk);
        puf_data <= {$random, $random};  // 64 bits
        puf_valid <= 1'b1;
        @(posedge clk);
        puf_valid <= 1'b0;
    end
end
```

**New Approach (Memory-Mapped):**
```verilog
// Initialize PUF memory
reg [7:0] puf_memory [0:7];
initial begin
    for (i = 0; i < 8; i = i + 1)
        puf_memory[i] = $random & 8'hFF;
end

// Respond to clocked reads
always @(posedge puf_clk) begin
    if (puf_enable)
        puf_data <= puf_memory[puf_addr];
end
```

### TRNG Simulator (Bit Generator)

**Old Approach:**
```verilog
always @(posedge clk) begin
    if (trng_req && !trng_valid) begin
        repeat(2) @(posedge clk);
        trng_data <= {$random, ..., $random};  // 132 bits
        trng_valid <= 1'b1;
        @(posedge clk);
        trng_valid <= 1'b0;
    end
end
```

**New Approach (1-bit per clock):**
```verilog
// Respond to clocked reads
always @(posedge trng_clk) begin
    if (trng_enable)
        trng_data <= $random & 1'b1;  // 1 bit
end
```

---

## Performance Comparison

| Metric | Old Design | New Design | Notes |
|--------|------------|------------|-------|
| **PUF data bus width** | 64 bits | 8 bits | 8× reduction |
| **TRNG data bus width** | 132 bits | 1 bit | 132× reduction |
| **PUF read cycles** | Variable (handshake) | ~17 cycles | Deterministic |
| **TRNG read cycles** | Variable (handshake) | ~45 cycles | Deterministic |
| **Total FE cycles** | Unknown | ~64 cycles | Predictable timing |
| **Total signals** | 8 signals | 9 signals | Added clocks |
| **Interface complexity** | Medium (handshake) | Low (clocked) | Simpler logic |

---

## Benefits of New Protocols

### 1. Reduced Interface Complexity
- **Narrower data buses**: 8-bit PUF, 1-bit TRNG vs 64-bit, 132-bit
- **Fewer wires**: Especially important for TRNG (132 → 1 bit)
- **Simpler external devices**: PUF and TRNG only need to provide narrow data

### 2. Deterministic Timing
- **No waiting**: No handshake uncertainty
- **Predictable latency**: Exactly 17 cycles for PUF, 45 for TRNG
- **Easier verification**: Fixed timing makes testbenches simpler

### 3. Realistic Hardware Modeling
- **Memory-mapped PUF**: Byte-addressable like SRAM PUF
- **Serial TRNG**: Realistic for entropy sources that generate bits serially
- **Standard protocols**: Similar to SPI, I2C byte/bit interfaces

### 4. Power Efficiency
- **Reduced TRNG load**: Only 22 true random bits needed (vs 132)
- **Lower pin count**: Fewer pins = less routing, lower power
- **Clocked interface**: Can be gated when not in use

---

## Migration Guide

### For Existing Designs

**Step 1:** Update fuzzyextractor.v
- Already done - new module ports and FSM

**Step 2:** Update top-level (secure_key_system.v)
- Replace PUF interface: `puf_read_req/puf_data[63:0]/puf_valid` → `puf_clk/puf_enable/puf_addr/puf_data[7:0]`
- Replace TRNG interface: `trng_req/trng_data[131:0]/trng_valid` → `trng_clk/trng_enable/trng_data`

**Step 3:** Update PUF simulator
- Replace handshake logic with memory-mapped byte reads
- Initialize 8-byte memory array
- Respond to `puf_clk` rising edges

**Step 4:** Update TRNG simulator
- Replace handshake logic with bit generation
- Respond to `trng_clk` rising edges
- Output 1 random bit per clock

**Step 5:** Update testbenches
- Use `secure_key_system_tb_new.v` as reference
- Update signal declarations
- Update DUT port connections

---

## Files Modified

1. **[fuzzyextractor.v](fuzzyextractor.v)** - Core module with new PUF/TRNG protocols
2. **[secure_key_system.v](secure_key_system.v)** - Top-level interface updates
3. **[secure_key_system_tb_new.v](secure_key_system_tb_new.v)** - New testbench with simulators

## Documentation Files

1. **[PUF_PROTOCOL_UPDATE.md](PUF_PROTOCOL_UPDATE.md)** - Detailed PUF interface documentation
2. **[TRNG_PROTOCOL_UPDATE.md](TRNG_PROTOCOL_UPDATE.md)** - Detailed TRNG interface documentation
3. **[INTERFACE_UPDATES_SUMMARY.md](INTERFACE_UPDATES_SUMMARY.md)** - This file

---

## Testing

Run the new testbench:
```bash
vlog secure_key_system_tb_new.v secure_key_system.v fuzzyextractor.v \
     hmac_top.v hmac_controller.v keccak_top.v keccak.v f_permutation.v \
     round.v rconst.v padder.v padder1.v

vsim -c secure_key_system_tb_new -do "run -all; quit"
```

Expected results:
- Key generation completes in ~567 cycles
- Helper data generated correctly
- HMAC operations work as before

---

## Conclusion

Both interfaces have been successfully updated to use clocked serial protocols:
- **PUF**: Byte-by-byte reading (8 bits/cycle)
- **TRNG**: Bit-by-bit reading with 6× replication (1 bit/cycle)

These changes result in:
- ✅ Simpler interfaces (fewer wires)
- ✅ Deterministic timing
- ✅ More realistic hardware modeling
- ✅ Lower power consumption potential
- ✅ Easier testing and verification
