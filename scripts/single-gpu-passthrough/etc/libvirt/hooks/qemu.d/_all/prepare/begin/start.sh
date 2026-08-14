#!/usr/bin/env bash
# _all/prepare/begin - release the GPU from the host so libvirt can hand it to
# the guest.
#
# Lives under qemu.d/_all/ so it runs for every domain; vms.conf decides which
# domains it actually acts on. Anything not listed there returns immediately
# without touching the host.
#
# Ordering rule that everything below follows:
#   validate -> stop userspace -> release console -> unload GPU driver -> load vfio
# Nothing destructive happens until the preflight has passed, so a broken domain
# definition can no longer black out the desktop.
#
# Second rule: never sleep for a fixed duration. Work that does not touch the
# GPU is started in the background so it overlaps the display manager teardown,
# and every wait polls the condition it cares about so the next step fires the
# moment the previous one is genuinely done.

set -uo pipefail

VFIO_TAG=vfio-start
. /etc/libvirt/hooks/vfio-lib.sh

GUEST="${1:-unknown}"
XML="$(cat)"          # libvirt feeds the full domain XML on stdin

# ---------------------------------------------------------------------------
# 0. Is this one of ours?
# ---------------------------------------------------------------------------

if ! vfio_guest_listed "$GUEST"; then
    vfio_log "domain '$GUEST' is not in the passthrough list; leaving the host alone"
    exit 0
fi

T0="$(vfio_now_ms)"
vfio_log "=== prepare/begin for domain '$GUEST' ==="

[ -n "$XML" ] || vfio_warn "empty domain XML on stdin; falling back to kvm.conf/autodetect"

# One GPU, one guest. If another domain already owns it, this start must fail
# here - before the marker is claimed - so that this domain's release/end sees
# an owner that is not itself and leaves the running guest's GPU alone.
OWNER="$(state_get active)"
if [ -n "$OWNER" ] && [ "$OWNER" != "$GUEST" ]; then
    vfio_die "the GPU is already handed over to domain '$OWNER'; refusing to start '$GUEST' on top of it"
fi
[ -n "$OWNER" ] && vfio_warn "stale teardown marker for '$OWNER' (previous release/end did not finish); re-running the handover"

# ---------------------------------------------------------------------------
# 1. Work out which PCI functions are being handed over
# ---------------------------------------------------------------------------

mapfile -t GPU_DEVS < <(xml_pci_hostdevs "$XML")

if [ "${#GPU_DEVS[@]}" -eq 0 ]; then
    # No XML (manual run) - fall back to explicit config, then to autodetect.
    for v in "${VIRSH_GPU_VIDEO:-}" "${VIRSH_GPU_AUDIO:-}" "${VIRSH_GPU_USB:-}" "${VIRSH_GPU_SERIAL:-}"; do
        [ -n "$v" ] || continue
        GPU_DEVS+=( "$(printf '%s' "$v" | sed -E 's/^pci_//; s/_/:/; s/_/:/; s/_/./')" )
    done
fi
[ "${#GPU_DEVS[@]}" -gt 0 ] || vfio_die "no PCI hostdevs found in domain XML and no VIRSH_GPU_* fallback set"

vfio_log "PCI functions to hand over: ${GPU_DEVS[*]}"

# Primary display function drives which host driver we tear down.
PRIMARY=""
for d in "${GPU_DEVS[@]}"; do
    pci_is_vga "$d" && { PRIMARY="$d"; break; }
done
[ -n "$PRIMARY" ] || PRIMARY="${GPU_DEVS[0]}"

HOST_GPU_DRIVER="$(pci_driver_of "$PRIMARY" 2>/dev/null || true)"
vfio_log "primary display function: $PRIMARY (host driver: ${HOST_GPU_DRIVER:-none})"

# ---------------------------------------------------------------------------
# 2. Preflight - everything that can fail must fail HERE, before teardown
# ---------------------------------------------------------------------------

preflight_fail=0
pf() { vfio_log "PREFLIGHT FAIL: $*"; preflight_fail=1; }

