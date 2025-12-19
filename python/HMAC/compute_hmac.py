#!/usr/bin/env python3
"""
Command-line utility to compute HMAC-SHA3-512.

Usage:
    python compute_hmac.py <key_hex> <message_word1> [message_word2] ...

Example:
    python compute_hmac.py 0123456789abcdef...cdef deadbeef cafebabe
"""

import sys
from hmac_sha3_512 import HMAC_SHA3_512


def main():
    if len(sys.argv) < 3:
        print("Usage: python compute_hmac.py <key_hex> <message_word1> [message_word2] ...")
        print("\nExample:")
        print("  python compute_hmac.py 0123456789abcdef0123456789abcdef0123456789abcdef0123456789abcdef0123456789abcdef0123456789abcdef0123456789abcdef0123456789abcdef deadbeef cafebabe")
        sys.exit(1)

    # Parse key (512 bits = 128 hex characters)
    key_hex = sys.argv[1].replace('0x', '').replace('_', '')

    if len(key_hex) != 128:
        print(f"Error: Key must be 128 hex characters (512 bits), got {len(key_hex)}")
        sys.exit(1)

    try:
        key_int = int(key_hex, 16)
    except ValueError:
        print(f"Error: Invalid hex key: {key_hex}")
        sys.exit(1)

    # Parse message words
    message_words = []
    for i, word_hex in enumerate(sys.argv[2:], 1):
        word_hex_clean = word_hex.replace('0x', '').replace('_', '')
        try:
            word = int(word_hex_clean, 16)
            if word > 0xFFFFFFFF:
                print(f"Error: Message word {i} exceeds 32 bits: {word_hex}")
                sys.exit(1)
            message_words.append(word)
        except ValueError:
            print(f"Error: Invalid hex word {i}: {word_hex}")
            sys.exit(1)

    # Compute HMAC
    print("="*70)
    print("HMAC-SHA3-512 Computation")
    print("="*70)

    print(f"\nKey (512 bits):")
    print(f"  {key_int:0128x}")

    print(f"\nMessage ({len(message_words)} words):")
    for i, word in enumerate(message_words):
        print(f"  Word {i}: 0x{word:08x}")

    hmac = HMAC_SHA3_512(key_int)
    hmac_value = hmac.compute(message_words)
    hmac_int = int.from_bytes(hmac_value, byteorder='big')

    print(f"\nHMAC-SHA3-512 (512 bits):")
    print(f"  {hmac_int:0128x}")

    print(f"\nFirst 64 bits:  0x{hmac_value[:8].hex()}")
    print(f"First 128 bits: 0x{hmac_value[:16].hex()}")
    print(f"First 256 bits: 0x{hmac_value[:32].hex()}")

    print("\n" + "="*70)


if __name__ == "__main__":
    main()
