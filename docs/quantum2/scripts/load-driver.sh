#!/usr/bin/env bash
# Authorize the Quantum over Thunderbolt, then insmod the dev build.
# Unload with: sudo rmmod snd_quantum
set -euo pipefail
cd "$(dirname "$0")/../../.."
boltctl list | grep -A6 'Quantum 2' | grep -q 'authorized' || \
  boltctl authorize "$(boltctl list | awk '/Quantum 2/{f=1} f&&/uuid/{print $3; exit}')"
make >/dev/null
modprobe snd-pcm; modprobe snd-rawmidi
insmod ./snd-quantum.ko dyndbg=+p   # show dev_dbg init/TCI trace
sleep 2
dmesg | grep -i quantum | tail -40
cat /proc/asound/cards
