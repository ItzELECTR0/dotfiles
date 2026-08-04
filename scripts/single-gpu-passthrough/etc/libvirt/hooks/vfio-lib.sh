#!/usr/bin/env bash
# /etc/libvirt/hooks/vfio-lib.sh
#
# Shared helpers for single-GPU passthrough libvirt hooks.
# Source this file; do not execute it.
#
# Everything here is auto-detecting: init system, display manager, GPU vendor,
# framebuffer console, sysfb platform devices and the PCI functions to hand over
# are all discovered at runtime. /etc/libvirt/hooks/kvm.conf may override any of
# it, but a working setup should not need to.

[ -n "${VFIO_LIB_SOURCED:-}" ] && return 0
VFIO_LIB_SOURCED=1

VFIO_STATE_DIR="${VFIO_STATE_DIR:-/run/libvirt/vfio-hook}"
VFIO_LOG="${VFIO_LOG:-/var/log/libvirt/vfio-hook.log}"

mkdir -p "$VFIO_STATE_DIR" 2>/dev/null
mkdir -p "$(dirname "$VFIO_LOG")" 2>/dev/null

# --------------------------------------------------------------------------
# logging
# --------------------------------------------------------------------------

vfio_log() {
    local msg
    msg="$(date '+%Y-%m-%d %H:%M:%S') [${VFIO_TAG:-vfio-hook}] $*"
    printf '%s\n' "$msg" >>"$VFIO_LOG" 2>/dev/null
    printf '%s\n' "$msg" >&2
    command -v logger >/dev/null 2>&1 && logger -t "${VFIO_TAG:-vfio-hook}" -- "$*"
    return 0
}

vfio_warn() { vfio_log "WARN: $*"; }
vfio_die()  { vfio_log "FATAL: $*"; exit 1; }

# Run a command, log it, never let it hang the hook forever.
# Optional leading -<seconds> sets the timeout (default 15).
vfio_run() {
    local t=15
    case "${1:-}" in
        -[0-9]*) t="${1#-}"; shift ;;
    esac
    vfio_log "run(${t}s): $*"
    timeout --kill-after=5 "$t" "$@"
}

# --------------------------------------------------------------------------
# init system abstraction  (systemd / dinit / openrc / runit / s6)
# --------------------------------------------------------------------------

VFIO_INIT=""

init_detect() {
    [ -n "$VFIO_INIT" ] && return 0
    if [ -n "${VFIO_INIT_OVERRIDE:-}" ]; then
        VFIO_INIT="$VFIO_INIT_OVERRIDE"
    elif [ -d /run/systemd/system ] && command -v systemctl >/dev/null 2>&1; then
        VFIO_INIT=systemd
    elif command -v dinitctl >/dev/null 2>&1 && { [ -e /run/dinitctl ] || pgrep -x dinit >/dev/null 2>&1; }; then
        VFIO_INIT=dinit
    elif command -v s6-rc >/dev/null 2>&1 && [ -d /run/s6-rc ]; then
        VFIO_INIT=s6
    elif command -v sv >/dev/null 2>&1 && { [ -d /run/runit ] || [ -d /etc/runit ]; }; then
        VFIO_INIT=runit
    elif command -v rc-service >/dev/null 2>&1; then
        VFIO_INIT=openrc
    else
        VFIO_INIT=none
    fi
    vfio_log "init system: $VFIO_INIT"
}

_sv_dir() {
    local d
    for d in /etc/runit/sv /etc/sv /var/service /run/runit/service /etc/service; do
        [ -e "$d/$1" ] && { printf '%s\n' "$d/$1"; return 0; }
    done
    return 1
}

svc_exists() {
    init_detect
    case "$VFIO_INIT" in
        systemd) systemctl cat -- "$1" >/dev/null 2>&1 ;;
        dinit)   dinitctl status "$1" >/dev/null 2>&1 ;;
        openrc)  [ -x "/etc/init.d/$1" ] ;;
        runit)   _sv_dir "$1" >/dev/null ;;
        s6)      s6-rc -a list 2>/dev/null | grep -qx -- "$1" ;;
        *)       return 1 ;;
    esac
}

