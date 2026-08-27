#!/usr/bin/env bash
# _all/release/end - give the GPU back to the host.
#
# Lives under qemu.d/_all/ so it runs for every domain; vms.conf decides which
# domains it acts on, and the teardown marker decides whether there is anything
# to undo. A domain that never got the GPU (because another one already had it)
# must fall straight through here, or stopping the second VM would rip the card
# out from under the first.
#
# This also runs when the domain FAILED to start, which is the only thing
# standing between a bad domain definition and a headless machine. It must
# therefore never abort early and never do anything that can kill its own
# process. Ordering rule:
#
#   release vfio -> load GPU driver -> WAIT FOR A FRAMEBUFFER -> rebind console
#
# The wait is not cosmetic. Binding fbcon with zero registered framebuffers
# NULL-derefs fbcon_cursor() in the kernel and kills this script mid-run, which
# is exactly how a failed start turns into "no signal until you hit reset".
#
# Speed rule as in start.sh: the two slow halves of the restore - dropping the
# vfio modules and loading the GPU driver stack - run concurrently, and every
# wait polls its condition instead of sleeping a fixed amount.

set -uo pipefail

VFIO_TAG=vfio-revert
. /etc/libvirt/hooks/vfio-lib.sh

GUEST="${1:-unknown}"
XML="$(cat 2>/dev/null || true)"
FORCE="${VFIO_FORCE_REVERT:-0}"

# ---------------------------------------------------------------------------
# 0. Should this domain be reverting anything?
# ---------------------------------------------------------------------------

if [ "$FORCE" != 1 ] && ! vfio_guest_listed "$GUEST"; then
    exit 0
fi

T0="$(vfio_now_ms)"
vfio_log "=== release/end for domain '$GUEST' ==="

# If prepare/begin never got past its preflight there is nothing to undo, and
# touching the console here would be actively harmful.
if ! state_has active; then
    vfio_log "no teardown marker - prepare/begin never handed the GPU over; nothing to do"
    exit 0
fi

# The marker names the domain that actually holds the card. Anyone else - a
# second passthrough VM whose start was refused, or one that never reached the
# handover - must leave the restore alone.
OWNER="$(state_get active)"
if [ "$FORCE" != 1 ] && [ -n "$OWNER" ] && [ "$OWNER" != "$GUEST" ]; then
    vfio_log "the GPU belongs to domain '$OWNER', not '$GUEST'; leaving it in place"
    exit 0
fi

# ---------------------------------------------------------------------------
# 1. Recover the device list
# ---------------------------------------------------------------------------

read -r -a GPU_DEVS <<<"$(state_get devices)"

if [ "${#GPU_DEVS[@]}" -eq 0 ] && [ -n "$XML" ]; then
    mapfile -t GPU_DEVS < <(xml_pci_hostdevs "$XML")
fi
if [ "${#GPU_DEVS[@]}" -eq 0 ]; then
    # Last resort: whatever is currently sitting on vfio-pci.
    mapfile -t GPU_DEVS < <(
        for l in /sys/bus/pci/drivers/vfio-pci/0000:*; do
            [ -e "$l" ] && basename "$l"
        done
    )
fi
vfio_log "restoring functions: ${GPU_DEVS[*]:-<none>}"

HOST_GPU_DRIVER="$(state_get gpu_driver)"
[ -n "$HOST_GPU_DRIVER" ] || HOST_GPU_DRIVER=nvidia

# ---------------------------------------------------------------------------
# 2. Take the functions off vfio-pci
# ---------------------------------------------------------------------------
# With managed='yes' libvirt already did this. Doing it again is a no-op; doing
# it when libvirt did not (failed start, crashed qemu) is what saves the boot.

for d in "${GPU_DEVS[@]:-}"; do
    [ -n "$d" ] || continue
    [ -d "/sys/bus/pci/devices/$d" ] || continue
    if [ "$(pci_driver_of "$d" 2>/dev/null || true)" = "vfio-pci" ]; then
        pci_unbind "$d"
    fi
    pci_clear_override "$d"
done

