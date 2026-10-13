#!/usr/bin/env bash
# Install the Quantum 2 UCM profile system-wide.
# Usage: sudo docs/quantum2/scripts/install-ucm.sh
set -euo pipefail
[ "$(id -u)" = 0 ] || { echo "Run with sudo"; exit 1; }
SRC="$(cd "$(dirname "$0")/../ucm2" && pwd)"
DST=/usr/share/alsa/ucm2
install -Dm644 "$SRC/conf.d/snd-quantum/snd-quantum.conf" "$DST/conf.d/snd-quantum/snd-quantum.conf"
install -Dm644 "$SRC/Quantum2/HiFi.conf" "$DST/Quantum2/HiFi.conf"
echo "Installed:"
ls -l "$DST/conf.d/snd-quantum/snd-quantum.conf" "$DST/Quantum2/HiFi.conf"
