#!/bin/bash
# pi-hdmi-edid installer — one-line deployment for Raspberry Pi 5
# Usage: curl -sL https://raw.githubusercontent.com/sunfounder/pi-hdmi-edid/main/install.sh | sudo bash
set -euo pipefail

[ "$(id -u)" -eq 0 ] || { echo "ERROR: must run as root"; exit 1; }

CMDLINE="/boot/firmware/cmdline.txt"
CONFIG_TXT="/boot/firmware/config.txt"
FAKE_EDID="/lib/firmware/edid-hdmi-audio.bin"
SCRIPT="/usr/local/bin/hdmi-edid"

echo "=== pi-hdmi-edid installer ==="
echo ""

# ─── Step 1: Download EDID generator & create default EDID ───
echo "[1/5] Downloading EDID generator..."
GEN="/tmp/hdmi-edid-gen"
curl -sL -o "$GEN" https://raw.githubusercontent.com/sunfounder/pi-hdmi-edid/main/hdmi-edid-gen
chmod +x "$GEN"
# Default active modes (same as hdmi-edid config defaults)
DEFAULT_MODES="4k30,4k25,4k24,1080p60,1080p50,1080p30,1080p25,1080p24,1080i60,1080i50,720p60,720p50,1440p60,1600p60,uw1080p60,uw1440p60,uxga60,1200p60,1050p60,900p60_1600,900p60,768p60,sxga60,800p60,x1024p60,480p60,480p60_720"
echo "  Generating default EDID..."
python3 "$GEN" "1080p60" "$DEFAULT_MODES"
rm -f "$GEN"
echo ""

# ─── Step 2: Detect audio EDID (sysfs + I2C fallback) ───
echo "[2/5] Detecting audio EDID..."
HAS_AUDIO_EDID=false
EDID_SIZE=0

# First try sysfs
EDID_PATH=$(ls /sys/class/drm/card*-HDMI-A-1/edid 2>/dev/null | head -1)
if [ -n "$EDID_PATH" ]; then
    TMP=$(mktemp)
    cat "$EDID_PATH" > "$TMP" 2>/dev/null || true
    EDID_SIZE=$(wc -c < "$TMP")
    rm -f "$TMP"
fi

# Check audio in EDID data
_check_audio_edid() {
    local edid_file="$1"
    local size=$(wc -c < "$edid_file")
    [ "$size" -lt 256 ] && return 1
    local tag=$(dd if="$edid_file" bs=1 skip=128 count=1 2>/dev/null | od -A n -t u1 | tr -d ' ')
    [ "$tag" != "2" ] && return 1
    local dtd_off=$(dd if="$edid_file" bs=1 skip=130 count=1 2>/dev/null | od -A n -t u1 | tr -d ' ')
    local scan_len=$((dtd_off > 4 ? dtd_off : 4))
    local i=0
    while [ $i -lt $scan_len ]; do
        local byte=$(dd if="$edid_file" bs=1 skip=$((132 + i)) count=1 2>/dev/null | od -A n -t u1 | tr -d ' ')
        local t=$(( (byte >> 5) & 7 ))
        local l=$(( byte & 31 ))
        [ "$t" = "1" ] && [ "$l" -ge 3 ] && return 0
        i=$((i + 1 + l))
    done
    return 1
}

if _check_audio_edid "$EDID_PATH" 2>/dev/null; then
    HAS_AUDIO_EDID=true
    echo "  Audio EDID detected via sysfs (${EDID_SIZE}B) -> Path A"
else
    # Check if connector is even connected
    CONN_STATUS=$(cat "${EDID_PATH%edid}status" 2>/dev/null || echo "unknown")
    if [ "$CONN_STATUS" != "connected" ]; then
        echo "  Connector is $CONN_STATUS — adding vc4.force_hotplug=1..."
        [ ! -f "${CMDLINE}.bak" ] && cp "$CMDLINE" "${CMDLINE}.bak"
        if ! grep -q 'vc4.force_hotplug=1' "$CMDLINE"; then
            sed -i '$s/$/ vc4.force_hotplug=1/' "$CMDLINE"
        fi
        # Assume Path A — reboot will confirm via boot service
        HAS_AUDIO_EDID=true
        echo "  Assuming Path A (will verify after reboot)"
    fi
    # Sysfs failed — try I2C
    echo "  Sysfs: no audio EDID (${EDID_SIZE}B), trying I2C..."
    DDC=""
    for bus in 13 11 14; do
        if i2cdetect -y $bus 0x50 0x50 2>/dev/null | grep -q 50; then
            DDC=$bus; break
        fi
    done
    if [ -n "$DDC" ]; then
        python3 -c "
import subprocess
data=bytearray(256)
for a in range(256):
    r=subprocess.run(['i2cget','-y','$DDC','0x50',str(a)],capture_output=True,text=True)
    if r.returncode==0: data[a]=int(r.stdout.strip(),16)