svc_active() {
    init_detect
    case "$VFIO_INIT" in
        systemd) systemctl is-active --quiet -- "$1" ;;
        dinit)   dinitctl status "$1" 2>/dev/null | grep -qiE 'state:[[:space:]]*STARTED' ;;
        openrc)  rc-service "$1" status >/dev/null 2>&1 ;;
        runit)   sv check "$1" >/dev/null 2>&1 ;;
        s6)      s6-rc -a list 2>/dev/null | grep -qx -- "$1" ;;
        *)       return 1 ;;
    esac
}

svc_stop() {
    init_detect
    svc_exists "$1" || { vfio_log "service $1 not present, skipping stop"; return 0; }
    vfio_log "stopping service: $1"
    case "$VFIO_INIT" in
        systemd) vfio_run -30 systemctl stop -- "$1" ;;
        dinit)   vfio_run -30 dinitctl stop "$1" ;;
        openrc)  vfio_run -30 rc-service "$1" stop ;;
        runit)   vfio_run -30 sv stop "$1" ;;
        s6)      vfio_run -30 s6-rc -d change "$1" ;;
        *)       return 0 ;;
    esac || vfio_warn "stop $1 returned non-zero"
    return 0
}

svc_start() {
    init_detect
    svc_exists "$1" || { vfio_log "service $1 not present, skipping start"; return 0; }
    vfio_log "starting service: $1"
    case "$VFIO_INIT" in
        systemd) vfio_run -30 systemctl start -- "$1" ;;
        dinit)   vfio_run -30 dinitctl start "$1" ;;
        openrc)  vfio_run -30 rc-service "$1" start ;;
        runit)   vfio_run -30 sv start "$1" ;;
        s6)      vfio_run -30 s6-rc -u change "$1" ;;
        *)       return 0 ;;
    esac || vfio_warn "start $1 returned non-zero"
    return 0
}

# --------------------------------------------------------------------------
# display manager detection
# --------------------------------------------------------------------------

VFIO_KNOWN_DMS="sddm gdm gdm3 lightdm lxdm xdm greetd ly emptty slim entrance cdm nodm tbsm"

detect_dm() {
    if [ -n "${VFIO_DM:-}" ]; then printf '%s\n' "$VFIO_DM"; return 0; fi
    init_detect

    # systemd records the active DM as a symlink; most reliable source there.
    if [ "$VFIO_INIT" = systemd ]; then
        local target
        target="$(readlink -f /etc/systemd/system/display-manager.service 2>/dev/null)"
        if [ -n "$target" ] && [ -e "$target" ]; then
            basename "$target" .service
            return 0
        fi
    fi

    local d
    for d in $VFIO_KNOWN_DMS; do
        svc_active "$d" && { printf '%s\n' "$d"; return 0; }
    done
    for d in $VFIO_KNOWN_DMS; do
        svc_exists "$d" && { printf '%s\n' "$d"; return 0; }
    done
    return 1
}

# Extra services worth stopping/starting around the handover, if they exist.
detect_gpu_services() {
    local s
    for s in nvidia-persistenced nvidia-powerd nvidiactl ollama; do
        svc_exists "$s" && printf '%s\n' "$s"
    done
}

# --------------------------------------------------------------------------
# XML parsing (the domain XML arrives on the hook's stdin)
# --------------------------------------------------------------------------

# Host PCI addresses of every <hostdev type='pci'>, as 0000:01:00.0
xml_pci_hostdevs() {
    local line inhd=0 insrc=0 d b s f
    while IFS= read -r line; do
        case "$line" in
            *"<hostdev"*"type='pci'"*|*'<hostdev'*'type="pci"'*) inhd=1; insrc=0 ;;
            *"</hostdev>"*) inhd=0; insrc=0; continue ;;
        esac
        [ "$inhd" = 1 ] || continue
        case "$line" in
            *"<source>"*)  insrc=1 ;;
            *"</source>"*) insrc=0; continue ;;
        esac
        [ "$insrc" = 1 ] || continue
        case "$line" in *"<address"*) ;; *) continue ;; esac
        # Strip quotes so one regex handles both '0x01' and "0x01".
        line="${line//\'/}"; line="${line//\"/}"
        [[ $line =~ domain=(0x)?([0-9a-fA-F]+)   ]] && d=${BASH_REMATCH[2]} || continue
        [[ $line =~ bus=(0x)?([0-9a-fA-F]+)      ]] && b=${BASH_REMATCH[2]} || continue
        [[ $line =~ slot=(0x)?([0-9a-fA-F]+)     ]] && s=${BASH_REMATCH[2]} || continue
        [[ $line =~ function=(0x)?([0-9a-fA-F]+) ]] && f=${BASH_REMATCH[2]} || continue
        printf '%04x:%02x:%02x.%x\n' "0x$d" "0x$b" "0x$s" "0x$f"
    done <<<"$1"
}

