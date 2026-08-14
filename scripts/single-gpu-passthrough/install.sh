#!/usr/bin/env bash
# Install the rebuilt single-GPU passthrough hooks.
#
#   doas install.sh
#
# Backs up whatever is currently in /etc/libvirt/hooks first.

set -euo pipefail

SRC="$(dirname "$(readlink -f "$0")")"
[ "$(id -u)" -eq 0 ] || { echo "run as root (doas $0)" >&2; exit 1; }

# The guest list lives in the desktop user's home, not in /etc - a file under
# /etc/libvirt/hooks needs a doas to edit whoever owns it, which was the whole
# thing we were trying to avoid. Work out whose home that is and stamp it into
# kvm.conf, which is root-owned and sourced.
OWNER="${SUDO_USER:-${DOAS_USER:-}}"
[ -n "$OWNER" ] || OWNER="$(stat -c %U "$SRC" 2>/dev/null || true)"
case "$OWNER" in ''|root) OWNER="" ;; esac

VMS_RELPATH=".config/vfio-passthrough/vms.conf"
VMS_TEMPLATE="$SRC/../../$VMS_RELPATH"
OWNER_HOME=""
[ -n "$OWNER" ] && OWNER_HOME="$(getent passwd "$OWNER" | cut -d: -f6)"

STAMP="$(date +%Y%m%d-%H%M%S)"
if [ -d /etc/libvirt/hooks ]; then
    cp -a /etc/libvirt/hooks "/etc/libvirt/hooks.bak.$STAMP"
    echo "backed up existing hooks -> /etc/libvirt/hooks.bak.$STAMP"
fi

install -d -m 0755 /etc/libvirt/hooks/qemu.d/_all/prepare/begin
install -d -m 0755 /etc/libvirt/hooks/qemu.d/_all/release/end
install -d -m 0755 /var/log/libvirt

install -m 0755 "$SRC/etc/libvirt/hooks/qemu"        /etc/libvirt/hooks/qemu
install -m 0644 "$SRC/etc/libvirt/hooks/vfio-lib.sh" /etc/libvirt/hooks/vfio-lib.sh
install -m 0755 "$SRC/etc/libvirt/hooks/qemu.d/_all/prepare/begin/start.sh" \
                /etc/libvirt/hooks/qemu.d/_all/prepare/begin/start.sh
install -m 0755 "$SRC/etc/libvirt/hooks/qemu.d/_all/release/end/revert.sh" \
                /etc/libvirt/hooks/qemu.d/_all/release/end/revert.sh
install -m 0755 "$SRC/usr/local/bin/vfio-recover"    /usr/local/bin/vfio-recover

# Older layouts put start.sh/revert.sh under a per-guest directory. Those now
# run in addition to the _all copies, which would mean two teardowns racing each
# other, so they go. Everything is in the backup above.
for stale in /etc/libvirt/hooks/qemu.d/*/prepare/begin/start.sh \
             /etc/libvirt/hooks/qemu.d/*/release/end/revert.sh; do
    [ -e "$stale" ] || continue
    case "$stale" in */qemu.d/_all/*) continue ;; esac
    rm -f "$stale"
    echo "removed superseded per-guest hook: $stale"
done
find /etc/libvirt/hooks/qemu.d -mindepth 1 -type d -empty -delete 2>/dev/null || true

# kvm.conf is pure overrides; don't clobber a customised one.
if [ ! -e /etc/libvirt/hooks/kvm.conf ] \
   || grep -qE '^\s*VIRSH_GPU_VIDEO=' /etc/libvirt/hooks/kvm.conf 2>/dev/null; then
    install -m 0644 "$SRC/etc/libvirt/hooks/kvm.conf" /etc/libvirt/hooks/kvm.conf
    echo "installed new kvm.conf (old values were the hardcoded VIRSH_GPU_* set)"
fi

# Record whose ~/.config the guest list is read from. Root-owned and sourced,
# unlike the guest list itself.
if [ -n "$OWNER" ]; then
    if grep -qE '^[[:space:]]*VFIO_USER=' /etc/libvirt/hooks/kvm.conf 2>/dev/null; then
        sed -i -E "s|^[[:space:]]*VFIO_USER=.*|VFIO_USER=$OWNER|" /etc/libvirt/hooks/kvm.conf
    else
        printf '\nVFIO_USER=%s\n' "$OWNER" >>/etc/libvirt/hooks/kvm.conf
    fi
    echo "guest list will be read from ~$OWNER/$VMS_RELPATH"
else
    echo "could not tell which user to read the guest list from;" \
         "set VFIO_USER in /etc/libvirt/hooks/kvm.conf" >&2
fi

# The guest list itself is never written by this installer - it belongs to the
# user (and, here, to their dotfiles). Just say whether it is actually there.
VMS="${OWNER_HOME:+$OWNER_HOME/$VMS_RELPATH}"
if [ -n "$VMS" ] && [ ! -e "$VMS" ]; then
    echo
    echo "NOTE: $VMS does not exist yet - no domain will get the GPU until it does."
    if [ -e "$VMS_TEMPLATE" ]; then
        # It ships in the dotfiles repo one directory layout up from here, so
        # the normal way to put it in place is to stow, not to copy.
        echo "      it ships in the dotfiles; stow them as $OWNER:"
        echo "        stow -t \"\$HOME\" -d \"$(readlink -f "$SRC/../..")\" ."
    fi
fi

# A pre-existing per-guest directory was the old way of saying "this domain gets
# the GPU". Say so rather than editing the user's file behind their back.
for d in "/etc/libvirt/hooks.bak.$STAMP"/qemu.d/*/; do
    [ -d "$d" ] || continue
    g="$(basename "$d")"
    case "$g" in _all|'*') continue ;; esac
    grep -qxF "vm $g" "${VMS:-/dev/null}" 2>/dev/null && continue
    grep -qxF "$g"    "${VMS:-/dev/null}" 2>/dev/null && continue
    echo "NOTE: domain '$g' had its own hook directory in the old layout." \
         "Add 'vm $g' to ${VMS:-your vms.conf} to keep it working."
done

# libvirt only re-reads hook scripts on daemon restart.
systemctl restart libvirtd 2>/dev/null || systemctl restart virtqemud 2>/dev/null || true

if [ -n "$VMS" ] && [ -r "$VMS" ]; then
    echo
    echo "domains with passthrough, per $VMS:"
    sed -E 's/#.*//; /^[[:space:]]*$/d; s/^[[:space:]]*(vm[[:space:]]+)?/  /' "$VMS" || true
    echo
    echo "add or remove them there any time - no root, no reinstall, no daemon restart."
fi
echo
echo "watch the handover from a second machine or a TTY with:"
echo "  journalctl -t vfio-start -t vfio-revert -t vfio-recover -f"
echo "  tail -f /var/log/libvirt/vfio-hook.log"
echo
echo "if a start ever leaves you at 'no signal', ssh in and run:  doas vfio-recover"
