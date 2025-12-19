#!/usr/bin/env python3
"""
SHA3-512 Implementation matching keccak_top.v hardware

This implementation matches the hardware behavior of keccak_top.v which
supports two modes:
1. PUF mode: Hash 704-bit input (22 words of 32 bits)
2. Block mode: Hash stream of 32-bit words

The hardware uses little-endian byte order for 32-bit words.
"""

import hashlib
from typing import List, Union


class SHA3_512_Hardware:
    """
    SHA3-512 implementation matching keccak_top.v hardware behavior.

    Key differences from standard SHA3:
    - Hardware uses little-endian 32-bit words
    - PUF mode: 704 bits = 22 words of 32 bits = 88 bytes
    - Block mode: Variable number of 32-bit words
    """

    @staticmethod
    def hash_puf_mode(data_704bit: int) -> bytes:
        """
        Hash 704-bit data (PUF mode).

        Hardware behavior (keccak_top.v lines 84-102):
        1. Load 704-bit data into puf_buffer
        2. Feed 22 words (32-bit each) to Keccak, LSB first
        3. Each word is fed as 4 bytes (little-endian)

        Args:
            data_704bit: 704-bit integer

        Returns:
            64 bytes (512 bits) SHA3-512 hash
        """
        # Convert 704-bit integer to 88 bytes (704/8)
        data_bytes = data_704bit.to_bytes(88, byteorder='little')

        # Compute SHA3-512
        hasher = hashlib.sha3_512()
        hasher.update(data_bytes)
        return hasher.digest()

    @staticmethod
    def hash_block_mode(words: List[int]) -> bytes:
        """
        Hash list of 32-bit words (Block mode).

        Hardware behavior (keccak_top.v lines 107-125):
        1. Receive stream of 32-bit words
        2. Feed each word to Keccak as 4 bytes (little-endian)

        Args:
            words: List of 32-bit integers

        Returns:
            64 bytes (512 bits) SHA3-512 hash
        """
        # Convert each 32-bit word to 4 bytes (little-endian)
        data_bytes = b''.join(word.to_bytes(4, byteorder='little') for word in words)

        # Compute SHA3-512
        hasher = hashlib.sha3_512()
        hasher.update(data_bytes)
        return hasher.digest()

    @staticmethod
    def hash_bytes(data: bytes) -> bytes:
        """
        Hash arbitrary byte sequence (standard SHA3-512).

        Args:
            data: Byte sequence

        Returns:
            64 bytes (512 bits) SHA3-512 hash
        """
        hasher = hashlib.sha3_512()
        hasher.update(data)
        return hasher.digest()


def test_vectors():
    """
    Test vectors matching keccak_top_tb.v testbench.
    """
    print("="*70)
    print("SHA3-512 Hardware Test Vectors")
    print("="*70)

    sha3 = SHA3_512_Hardware()

    # ===========================================
    # Test 1: PUF Mode - Pattern 0xAA...AA
    # ===========================================
    print("\n[TEST 1] PUF Mode: 704-bit input (0xAA pattern)")

    # 704 bits of 0xAA
    puf_data_1 = int('AA' * 88, 16)

    result_1 = sha3.hash_puf_mode(puf_data_1)
    result_1_int = int.from_bytes(result_1, byteorder='big')

    print(f"  Input (704 bits): {puf_data_1:0176x}")
    print(f"  Output (512 bits): {result_1_int:0128x}")
    print(f"  First 64 bits: 0x{result_1[:8].hex()}")

    # ===========================================
    # Test 2: PUF Mode - Pattern 0x0123456789ABCDEF
    # ===========================================
    print("\n[TEST 2] PUF Mode: 704-bit input (0x0123... pattern)")

    # Pattern: 0x0123456789ABCDEF repeated (truncated to 704 bits)
    pattern = "0123456789ABCDEF" * 11  # 11 * 64 bits = 704 bits
    puf_data_2 = int(pattern[:176], 16)  # Take first 176 hex chars (704 bits)

    result_2 = sha3.hash_puf_mode(puf_data_2)
    result_2_int = int.from_bytes(result_2, byteorder='big')

    print(f"  Input (704 bits): {puf_data_2:0176x}")
    print(f"  Output (512 bits): {result_2_int:0128x}")
    print(f"  First 64 bits: 0x{result_2[:8].hex()}")

    # ===========================================
    # Test 3: Block Mode - 2 words [0xDEADBEEF, 0xCAFEBABE]
    # ===========================================
    print("\n[TEST 3] Block Mode: 2 words")

    words_3 = [0xDEADBEEF, 0xCAFEBABE]

    result_3 = sha3.hash_block_mode(words_3)
    result_3_int = int.from_bytes(result_3, byteorder='big')

    print(f"  Input words: {[f'0x{w:08x}' for w in words_3]}")
    print(f"  Output (512 bits): {result_3_int:0128x}")
    print(f"  First 64 bits: 0x{result_3[:8].hex()}")

    # ===========================================
    # Test 4: Block Mode - 4 words
    # ===========================================
    print("\n[TEST 4] Block Mode: 4 words")

    words_4 = [0x01234567, 0x89ABCDEF, 0xFEDCBA98, 0x76543210]

    result_4 = sha3.hash_block_mode(words_4)
    result_4_int = int.from_bytes(result_4, byteorder='big')

    print(f"  Input words: {[f'0x{w:08x}' for w in words_4]}")
    print(f"  Output (512 bits): {result_4_int:0128x}")
    print(f"  First 64 bits: 0x{result_4[:8].hex()}")

    # ===========================================
    # Test 5: Block Mode - 1 word
    # ===========================================
    print("\n[TEST 5] Block Mode: 1 word")

    words_5 = [0x12345678]

    result_5 = sha3.hash_block_mode(words_5)
    result_5_int = int.from_bytes(result_5, byteorder='big')

    print(f"  Input words: {[f'0x{w:08x}' for w in words_5]}")
    print(f"  Output (512 bits): {result_5_int:0128x}")
    print(f"  First 64 bits: 0x{result_5[:8].hex()}")

    print("\n" + "="*70)
    print("Copy these outputs to verify against hardware simulation!")
    print("="*70)


if __name__ == "__main__":
    test_vectors()