with open('/tmp/i2c-edid.bin','wb') as f: f.write(bytes(data))
" 2>/dev/null
        if [ -f /tmp/i2c-edid.bin ] && _check_audio_edid /tmp/i2c-edid.bin 2>/dev/null; then
            HAS_AUDIO_EDID=true
            EDID_SIZE=$(wc -c < /tmp/i2c-edid.bin)
            echo "  Audio EDID detected via I2C bus $DDC (${EDID_SIZE}B) -> Path A"
        else
            echo "  I2C: no audio EDID -> Path B"
        fi
        rm -f /tmp/i2c-edid.bin
    else
        echo "  No DDC bus found -> Path B"
    fi
fi

# ─── Step 3: Configure kernel ───
echo "[3/5] Configuring kernel..."

if $HAS_AUDIO_EDID; then
    echo "  Path A: No kernel parameters added (extractor provides audio EDID)"
    [ ! -f "${CMDLINE}.bak" ] && cp "$CMDLINE" "${CMDLINE}.bak"
else
    if ! grep -q 'vc4.force_hotplug=1' "$CMDLINE"; then
        [ ! -f "${CMDLINE}.bak" ] && cp "$CMDLINE" "${CMDLINE}.bak"
        sed -i '$s/$/ vc4.force_hotplug=1/' "$CMDLINE"
        echo "  Added vc4.force_hotplug=1"
    else
        echo "  vc4.force_hotplug=1 already present"
    fi
    if ! grep -q 'drm.edid_firmware=HDMI-A-1:edid-hdmi-audio.bin' "$CMDLINE"; then
        sed -i '$s/$/ drm.edid_firmware=HDMI-A-1:edid-hdmi-audio.bin/' "$CMDLINE"
        echo "  Added drm.edid_firmware=HDMI-A-1:edid-hdmi-audio.bin"
    else
        echo "  drm.edid_firmware already present"
    fi
fi

echo "[4/5] Configuring config.txt..."
if ! grep -q '^hdmi_force_hotplug=1' "$CONFIG_TXT"; then
    sed -i '/^dtoverlay=vc4-kms-v3d$/a hdmi_force_hotplug=1' "$CONFIG_TXT"
    echo "  Added hdmi_force_hotplug=1"
else
    echo "  hdmi_force_hotplug=1 already present"
fi

# ─── Step 4: Install scripts ───
echo "[5/5] Installing scripts..."
curl -sL -o "$SCRIPT" https://raw.githubusercontent.com/sunfounder/pi-hdmi-edid/main/hdmi-edid
chmod +x "$SCRIPT"
echo "  Installed to $SCRIPT"
curl -sL -o /usr/local/bin/hdmi-edid-gen https://raw.githubusercontent.com/sunfounder/pi-hdmi-edid/main/hdmi-edid-gen
chmod +x /usr/local/bin/hdmi-edid-gen
echo "  Installed hdmi-edid-gen"
curl -sL -o /usr/local/bin/hdmi-edid-merge https://raw.githubusercontent.com/sunfounder/pi-hdmi-edid/main/hdmi-edid-merge
chmod +x /usr/local/bin/hdmi-edid-merge
echo "  Installed hdmi-edid-merge"

# ─── Step 5: Install systemd service (Path A only) ───
if $HAS_AUDIO_EDID; then
    cat > /etc/systemd/system/hdmi-edid-boot.service << 'UNITEOF'
[Unit]
Description=HDMI EDID Boot Setup
After=multi-user.target

[Service]
Type=oneshot
ExecStart=/usr/local/bin/hdmi-edid switch
RemainAfterExit=yes
StandardOutput=journal
StandardError=journal

[Install]
WantedBy=multi-user.target
UNITEOF
    systemctl daemon-reload
    systemctl enable hdmi-edid-boot.service
    echo "  Service installed and enabled (Path A)"
else
    echo "  Path B: no boot service (drm.edid_firmware handles EDID)"
    # Disable if previously installed
    systemctl disable hdmi-edid-boot.service 2>/dev/null || true
    rm -f /etc/systemd/system/hdmi-edid-boot.service
    systemctl daemon-reload
fi

echo ""
echo "========================================"
if $HAS_AUDIO_EDID; then
    echo "  Path A: extractor provides audio EDID"
    echo "  -> 4K passthrough + audio work automatically"
else
    echo "  Path B: drm.edid_firmware mode"
    echo "  -> Audio works, 36 resolutions in fake EDID"
    echo "  -> hdmi-edid config to merge external EDID"
fi
echo "========================================"
echo ""
echo "Commands:"
echo "  hdmi-edid switch      # (Path A) switch real/fake EDID"
echo "  hdmi-edid config      # manage EDID resolutions"
echo "  hdmi-edid uninstall   # remove all configuration"
