#!/usr/bin/env bash
# Install the rebuilt single-GPU passthrough hooks.
#
#   doas install.sh
#
# Backs up whatever is currently in /etc/libvirt/hooks first.

set -euo pipefail

SRC="$(dirname "$(readlink -f "$0")")"
[ "$(id -u)" -eq 0 ] || { echo "run as root (doas $0)" >&2; exit 1; }

STAMP="$(date +%Y%m%d-%H%M%S)"
if [ -d /etc/libvirt/hooks ]; then
    cp -a /etc/libvirt/hooks "/etc/libvirt/hooks.bak.$STAMP"
    echo "backed up existing hooks -> /etc/libvirt/hooks.bak.$STAMP"
fi

install -d -m 0755 /etc/libvirt/hooks/qemu.d/spark/prepare/begin
install -d -m 0755 /etc/libvirt/hooks/qemu.d/spark/release/end
install -d -m 0755 /var/log/libvirt

install -m 0755 "$SRC/etc/libvirt/hooks/qemu"        /etc/libvirt/hooks/qemu
install -m 0644 "$SRC/etc/libvirt/hooks/vfio-lib.sh" /etc/libvirt/hooks/vfio-lib.sh
install -m 0755 "$SRC/etc/libvirt/hooks/qemu.d/spark/prepare/begin/start.sh" \
                /etc/libvirt/hooks/qemu.d/spark/prepare/begin/start.sh
install -m 0755 "$SRC/etc/libvirt/hooks/qemu.d/spark/release/end/revert.sh" \
                /etc/libvirt/hooks/qemu.d/spark/release/end/revert.sh
install -m 0755 "$SRC/usr/local/bin/vfio-recover"    /usr/local/bin/vfio-recover

# kvm.conf is now pure overrides; don't clobber a customised one.
if [ ! -e /etc/libvirt/hooks/kvm.conf ] \
   || grep -qE '^\s*VIRSH_GPU_VIDEO=' /etc/libvirt/hooks/kvm.conf 2>/dev/null; then
    install -m 0644 "$SRC/etc/libvirt/hooks/kvm.conf" /etc/libvirt/hooks/kvm.conf
    echo "installed new kvm.conf (old values were the hardcoded VIRSH_GPU_* set)"
fi

# libvirt only re-reads hook scripts on daemon restart.
systemctl restart libvirtd 2>/dev/null || systemctl restart virtqemud 2>/dev/null || true

echo
echo "installed. watch the handover from a second machine or a TTY with:"
echo "  journalctl -t vfio-start -t vfio-revert -t vfio-recover -f"
echo "  tail -f /var/log/libvirt/vfio-hook.log"
echo
echo "if a start ever leaves you at 'no signal', ssh in and run:  doas vfio-recover"
