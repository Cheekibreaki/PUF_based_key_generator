"""
SHA3-512 Implementation matching keccak_top.v hardware.

This package provides SHA3-512 hashing that matches the hardware behavior
in both PUF mode (704-bit input) and Block mode (word stream).

Main classes:
    SHA3_512_Hardware: SHA3-512 computation matching hardware

Example usage:
    from SHA3 import SHA3_512_Hardware

    sha3 = SHA3_512_Hardware()

    # PUF mode
    hash1 = sha3.hash_puf_mode(0xAA...AA)  # 704-bit int

    # Block mode
    hash2 = sha3.hash_block_mode([0xDEADBEEF, 0xCAFEBABE])
"""

from .sha3_512 import SHA3_512_Hardware

__all__ = ['SHA3_512_Hardware']
__version__ = '1.0.0'
