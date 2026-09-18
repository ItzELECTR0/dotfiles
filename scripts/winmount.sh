#!/usr/bin/env bash
#
# winmount.sh
#
# Toggles mount/unmount of the Windows 11 VM's disk image on the host.
#   1st run -> loads nbd + ntfs3 modules, connects the image via qemu-nbd,
#              finds the Windows partition and mounts it with your uid/gid.
#   2nd run -> unmounts it, disconnects qemu-nbd, unloads the modules.
#
# Live mounting: if the VM is running, the image is exported and mounted
# READ-ONLY. Writing to a disk the guest is also writing to would corrupt it,
# so read-write is only used when the VM is shut down. A live mount also needs
# force-share=on, otherwise qemu-nbd refuses to open an image another qemu
# process has locked (same thing `qemu-img -U` does).
#
# Counterpart to macmount.sh. Defaults to /dev/nbd1 so both can be mounted at
# the same time. The privileged half runs as one doas call, so it asks for
# the password once instead of once per command.
#
# Usage: winmount.sh [-p|--path IMG] [-l|--live] [-u|--umount] [-h|--help]
#   (no args)     toggle mount/unmount
#   -p, --path    mount this image instead of the default one
#   -l, --live    force the read-only live path even if the VM looks shut down
#   -u, --umount  unmount only, never mount
#
# Env overrides: WINMOUNT_IMG, WINMOUNT_DIR, WINMOUNT_NBD, WINMOUNT_PART,
#                WINMOUNT_FORMAT (skip format detection), WINMOUNT_FORCE=1
#                (mount a dirty volume read-write anyway)

set -uo pipefail

IMG_PATH="${WINMOUNT_IMG:-/var/lib/libvirt/images/spark.img}"
IMG_FORMAT="${WINMOUNT_FORMAT:-}"   # empty = ask qemu-img what the image is
MOUNT_POINT="${WINMOUNT_DIR:-$HOME/Windows}"
NBD_DEV="${WINMOUNT_NBD:-/dev/nbd1}"
PART_DEV="${WINMOUNT_PART:-}"   # empty = autodetect the largest NTFS partition
FS_TYPE="ntfs3"
FS_MODULE="ntfs3"

SELF="$(readlink -f "$0")"
MOUNT_UID="${WINMOUNT_UID:-$(id -u)}"
MOUNT_GID="${WINMOUNT_GID:-$(id -g)}"

FORCE_LIVE="${WINMOUNT_LIVE:-0}"
UMOUNT_ONLY="${WINMOUNT_UMOUNT:-0}"

usage() {
    cat <<'EOF'
Usage: winmount.sh [-p|--path IMG] [-l|--live] [-u|--umount] [-h|--help]
  (no args)     toggle mount/unmount
  -p, --path    mount this image instead of the default one
  -l, --live    force the read-only live path even if the VM looks shut down
  -u, --umount  unmount only, never mount

Env overrides: WINMOUNT_IMG, WINMOUNT_DIR, WINMOUNT_NBD, WINMOUNT_PART,
               WINMOUNT_FORMAT (skip format detection), WINMOUNT_FORCE=1
               (mount a dirty volume read-write anyway)
EOF
}

while [ $# -gt 0 ]; do
    case "$1" in
        -p|--path)   shift
                     [ $# -gt 0 ] || { echo "--path needs an image" >&2; exit 2; }
                     IMG_PATH="$1" ;;
        --path=*)    IMG_PATH="${1#--path=}" ;;
        -l|--live)   FORCE_LIVE=1 ;;
        -u|--umount) UMOUNT_ONLY=1 ;;
        -h|--help)   usage; exit 0 ;;
        *)           echo "Unknown option: $1 (try --help)" >&2; exit 2 ;;
    esac
    shift
done

IMG_PATH="$(readlink -f "$IMG_PATH" 2>/dev/null || printf '%s' "$IMG_PATH")"

