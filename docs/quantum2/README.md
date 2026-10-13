# PreSonus Quantum 2 (1c67:0102) on Linux

This fork adds the original Thunderbolt 2 **Quantum 2** to the snd-quantum RFC driver. Upstream has only been verified on the Quantum 2626 (`1c67:0104`).

**Status (2026-10-13):** working. TCI handshake OK, LED solid blue, ALSA card `Quantum2`. All six sample rates (44.1–192 kHz) work for playback and capture streams; see [Sample rate](#sample-rate). Playback is verified by ear on outputs 1/2; capture has not been tested with real input yet. The PipeWire profile below runs at 48 kHz.

Test machine: Mac Pro 7,1 (2019), Titan Ridge TB3 controller with a TB3↔TB2 adapter, CachyOS, kernels 7.2.9 (clang-built) and 6.18-lts.

## What the patch changes

- Adds PCI ID `1c67:0102` ("Quantum 2").
- The PCM channel count comes from `QUANTUM_REG_CHANNEL_COUNTS` (0x10200) instead of the 2626's hard-coded 26. The DMA path already reads this register.
- Adds `dkms.conf`, and the Makefile builds with clang (`LLVM=1`) or gcc to match the target kernel's config.
- Sample rate (all models): the cached rate starts unknown instead of an assumed 48 kHz, so the first stream always sends the rate command.
- Sample rate (Quantum 2): 44.1–192 kHz through the Quantum 2's form of `SET_SAMPLE_RATE`, with the status word checked, and channel counts that follow the rate; see [Sample rate](#sample-rate). The rate and clock source are read at probe. The 2626 path is unchanged.
- Preallocates 512 KiB per PCM stream instead of 64 KiB. With 24 channels, 64 KiB capped the buffer at 640 frames.
- Debug output (`dyndbg`) hex-dumps TCI payloads in both directions.

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

## Sample rate

The Quantum 2 runs at 44.1, 48, 88.2, 96, 176.4 and 192 kHz. The DMA channel count changes with the rate (ADAT S/MUX halves above 48 kHz; ADAT and S/PDIF are off above 96 kHz):

| Rate | Playback / capture channels | `CHANNEL_COUNTS` |
|---|---|---|
| 44.1, 48 kHz | 24 / 22 | `0x1816` |
| 88.2, 96 kHz | 16 / 14 | `0x100e` |
| 176.4, 192 kHz | 6 / 4 | `0x0604` |

The driver constrains ALSA's rate and channels against this table, so a client has to ask for a matching pair. `aplay -c 24 -r 96000` doesn't fail: ALSA picks the nearest rate that allows 24 channels (48 kHz) and prints "rate is not accurate". Use `-c 16` at 88.2/96 kHz and `-c 6` at 176.4/192 kHz.

The TCI commands on this FPGA (image `0x01010017`), channel 0x31:

- `SET_SAMPLE_RATE` (code 0x32) takes two little-endian u32s, `{clock source, rate enum}`, where the enum is 1-based: 1 = 44.1 kHz … 6 = 192 kHz. It answers with a status word, `0` on success. The encoding comes from the DriverKit analysis in [Jamie Steele's notes](https://github.com/jamie-steele/presonus-quantum-linux/blob/master/notes/TCI_PROTOCOL.md).
- Asked for the rate it is already running at, the device sends no reply, so the driver reads the rate back after a timeout.
- `GET_SAMPLE_RATE` (code 0x31) takes the clock source and returns `{device rate enum, rate measured on that source}`.
- The 2626's form, a single rate in Hz, gets status `1` and leaves the clock alone. A one-word enum payload only ever selected 48 kHz, which is why the first version of this patch was 48 kHz only.
- The clock event reports the rate seen on one source (including S/PDIF lock and unlock), not a clock source change. The driver updates its cached rate only when the event names the active source.
- After a rate change the driver waits for `CHANNEL_COUNTS` to follow, and frees DMA before changing the rate, as the vendor driver does.

Before the fix, the RFC driver assumed the device started at 48 kHz and never sent the rate command. The device kept its power-on rate (44.1 kHz here) while ALSA ran at 48 kHz: an 8% drift that PipeWire corrected with audible resync clicks.

Verified at all six rates in both directions: the `hw_ptr` clock in `/proc/asound/Quantum2/pcm0p/sub0/status` stays within 0.005% of nominal.

## Thunderbolt notes

- With TB security level `user`, the Quantum's PCIe function doesn't appear until it's authorized: `boltctl authorize <uuid>`, or `boltctl enroll --policy auto <uuid>` to make it permanent.
- The PCI address depends on when the device is authorized. On the test machine it was `e6:00.0` when hotplugged and `cf:00.0` when auto-authorized at boot. Don't hard-code it. PipeWire's default node names contain the address, so a saved default output is lost when it changes; `wireplumber/51-quantum2-names.conf` gives the UCM nodes stable names (see below).

## Install

```sh
# One-off test (authorize, build, insmod with debug output, show dmesg):
sudo docs/quantum2/scripts/load-driver.sh

# Persistent (boltctl enroll + DKMS for every kernel with headers):
sudo docs/quantum2/scripts/install-persistent.sh
```

After changing the driver, bump `PACKAGE_VERSION` in `dkms.conf` and re-run the persistent install. The module autoloads through its PCI alias.

## PipeWire: UCM profile

`ucm2/` holds an ALSA UCM profile, so PipeWire shows named devices instead of one 24-channel "Multichannel" sink:

```sh
sudo docs/quantum2/scripts/install-ucm.sh   # copies into /usr/share/alsa/ucm2
systemctl --user restart wireplumber pipewire pipewire-pulse
```

| PipeWire device | Channels | Status |
|---|---|---|
| Main Out 1/2 + Headphones | playback 0-1 | verified by ear |
| Line Out 3/4 | playback 2-3 | assumed (analog first, as on the 2626) |
| Mic/Inst 1, Mic/Inst 2, Mic/Line 3, Mic/Line 4 | capture 0-3 | assumed |

The outputs and inputs share one hardware stream per direction through `dshare`/`dsnoop` (48 kHz, 128-frame periods). S/PDIF and ADAT channels are left unmapped until their order is verified.

The UCM profile assumes the 24/22-channel layout, so the desktop stays at 48 kHz. Other rates work directly on `hw:Quantum2` (for example with JACK or a pro-audio profile).

Stable node names, so the default output survives the PCI address changing:

```sh
mkdir -p ~/.config/wireplumber/wireplumber.conf.d
cp docs/quantum2/wireplumber/51-quantum2-names.conf ~/.config/wireplumber/wireplumber.conf.d/
systemctl --user restart wireplumber
wpctl set-default "$(pw-dump | jq -r '.[] | select(.info.props["node.name"]=="quantum2.main_out") | .id')"
```

This names the nodes `quantum2.main_out`, `quantum2.line_out_3_4`, `quantum2.mic_inst_1`, `quantum2.mic_inst_2`, `quantum2.mic_line_3` and `quantum2.mic_line_4`.

`conf.d/snd-quantum/snd-quantum.conf` selects the profile only when the ALSA card id is `Quantum2`. Other Quantum models fall back to PipeWire's plain multichannel profile.

### Without UCM: stereo loopback stopgap

If you'd rather not install system files, `pipewire/` and `wireplumber/` create a "Quantum 2 Main Out 1/2" sink that loops into AUX0/AUX1. Don't combine it with the UCM profile, because the WirePlumber rule would give every UCM sink the same name.

```sh
mkdir -p ~/.config/wireplumber/wireplumber.conf.d ~/.config/pipewire/pipewire.conf.d
cp docs/quantum2/wireplumber/60-quantum2-node-name.conf ~/.config/wireplumber/wireplumber.conf.d/
cp docs/quantum2/pipewire/60-quantum2-stereo.conf ~/.config/pipewire/pipewire.conf.d/
systemctl --user restart wireplumber pipewire
```

## Not done yet

- A UCM/PipeWire profile for 88.2–192 kHz (the current one assumes 24 channels).
- External clock (S/PDIF, ADAT 1) on the Quantum 2.
- Verify Line Out 3/4 and the inputs, then map S/PDIF and ADAT in the UCM profile.
- Capture testing with real inputs, and MIDI.
- The hardware interrupts every 32 frames (about 1,500/s at 48 kHz), independent of the ALSA period. CPU cost is negligible.

## Files

- `scripts/probe-regs.sh`: read-only register dump (root, no driver bound)
- `scripts/load-driver.sh`: authorize, build, insmod, show dmesg
- `scripts/install-persistent.sh`: boltctl enroll + DKMS install
- `captures/`: register probe, `lspci -vvv`, `boltctl info` (UUIDs redacted)
- `scripts/install-ucm.sh`: install the UCM profile
- `ucm2/`: UCM profile (`conf.d/snd-quantum/`, `Quantum2/HiFi.conf`)
- `wireplumber/51-quantum2-names.conf`: stable node names for the UCM profile
- `pipewire/`, `wireplumber/60-quantum2-node-name.conf`: stereo sink stopgap (without UCM only)
