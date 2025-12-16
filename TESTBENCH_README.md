# HMAC Testbench Suite

This directory contains a comprehensive testbench suite for the HMAC-SHA3-512 hardware design with PUF key generation.

## Testbench Files

### 1. `hmac_tb.v` - Basic Functional Test
**Purpose**: Simple smoke test with 2 basic test cases
**Test Count**: 2 tests
**Runtime**: ~5-10 seconds (simulation time)

**Tests Covered**:
- Basic PUF key generation
- Simple 3-word HMAC computation

**When to Use**: Quick sanity check after making code changes

```bash
# Example compilation (Icarus Verilog)
iverilog -o hmac_tb.vvp hmac_tb.v hmac_top.v hmac_controller.v keccak_top.v keccak.v padder.v f_permutation.v round.v rconst.v padder1.v
vvp hmac_tb.vvp
```

---

### 2. `hmac_tb_comprehensive.v` - Comprehensive Functional Test
**Purpose**: Thorough functional verification with varied message lengths
**Test Count**: 15 tests
**Runtime**: ~1-2 minutes (simulation time)

**Tests Covered**:
1. Basic PUF key generation
2. HMAC with single-word message
3. HMAC with 3-word message
4. HMAC with exactly 18 words (full rate block)
5. HMAC with 36 words (two full blocks)
6. HMAC with 19 words (1 full + 1 partial block)
7. HMAC with single zero word
8. HMAC with all 0xFF pattern
9. Regenerate PUF key with different input
10. HMAC with new key
11. Back-to-back HMAC operations
12. Large message (50 words)
13. Alternating 0xAAAA/0x5555 pattern
14. Reset during PUF operation
15. Determinism check (same input → same output)

**When to Use**: Before releasing code, after major changes

```bash
# Example compilation
iverilog -o hmac_tb_comprehensive.vvp hmac_tb_comprehensive.v hmac_top.v hmac_controller.v keccak_top.v keccak.v padder.v f_permutation.v round.v rconst.v padder1.v
vvp hmac_tb_comprehensive.vvp
```

**Expected Output**:
```
========================================
  Test Summary
========================================
  Total Tests:  15
  Passed:       <count>
  Failed:       0
========================================

  *** ALL TESTS PASSED ***
```

---

### 3. `hmac_tb_stress.v` - Stress and Edge Case Testing
**Purpose**: Stress testing with edge cases, long messages, and rapid operations
**Test Count**: 15 tests
**Runtime**: ~3-5 minutes (simulation time)

**Tests Covered**:
1. Rapid PUF regeneration (10 iterations)
2. Very long message (100 words)
3. Burst HMAC operations (20 short messages)
4. Slow message streaming with random gaps
5. Multiple 18-word blocks (54 words total)
6. Alternating PUF and HMAC operations
7. Boundary testing (17, 18, 19 word messages)
8. Zero PUF input
9. All-ones PUF input
10. Walking 1's PUF pattern
11. Random data stress (10 iterations with random lengths)
12. Sequential counter message (30 words)
13. msg_ready handshake verification
14. Back-to-back with no idle cycles
15. Very large message (200 words)

**When to Use**: Final validation, finding corner case bugs

```bash
# Example compilation
iverilog -o hmac_tb_stress.vvp hmac_tb_stress.v hmac_top.v hmac_controller.v keccak_top.v keccak.v padder.v f_permutation.v round.v rconst.v padder1.v
vvp hmac_tb_stress.vvp
```

---

### 4. `hmac_tb_protocol.v` - Protocol and Timing Verification
**Purpose**: Verify signal timing, handshakes, and protocol compliance
**Test Count**: 11 tests
**Runtime**: ~1-2 minutes (simulation time)

**Tests Covered**:
1. Verify `done` is single-cycle pulse (PUF)
2. Verify `done` is single-cycle pulse (HMAC)
3. Verify `puf_key` persistence across operations
4. `msg_ready` handshake protocol
5. `msg_ready` at 18-word boundary
6. Verify no glitches on `done`
7. Start signal timing behavior
8. HMAC output stability after done
9. Reset during operation
10. Measure PUF operation latency
11. Measure HMAC latency for various message lengths