# Every file='...' attribute (disk sources, <rom file=>, <nvram template=> is separate)
xml_file_attrs() {
    printf '%s\n' "$1" \
        | grep -oE "(file|template)=('[^']*'|\"[^\"]*\")" \
        | sed -E "s/^(file|template)=['\"]//; s/['\"]$//"
}

# Text content of a simple element, e.g. xml_elem_text "$xml" loader
xml_elem_text() {
    printf '%s\n' "$1" \
        | grep -oE "<$2( [^>]*)?>[^<]+</$2>" \
        | sed -E "s@^<$2( [^>]*)?>@@; s@</$2>\$@@"
}

xml_domain_name() { xml_elem_text "$1" name | head -n1; }

# True when libvirt itself will bind/unbind vfio-pci for the hostdevs.
xml_hostdev_managed() {
    case "$1" in
        *"managed='yes'"*|*'managed="yes"'*) return 0 ;;
        *) return 1 ;;
    esac
}

# --------------------------------------------------------------------------
# PCI helpers
# --------------------------------------------------------------------------

pci_driver_of() {
    local l
    l="$(readlink -f "/sys/bus/pci/devices/$1/driver" 2>/dev/null)" || return 1
    [ -n "$l" ] || return 1
    basename "$l"
}

pci_class_of() { cat "/sys/bus/pci/devices/$1/class" 2>/dev/null; }

pci_is_vga() {
    case "$(pci_class_of "$1")" in 0x0300*|0x0302*) return 0 ;; *) return 1 ;; esac
}

iommu_group_of() {
    local g
    g="$(readlink -f "/sys/bus/pci/devices/$1/iommu_group" 2>/dev/null)" || return 1
    [ -n "$g" ] || return 1
    basename "$g"
}

iommu_group_members() {
    local g="$1" d
    for d in "/sys/kernel/iommu_groups/$g/devices/"*; do
        [ -e "$d" ] || continue
        basename "$d"
    done
}

iommu_enabled() {
    [ -d /sys/kernel/iommu_groups ] && [ -n "$(ls -A /sys/kernel/iommu_groups 2>/dev/null)" ]
}

pci_unbind() {
    local addr="$1" drv
    drv="$(pci_driver_of "$addr")" || return 0
    vfio_log "unbinding $addr from $drv"
    echo "$addr" >"/sys/bus/pci/drivers/$drv/unbind" 2>/dev/null \
        || vfio_warn "unbind $addr from $drv failed"
}

pci_clear_override() {
    local f="/sys/bus/pci/devices/$1/driver_override"
    [ -w "$f" ] && printf '\n' >"$f" 2>/dev/null
    return 0
}

pci_bind_vfio() {
    local addr="$1"
    [ -w "/sys/bus/pci/devices/$addr/driver_override" ] || return 1
    echo vfio-pci >"/sys/bus/pci/devices/$addr/driver_override"
    echo "$addr"  >/sys/bus/pci/drivers_probe 2>/dev/null
    vfio_log "bound $addr to vfio-pci (driver_override)"
}

pci_reprobe() {
    local addr="$1"
    pci_driver_of "$addr" >/dev/null && return 0
    echo "$addr" >/sys/bus/pci/drivers_probe 2>/dev/null \
        && vfio_log "reprobed $addr -> $(pci_driver_of "$addr" 2>/dev/null || echo none)"
    return 0
}

# --------------------------------------------------------------------------
# kernel module helpers
# --------------------------------------------------------------------------

mod_loaded() { lsmod 2>/dev/null | awk '{print $1}' | grep -qx -- "$1"; }

mod_users() { lsmod 2>/dev/null | awk -v m="$1" '$1==m {for(i=4;i<=NF;i++) printf "%s ", $i}'; }