# ---------------------------------------------------------------------------
# 3. Bring the host GPU driver back
# ---------------------------------------------------------------------------
# Unloading vfio and loading the GPU stack are independent once the functions
# are unbound, and they are the two slowest steps of the restore, so they run at
# the same time. The vfio unload is still joined before anything is re-probed:
# a vfio-pci carrying `ids=` from modprobe.d would otherwise be free to grab the
# card back the moment we ask the bus to probe it.

{ for m in $VFIO_MODULES; do mod_unload "$m" 4000 || true; done; } & VFIOMOD_PID=$!

STACK="$(gpu_module_stack "$HOST_GPU_DRIVER")"
# gpu_module_stack lists teardown order (outermost first); load in reverse.
REVERSED=""
for m in $STACK; do REVERSED="$m $REVERSED"; done

for m in $REVERSED; do
    case "$m" in
        nvidia_drm) mod_load nvidia_drm modeset=1 fbdev=1 ;;
        *)          mod_load "$m" ;;
    esac
done

# non-fatal: another VM may still hold vfio, and nothing below needs it gone.
wait "$VFIOMOD_PID" 2>/dev/null || true

{
    for m in $(gpu_aux_modules "$HOST_GPU_DRIVER"); do mod_load "$m" || true; done
} & AUXMOD_PID=$!

# Re-probe every function so the secondary drivers (HDA audio, xHCI, i2c) come
# back too. Prefer the driver we recorded at teardown time.
for d in "${GPU_DEVS[@]:-}"; do
    [ -n "$d" ] || continue
    [ -d "/sys/bus/pci/devices/$d" ] || continue
    pci_reprobe "$d"
done

# If a function is still orphaned, a bus rescan usually picks it up.
all_bound() {
    local d
    for d in "${GPU_DEVS[@]:-}"; do
        [ -n "$d" ] || continue
        pci_driver_of "$d" >/dev/null 2>&1 || return 1
    done
    return 0
}

if ! all_bound; then
    vfio_log "some functions still unbound; triggering PCI rescan"
    echo 1 >/sys/bus/pci/rescan 2>/dev/null || true
    vfio_wait 3000 all_bound || vfio_warn "functions still unbound after rescan"
fi

# ---------------------------------------------------------------------------
# 4. Console - only after a framebuffer actually exists
# ---------------------------------------------------------------------------

sysfb_rebind          # no-op unless start.sh actually unbound something

if wait_for_fb 15; then
    fbcon_rebind
else
    # No fb from the GPU driver and no sysfb to fall back on. Rebinding fbcon
    # now would oops the kernel and abandon the rest of this script, so skip it.
    # The display manager below can still bring up a working session via DRM
    # even with no fbcon; the text console just stays on the dummy driver.
    vfio_warn "continuing without fbcon; starting the display manager anyway"
fi

# ---------------------------------------------------------------------------
# 5. Userspace back up
# ---------------------------------------------------------------------------
# The display manager is what the user is waiting to see, so it goes first and
# everything else is pushed off the critical path.

DM="$(state_get dm)"
[ -n "$DM" ] || DM="$(detect_dm || true)"

{
    for s in $(detect_gpu_services); do
        state_has "svc_$s" && { svc_start "$s"; state_drop "svc_$s"; }
    done
} & SVC_PID=$!

if [ -n "$DM" ]; then
    svc_start "$DM"
else
    vfio_warn "no display manager to start"
fi

wait "$SVC_PID"    2>/dev/null || true
wait "$AUXMOD_PID" 2>/dev/null || true

# NOTE: no `virsh nodedev-reattach` here. Beyond the re-entrancy problem, it is
# redundant with managed='yes', and its failure mode is a hook that gets killed
# halfway through the restore.

# Restore CPU governor
if state_has governor; then
    GOV="$(state_get governor)"
    if [ -n "$GOV" ] && [ -e /sys/devices/system/cpu/cpu0/cpufreq/scaling_governor ]; then
        vfio_log "restoring CPU governor to '$GOV'"
        echo "$GOV" | tee /sys/devices/system/cpu/cpu*/cpufreq/scaling_governor > /dev/null || true
    fi
    state_drop governor
fi

state_drop active
state_drop devices
state_drop primary
state_drop gpu_driver
state_drop dm
rm -f "$VFIO_STATE_DIR/drivers"

vfio_log "=== release/end complete for '$GUEST' in $(( $(vfio_now_ms) - T0 ))ms ==="
exit 0