**When to Use**: Debugging timing issues, verifying protocol correctness

```bash
# Example compilation
iverilog -o hmac_tb_protocol.vvp hmac_tb_protocol.v hmac_top.v hmac_controller.v keccak_top.v keccak.v padder.v f_permutation.v round.v rconst.v padder1.v
vvp hmac_tb_protocol.vvp
```

**Key Metrics Reported**:
- PUF operation latency (cycles)
- HMAC latency vs message length
- Signal pulse widths
- Handshake timing

---

## Quick Start Guide

### Running All Tests

```bash
#!/bin/bash
# Run all testbenches

echo "Running basic testbench..."
iverilog -o hmac_tb.vvp hmac_tb.v hmac_top.v hmac_controller.v keccak_top.v keccak.v padder.v f_permutation.v round.v rconst.v padder1.v
vvp hmac_tb.vvp

echo "Running comprehensive testbench..."
iverilog -o hmac_tb_comprehensive.vvp hmac_tb_comprehensive.v hmac_top.v hmac_controller.v keccak_top.v keccak.v padder.v f_permutation.v round.v rconst.v padder1.v
vvp hmac_tb_comprehensive.vvp

echo "Running stress testbench..."
iverilog -o hmac_tb_stress.vvp hmac_tb_stress.v hmac_top.v hmac_controller.v keccak_top.v keccak.v padder.v f_permutation.v round.v rconst.v padder1.v
vvp hmac_tb_stress.vvp

echo "Running protocol testbench..."
iverilog -o hmac_tb_protocol.vvp hmac_tb_protocol.v hmac_top.v hmac_controller.v keccak_top.v keccak.v padder.v f_permutation.v round.v rconst.v padder1.v
vvp hmac_tb_protocol.vvp

echo "All tests complete!"
```

### Using ModelSim/QuestaSim

```tcl
# Compile design files
vlog hmac_top.v hmac_controller.v keccak_top.v keccak.v padder.v f_permutation.v round.v rconst.v padder1.v

# Compile and run testbench
vlog hmac_tb_comprehensive.v
vsim -c hmac_tb_comprehensive -do "run -all; quit"
```

### Using Vivado Simulator

```tcl
# Create project and add files
create_project hmac_test ./hmac_test -part xc7a35ticsg324-1L

add_files {
    hmac_top.v
    hmac_controller.v
    keccak_top.v
    keccak.v
    padder.v
    f_permutation.v
    round.v
    rconst.v
    padder1.v
}

add_files -fileset sim_1 hmac_tb_comprehensive.v

# Run simulation
launch_simulation
run all
```

---

## Understanding Test Results

### Pass/Fail Criteria

Each testbench reports:
- **Test Count**: Total number of test cases executed
- **Pass Count**: Number of successful tests
- **Fail/Error Count**: Number of failures

### Common Issues and Debugging

#### Issue: Timeout Errors
```
[ERROR] Timeout waiting for done signal after XXXX cycles!
```
**Possible Causes**:
- FSM stuck in a state
- SHA core not processing data
- Flow control deadlock

**Debug Steps**:
1. Check waveforms around the timeout
2. Verify `msg_ready` handshake
3. Look for `buffer_full` backpressure issues

#### Issue: HMAC Values Don't Change
```
[WARN] HMAC value unchanged from previous test
```
**Possible Causes**:
- Key not being used
- Message not being sent correctly
- Core not restarting properly

**Debug Steps**:
1. Verify `start_hmac` pulse
2. Check message words are different
3. Verify `done` signal pulsed

#### Issue: Done Pulse Width ≠ 1
```
[WARN] done pulse width is not 1 cycle!
```
**Possible Causes**:
- FSM not transitioning correctly from S_DONE to S_IDLE
- Combinational logic issue in done signal

**Debug Steps**:
1. Check FSM state transitions
2. Verify `done` is only asserted in S_DONE state

---

