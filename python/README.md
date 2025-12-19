# Python Software Implementations

This directory contains Python software implementations of the hardware algorithms used in the PUF-based key generator system.

## Directory Structure

```
python/
├── HMAC/                   # HMAC-SHA3-512 implementation
│   ├── hmac_sha3_512.py   # Main HMAC class
│   ├── verify_hmac.py     # Verification against hardware
│   ├── compute_hmac.py    # Command-line utility
│   ├── README.md          # HMAC documentation
│   └── __init__.py        # Package initialization
├── SHA3/                   # SHA3-512 implementation
│   ├── sha3_512.py        # Main SHA3 class
│   ├── verify_keccak.py   # Verification against keccak_top
│   ├── README.md          # SHA3 documentation
│   └── __init__.py        # Package initialization
└── README.md              # This file
```

## Available Implementations

### 1. HMAC-SHA3-512

Software implementation of the simplified HMAC-SHA3-512 algorithm used in hardware.

**Algorithm**: `HMAC = SHA3-512((K ⊕ ipad) || message)`

**Files**: `python/HMAC/`

**Quick Start**:
```bash
cd python/HMAC
python hmac_sha3_512.py      # Run test
python compute_hmac.py <key> <msg_words...>  # Compute HMAC
```

See [HMAC/README.md](HMAC/README.md) for detailed documentation.

### 2. SHA3-512

Software implementation matching `keccak_top.v` hardware with PUF mode (704-bit) and Block mode (word stream).

**Algorithm**: Standard SHA3-512 with hardware-specific byte ordering

**Files**: `python/SHA3/`

**Quick Start**:
```bash
cd python/SHA3
python sha3_512.py           # Generate test vectors
python verify_keccak.py      # Verify against hardware
```

See [SHA3/README.md](SHA3/README.md) for detailed documentation.

## Purpose

These Python implementations serve multiple purposes:

1. **Verification**: Compare hardware simulation results with software reference
2. **Testing**: Generate test vectors for hardware testbenches
3. **Reference**: Understand algorithm behavior before hardware implementation
4. **Integration**: Use in mixed hardware/software systems

## Requirements

- Python 3.6 or higher
- Standard library only (no external dependencies)

## Future Implementations

Potential additions:
- Reed-Muller encoding/decoding (Fuzzy Extractor)
- PUF modeling and simulation
- Complete key generation flow
- Test vector generation utilities

## Usage with Hardware

### Verify Hardware Simulation

1. Run hardware simulation:
   ```bash
   cd Modelsim
   vsim -do "run -all" secure_key_system_tb_new
   ```

2. Extract results from waveform/log:
   - PUF key (512 bits)
   - Message words
   - HMAC output (512 bits)

3. Verify with Python:
   ```bash
   cd python/HMAC
   python verify_hmac.py
   # Edit script with actual values and re-run
   ```

### Generate Test Vectors

Use the Python implementations to generate test vectors for hardware verification:

```python
from HMAC import HMAC_SHA3_512

# Generate test case
key = 0x0123...
message = [0xDEADBEEF, 0xCAFEBABE]
hmac = HMAC_SHA3_512(key)
expected = hmac.compute(message)

# Use in testbench
print(f"Expected HMAC: {expected.hex()}")
```

## Contributing

When adding new implementations:
1. Match hardware behavior exactly
2. Include verification scripts
3. Add comprehensive documentation
4. Provide usage examples
5. Keep zero external dependencies when possible
