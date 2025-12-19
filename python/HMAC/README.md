# HMAC-SHA3-512 Python Implementation

This directory contains a Python software implementation of the HMAC-SHA3-512 algorithm that matches the hardware implementation in `hmac_controller.v`.

## Algorithm

The hardware implements a **simplified HMAC**:

```
HMAC = SHA3-512((K ⊕ ipad) || message)
```

Where:
- **K**: 512-bit key (derived from PUF)
- **ipad**: 0x36 repeated 72 times (576 bits)
- **K_padded**: K with 64 zero bits appended (to make 576 bits)
- **||**: Concatenation

## Differences from Standard HMAC

Standard HMAC-SHA3 uses:
```
HMAC = SHA3(opad || SHA3(ipad || message))
```

This implementation uses a simplified version (single hash):
```
HMAC = SHA3(ipad || message)
```

This matches the hardware implementation in `hmac_controller.v` lines 49-54.

## Files

- `hmac_sha3_512.py`: Main implementation
- `verify_hmac.py`: Verification script to compare with hardware simulation results
- `README.md`: This file

## Usage

### Basic Usage

```python
from hmac_sha3_512 import HMAC_SHA3_512

# Initialize with 512-bit key (as integer or bytes)
key = 0x0123...CDEF  # 512-bit hex value
hmac = HMAC_SHA3_512(key)

# Compute HMAC for a message
message = [0xDEADBEEF, 0xCAFEBABE]  # List of 32-bit words
hmac_value = hmac.compute(message)  # Returns 64 bytes

# Or get hex string
hmac_hex = hmac.compute_hex(message)  # Returns 128-character hex string
```

### Run Test

```bash
python hmac_sha3_512.py
```

## Hardware Matching

The implementation matches the hardware behavior:

1. **Key Padding** (line 150 in `hmac_controller.v`):
   ```verilog
   wire [575:0] key_padded = {puf_key_out, 64'b0};
   ```
   Python: `key + b'\x00' * 8`

2. **ipad XOR** (line 54 in `hmac_controller.v`):
   ```verilog
   wire [575:0] key_xor_ipad = key_padded ^ IPAD;
   ```
   Python: `bytes(a ^ b for a, b in zip(key_padded, ipad))`

3. **Message Format**:
   - Hardware uses 32-bit words (little-endian)
   - Python converts word list to bytes with `word.to_bytes(4, byteorder='little')`

4. **Hash**:
   - Hardware: SHA3-512 via Keccak core
   - Python: `hashlib.sha3_512()`

## Verification

To verify against hardware simulation results:

1. Run the hardware testbench to get HMAC output
2. Extract the key and message from simulation
3. Use `verify_hmac.py` to compare:

```python
from verify_hmac import verify_with_hardware

# Example from simulation
puf_key = 0x...  # From simulation
message = [0xDEADBEEF, 0xCAFEBABE]
expected_hmac = 0x...  # From simulation waveform

verify_with_hardware(puf_key, message, expected_hmac)
```

## Requirements

- Python 3.6+
- No external dependencies (uses standard library `hashlib`)
