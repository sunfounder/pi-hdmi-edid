# Pi HDMI EDID

One script to manage HDMI EDID on Raspberry Pi 5 with audio extractors.

## Install

```bash
curl -sL https://raw.githubusercontent.com/sunfounder/pi-hdmi-edid/main/install.sh | sudo bash
sudo reboot
```

## Usage

```bash
hdmi-edid switch     # Auto-detect: real EDID if available, else fake (1080p+audio)
hdmi-edid uninstall  # Remove all configuration
```

At boot, systemd runs `hdmi-edid switch` automatically.

## How It Works

| Scenario | Boot | Manual |
|----------|------|--------|
| Extractor only | Auto-apply fake EDID → 1080p + audio | `hdmi-edid switch` |
| Extractor + 4K display | DDC has real EDID → keep 4K | `hdmi-edid switch` |
| Unplug 4K display | — | `hdmi-edid switch` |

- `vc4.force_hotplug=1` in cmdline.txt forces HDMI connector "connected"
- Fake EDID (256B base64 embedded) provides 1080p + LPCM 2ch audio
- `edid_override` debugfs for runtime switching without reboot

## Files

```
├── install.sh        # One-line installer
├── hdmi-edid         # Runtime script (switch|uninstall)
├── hdmi-edid-boot.service  # systemd unit
├── README.md
├── LICENSE
└── docs/
```

## Requirements

- Raspberry Pi 5 (or Pi 4 with vc4-kms-v3d)
- Raspberry Pi OS Bookworm
- Zero dependencies (pure bash)

## License

MIT
