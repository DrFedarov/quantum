#!/usr/bin/env bash
# Read-only probe of Quantum BAR0: version + channel-count registers.
# Run as root with NO driver bound. Avoids read-to-clear regs (0x10004 etc).
set -euo pipefail
BDF=${1:-$(lspci -D -d 1c67: | awk '{print $1}' | head -1)}
[ -n "$BDF" ] || { echo "No 1c67: device on PCI. Run: boltctl authorize <uuid>"; exit 1; }
DEV=/sys/bus/pci/devices/$BDF
[ -e "$DEV/driver" ] && { echo "A driver is bound to $BDF; unload it first."; exit 1; }
echo "Device: $BDF ($(cat $DEV/vendor):$(cat $DEV/device))"
setpci -s "$BDF" COMMAND=0x0002:0x0002   # enable memory decode only (no bus master)
python3 -I - "$DEV/resource0" <<'PY'
import mmap, struct, sys
regs = {0x00000:"FPGA_BL_VER",0x00004:"FPGA_IMAGE_VER",0x00008:"FPGA_IFC_VER",
        0x00010:"MCU_BL_VER",0x00014:"MCU_MAIN_VER",0x0007c:"CMD_MSG_CONFIG",
        0x00104:"DFU_PAYLOAD_SIZE",0x10200:"CHANNEL_COUNTS",
        0x10300:"ADDR_PER_SEGMENT",0x10304:"ADDR_PER_SEGMENT2"}
with open(sys.argv[1], "r+b") as f:
    m = mmap.mmap(f.fileno(), 0x20000, access=mmap.ACCESS_READ)
    for off, name in regs.items():
        v = struct.unpack_from("<I", m, off)[0]
        extra = ""
        if name == "CHANNEL_COUNTS":
            extra = f"  -> playback={(v>>8)&0xff} capture={v&0xff}"
        print(f"  0x{off:05x} {name:18s} 0x{v:08x}{extra}")
PY
setpci -s "$BDF" COMMAND=0x0000:0x0002   # disable memory decode again