# Everything past here needs root, and prefixing each command with doas asks
# for the password half a dozen times per run, so hand the job over once.
if [ "$(id -u)" -ne 0 ]; then
    exec doas env WINMOUNT_UID="$MOUNT_UID" WINMOUNT_GID="$MOUNT_GID" \
        WINMOUNT_IMG="$IMG_PATH" WINMOUNT_DIR="$MOUNT_POINT" \
        WINMOUNT_NBD="$NBD_DEV" WINMOUNT_PART="$PART_DEV" \
        WINMOUNT_FORMAT="$IMG_FORMAT" WINMOUNT_FORCE="${WINMOUNT_FORCE:-0}" \
        WINMOUNT_LIVE="$FORCE_LIVE" WINMOUNT_UMOUNT="$UMOUNT_ONLY" \
        "$SELF"
fi

# --- helpers ---------------------------------------------------------------

# Is some qemu process already holding this image open? Covers both libvirt
# (which passes the disk inside a -blockdev JSON blob) and a hand-rolled
# -drive line, so the match is a substring of argv rather than a whole arg.
# A containerised VM (WinBoat) passes its own in-container path for the same
# file, so match the basename too; a false positive only costs a read-only mount.
vm_is_running() {
    local img base cmdline comm pidpath
    img="$(readlink -f "$1" 2>/dev/null || printf '%s' "$1")"
    base="${img##*/}"
    for pidpath in /proc/[0-9]*; do
        comm="$(cat "$pidpath/comm" 2>/dev/null)" || continue
        case "$comm" in
            qemu-system-*|qemu-kvm*) ;;
            *) continue ;;
        esac
        cmdline="$(tr '\0' '\n' < "$pidpath/cmdline" 2>/dev/null)" || continue
        case "$cmdline" in
            *"$img"*|*"$base"*) return 0 ;;
        esac
    done
    return 1
}

# size is 0 while an nbd device is disconnected, non-zero once it's live
dev_size() {
    cat "/sys/class/block/${1##*/}/size" 2>/dev/null || echo 0
}

# Don't rmmod nbd out from under a sibling script (macmount.sh) holding another
# device.
nbd_others_connected() {
    local me="${1##*/}" name d
    for d in /sys/class/block/nbd*; do
        [ -d "$d" ] || continue
        name="${d##*/}"
        case "$name" in "$me"|"$me"p*) continue ;; esac
        [ "$(dev_size "$name")" -gt 0 ] && return 0
    done
    return 1
}

fs_still_mounted() {
    awk -v t="$1" '$3 == t { found = 1 } END { exit !found }' /proc/mounts
}

wait_for_dev() {
    local dev="$1" i
    for i in $(seq 1 20); do
        [ "$(dev_size "$dev")" -gt 0 ] && return 0
        sleep 0.5
    done
    return 1
}

# A Windows 11 GPT disk has several partitions (EFI, MSR, Windows, Recovery)
# and both Windows and Recovery are NTFS, so pick the biggest NTFS one.
# blkid -p probes the device directly instead of trusting the udev cache,
# which matters for a device that appeared a second ago.
find_windows_partition() {
    local dev name size type best="" best_size=0
    for dev in "$NBD_DEV"p*; do
        [ -b "$dev" ] || continue
        name="${dev##*/}"
        size="$(dev_size "$name")"
        [ "$size" -gt 0 ] || continue
        type="$(blkid -p -s TYPE -o value "$dev" 2>/dev/null)"
        [ "$type" = "ntfs" ] || continue
        if [ "$size" -gt "$best_size" ]; then
            best="$dev"
            best_size="$size"
        fi
    done
    [ -n "$best" ] || return 1
    printf '%s\n' "$best"
}

# --- unmount ---------------------------------------------------------------

