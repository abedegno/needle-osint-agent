#!/usr/bin/env python3
# ulid.py — canonical ULID encode/decode/validate. Crockford base32, 26 chars, first char [0-7].
# A ULID is 128 bits = 48-bit ms timestamp (high) + 80-bit randomness (low).
import sys, os, time
ALPHABET = "0123456789ABCDEFGHJKMNPQRSTVWXYZ"   # Crockford (no I,L,O,U)
_DEC = {c: i for i, c in enumerate(ALPHABET)}

def encode(ms, rand80):
    if not (0 <= ms < (1 << 48)): raise ValueError("ms out of range")
    if not (0 <= rand80 < (1 << 80)): raise ValueError("rand out of range")
    val = (ms << 80) | rand80
    out = []
    for _ in range(26):
        out.append(ALPHABET[val & 0x1F]); val >>= 5
    return "".join(reversed(out))

def decode(s):
    if len(s) != 26: raise ValueError("length")
    val = 0
    for ch in s:
        if ch not in _DEC: raise ValueError("alphabet")
        val = (val << 5) | _DEC[ch]
    if val >= (1 << 128): raise ValueError("over 128 bits")   # first char must be 0..7
    return (val >> 80), (val & ((1 << 80) - 1))

def is_canonical(s):
    try: return encode(*decode(s)) == s
    except ValueError: return False

def new(ms=None):
    if ms is None: ms = int(time.time() * 1000)
    return encode(ms, int.from_bytes(os.urandom(10), "big"))

if __name__ == "__main__":
    a = sys.argv
    if len(a) == 3 and a[1] == "--check":
        sys.exit(0 if is_canonical(a[2]) else 1)
    if len(a) == 3 and a[1] == "--ms":
        try: print(decode(a[2])[0]); sys.exit(0)
        except ValueError: sys.exit(1)
    if len(a) >= 2 and a[1] == "--new":
        print(new(int(a[2]) if len(a) > 2 else None)); sys.exit(0)
    sys.exit(2)
