# Pi HDMI EDID Dynamic Switch

Automated EDID management for Raspberry Pi 5 with HDMI audio extractors.

## Problem

HDMI audio extractors often don't provide EDID or assert HPD, causing the Pi5's
vc4-kms-v3d driver to reject HDMI audio (error -524 ENOTSUPP). Meanwhile, when
a 4K display is connected behind the extractor, the real EDID must be read for
proper resolution.

**The core conflict:** force a fake EDID → audio works but 4K is blocked;
don't force → 4K works but audio is blocked.

## Solution

Three pieces:

1. `vc4.force_hotplug=1` in cmdline.txt — forces HDMI connector to "connected"
2. `hdmi-edid-boot-check` systemd service — at boot, detects real EDID; if absent,
   writes a fake EDID (1080p + audio) via debugfs `edid_override`
3. `hdmi-edid-switch` — one-command manual toggle that clears the override,
   reads DDC, and uses real EDID if available or falls back to fake

```
Boot
  │  vc4.force_hotplug=1 → connector forced connected
  │  hdmi-edid-boot-check → read DDC
  │    ├─ Real EDID present → no override (4K works)
  │    └─ No EDID → write fake EDID to edid_override (1080p + audio)
  │
  └─ Runtime: hdmi-edid-switch
       Clear override → read DDC → real if available / fake if not
```

## Behavior Matrix

| Scenario | Action | Result |
|----------|--------|--------|
| Extractor only (no display) | Boot auto | Fake EDID 1080p + audio |
| Extractor + 4K display | Boot auto | Real EDID → 4096x2160/3840x2160 |
| Unplug 4K display | `hdmi-edid-switch` | Auto fallback to fake EDID |
| Plug 4K display | `hdmi-edid-switch` | Auto switch to 4K |

## Files

```
pi-hdmi-edid/
├── scripts/
│   ├── hdmi-edid-boot-check    # Boot-time EDID detection (systemd oneshot)
│   ├── hdmi-edid-switch        # One-command manual toggle
│   ├── hdmi-edid-rollback      # Restore original config
│   └── generate-fake-edid.py   # Generate the 256-byte fake EDID binary
├── systemd/
│   └── hdmi-edid-boot.service  # Systemd unit file
└── docs/
    └── Pi-HDMI-EDID.md         # Full documentation (Chinese)
```

## Quick Start

```bash
# 1. Generate fake EDID
sudo python3 scripts/generate-fake-edid.py

# 2. Install scripts
sudo cp scripts/hdmi-edid-* /usr/local/bin/
sudo chmod +x /usr/local/bin/hdmi-edid-*

# 3. Install systemd service
sudo cp systemd/hdmi-edid-boot.service /etc/systemd/system/
sudo systemctl daemon-reload
sudo systemctl enable hdmi-edid-boot.service

# 4. Add vc4.force_hotplug=1 to /boot/firmware/cmdline.txt
# 5. Reboot

# 6. Switch EDID mode anytime
sudo hdmi-edid-switch
```

## Requirements

- Raspberry Pi 5 (or Pi 4 with vc4-kms-v3d)
- Raspberry Pi OS Bookworm
- Kernel 6.x with debugfs mounted

## Key Interfaces

| Interface | Path | Purpose |
|-----------|------|---------|
| Runtime EDID override | `/sys/kernel/debug/dri/1/HDMI-A-1/edid_override` | Write EDID=override; write "reset"=restore |
| Trigger reprobe | `echo detect > /sys/class/drm/card1-HDMI-A-1/status` | Re-read DDC, refresh mode list |
| Force hotplug | `vc4.force_hotplug=1` (cmdline) | Force connector connected without physical HPD |

## Caveats

- `vc4.force_hotplug=1` blocks HPD transitions — auto-detection of 4K passthrough
  requires manual `hdmi-edid-switch`
- `stat -c%s` is unreliable on sysfs files — use `cat | wc -c` for binary data
- bash `$()` strips null bytes from binary EDID — use temp files
- Runtime write to `/sys/module/vc4/parameters/force_hotplug` has no effect —
  must be set in cmdline.txt before boot

## References

- [Pi Forum: Pi5 HDMI sound after projector](https://forums.raspberrypi.com/viewtopic.php?t=368491)
- [Pi Forum: Pi5 HDMI issues with receiver](https://forums.raspberrypi.com/viewtopic.php?t=358917)
- [Arch Wiki: Kernel Mode Setting](https://wiki.archlinux.org/title/kernel_mode_setting)
- [Kernel docs: drm.edid_firmware](https://www.kernel.org/doc/html/latest/admin-guide/edid.html)

## License

MIT