## Waveform Analysis

All testbenches generate VCD files for waveform viewing:

### GTKWave (Open Source)
```bash
gtkwave hmac_tb_comprehensive.vcd &
```

**Recommended Signals to View**:
```
hmac_tb_comprehensive
├── clk
├── reset
├── start_puf
├── start_hmac
├── done
├── puf_key[63:0]  (lower bits for readability)
├── hmac_value[63:0]
├── msg_word
├── msg_valid
├── msg_ready
└── dut
    └── u_ctrl
        ├── state[4:0]
        ├── send_words_left
        ├── msg_count
        └── sha_out_ready
```

### ModelSim
```tcl
vsim hmac_tb_comprehensive
add wave -recursive /*
run -all
```

---

## Test Coverage Summary

| Feature | Basic | Comprehensive | Stress | Protocol |
|---------|-------|---------------|--------|----------|
| PUF Generation | ✓ | ✓ | ✓ | ✓ |
| Single Word HMAC | - | ✓ | ✓ | ✓ |
| Multi-word HMAC | ✓ | ✓ | ✓ | ✓ |
| Full Rate Block (18 words) | - | ✓ | ✓ | ✓ |
| Multiple Blocks | - | ✓ | ✓ | ✓ |
| Partial Blocks | - | ✓ | ✓ | ✓ |
| Back-to-back Operations | - | ✓ | ✓ | ✓ |
| Very Long Messages | - | ✓ | ✓ | - |
| Edge Cases (0, all-1s) | - | ✓ | ✓ | - |
| Determinism Check | - | ✓ | - | - |
| Handshake Protocol | - | - | ✓ | ✓ |
| Signal Timing | - | - | - | ✓ |
| Latency Measurement | - | - | - | ✓ |
| Reset Testing | - | ✓ | - | ✓ |
| Random Data | - | - | ✓ | - |

---

## Regression Testing

Recommended test flow for code changes:

1. **Small changes**: Run `hmac_tb.v` (quick check)
2. **Logic changes**: Run `hmac_tb_comprehensive.v`
3. **FSM/Control changes**: Run `hmac_tb_protocol.v`
4. **Before commit**: Run all testbenches
5. **Before release**: Run all testbenches + manual waveform review

---

## Adding New Tests

To add a new test case to `hmac_tb_comprehensive.v`:

```verilog
// ============================================================
// Test XX: Description of Test
// ============================================================
test_num = test_num + 1;
$display("\n[TEST %0d] Your Test Description", test_num);
$display("----------------------------------------");

// Your test code here
// ...

// Check results
if (/* condition */) begin
    $display("  [PASS] Test passed");
    pass_count = pass_count + 1;
end else begin
    $display("  [FAIL] Test failed");
    fail_count = fail_count + 1;
end
```

---

## Known Limitations

1. **Simulation Time**: Large message tests can take significant simulation time
2. **Random Seed**: Some tests use `$random` - may want to add seed control for reproducibility
3. **Timing**: Tests don't verify setup/hold times (use STA tools for that)
4. **Coverage**: Functional tests only - no formal verification included

---

## Support and Issues

If tests fail unexpectedly:
1. Check waveforms first
2. Review the specific test case description
3. Enable detailed debug messages (modify `$display` statements)
4. Compare against known-good simulation results

---

## Test Automation

For CI/CD integration, return codes can be used:

```bash
#!/bin/bash
# run_tests.sh

FAIL=0

for tb in hmac_tb hmac_tb_comprehensive hmac_tb_stress hmac_tb_protocol; do
    echo "Running $tb..."
    iverilog -o $tb.vvp $tb.v hmac_top.v hmac_controller.v keccak_top.v keccak.v \
             padder.v f_permutation.v round.v rconst.v padder1.v

    if vvp $tb.vvp | grep -q "FAIL\|ERROR"; then
        echo "$tb: FAILED"
        FAIL=1
    else
        echo "$tb: PASSED"
    fi
done

exit $FAIL
```

---

**Last Updated**: 2025-12-16
**Version**: 1.0