# Retry because refcounts drop asynchronously after the session dies.
mod_unload() {
    local m="$1" tries="${2:-20}" i
    mod_loaded "$m" || return 0
    for ((i = 0; i < tries; i++)); do
        if modprobe -r "$m" 2>/dev/null; then
            vfio_log "unloaded module $m"
            return 0
        fi
        sleep 0.25
    done
    vfio_warn "could not unload $m (in use by: $(mod_users "$m"))"
    return 1
}

mod_load() {
    local m="$1"; shift
    mod_loaded "$m" && return 0
    if modprobe "$m" "$@" 2>/dev/null; then
        vfio_log "loaded module $m $*"
        return 0
    fi
    # Retry without extra params: a modprobe.d conf may already set them.
    if [ "$#" -gt 0 ] && modprobe "$m" 2>/dev/null; then
        vfio_log "loaded module $m (without params)"
        return 0
    fi
    vfio_warn "could not load $m"
    return 1
}

# Module teardown/bringup order per host GPU driver.
# Listed outermost-first; bring-up walks the list in reverse.
gpu_module_stack() {
    case "$1" in
        nvidia|nvidia-drm|nvidia-gpu)
            echo "nvidia_drm nvidia_modeset nvidia_uvm nvidia" ;;
        nouveau) echo "nouveau" ;;
        amdgpu)  echo "amdgpu" ;;
        radeon)  echo "radeon" ;;
        i915)    echo "i915" ;;
        xe)      echo "xe" ;;
        *)       echo "" ;;
    esac
}

# Auxiliary modules that latch onto secondary functions of the same card.
gpu_aux_modules() {
    case "$1" in
        nvidia|nvidia-drm|nvidia-gpu)
            echo "nvidia_peermem nvidia_vgpu_vfio i2c_nvidia_gpu" ;;
        *) echo "" ;;
    esac
}

VFIO_MODULES="vfio_pci vfio_iommu_type1 vfio"

# --------------------------------------------------------------------------
# console framebuffer handover
# --------------------------------------------------------------------------

# The vtconsole whose name is "frame buffer device" is fbcon. Index is NOT
# stable: on this class of system vtcon0 is the dummy console and vtcon1 is
# fbcon, but the order flips depending on driver probe order. Always match by
# name, never by index.
fbcon_vtcons() {
    local v
    for v in /sys/class/vtconsole/vtcon*; do
        [ -r "$v/name" ] || continue
        grep -qi 'frame buffer device' "$v/name" && printf '%s\n' "$v"
    done
}

fb_present() {
    local f
    for f in /sys/class/graphics/fb[0-9]*; do
        [ -e "$f" ] && return 0
    done
    return 1
}

fbcon_unbind() {
    local v
    for v in $(fbcon_vtcons); do
        [ "$(cat "$v/bind" 2>/dev/null)" = "1" ] || continue
        vfio_log "unbinding fbcon: $v ($(cat "$v/name" 2>/dev/null))"
        echo 0 >"$v/bind" 2>/dev/null || vfio_warn "fbcon unbind $v failed"
    done
    return 0
}

# SAFETY: binding fbcon while zero framebuffer devices are registered
# dereferences a NULL fb_info inside fbcon_cursor() and oopses the kernel
# (fbcon_cursor -> hide_cursor -> redraw_screen -> do_bind_con_driver ->
# store_bind). The oopsing task is killed, so the rest of the revert script
# never runs and the machine is left headless. Refuse unless an fb exists.
fbcon_rebind() {
    if ! fb_present; then
        vfio_warn "no /sys/class/graphics/fb* registered - refusing to bind fbcon (would oops the kernel)"
        return 1
    fi
    local v
    for v in $(fbcon_vtcons); do
        [ "$(cat "$v/bind" 2>/dev/null)" = "0" ] || continue
        vfio_log "rebinding fbcon: $v"
        echo 1 >"$v/bind" 2>/dev/null || vfio_warn "fbcon bind $v failed"
    done
    return 0
}

wait_for_fb() {
    local deadline=$(( SECONDS + ${1:-10} ))
    while [ "$SECONDS" -lt "$deadline" ]; do
        fb_present && { vfio_log "framebuffer present: $(cat /sys/class/graphics/fb0/name 2>/dev/null)"; return 0; }
        sleep 0.25
    done
    vfio_warn "no framebuffer appeared within ${1:-10}s"
    return 1
}