iommu_enabled || pf "IOMMU is not active (need intel_iommu=on / amd_iommu=on on the kernel cmdline)"

# Every host file the domain references must exist and be readable. This is the
# check that would have caught the missing virtio-win ISO before the screen went
# dark instead of after.
while IFS= read -r p; do
    [ -n "$p" ] || continue
    case "$p" in /*) ;; *) continue ;; esac
    [ -e "$p" ] || pf "domain references missing file: $p"
done < <(xml_file_attrs "$XML")

for tag in loader emulator; do
    while IFS= read -r p; do
        [ -n "$p" ] || continue
        case "$p" in /*) ;; *) continue ;; esac
        [ -e "$p" ] || pf "<$tag> path does not exist: $p"
    done < <(xml_elem_text "$XML" "$tag")
done

# <nvram> may legitimately not exist yet (libvirt creates it from the template),
# but its parent directory must.
while IFS= read -r p; do
    [ -n "$p" ] || continue
    case "$p" in /*) ;; *) continue ;; esac
    [ -d "$(dirname "$p")" ] || pf "<nvram> directory missing: $(dirname "$p")"
done < <(xml_elem_text "$XML" nvram)

# Every hostdev must exist, and its whole IOMMU group must be going to the guest,
# otherwise vfio refuses to open the group.
declare -A IN_DOMAIN=()
for d in "${GPU_DEVS[@]}"; do IN_DOMAIN["$d"]=1; done

for d in "${GPU_DEVS[@]}"; do
    [ -d "/sys/bus/pci/devices/$d" ] || { pf "hostdev $d does not exist on this host"; continue; }
    grp="$(iommu_group_of "$d")" || { pf "hostdev $d has no IOMMU group"; continue; }
    for member in $(iommu_group_members "$grp"); do
        [ -n "${IN_DOMAIN[$member]:-}" ] && continue
        # PCIe root ports and bridges in the group are fine, they are not passed.
        case "$(pci_class_of "$member")" in 0x0604*|0x0600*|0x0601*) continue ;; esac
        pf "IOMMU group $grp also contains $member ($(lspci -nns "${member#0000:}" 2>/dev/null | cut -d' ' -f2-)) which is not in the domain - vfio will refuse the group"
    done
done

# Nothing to fall back to if the handover leaves us headless, so make sure a
# remote path exists. Warning only.
svc_active sshd || svc_active ssh || svc_active sshd.socket \
    || vfio_warn "no sshd running - if this handover fails you will have no remote way in"

if [ "$preflight_fail" -ne 0 ]; then
    vfio_die "preflight failed; refusing to tear down the display. Nothing was changed."
fi
vfio_log "preflight OK ($(( $(vfio_now_ms) - T0 ))ms)"

# Only now do we own the teardown; revert.sh keys off this marker.
state_set active "$GUEST"
state_set devices "${GPU_DEVS[*]}"
state_set primary "$PRIMARY"
state_set gpu_driver "${HOST_GPU_DRIVER:-}"

# Record the current driver of each function so revert can put them back.
: >"$VFIO_STATE_DIR/drivers"
for d in "${GPU_DEVS[@]}"; do
    printf '%s %s\n' "$d" "$(pci_driver_of "$d" 2>/dev/null || echo none)" >>"$VFIO_STATE_DIR/drivers"
done
vfio_log "recorded host drivers:$(sed 's/^/ /' "$VFIO_STATE_DIR/drivers" | tr '\n' ',')"

# ---------------------------------------------------------------------------
# 3. Background the work that does not touch the GPU
# ---------------------------------------------------------------------------
# vfio-pci can be resident while the host driver still owns the card; the driver
# core will not move a bound device. Loading it now, alongside the display
# manager teardown, takes the modprobe off the critical path between "GPU is
# free" and "libvirt may bind it". Collected before the hook returns.
{ mod_load vfio && mod_load vfio_iommu_type1 && mod_load vfio_pci; } & VFIOMOD_PID=$!

# ---------------------------------------------------------------------------
# 4. Stop userspace holding the GPU
# ---------------------------------------------------------------------------

DM="$(detect_dm || true)"
GPU_SVCS="$(detect_gpu_services)"

for s in $GPU_SVCS; do state_set "svc_$s" 1; done
{ for s in $GPU_SVCS; do svc_stop "$s"; done; } & SVC_PID=$!

if [ -n "$DM" ]; then
    state_set dm "$DM"
    svc_stop "$DM"
else
    vfio_warn "no display manager detected - assuming a bare TTY session"
fi

# Both of these hold /dev/nvidia*, so the module unload below cannot start until
# they are actually gone.
wait "$SVC_PID" 2>/dev/null

# ---------------------------------------------------------------------------
# 5. Release the console
# ---------------------------------------------------------------------------

fbcon_unbind
sysfb_unbind

# ---------------------------------------------------------------------------
# 6. Unload the host GPU driver stack
# ---------------------------------------------------------------------------
# A failing modprobe -r returns immediately, so retrying it IS the readiness
# check for "has userspace let go of the card yet" - no fixed grace period, and
# no eviction pass at all in the normal case where the session exited cleanly.

STACK="$(gpu_module_stack "${HOST_GPU_DRIVER:-}")"

failed_mods=0
for m in $STACK; do
    mod_unload "$m" 1500 || failed_mods=1
done

if [ "$failed_mods" -ne 0 ]; then
    # Something is still holding a GPU node. Only now is killing it justified.
    kill_gpu_holders
    failed_mods=0
    for m in $STACK; do
        mod_unload "$m" 8000 || failed_mods=1
    done
fi

for m in $(gpu_aux_modules "${HOST_GPU_DRIVER:-}"); do
    mod_unload "$m" 500 || true     # best effort, these are not fatal
done

# Deliberately NOT touching drm / drm_kms_helper / drm_buddy / ttm and friends.
# They are shared with any other DRM driver that happens to be loaded (on this
# host, a stray amdgpu from mkinitcpio MODULES pins them), and unloading them is
# neither necessary to free the card nor possible while another driver is up.

# Anything still bound to a function of the card (HDA audio, xHCI, the i2c
# nvidia-gpu driver) gets unbound directly rather than by unloading its module,
# which would take unrelated devices down with it.
for d in "${GPU_DEVS[@]}"; do
    cur="$(pci_driver_of "$d" 2>/dev/null || true)"
    [ -n "$cur" ] && [ "$cur" != "vfio-pci" ] && pci_unbind "$d"
done

if [ "$failed_mods" -ne 0 ]; then
    vfio_log "GPU driver still resident; state:"
    vfio_log "$(lsmod | grep -iE "^nvidia|^amdgpu|^i915|^nouveau|^xe " | tr '\n' ';')"
    vfio_die "could not fully release ${HOST_GPU_DRIVER:-the GPU driver}; aborting so revert can put the desktop back"
fi

# ---------------------------------------------------------------------------
# 7. Hand the functions to vfio
# ---------------------------------------------------------------------------

wait "$VFIOMOD_PID" 2>/dev/null || vfio_warn "vfio module preload reported a problem"
for m in vfio vfio_iommu_type1 vfio_pci; do
    mod_loaded "$m" || mod_load "$m"
done

# With managed='yes' libvirt performs the vfio-pci bind itself; doing it here as
# well just races it. Only bind manually for managed='no' domains.
if xml_hostdev_managed "$XML"; then
    vfio_log "hostdevs are managed='yes' - leaving the vfio-pci bind to libvirt"
else
    for d in "${GPU_DEVS[@]}"; do pci_bind_vfio "$d" || vfio_warn "manual vfio-pci bind failed for $d"; done
fi

# NOTE: no `virsh nodedev-detach` anywhere in this script. virsh re-enters
# libvirtd while libvirtd is synchronously blocked waiting for this hook, which
# contends on the hostdev manager lock. It is also redundant with managed='yes'.

vfio_log "=== prepare/begin complete for '$GUEST' in $(( $(vfio_now_ms) - T0 ))ms ==="
exit 0
