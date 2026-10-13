# PreSonus Quantum 2 (1c67:0102) on Linux

This fork adds the original Thunderbolt 2 **Quantum 2** to the snd-quantum RFC driver. Upstream has only been verified on the Quantum 2626 (`1c67:0104`).

**Status (2026-10-12):** working for playback. TCI handshake OK, LED solid blue, ALSA card `Quantum2`, PipeWire streams 24 channels at 48 kHz. Capture opens but has not been tested with real input yet.

Test machine: Mac Pro 7,1 (2019), Titan Ridge TB3 controller with a TB3↔TB2 adapter, CachyOS, kernels 7.2.9 (clang-built) and 6.18-lts.

## What the patch changes

- Adds PCI ID `1c67:0102` ("Quantum 2").
- The PCM channel count comes from `QUANTUM_REG_CHANNEL_COUNTS` (0x10200) instead of the 2626's hard-coded 26. The DMA path already reads this register.
- Adds `dkms.conf`, and the Makefile builds with clang (`LLVM=1`) or gcc to match the target kernel's config.

## Hardware facts

From a read-only BAR0 probe with no driver bound (`captures/probe-regs_2026-10-12.txt`, made with `scripts/probe-regs.sh`):

| Register | Quantum 2 | Quantum 2626 |
|---|---|---|
| FPGA_IFC_VER (0x08) | `0x10` | `0x10` |
| FPGA_IMAGE_VER (0x04) | `0x01010017` | `0x01030060` |
| MCU_BL / MCU_MAIN (0x10/0x14) | `0` (driver only logs them) | |
| CMD_MSG_CONFIG (0x7c) | `0x10000008` (8 command slots) | |
| CHANNEL_COUNTS (0x10200) | `0x1816`, so **24 playback / 22 capture** | `0x1a1a` (26/26) |
| ADDR_PER_SEGMENT (0x10300/4) | 15 / 15 | 15 / 15 |

- BAR0 is 1 MiB of MMIO, PCI class 0401, the same layout as the 2626. The TB2-era FPGA speaks the same TCI protocol.
- **Output map (checked by ear):** DMA channel 1 goes to rear line out 1, channel 2 to rear line out 2. The front headphone jack mirrors 1/2 in hardware, and its level knob has to be up. Channels 3–8 are silent on the headphones.

## Thunderbolt notes

- With TB security level `user`, the Quantum's PCIe function doesn't appear until it's authorized: `boltctl authorize <uuid>`, or `boltctl enroll --policy auto <uuid>` to make it permanent.
- The PCI address depends on when the device is authorized. On the test machine it was `e6:00.0` when hotplugged and `cf:00.0` when auto-authorized at boot. Don't hard-code it. The WirePlumber rule below gives the PipeWire nodes stable names.

## Install

```sh
# One-off test (authorize, build, insmod with debug output, show dmesg):
sudo docs/quantum2/scripts/load-driver.sh

# Persistent (boltctl enroll + DKMS for every kernel with headers):
sudo docs/quantum2/scripts/install-persistent.sh
```

After changing the driver, bump `PACKAGE_VERSION` in `dkms.conf` and re-run the persistent install. The module autoloads through its PCI alias.

## PipeWire: stereo "Main Out 1/2" sink

There's no UCM profile for the Quantum 2 yet, so PipeWire shows one 24-channel "Multichannel" sink. As a stopgap:

```sh
mkdir -p ~/.config/wireplumber/wireplumber.conf.d ~/.config/pipewire/pipewire.conf.d
cp docs/quantum2/wireplumber/60-quantum2-node-name.conf ~/.config/wireplumber/wireplumber.conf.d/
cp docs/quantum2/pipewire/60-quantum2-stereo.conf ~/.config/pipewire/pipewire.conf.d/
systemctl --user restart wireplumber pipewire
```

This creates a "Quantum 2 Main Out 1/2" sink that loops into AUX0/AUX1. Tested: with HDMI set as the default sink, the loopback still links to `quantum2_multichannel_out` by name.

## Not done yet

- A UCM profile `Quantum2/HiFi.conf`, adapted from the 2626 one with the channel map corrected.
- Capture testing with real inputs, and MIDI.
- The interrupt rate is about 1,380/s with a 128-frame period at 48 kHz, roughly 3.7× the period rate. CPU cost is negligible, but it's worth understanding.

## Files

- `scripts/probe-regs.sh`: read-only register dump (root, no driver bound)
- `scripts/load-driver.sh`: authorize, build, insmod, show dmesg
- `scripts/install-persistent.sh`: boltctl enroll + DKMS install
- `captures/`: register probe, `lspci -vvv`, `boltctl info` (UUIDs redacted)
- `pipewire/`, `wireplumber/`: stereo sink stopgap
