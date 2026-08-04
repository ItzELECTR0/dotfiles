#!/usr/bin/env bash
#
# macmount.sh
#
# Toggles mount/unmount of mac_hdd_ng.img (OSX-KVM) on the host.
#   1st run -> loads nbd + apfs modules, connects the image via qemu-nbd,
#              mounts it read-write with your uid/gid.
#   2nd run -> unmounts it, disconnects qemu-nbd, unloads the modules.

set -uo pipefail

IMG_PATH="$HOME/.osx-kvm/mac_hdd_ng.img"
MOUNT_POINT="$HOME/macOS"
NBD_DEV="/dev/nbd0"
PART_DEV="${NBD_DEV}p2"
MOUNT_OPTS="readwrite,uid=$(id -u),gid=$(id -g)"

if mountpoint -q "$MOUNT_POINT" 2>/dev/null; then
    echo "==> $MOUNT_POINT is mounted, unmounting..."
    doas umount "$MOUNT_POINT"

    echo "==> Disconnecting $NBD_DEV..."
    doas qemu-nbd --disconnect "$NBD_DEV"

    # give the kernel a moment to release the device before unloading modules
    sleep 1

    echo "==> Unloading apfs and nbd modules..."
    doas rmmod apfs 2>/dev/null || echo "    (apfs module busy or already unloaded)"
    doas rmmod nbd 2>/dev/null || echo "    (nbd module busy, in use, or already unloaded)"

    echo "==> Removing $MOUNT_POINT..."
    rmdir "$MOUNT_POINT" 2>/dev/null || echo "    (couldn't remove $MOUNT_POINT, check it's empty)"

    echo "==> Done. Image unmounted and cleaned up."
else
    echo "==> Loading nbd and apfs modules..."
    doas modprobe nbd max_part=8
    doas modprobe apfs

    echo "==> Connecting $IMG_PATH to $NBD_DEV..."
    if ! doas qemu-nbd --connect="$NBD_DEV" "$IMG_PATH"; then
        echo "    Connect failed. If this is a stale write-lock, check for a"
        echo "    lingering qemu process with: ps aux | grep qemu"
        exit 1
    fi

    # Wait for the kernel to register the partition device before mounting.
    # The kernel scans the partition table right after the capacity change,
    # but nbd0p2 can take a moment longer to show up than nbd0 itself.
    echo "==> Waiting for $PART_DEV to appear..."
    PART_NAME="$(basename "$PART_DEV")"
    SIZE=0
    for _ in $(seq 1 20); do
        SIZE="$(cat "/sys/class/block/$PART_NAME/size" 2>/dev/null || echo 0)"
        if [ "$SIZE" -gt 0 ]; then
            break
        fi
        sleep 0.5
    done
    if [ "$SIZE" -eq 0 ]; then
        echo "    $PART_DEV never appeared -- connection didn't come up cleanly."
        doas qemu-nbd --disconnect "$NBD_DEV"
        exit 1
    fi

    echo "==> Creating $MOUNT_POINT..."
    mkdir -p "$MOUNT_POINT"

    echo "==> Mounting $PART_DEV at $MOUNT_POINT..."
    if ! doas mount -t apfs "$PART_DEV" "$MOUNT_POINT" -o "$MOUNT_OPTS"; then
        echo "    Mount failed. Cleaning up nbd connection..."
        doas qemu-nbd --disconnect "$NBD_DEV"
        rmdir "$MOUNT_POINT" 2>/dev/null
        exit 1
    fi

    echo "==> Mounted. Browse it at $MOUNT_POINT"
fi
