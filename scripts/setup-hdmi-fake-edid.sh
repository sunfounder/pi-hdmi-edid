#!/bin/bash
#=============================================================================
# setup-hdmi-fake-edid — Force HDMI audio via fake EDID on Raspberry Pi
#
# Use case: HDMI audio extractors / capture cards that don't provide EDID
#           need this to enable HDMI audio output on the Pi.
#
# Usage:   sudo ./setup-hdmi-fake-edid.sh [HDMI-A-1|HDMI-A-2]
#          Defaults to HDMI-A-1
#=============================================================================
set -euo pipefail

CONNECTOR="${1:-HDMI-A-1}"

EDID_FILE="/lib/firmware/edid-hdmi-audio.bin"
HOOK_FILE="/etc/initramfs-tools/hooks/edid-hdmi-audio"
CMDLINE="/boot/firmware/cmdline.txt"
CONFIG="/boot/firmware/config.txt"

RED='\033[0;31m'; GREEN='\033[0;32m'; YELLOW='\033[1;33m'; NC='\033[0m'
info()  { echo -e "${GREEN}[INFO]${NC} $*"; }
warn()  { echo -e "${YELLOW}[WARN]${NC} $*"; }
err()   { echo -e "${RED}[ERROR]${NC} $*"; exit 1; }

#--- Permission check ---
[[ $EUID -eq 0 ]] || err "Please run with sudo"

info "=== HDMI Fake EDID Audio Setup ==="
info "Target connector: $CONNECTOR"
echo ""

#=============================================================================
# Step 1: Generate EDID binary (256 bytes)
#=============================================================================
info "Step 1/5: Generating EDID file..."

python3 << 'PYEOF'
import struct

edid = bytearray(256)
CEA = 128  # CEA extension block base offset

# ---- Block 0: Base EDID ----
edid[0:8]   = bytes([0x00,0xFF,0xFF,0xFF,0xFF,0xFF,0xFF,0x00])
edid[8:10]  = bytes([0x48,0xF2])
edid[10:12] = bytes([0x01,0x00])
edid[12:16] = struct.pack('<I', 1)
edid[16]    = 26
edid[17]    = 35
edid[18]    = 0x01
edid[19]    = 0x04
edid[20]    = 0xA5
edid[21:23] = bytes([0x00,0x00])
edid[23]    = 0x78
edid[24]    = 0x0E
edid[25:35] = bytes([0xEE,0x91,0xA3,0x54,0x4C,0x99,0x26,0x0F,0x50,0x54])
edid[35:38] = bytes([0x21,0x08,0x00])
for i in range(38,54,2):
    edid[i]=0x01; edid[i+1]=0x01

# DTD: 1920x1080@60Hz
pclk = 14850
ha,hb,hso,hsw = 1920,280,88,44
va,vb,vso,vsw = 1080,45,4,5
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
for i in range(72,108): edid[i]=0x00
edid[108:126] = bytes([0x00,0x00,0x00,0xFD,0x00,57,63,30,85,170,
                       0x00,0x00,0x00,0x00,0x00,0x00,0x00,0x00])
edid[126] = 0x01
edid[127] = (256 - sum(edid[:127])) & 0xFF

# ---- Block 1: CEA-861 Extension (all offsets relative to CEA start) ----
edid[CEA+0] = 0x02
edid[CEA+1] = 0x03

pos = 4  # data block start (relative to CEA)

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

edid[CEA+2] = pos    # DTD offset — MUST be <= 127!
edid[CEA+3] = 0x00   # 0 native DTDs

for i in range(pos, 127): edid[CEA+i] = 0x00
edid[CEA+127] = (256 - sum(edid[CEA:CEA+127])) & 0xFF

with open('/lib/firmware/edid-hdmi-audio.bin', 'wb') as f:
    f.write(bytes(edid))

cs0 = (256 - sum(edid[:127])) & 0xFF
cs1 = (256 - sum(edid[128:255])) & 0xFF
print(f'  Block0 checksum: 0x{cs0:02x} OK' if cs0==edid[127] else f'  Block0 checksum: BAD!')
print(f'  Block1 checksum: 0x{cs1:02x} OK' if cs1==edid[255] else f'  Block1 checksum: BAD!')
print(f'  CEA DTD offset: {edid[130]} (<=127 is good)')
PYEOF

