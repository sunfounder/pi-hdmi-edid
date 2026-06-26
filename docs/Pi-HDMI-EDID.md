---
title: Pi HDMI EDID动态切换方案
created: 2026-06-25
updated: 2026-06-26
type: concept
tags: [HDMI, 音频, EDID, Pi5, vc4, 驱动, debugfs, 动态切换]
sources: []
confidence: high
---

# Pi HDMI EDID 动态切换方案

## 问题

HDMI音频提取器连接树莓派时，提取器不提供EDID或不断言HPD，导致Pi5内核（vc4-kms-v3d）
无法启用HDMI音频。同时当提取器后面接入4K显示器时，需要读取显示器真实EDID以获取4K分辨率。

**核心矛盾**：强制假EDID → 音频可用但4K不可用；不强制 → 4K可用但音频不可用。

## 方案

三步：`vc4.force_hotplug=1` 强制connector connected + 开机自动判断 + 手动一键切换。

```
开机
  │  vc4.force_hotplug=1 → connector forced connected
  │  hdmi-edid-boot-check → 读DDC
  │    ├─ 有真EDID → 不操作（4K可用）
  │    └─ 无真EDID → 写假EDID到edid_override（1080p+音频）
  │
  └─ 运行时: hdmi-edid-switch
       清override → 读DDC → 有则用真/无则用假
```

## Pi上部署文件

| 文件 | 作用 |
|------|------|
| `/boot/firmware/config.txt` | `hdmi_force_hotplug=1` |
| `/boot/firmware/cmdline.txt` | `vc4.force_hotplug=1` |
| `/lib/firmware/edid-hdmi-audio.bin` | 假EDID(256B,1080p+LPCM音频) |
| `/usr/local/bin/hdmi-edid-boot-check` | 开机检测，systemd调用 |
| `/usr/local/bin/hdmi-edid-switch` | 手动一键切换 |
| `/usr/local/bin/hdmi-edid-rollback` | 恢复原始配置 |
| `/etc/systemd/system/hdmi-edid-boot.service` | 开机自动运行 |

## 关键接口

| 接口 | 路径 | 作用 |
|------|------|------|
| 运行时EDID覆盖 | `/sys/kernel/debug/dri/1/HDMI-A-1/edid_override` | 写EDID=覆盖；写"reset"=恢复 |
| 触发重探测 | `echo detect > /sys/class/drm/card1-HDMI-A-1/status` | 重读DDC刷新模式 |
| 强制热插拔 | `vc4.force_hotplug=1` (cmdline) | 无设备时强制connector connected |

## 使用方式

```bash
# 一键切换（自动判断真/假EDID）
hdmi-edid-switch

# 查看启动日志
journalctl -t hdmi-edid-boot --no-pager

# 验证音频
aplay -D plughw:vc4hdmi0 /usr/share/sounds/alsa/Front_Center.wav

# 查看当前分辨率
cat /sys/class/drm/card1-HDMI-A-1/modes | head -10

# 回滚
hdmi-edid-rollback && shutdown -r now
```

## 效果

| 场景 | 行为 | 分辨率 |
|------|------|--------|
| 只插提取器 | 开机无EDID → 自动写假EDID | 1080p + 音频 |
| 提取器+4K屏 | 开机读到真EDID → 不覆盖 | 4096x2160/3840x2160 |
| 4K屏拔出 | 跑 `hdmi-edid-switch` | 自动切回假EDID |
| 4K屏插入 | 跑 `hdmi-edid-switch` | 自动切回4K |

## 根因

内核 `vc4_hdmi_audio_can_stream()` 检查 `display->is_hdmi`，由EDID的CEA-861扩展块决定。
无EDID或无CEA块 → 音频返回-524 ENOTSUPP。

`vc4.force_hotplug=1` 让 `vc4_hdmi_detect()` 永远返回connected，绕过HPD检测。
但它同时**阻断HPD翻转** → 提取器切换透传模式时Pi不会自动重读EDID。
因此需要手动 `hdmi-edid-switch` 触发重读。

## 假EDID结构

| 块 | 大小 | 内容 |
|----|------|------|
| Block 0 | 128B | 基础EDID: 1920x1080@60Hz |
| Block 1 (CEA-861) | 128B | Audio: LPCM 2ch + Speaker: FL/FR + HDMI Vendor |

## 踩坑

1. `stat -c%s` 对sysfs文件不可靠，必须用 `cat | wc -c`
2. bash `$()` 截断二进制null byte，必须写临时文件
3. `vc4.force_hotplug` 运行时写入 `/sys/module/vc4/parameters/` 无效，必须cmdline重启
4. `hdmi_force_hotplug=1` (config.txt) 在Pi5 vc4-kms-v3d下不生效
5. `video=HDMI-A-1:...D` 的 `D` 后缀只影响fbdev层，不影响vc4 detect()

## 参考

- [Pi Forum: Pi5 HDMI sound after projector](https://forums.raspberrypi.com/viewtopic.php?t=368491) — `vc4.force_hotplug=1` 方案起源
- [Pi Forum: Pi5 HDMI issues with receiver](https://forums.raspberrypi.com/viewtopic.php?t=358917) — EDID emulator硬件方案，最终结论是买物理EDID Feeder
- [Pi Forum: HDMI issues with new Pi5](https://forums.raspberrypi.com/viewtopic.php?t=358917&start=25) — `drm.edid_firmware` + `video=...D` 的讨论
- [Arch Wiki: Kernel Mode Setting](https://wiki.archlinux.org/title/kernel_mode_setting) — debugfs `edid_override` 文档
- [内核文档: drm.edid_firmware](https://www.kernel.org/doc/html/latest/admin-guide/edid.html)
- 内核源码: `drivers/gpu/drm/vc4/vc4_hdmi.c` (vc4_hdmi_audio_startup, vc4_hdmi_detect)
