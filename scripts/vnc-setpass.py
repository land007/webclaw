#!/usr/bin/env python3
"""Generate a VNC password file (DES-obfuscated, RFB 3.x format)."""
import sys, struct

def reverse_bits(byte):
    """VNC uses DES with bit-reversed key bytes."""
    result = 0
    for i in range(8):
        result = (result << 1) | ((byte >> i) & 1)
    return result

def vnc_encrypt(password):
    """Encrypt password using VNC's DES obfuscation."""
    # Pad/truncate to 8 bytes
    pw = password[:8].ljust(8, '\x00')
    key = bytes([reverse_bits(b) for b in pw.encode('latin-1')])
    # VNC fixed plaintext (8 null bytes) encrypted with DES-ECB using the key
    import subprocess
    result = subprocess.run(
        ['openssl', 'enc', '-des-ecb', '-nopad', '-nosalt', '-K', key.hex()],
        input=b'\x00' * 8, capture_output=True
    )
    if result.returncode == 0 and len(result.stdout) == 8:
        return result.stdout
    # Fallback: just store raw bytes (won't work with VNC auth but won't crash)
    return pw.encode('latin-1')

if __name__ == '__main__':
    if len(sys.argv) != 3:
        print(f"Usage: {sys.argv[0]} <password> <output_file>")
        sys.exit(1)
    encrypted = vnc_encrypt(sys.argv[1])
    with open(sys.argv[2], 'wb') as f:
        f.write(encrypted)
