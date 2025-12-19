#!/usr/bin/env python3
"""
HMAC-SHA3-512 Implementation
Matches the hardware implementation in hmac_controller.v

Simplified HMAC: TAG = SHA3_512((K ^ ipad) || message)
- Key is 512 bits (64 bytes)
- ipad is 0x36 repeated 72 times (576 bits)
- Key is padded to 576 bits by appending 64 zero bits
"""

import hashlib
from typing import List, Union


class HMAC_SHA3_512:
    """
    Simplified HMAC-SHA3-512 implementation matching hardware design.

    Hardware behavior:
    1. Key (512 bits) is padded to 576 bits by appending 64 zero bits
    2. Padded key is XORed with ipad (0x36 repeated 72 times)
    3. Result is concatenated with message
    4. SHA3-512 hash is computed: SHA3-512((K_padded ^ ipad) || message)
    """

    IPAD_BYTE = 0x36
    KEY_BITS = 512
    PADDED_KEY_BITS = 576
    RATE_WORDS = 18  # 18 words of 32 bits = 576 bits

    def __init__(self, key: Union[bytes, int]):
        """
        Initialize HMAC with a key.

        Args:
            key: Either bytes (64 bytes for 512-bit key) or int (512-bit integer)
        """
        if isinstance(key, int):
            # Convert integer to 64 bytes (512 bits), big-endian
            self.key = key.to_bytes(64, byteorder='big')
        elif isinstance(key, bytes):
            if len(key) != 64:
                raise ValueError(f"Key must be 64 bytes (512 bits), got {len(key)} bytes")
            self.key = key
        else:
            raise TypeError("Key must be bytes or int")

    def _pad_key(self) -> bytes:
        """
        Pad 512-bit key to 576 bits by appending 64 zero bits.

        Returns:
            72 bytes (576 bits)
        """
        # Append 8 zero bytes (64 bits) to the 64-byte key
        return self.key + b'\x00' * 8

    def _compute_ipad_block(self) -> bytes:
        """
        Compute (K_padded ^ ipad) block.

        Returns:
            72 bytes (576 bits)
        """
        key_padded = self._pad_key()
        ipad = bytes([self.IPAD_BYTE] * 72)

        # XOR operation
        key_xor_ipad = bytes(a ^ b for a, b in zip(key_padded, ipad))
        return key_xor_ipad

    def compute(self, message: Union[bytes, List[int]]) -> bytes:
        """
        Compute HMAC-SHA3-512.

        Hardware algorithm:
        1. Compute ipad_block = (K_padded ^ ipad)
        2. Concatenate: ipad_block || message
        3. Compute: SHA3-512(ipad_block || message)

        Args:
            message: Message as bytes or list of 32-bit words

        Returns:
            64 bytes (512 bits) HMAC value
        """
        # Handle message input
        if isinstance(message, list):
            # Convert list of 32-bit words to bytes (little-endian to match hardware)
            msg_bytes = b''.join(word.to_bytes(4, byteorder='little') for word in message)
        elif isinstance(message, bytes):
            msg_bytes = message
        else:
            raise TypeError("Message must be bytes or list of 32-bit words")

        # Compute ipad block
        ipad_block = self._compute_ipad_block()

        # Concatenate and hash
        data = ipad_block + msg_bytes

        # Use SHA3-512
        hasher = hashlib.sha3_512()
        hasher.update(data)

        return hasher.digest()

    def compute_hex(self, message: Union[bytes, List[int]]) -> str:
        """
        Compute HMAC and return as hex string.

        Args:
            message: Message as bytes or list of 32-bit words

        Returns:
            Hex string (128 characters for 512 bits)
        """
        return self.compute(message).hex()


def test_hmac():
    """Test the HMAC implementation with example data."""
    print("="*60)
    print("HMAC-SHA3-512 Test")
    print("="*60)

    # Example key (512 bits = 64 bytes)
    key_int = 0x0123456789ABCDEF0123456789ABCDEF0123456789ABCDEF0123456789ABCDEF0123456789ABCDEF0123456789ABCDEF0123456789ABCDEF0123456789ABCDEF

    # Create HMAC instance
    hmac = HMAC_SHA3_512(key_int)

    # Test message (matching testbench: 0xDEADBEEF, 0xCAFEBABE)
    message_words = [0xDEADBEEF, 0xCAFEBABE]

    print(f"\nKey (512 bits):")
    print(f"  {key_int:0128x}")

    print(f"\nMessage (2 words):")
    for i, word in enumerate(message_words):
        print(f"  Word {i}: 0x{word:08x}")

    # Compute HMAC
    hmac_value = hmac.compute(message_words)

    print(f"\nHMAC-SHA3-512 Result (512 bits):")
    print(f"  {hmac_value.hex()}")
    print(f"\nFirst 64 bits: 0x{hmac_value[:8].hex()}")
    print(f"First 128 bits: 0x{hmac_value[:16].hex()}")

    # Show intermediate ipad block
    ipad_block = hmac._compute_ipad_block()
    print(f"\nIntermediate (K_padded ^ ipad) block (576 bits):")
    print(f"  {ipad_block.hex()}")

    print("\n" + "="*60)


if __name__ == "__main__":
    test_hmac()
