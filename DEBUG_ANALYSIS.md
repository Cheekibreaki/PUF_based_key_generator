# Debug Analysis - Secure Key System Test Failures

## Problem Summary

The `secure_key_system_tb` shows 5 out of 8 tests failing with these symptoms:
1. HMAC operations completing in only 48 cycles (expected: 500-1000 cycles)
2. All HMAC outputs identical regardless of input message
3. Key regeneration completing in 0 cycles (fuzzy extractor not re-running)

## Root Causes Identified

### 1. **CRITICAL: Race Condition in keccak_top.v** (FIXED)

**Location:** [keccak_top.v:82-125](keccak_top.v#L82-L125)

**Problem:**
```verilog
// BEFORE (BUGGY):
if (mode_puf) begin
    // PUF mode logic
end

if (mode_block) begin
    // Block mode logic
end
```

Both `mode_puf` and `mode_block` could be high simultaneously, causing:
- Both blocks execute in the same clock cycle
- Multiple drivers for `ke_in`, `ke_in_ready`, `ke_is_last`, `busy_r`
- Unpredictable behavior and wrong outputs

**Fix Applied:**
```verilog
// AFTER (FIXED):
if (mode_puf && !mode_block) begin
    // PUF mode logic
end
else if (mode_block && !mode_puf) begin
    // Block mode logic
end
```

Now the modes are mutually exclusive, preventing the race condition.

### 2. **Suspected: Keccak State Not Clearing Between Operations**

The previous fix in `f_permutation.v` added state reset logic, but it may not be working correctly in the integrated system. The `sha_init` signal should reset the Keccak sponge state for each new hash operation.

**Key Signal Flow:**
- `hmac_controller.v` asserts `sha_init` in states `S_PUF_INIT` and `S_MAC_INIT`
- `keccak_top.v` passes `reset | sha_init` to `keccak` module
- `keccak.v` should pass this to `f_permutation.v`

Need to verify this signal propagates correctly through all levels.

### 3. **Key Regeneration Issue**

**Location:** [secure_key_system.v:191-196](secure_key_system.v#L191-L196)

When in `S_READY` state, asserting `start_keygen` should transition back to `S_FE_REQUEST`, but the testbench shows 0 cycles. This suggests:
- Either the transition isn't happening
- Or the fuzzy extractor completes instantly (cached values?)
- Or the testbench isn't actually triggering regeneration correctly

## Debug Tools Created

### Debug Testbench: `secure_key_system_tb_debug.v`

Features:
1. **FSM State Monitoring**: Displays state transitions for both main FSM and HMAC controller
2. **Cycle Counting**: Tracks exact cycle counts for each operation
3. **Signal Tracing**: Logs key signals (`sha_init`, `start_hmac`, `hmac_done`, `sha_out_ready`)
4. **Message Tracking**: Shows when message words are sent
5. **Waveform Generation**: Creates VCD file for detailed inspection

Usage:
```bash
vlog secure_key_system_tb_debug.v secure_key_system.v hmac_top.v hmac_controller.v keccak_top.v keccak.v f_permutation.v round.v rconst.v padder.v padder1.v device_rfe_gen.v
vsim -c secure_key_system_tb_debug -do "run -all; quit"
```

Expected output will show:
- Exact state transitions with timestamps
- Cycle-by-cycle signal changes
- Where the FSM gets stuck or completes too quickly

## Investigation Plan

### Step 1: Run Debug Testbench
Run `secure_key_system_tb_debug` to see:
- Which HMAC controller states are being entered
- How many cycles spent in each state
- Whether `sha_init` pulses correctly
- Whether `sha_out_ready` appears at expected times

### Step 2: Verify Keccak State Reset
Check if the `was_idle` logic in `f_permutation.v` correctly detects new hash operations:
- Should see `new_hash_start` pulse at the beginning of each operation
- Keccak state should be cleared to zeros when this happens

### Step 3: Check HMAC Controller FSM
The HMAC should go through these states for a single-word message:
1. `S_IDLE`
2. `S_MAC_INIT` (1 cycle - asserts `sha_init`)
3. `S_IPAD_LOAD` (1 cycle - loads K^ipad into send buffer)
4. `S_IPAD_SEND` (18+ cycles - sends 18 words to Keccak)
5. `S_MSG_COLLECT` (waits for message words)
6. `S_MSG_LOAD` (1 cycle)
7. `S_MSG_SEND` (1+ cycles)
8. `S_MAC_WAIT` (wait for Keccak to complete - should be ~500+ cycles for 24 rounds)
9. `S_DONE` (1 cycle)

If it's completing in 48 cycles, it's likely skipping `S_MAC_WAIT` or `S_IPAD_SEND`.

### Step 4: Message Collection Timing
The testbench might be sending messages before the HMAC controller is ready:
- Check if `msg_ready` is being honored
- Verify message words are buffered correctly in `hmac_controller.v:124-131`

## Expected Behavior vs Observed

| Operation | Expected Cycles | Observed Cycles | Status |
|-----------|----------------|-----------------|--------|
| Key Generation | ~500-1000 | 83 | ⚠️ Fast but acceptable |
| HMAC Single Word | ~500-1000 | 48 | ❌ Too fast |
| HMAC Multi-Word | ~500-1000 | 48 | ❌ Too fast |
| Key Regeneration | ~500-1000 | 0 | ❌ Not running |

## Key Signals to Monitor

1. **hmac_controller state** - Should progress through all states
2. **sha_init** - Should pulse once per hash operation
3. **sha_busy** - Should stay high during Keccak processing
4. **sha_out_ready** - Should pulse when hash completes
5. **mode_puf / mode_block** - Should be mutually exclusive (now fixed)
6. **new_hash_start** (in f_permutation) - Should pulse for each new hash

## Next Steps

1. ✅ **DONE**: Fix race condition in `keccak_top.v`
2. ⏭️ **TODO**: Run `secure_key_system_tb_debug.v` to capture detailed trace
3. ⏭️ **TODO**: Analyze state transitions to find where FSM is short-circuiting
4. ⏭️ **TODO**: Verify Keccak state reset is working in integrated system
5. ⏭️ **TODO**: Fix any additional issues found

## Files Modified

1. `keccak_top.v` - Fixed mode race condition (lines 82-125)
2. Created `secure_key_system_tb_debug.v` - Debug testbench with detailed tracing
3. Created this `DEBUG_ANALYSIS.md` - Documentation of findings

## Additional Notes

The 48-cycle completion time is suspicious because:
- Keccak needs 24 rounds × ~2 cycles = ~48 cycles for the permutation itself
- But HMAC requires multiple Keccak calls: one for ipad block, possibly more for message blocks
- The fact that it's exactly 48 cycles suggests it might be running only ONE Keccak permutation
- This could mean the FSM is bypassing the HMAC logic and just hashing once

The identical outputs suggest that either:
1. The Keccak state isn't being reset, so all operations see stale data
2. The message data isn't being XORed into the state correctly
3. The output is being captured from the wrong stage (PUF key instead of HMAC result)

Run the debug testbench to confirm these hypotheses.
