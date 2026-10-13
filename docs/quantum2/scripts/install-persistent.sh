#!/usr/bin/env bash
# Make the Quantum 2 work at every boot: enroll it with boltd and install
# snd-quantum through DKMS for every kernel that has headers.
# Needs: dkms, bolt, kernel headers. Plug in and power on the Quantum first.
# Usage: sudo docs/quantum2/scripts/install-persistent.sh
set -euo pipefail
[ "$(id -u)" = 0 ] || { echo "Run with sudo"; exit 1; }
command -v dkms >/dev/null || { echo "Install dkms first"; exit 1; }

SRC="$(cd "$(dirname "$0")/../../.." && pwd)"
NAME=snd-quantum
VER=$(sed -n 's/^PACKAGE_VERSION="\(.*\)"/\1/p' "$SRC/dkms.conf")
UUID=$(boltctl list | awk '/Quantum 2/{f=1} f&&/uuid/{print $3; exit}')
[ -n "$UUID" ] || { echo "Quantum 2 not found in 'boltctl list'"; exit 1; }

echo "== 1. Thunderbolt: enroll Quantum 2 ($UUID), auto-authorize on connect"
if boltctl info "$UUID" | grep -q 'stored: *yes'; then
    echo "already enrolled"
else
    boltctl enroll --policy auto "$UUID"
fi

echo "== 2. Copy driver source to /usr/src/$NAME-$VER"
if dkms status -m "$NAME" -v "$VER" | grep -q .; then
    dkms remove -m "$NAME" -v "$VER" --all
fi
rm -rf "/usr/src/$NAME-$VER"
mkdir -p "/usr/src/$NAME-$VER"
cp -r "$SRC"/{sound,include,Makefile,dkms.conf,LICENSE} "/usr/src/$NAME-$VER/"
find "/usr/src/$NAME-$VER" \( -name '*.o' -o -name '*.ko' -o -name '*.mod*' -o -name '.*.cmd' \) -delete

echo "== 3. Build + install for each kernel with headers"
dkms add -m "$NAME" -v "$VER"
for k in /usr/lib/modules/*; do
    k=$(basename "$k")
    if [ -e "/usr/lib/modules/$k/build/Makefile" ]; then
        echo "-- $k"
        dkms install -m "$NAME" -v "$VER" -k "$k" || echo "!! build failed for $k (non-fatal)"
    fi
done

echo "== Result"
dkms status -m "$NAME"
boltctl info "$UUID" | grep -E 'stored|policy|status'
echo "Module the running kernel will load: $(modinfo -n $NAME)"