# --------------------------------------------------------------------------
# sysfb platform devices (efifb / simpledrm / vesafb)
# --------------------------------------------------------------------------
# Which of these exists depends on kernel config (CONFIG_SYSFB_SIMPLEFB,
# CONFIG_DRM_SIMPLEDRM, CONFIG_FB_EFI). Sweep all of them instead of hardcoding
# efi-framebuffer.0, and record what was actually unbound so revert can undo
# exactly that and nothing else.

VFIO_SYSFB_DRIVERS="efi-framebuffer simple-framebuffer vesa-framebuffer platform-framebuffer"

sysfb_unbind() {
    local statefile="$VFIO_STATE_DIR/sysfb" drv dir dev name
    : >"$statefile"
    for drv in $VFIO_SYSFB_DRIVERS; do
        dir="/sys/bus/platform/drivers/$drv"
        [ -d "$dir" ] || continue
        for dev in "$dir"/*; do
            name="$(basename "$dev")"
            case "$name" in bind|unbind|uevent|module|new_id|remove_id) continue ;; esac
            [ -L "$dev" ] || continue
            printf '%s %s\n' "$drv" "$name" >>"$statefile"
            if echo "$name" >"$dir/unbind" 2>/dev/null; then
                vfio_log "unbound sysfb $drv/$name"
            else
                vfio_warn "could not unbind sysfb $drv/$name"
            fi
        done
    done
    [ -s "$statefile" ] || vfio_log "no sysfb platform devices bound (console already owned by the GPU driver)"
    return 0
}

sysfb_rebind() {
    local statefile="$VFIO_STATE_DIR/sysfb" drv name
    [ -s "$statefile" ] || return 0
    while read -r drv name; do
        [ -n "$drv" ] || continue
        echo "$name" >"/sys/bus/platform/drivers/$drv/bind" 2>/dev/null \
            && vfio_log "rebound sysfb $drv/$name" \
            || vfio_warn "could not rebind sysfb $drv/$name"
    done <"$statefile"
    rm -f "$statefile"
    return 0
}

# --------------------------------------------------------------------------
# processes holding the GPU
# --------------------------------------------------------------------------

kill_gpu_holders() {
    local nodes=() n
    for n in /dev/nvidia* /dev/dri/card* /dev/dri/renderD*; do
        [ -e "$n" ] && nodes+=("$n")
    done
    [ "${#nodes[@]}" -gt 0 ] || return 0

    # Never signal ourselves or anything we are running under - libvirtd is an
    # ancestor of this process and killing it takes the VM start with it.
    local safe="" p=$$
    while [ -n "$p" ] && [ "$p" -gt 1 ] 2>/dev/null; do
        safe="$safe $p"
        p="$(awk '{print $4}' "/proc/$p/stat" 2>/dev/null)"
    done
    vfio_log "protected pids:$safe"

    local raw pids=""
    if command -v fuser >/dev/null 2>&1; then
        raw="$(fuser "${nodes[@]}" 2>/dev/null | tr -s ' ' '\n')"
    elif command -v lsof >/dev/null 2>&1; then
        raw="$(lsof -t "${nodes[@]}" 2>/dev/null)"
    else
        vfio_warn "neither fuser nor lsof available; cannot evict GPU holders"
        return 0
    fi

    for p in $raw; do
        case "$p" in ''|*[!0-9]*) continue ;; esac
        case " $safe " in *" $p "*) continue ;; esac
        case " $pids " in *" $p "*) continue ;; esac   # a pid holds several nodes
        pids="$pids $p"
    done

    [ -n "$pids" ] || return 0
    vfio_log "evicting processes holding the GPU:$pids"
    # shellcheck disable=SC2086
    kill -TERM $pids 2>/dev/null
    sleep 2
    # shellcheck disable=SC2086
    kill -KILL $pids 2>/dev/null
    return 0
}

# --------------------------------------------------------------------------
# state
# --------------------------------------------------------------------------

state_set()  { printf '%s\n' "$2" >"$VFIO_STATE_DIR/$1"; }
state_get()  { cat "$VFIO_STATE_DIR/$1" 2>/dev/null; }
state_has()  { [ -e "$VFIO_STATE_DIR/$1" ]; }
state_drop() { rm -f "$VFIO_STATE_DIR/$1"; }

# Optional user overrides. Anything set here wins over auto-detection.
[ -r /etc/libvirt/hooks/kvm.conf ] && . /etc/libvirt/hooks/kvm.conf

return 0
