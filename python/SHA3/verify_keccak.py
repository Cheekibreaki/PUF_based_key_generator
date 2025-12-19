#!/usr/bin/env python3
"""
Verification script to compare Python SHA3 with keccak_top hardware simulation.

Usage:
1. Run hardware simulation: vsim -do "run -all" keccak_top_tb
2. Extract hash outputs from simulation
3. Run this script to verify against Python results
"""

from sha3_512 import SHA3_512_Hardware


def verify_puf_mode(data_704bit: int, expected_hash: int):
    """
    Verify PUF mode against hardware result.

    Args:
        data_704bit: 704-bit input as integer
        expected_hash: Expected 512-bit hash from hardware

    Returns:
        bool: True if match
    """
    print("="*70)
    print("PUF Mode Verification")
    print("="*70)

    sha3 = SHA3_512_Hardware()
    computed_hash_bytes = sha3.hash_puf_mode(data_704bit)
    computed_hash_int = int.from_bytes(computed_hash_bytes, byteorder='big')

    print(f"\nInput (704 bits):")
    print(f"  {data_704bit:0176x}")

    print(f"\nExpected Hash (from hardware):")
    print(f"  {expected_hash:0128x}")

    print(f"\nComputed Hash (from Python):")
    print(f"  {computed_hash_int:0128x}")

    match = (computed_hash_int == expected_hash)

    print(f"\n{'='*70}")
    if match:
        print("[PASS] MATCH: Python and hardware outputs are identical!")
    else:
        print("[FAIL] MISMATCH: Outputs differ!")

        # Show byte-by-byte comparison
        expected_bytes = expected_hash.to_bytes(64, byteorder='big')
        print("\nDifferences:")
        for i in range(64):
            exp_byte = expected_bytes[i]
            comp_byte = computed_hash_bytes[i]
            if exp_byte != comp_byte:
                print(f"  Byte {i:2d}: Expected 0x{exp_byte:02x}, Got 0x{comp_byte:02x}")

    print("="*70)
    return match


def verify_block_mode(words: list, expected_hash: int):
    """
    Verify Block mode against hardware result.

    Args:
        words: List of 32-bit words
        expected_hash: Expected 512-bit hash from hardware

    Returns:
        bool: True if match
    """
    print("="*70)
    print("Block Mode Verification")
    print("="*70)

    sha3 = SHA3_512_Hardware()
    computed_hash_bytes = sha3.hash_block_mode(words)
    computed_hash_int = int.from_bytes(computed_hash_bytes, byteorder='big')

    print(f"\nInput ({len(words)} words):")
    for i, word in enumerate(words):
        print(f"  Word {i}: 0x{word:08x}")

    print(f"\nExpected Hash (from hardware):")
    print(f"  {expected_hash:0128x}")

    print(f"\nComputed Hash (from Python):")
    print(f"  {computed_hash_int:0128x}")

    match = (computed_hash_int == expected_hash)

    print(f"\n{'='*70}")
    if match:
        print("[PASS] MATCH: Python and hardware outputs are identical!")
    else:
        print("[FAIL] MISMATCH: Outputs differ!")

        # Show byte-by-byte comparison
        expected_bytes = expected_hash.to_bytes(64, byteorder='big')
        print("\nDifferences:")
        for i in range(64):
            exp_byte = expected_bytes[i]
            comp_byte = computed_hash_bytes[i]
            if exp_byte != comp_byte:
                print(f"  Byte {i:2d}: Expected 0x{exp_byte:02x}, Got 0x{comp_byte:02x}")

    print("="*70)
    return match


def example_verification():
    """
    Example verification with pre-computed test vectors.
    Replace with actual hardware simulation results.
    """
    print("\n*** Example Verification ***\n")

    sha3 = SHA3_512_Hardware()

    # Test 1: PUF mode with 0xAA pattern
    print("\n[TEST 1] PUF Mode (0xAA pattern)")
    puf_data = int('AA' * 88, 16)
    expected_puf = sha3.hash_puf_mode(puf_data)
    expected_puf_int = int.from_bytes(expected_puf, byteorder='big')
    verify_puf_mode(puf_data, expected_puf_int)

    print("\n")

    # Test 2: Block mode with [0xDEADBEEF, 0xCAFEBABE]
    print("\n[TEST 2] Block Mode (2 words)")
    words = [0xDEADBEEF, 0xCAFEBABE]
    expected_block = sha3.hash_block_mode(words)
    expected_block_int = int.from_bytes(expected_block, byteorder='big')
    verify_block_mode(words, expected_block_int)

    print("\n" + "="*70)
    print("NOTE: To verify against actual hardware simulation:")
    print("  1. Run: vsim -do \"run -all\" keccak_top_tb")
    print("  2. From simulation output, extract hash values (512 bits)")
    print("  3. Update this script with actual values")
    print("  4. Re-run verification")
    print("="*70)


if __name__ == "__main__":
    example_verification()

    print("\n\n*** Ready for Hardware Verification ***")
    print("\nTo verify with your simulation results:")
    print("  1. Run hardware simulation")
    print("  2. Extract hash outputs from transcript or waveform")
    print("  3. Call verify_puf_mode() or verify_block_mode() with actual values")