if mountpoint -q "$MOUNT_POINT" 2>/dev/null; then
    echo "==> $MOUNT_POINT is mounted, unmounting..."
    if ! umount "$MOUNT_POINT"; then
        echo "    Unmount failed. Something is still using it:"
        fuser -vm "$MOUNT_POINT" 2>&1 | sed 's/^/    /'
        exit 1
    fi

    echo "==> Disconnecting $NBD_DEV..."
    qemu-nbd --disconnect "$NBD_DEV"

    # give the kernel a moment to release the device before unloading modules
    sleep 1

    echo "==> Unloading $FS_MODULE and nbd modules..."
    if fs_still_mounted "$FS_TYPE"; then
        echo "    (another $FS_TYPE mount is live, leaving $FS_MODULE loaded)"
    else
        rmmod "$FS_MODULE" 2>/dev/null || echo "    ($FS_MODULE module busy, built in, or already unloaded)"
    fi
    if nbd_others_connected "$NBD_DEV"; then
        echo "    (another nbd device is connected, leaving nbd loaded)"
    else
        rmmod nbd 2>/dev/null || echo "    (nbd module busy, in use, or already unloaded)"
    fi

    echo "==> Removing $MOUNT_POINT..."
    rmdir "$MOUNT_POINT" 2>/dev/null || echo "    (couldn't remove $MOUNT_POINT, check it's empty)"

    echo "==> Done. Image unmounted and cleaned up."
    exit 0
fi

if [ "$UMOUNT_ONLY" -eq 1 ]; then
    echo "==> $MOUNT_POINT isn't mounted, nothing to do."
    exit 0
fi

# --- mount -----------------------------------------------------------------

if [ ! -e "$IMG_PATH" ]; then
    echo "==> Image not found: $IMG_PATH" >&2
    exit 1
fi

# --path can point at anything, so ask qemu what the image is instead of
# assuming the default one's raw format.
if [ -z "$IMG_FORMAT" ]; then
    IMG_FORMAT="$(qemu-img info -U "$IMG_PATH" 2>/dev/null | awk -F': ' '/^file format:/ { print $2; exit }')"
    IMG_FORMAT="${IMG_FORMAT:-raw}"
fi

if [ "$(dev_size "$NBD_DEV")" -gt 0 ]; then
    echo "==> $NBD_DEV is already connected to something." >&2
    echo "    Disconnect it first (doas qemu-nbd --disconnect $NBD_DEV) or set" >&2
    echo "    WINMOUNT_NBD to a free device." >&2
    exit 1
fi

READ_ONLY=0
if [ "$FORCE_LIVE" -eq 1 ]; then
    READ_ONLY=1
    echo "==> Live mount forced, mounting read-only."
elif vm_is_running "$IMG_PATH"; then
    READ_ONLY=1
    echo "==> A qemu process is using $IMG_PATH -- the VM is running."
    echo "    Mounting read-only. Writing to a live disk would corrupt it."
    echo "    Note the guest keeps writing underneath you, so what you see is a"
    echo "    snapshot of a moving target: files being written may look torn."
else
    echo "==> VM looks shut down, mounting read-write."
fi

echo "==> Loading nbd and $FS_MODULE modules..."
modprobe nbd max_part=8
modprobe "$FS_MODULE"

echo "==> Connecting $IMG_PATH to $NBD_DEV..."
if [ "$READ_ONLY" -eq 1 ]; then
    # --image-opts is comma-separated, so a comma in the path would be parsed
    # as an option boundary.
    case "$IMG_PATH" in
        *,*) echo "    Image path contains a comma; --image-opts can't express that." >&2
             exit 1 ;;
    esac
    # force-share=on drops the CONSISTENT_READ requirement, which is what lets
    # us open an image the running VM holds a write lock on.
    CONNECT=(qemu-nbd --connect="$NBD_DEV" --read-only --image-opts
             "driver=$IMG_FORMAT,file.driver=file,file.filename=$IMG_PATH,force-share=on,read-only=on")
else
    CONNECT=(qemu-nbd --connect="$NBD_DEV" --format="$IMG_FORMAT" "$IMG_PATH")
fi

