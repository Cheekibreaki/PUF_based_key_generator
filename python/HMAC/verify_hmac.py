#!/usr/bin/env python3
"""
Verification script to compare Python HMAC with hardware simulation results.

Usage:
1. Run hardware simulation and extract:
   - PUF key (512 bits)
   - Message words (list of 32-bit values)
   - HMAC output (512 bits)

2. Run this script to verify:
   python verify_hmac.py
"""

from hmac_sha3_512 import HMAC_SHA3_512


def verify_with_hardware(puf_key: int, message: list, expected_hmac: int):
    """
    Verify Python implementation against hardware simulation results.

    Args:
        puf_key: 512-bit key as integer
        message: List of 32-bit message words
        expected_hmac: Expected HMAC output as 512-bit integer

    Returns:
        bool: True if match, False otherwise
    """
    print("="*70)
    print("HMAC Verification: Python vs Hardware")
    print("="*70)

    # Create HMAC instance
    hmac = HMAC_SHA3_512(puf_key)

    # Compute HMAC
    computed_hmac_bytes = hmac.compute(message)
    computed_hmac_int = int.from_bytes(computed_hmac_bytes, byteorder='big')

    # Convert expected to bytes for comparison
    expected_hmac_bytes = expected_hmac.to_bytes(64, byteorder='big')

    # Display inputs
    print(f"\nInputs:")
    print(f"  PUF Key (512 bits):")
    print(f"    {puf_key:0128x}")
    print(f"\n  Message ({len(message)} words):")
    for i, word in enumerate(message):
        print(f"    Word {i}: 0x{word:08x}")

    # Display outputs
    print(f"\nOutputs:")
    print(f"  Expected HMAC (from hardware):")
    print(f"    {expected_hmac:0128x}")
    print(f"\n  Computed HMAC (from Python):")
    print(f"    {computed_hmac_int:0128x}")

    # Compare
    match = (computed_hmac_int == expected_hmac)

    print(f"\n{'='*70}")
    if match:
        print("[PASS] MATCH: Python and hardware outputs are identical!")
        print("="*70)
        return True
    else:
        print("[FAIL] MISMATCH: Outputs differ!")
        print("\nDifferences:")

        # Show byte-by-byte comparison
        for i in range(64):
            exp_byte = expected_hmac_bytes[i]
            comp_byte = computed_hmac_bytes[i]
            if exp_byte != comp_byte:
                print(f"  Byte {i:2d}: Expected 0x{exp_byte:02x}, Got 0x{comp_byte:02x}")

        print("="*70)
        return False


def example_verification():
    """
    Example verification with test data.

    To use with actual hardware results:
    1. Run the testbench: vsim -do "run -all" secure_key_system_tb_new
    2. Extract values from simulation output
    3. Replace the values below
    """
    print("\n*** Example Verification (Test Data) ***\n")

    # Example test data (replace with actual hardware simulation results)
    puf_key = 0x0123456789ABCDEF0123456789ABCDEF0123456789ABCDEF0123456789ABCDEF0123456789ABCDEF0123456789ABCDEF0123456789ABCDEF0123456789ABCDEF

    # Message from testbench (secure_key_system_tb_new.v line 381-382)
    message = [0xDEADBEEF, 0xCAFEBABE]

    # Compute expected (since we don't have real hardware results yet)
    hmac = HMAC_SHA3_512(puf_key)
    expected_hmac_bytes = hmac.compute(message)
    expected_hmac = int.from_bytes(expected_hmac_bytes, byteorder='big')

    # Verify (should always match in this example)
    verify_with_hardware(puf_key, message, expected_hmac)

    print("\n" + "="*70)
    print("NOTE: To verify against actual hardware simulation:")
    print("  1. Run: cd Modelsim && vsim -do \"run -all\" secure_key_system_tb_new")
    print("  2. From simulation output, extract:")
    print("     - PUF Key (first 64 bits shown, need full 512 bits)")
    print("     - HMAC Value (first 64 bits shown, need full 512 bits)")
    print("  3. Update this script with actual values")
    print("  4. Re-run verification")
    print("="*70)


def parse_verilog_hex(hex_str: str, bits: int) -> int:
    """
    Parse Verilog hex output to integer.

    Args:
        hex_str: Hex string from Verilog (may have underscores or 'h' prefix)
        bits: Expected bit width

    Returns:
        Integer value
    """
    # Remove common Verilog formatting
    cleaned = hex_str.replace('_', '').replace('h', '').replace('0x', '')
    return int(cleaned, 16)


if __name__ == "__main__":
    example_verification()

    print("\n\n*** Ready for Hardware Verification ***")
    print("\nTo verify with your simulation results:")
    print("  1. Run hardware simulation")
    print("  2. Modify this file with actual puf_key, message, and expected_hmac")
    print("  3. Call: verify_with_hardware(puf_key, message, expected_hmac)")