#=============================================================================
# Step 2: Create initramfs hook
#=============================================================================
info "Step 2/5: Creating initramfs hook..."

cat > "$HOOK_FILE" << 'HOOKEOF'
#!/bin/sh
PREREQ=""
prereqs() { echo "$PREREQ"; }
case $1 in prereqs) prereqs; exit 0;; esac
. /usr/share/initramfs-tools/hook-functions
mkdir -p ${DESTDIR}/lib/firmware
cp /lib/firmware/edid-hdmi-audio.bin ${DESTDIR}/lib/firmware/edid-hdmi-audio.bin
exit 0
HOOKEOF
chmod +x "$HOOK_FILE"

#=============================================================================
# Step 3: Configure kernel command line
#=============================================================================
info "Step 3/5: Configuring kernel cmdline..."

if [[ ! -f "${CMDLINE}.bak" ]]; then
    cp "$CMDLINE" "${CMDLINE}.bak"
    info "  Backed up cmdline.txt"
fi

CURRENT=$(cat "$CMDLINE")

for param in "drm.edid_firmware=${CONNECTOR}:edid-hdmi-audio.bin" \
             "video=${CONNECTOR}:1920x1080@60D" \
             "vc4.force_hotplug=1"; do
    key="${param%%=*}"
    if echo "$CURRENT" | grep -q "$key="; then
        warn "  $key= already present, skipping"
    else
        CURRENT="$CURRENT $param"
        info "  Added: $param"
    fi
done

CURRENT=$(echo "$CURRENT" | sed 's/ quiet//g; s/splash//g; s/ plymouth\.ignore-serial-consoles//g')
echo "$CURRENT" > "$CMDLINE"

#=============================================================================
# Step 4: Configure firmware (config.txt)
#=============================================================================
info "Step 4/5: Configuring firmware..."

if ! grep -q '^hdmi_force_hotplug=1' "$CONFIG"; then
    if grep -q '^dtoverlay=vc4-kms-v3d' "$CONFIG"; then
        sed -i '/^dtoverlay=vc4-kms-v3d$/a hdmi_force_hotplug=1' "$CONFIG"
    else
        echo 'hdmi_force_hotplug=1' >> "$CONFIG"
    fi
    info "  Added hdmi_force_hotplug=1"
else
    warn "  hdmi_force_hotplug=1 already present"
fi

#=============================================================================
# Step 5: Rebuild initramfs
#=============================================================================
info "Step 5/5: Rebuilding initramfs..."

update-initramfs -u -k all

# Verify across all installed initramfs files (Pi 5 uses _2712, Pi 4 uses _v8, etc.)
FOUND=false
for img in /boot/firmware/initramfs*; do
    if lsinitramfs "$img" 2>/dev/null | grep -q edid-hdmi-audio; then
        info "EDID packed into $(basename "$img")"
        FOUND=true
    fi
done
if ! $FOUND; then
    warn "EDID not found in initramfs files (may still boot fine if /lib/firmware is available early)"
fi

echo ""
info "============================================"
info "  Setup complete. Reboot to take effect."
info "============================================"
echo ""
echo "Reboot:  sudo systemctl reboot"
echo ""
echo "Verify:"
echo "  dmesg | grep 'ELD size'"
echo "  speaker-test -D plughw:vc4hdmi0 -c 2 -t sine -f 440"
echo ""
echo "Rollback:"
echo "  sudo cp /boot/firmware/cmdline.txt.bak /boot/firmware/cmdline.txt"
echo "  sudo sed -i '/hdmi_force_hotplug=1/d' /boot/firmware/config.txt"
echo "  sudo rm /lib/firmware/edid-hdmi-audio.bin"
echo "  sudo rm /etc/initramfs-tools/hooks/edid-hdmi-audio"
echo "  sudo update-initramfs -u -k all"
echo "  sudo systemctl reboot"
