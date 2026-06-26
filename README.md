# Pi HDMI EDID Dynamic Switch

One script to manage HDMI EDID on Raspberry Pi 5 with audio extractors.

## Problem

HDMI audio extractors often don't assert HPD or provide EDID, causing Pi5's
vc4-kms-v3d driver to reject HDMI audio. When a 4K display is connected behind
the extractor, real EDID must be available for proper resolution.

## Solution

```bash
sudo hdmi-edid setup     # One-time deployment
sudo hdmi-edid switch    # Auto-detect and switch EDID mode
sudo hdmi-edid rollback  # Restore original config
```

At boot, systemd runs `hdmi-edid switch` — reads DDC, uses real EDID if present,
otherwise applies a fake EDID with 1080p + audio.

## Quick Start

```bash
curl -O https://raw.githubusercontent.com/sunfounder/pi-hdmi-edid/main/hdmi-edid
chmod +x hdmi-edid
sudo ./hdmi-edid setup
sudo reboot
```

After reboot, the extractor's audio works. When 4K display is connected, run:

```bash
sudo hdmi-edid switch
```

## Files

```
├── hdmi-edid                   # Main script (setup|switch|rollback)
├── hdmi-edid-boot.service      # systemd unit
├── README.md
├── LICENSE
└── docs/Pi-HDMI-EDID.md        # Full documentation (Chinese)
```

## Requirements

- Raspberry Pi 5 (or Pi 4 with vc4-kms-v3d)
- Raspberry Pi OS Bookworm
- No external dependencies (pure bash, embedded EDID binary)

## License

MIT