if ! "${CONNECT[@]}"; then
    echo "    Connect failed. If this is a stale write-lock, check for a"
    echo "    lingering qemu process with: ps aux | grep qemu"
    echo "    If the VM really is running, force the read-only path: $0 --live"
    exit 1
fi

# Wait for the kernel to register the partition devices before probing them.
# The kernel scans the partition table right after the capacity change, but the
# partition nodes can take a moment longer to show up than nbd1 itself.
echo "==> Waiting for partitions on $NBD_DEV..."
if ! wait_for_dev "${NBD_DEV}p1"; then
    echo "    No partitions appeared -- connection didn't come up cleanly."
    qemu-nbd --disconnect "$NBD_DEV"
    exit 1
fi

if [ -z "$PART_DEV" ]; then
    echo "==> Looking for the Windows partition..."
    # p1 showing up doesn't mean the whole table has been added yet, so give the
    # later partitions a few tries to appear before giving up.
    for _ in $(seq 1 10); do
        PART_DEV="$(find_windows_partition)"
        [ -n "$PART_DEV" ] && break
        sleep 0.5
    done
    if [ -z "$PART_DEV" ]; then
        echo "    No NTFS partition found on $NBD_DEV. Partition table:"
        lsblk -o NAME,SIZE,FSTYPE,LABEL "$NBD_DEV" 2>&1 | sed 's/^/    /'
        echo "    Set WINMOUNT_PART to pick one by hand."
        qemu-nbd --disconnect "$NBD_DEV"
        exit 1
    fi
    echo "    Picked $PART_DEV ($(( $(dev_size "$PART_DEV") / 2097152 )) GiB)"
elif ! wait_for_dev "$PART_DEV"; then
    echo "    $PART_DEV never appeared."
    qemu-nbd --disconnect "$NBD_DEV"
    exit 1
fi

echo "==> Creating $MOUNT_POINT..."
mkdir -p "$MOUNT_POINT"
chown "$MOUNT_UID:$MOUNT_GID" "$MOUNT_POINT"

# ntfs3 refuses a read-write mount of a volume marked dirty, which is what you
# get from hibernation or Windows' Fast Startup. 'force' overrides that; it's
# safe alongside 'ro' because nothing gets written, but read-write on a dirty
# volume can lose data, so that needs WINMOUNT_FORCE=1 set deliberately.
NTFS_OPTS="uid=$MOUNT_UID,gid=$MOUNT_GID,umask=022,windows_names"
if [ "$READ_ONLY" -eq 1 ]; then
    MOUNT_OPTS="ro,force,$NTFS_OPTS"
elif [ "${WINMOUNT_FORCE:-0}" = "1" ]; then
    MOUNT_OPTS="rw,force,$NTFS_OPTS"
else
    MOUNT_OPTS="rw,$NTFS_OPTS"
fi

echo "==> Mounting $PART_DEV at $MOUNT_POINT ($MOUNT_OPTS)..."
if ! mount -t "$FS_TYPE" "$PART_DEV" "$MOUNT_POINT" -o "$MOUNT_OPTS"; then
    echo "    Mount failed. Kernel said:"
    dmesg | tail -5 | sed 's/^/    /'
    if [ "$READ_ONLY" -eq 0 ]; then
        echo "    If it says the volume is dirty, Windows was hibernated or shut"
        echo "    down with Fast Startup. Boot it and run 'shutdown /s /t 0', or"
        echo "    disable Fast Startup. To mount it anyway (risks losing whatever"
        echo "    Windows had in flight): WINMOUNT_FORCE=1 $0"
    fi
    echo "    Cleaning up nbd connection..."
    qemu-nbd --disconnect "$NBD_DEV"
    rmdir "$MOUNT_POINT" 2>/dev/null
    exit 1
fi

if [ "$READ_ONLY" -eq 1 ]; then
    echo "==> Mounted READ-ONLY. Browse it at $MOUNT_POINT"
else
    echo "==> Mounted read-write. Browse it at $MOUNT_POINT"
fi
