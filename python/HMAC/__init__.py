"""
HMAC-SHA3-512 Implementation matching hardware design.

This package provides a Python implementation of the simplified HMAC-SHA3-512
algorithm used in the PUF-based key generator hardware.

Main classes:
    HMAC_SHA3_512: HMAC computation class

Example usage:
    from HMAC import HMAC_SHA3_512

    key = 0x0123...  # 512-bit key
    hmac = HMAC_SHA3_512(key)
    result = hmac.compute([0xDEADBEEF, 0xCAFEBABE])
"""

from .hmac_sha3_512 import HMAC_SHA3_512

__all__ = ['HMAC_SHA3_512']
__version__ = '1.0.0'
