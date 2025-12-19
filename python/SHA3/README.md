# SHA3-512 Python Implementation

This directory contains a Python software implementation of SHA3-512 that matches the hardware implementation in `keccak_top.v`.

## Hardware Matching

The implementation matches two modes from `keccak_top.v`:

### 1. PUF Mode (704-bit input)
```verilog
// Hardware: keccak_top.v lines 84-102
// Feeds 704 bits as 22 words (32-bit each), LSB first
```

**Python equivalent:**
```python
from SHA3 import SHA3_512_Hardware

sha3 = SHA3_512_Hardware()
result = sha3.hash_puf_mode(0xAA...AA)  # 704-bit integer
```

### 2. Block Mode (word stream)
```verilog
// Hardware: keccak_top.v lines 107-125
// Feeds stream of 32-bit words
```

**Python equivalent:**
```python
sha3 = SHA3_512_Hardware()
result = sha3.hash_block_mode([0xDEADBEEF, 0xCAFEBABE])
```

## Key Implementation Details

### Byte Order
Hardware feeds 32-bit words in **little-endian** byte order:
- Word `0xDEADBEEF` → bytes `[0xEF, 0xBE, 0xAD, 0xDE]`
- Python: `word.to_bytes(4, byteorder='little')`

### Data Widths
- **PUF mode**: 704 bits = 22 words × 32 bits = 88 bytes
- **Block mode**: Variable number of 32-bit words
- **Output**: Always 512 bits = 64 bytes

## Files

- `sha3_512.py`: Main SHA3-512 implementation
- `verify_keccak.py`: Verification against hardware simulation
- `README.md`: This file

## Usage

### Generate Test Vectors

```bash
python sha3_512.py
```

This generates outputs for all test cases in `keccak_top_tb.v`:
1. PUF mode with 0xAA pattern
2. PUF mode with 0x0123... pattern
3. Block mode with 2 words `[0xDEADBEEF, 0xCAFEBABE]`
4. Block mode with 4 words
5. Block mode with 1 word

### Verify Against Hardware

1. Run hardware testbench:
   ```bash
   cd Modelsim
   vlog ../keccak_top_tb.v ../keccak_top.v ../keccak.v ../f_permutation.v
   vsim -do "run -all" keccak_top_tb
   ```

2. Extract hash outputs from simulation transcript

3. Verify with Python:
   ```bash
   cd python/SHA3
   python verify_keccak.py
   ```

   Or programmatically:
   ```python
   from verify_keccak import verify_puf_mode, verify_block_mode

   # Example: Verify PUF mode result
   puf_input = 0xAA...AA  # 704 bits
   hw_output = 0x...      # 512-bit hash from simulation
   verify_puf_mode(puf_input, hw_output)

   # Example: Verify Block mode result
   words = [0xDEADBEEF, 0xCAFEBABE]
   hw_output = 0x...      # 512-bit hash from simulation
   verify_block_mode(words, hw_output)
   ```

## Test Vectors

The testbench `keccak_top_tb.v` uses these hardcoded test vectors:

### Test 1: PUF Mode (0xAA pattern)
```
Input:  704 bits of 0xAA
```

### Test 2: PUF Mode (0x0123... pattern)
```
Input:  0x0123456789ABCDEF... (repeated, 704 bits)
```

### Test 3: Block Mode (2 words)
```
Input:  [0xDEADBEEF, 0xCAFEBABE]
```

### Test 4: Block Mode (4 words)
```
Input:  [0x01234567, 0x89ABCDEF, 0xFEDCBA98, 0x76543210]
```

### Test 5: Block Mode (1 word)
```
Input:  [0x12345678]
```

## Hardware Correspondence

| Hardware Signal | Python Equivalent |
|----------------|-------------------|
| `data_in[703:0]` | 704-bit integer |
| `block_word[31:0]` | 32-bit integer in list |
| `out[511:0]` | 64 bytes (byteorder='big' for display) |
| `sha_init` | Create new hasher instance |
| `mode_puf` | Call `hash_puf_mode()` |
| `mode_block` | Call `hash_block_mode()` |

## Requirements

- Python 3.6+
- Standard library `hashlib` (no external dependencies)
