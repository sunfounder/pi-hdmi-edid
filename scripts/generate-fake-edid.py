#!/usr/bin/env python3
"""Generate a 256-byte fake EDID with 1080p video and LPCM 2ch audio."""
import struct
import sys

OUT = sys.argv[1] if len(sys.argv) > 1 else "/lib/firmware/edid-hdmi-audio.bin"

edid = bytearray(256)
CEA = 128

# Block 0: Base EDID
edid[0:8]   = bytes([0x00,0xFF,0xFF,0xFF,0xFF,0xFF,0xFF,0x00])
edid[8:10]  = bytes([0x48,0xF2])    # Manufacturer ID
edid[10:12] = bytes([0x01,0x00])    # Product code
edid[12:16] = struct.pack('<I', 1)  # Serial number
edid[16]    = 26                    # Week of manufacture
edid[17]    = 35                    # Year - 1990 = 2025
edid[18]    = 0x01                  # EDID version 1.3
edid[19]    = 0x04
edid[20]    = 0xA5                  # Digital input
edid[21:23] = bytes([0x00,0x00])
edid[23]    = 0x78                  # Max H: 120cm
edid[24]    = 0x0E                  # Max V: 14cm (unused for digital)
edid[25:35] = bytes([0xEE,0x91,0xA3,0x54,0x4C,0x99,0x26,0x0F,0x50,0x54])
edid[35:38] = bytes([0x21,0x08,0x00])
for i in range(38,54,2):
    edid[i]=0x01; edid[i+1]=0x01

# DTD: 1920x1080 @ 60Hz
pclk = 14850  # 148.5 MHz
ha, hb, hso, hsw = 1920, 280, 88, 44
va, vb, vso, vsw = 1080, 45, 4, 5
edid[54:56] = struct.pack('<H', pclk)
edid[56] = ha & 0xFF
edid[57] = hb & 0xFF
edid[58] = ((ha>>8)&0xF)<<4 | ((hb>>8)&0xF)
edid[59] = va & 0xFF
edid[60] = vb & 0xFF
edid[61] = ((va>>8)&0xF)<<4 | ((vb>>8)&0xF)
edid[62] = hso & 0xFF
edid[63] = hsw & 0xFF
edid[64] = ((vso&0xF)<<4) | (vsw&0xF)
edid[65] = ((hso>>8)&0x3)<<2 | ((hsw>>8)&0x3)
edid[66:72] = bytes([0x00,0x00,0x00,0x18,0x00,0x00])
# Padding
for i in range(72,108):
    edid[i]=0x00
# Monitor range limits
edid[108:126] = bytes([0x00,0x00,0x00,0xFD,0x00,57,63,30,85,170,
                       0x00,0x00,0x00,0x00,0x00,0x00,0x00,0x00])
edid[126] = 0x01  # 1 extension block
edid[127] = (256 - sum(edid[:127])) & 0xFF

# Block 1: CEA-861 Extension
edid[CEA+0] = 0x02
edid[CEA+1] = 0x03
pos = 4

# Audio: LPCM 2ch, 32/44.1/48kHz, 16/20/24bit
edid[CEA+pos]   = (1<<5)|3
edid[CEA+pos+1] = 0x09
edid[CEA+pos+2] = 0x07
edid[CEA+pos+3] = 0x07; pos += 4

# Speaker: FL/FR
edid[CEA+pos]   = (4<<5)|3
edid[CEA+pos+1] = 0x00
edid[CEA+pos+2] = 0x00
edid[CEA+pos+3] = 0x01; pos += 4

# Vendor: HDMI (IEEE OUI 0x000C03)
edid[CEA+pos]   = (3<<5)|5
edid[CEA+pos+1] = 0x03
edid[CEA+pos+2] = 0x0C
edid[CEA+pos+3] = 0x00
edid[CEA+pos+4] = 0x10
edid[CEA+pos+5] = 0x00; pos += 6

edid[CEA+2] = pos   # DTD offset
edid[CEA+3] = 0x00  # 0 native DTDs
for i in range(pos, 127):
    edid[CEA+i] = 0x00
edid[CEA+127] = (256 - sum(edid[CEA:CEA+127])) & 0xFF

with open(OUT, 'wb') as f:
    f.write(bytes(edid))

cs0 = (256 - sum(edid[:127])) & 0xFF
cs1 = (256 - sum(edid[128:255])) & 0xFF
print(f"Written {len(edid)} bytes to {OUT}")
print(f"Block0 checksum: 0x{cs0:02x} {'OK' if cs0==edid[127] else 'BAD'}")
print(f"Block1 checksum: 0x{cs1:02x} {'OK' if cs1==edid[255] else 'BAD'}")
