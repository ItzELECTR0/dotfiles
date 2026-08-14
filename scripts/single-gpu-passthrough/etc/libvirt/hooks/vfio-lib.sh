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

# Every timestamp, number and pattern below is parsed, not displayed. A stray
# locale turns EPOCHREALTIME's separator into a comma and breaks the millisecond
# arithmetic the whole "wait for the real thing" model is built on.
export LC_ALL=C

VFIO_STATE_DIR="${VFIO_STATE_DIR:-/run/libvirt/vfio-hook}"
VFIO_LOG="${VFIO_LOG:-/var/log/libvirt/vfio-hook.log}"

mkdir -p "$VFIO_STATE_DIR" 2>/dev/null
mkdir -p "$(dirname "$VFIO_LOG")" 2>/dev/null

# --------------------------------------------------------------------------
# logging
# --------------------------------------------------------------------------
# A hook logs on the order of fifty lines, and the naive implementation forks
# date(1) and logger(1) for every one of them. On the switch path that is a
# tenth of a second of pure fork overhead, so both are hoisted out: the
# timestamp comes from bash's printf, and syslog gets one long-lived logger
# fed through a file descriptor.

VFIO_LOG_FD=""
{ exec {VFIO_LOG_FD}>>"$VFIO_LOG"; } 2>/dev/null || VFIO_LOG_FD=""

# The logger gets its own stdout/stderr so it holds nothing of libvirtd's pipe
# open: a hook that has exited but whose grandchild still owns stderr is a hook
# libvirtd can sit and wait on.
VFIO_SYSLOG_FD=""
if [ "${VFIO_SYSLOG:-1}" != 0 ] && command -v logger >/dev/null 2>&1; then
    { exec {VFIO_SYSLOG_FD}> >(exec logger -t "${VFIO_TAG:-vfio-hook}" >/dev/null 2>&1); } 2>/dev/null \
        || VFIO_SYSLOG_FD=""
fi

vfio_log() {
    local msg
    printf -v msg '%(%Y-%m-%d %H:%M:%S)T [%s] %s' -1 "${VFIO_TAG:-vfio-hook}" "$*"
    [ -n "$VFIO_LOG_FD" ] && printf '%s\n' "$msg" >&"$VFIO_LOG_FD" 2>/dev/null
    printf '%s\n' "$msg" >&2
    [ -n "$VFIO_SYSLOG_FD" ] && printf '%s\n' "$*" >&"$VFIO_SYSLOG_FD" 2>/dev/null
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
# waiting
# --------------------------------------------------------------------------
# Nothing in the handover path sleeps for a fixed duration. Every step that has
# to wait waits on the condition it actually cares about and continues the
# millisecond it holds, because the wall-clock cost of the switch is dominated
# by these waits.

# Sub-second naps without forking sleep(1). Opening a process substitution
# read-write keeps a writer alive on our side, so the read never sees EOF and
# the timeout is what expires.
VFIO_NAP_FD=""
{ exec {VFIO_NAP_FD}<> <(:); } 2>/dev/null || VFIO_NAP_FD=""

vfio_nap() {
    if [ -n "$VFIO_NAP_FD" ]; then
        read -r -t "$1" -u "$VFIO_NAP_FD" _ 2>/dev/null
    else
        sleep "$1"
    fi
    return 0
}

# Milliseconds on a monotonic-enough clock. EPOCHREALTIME is a bash builtin, so
# reading it costs nothing.
vfio_now_ms() {
    local e="${EPOCHREALTIME:-}"
    if [ -n "$e" ]; then
        printf '%s' "$(( ${e%.*} * 1000 + 10#${e#*.} / 1000 ))"
    else
        printf '%s' "$(( SECONDS * 1000 ))"
    fi
}

# vfio_wait <timeout_ms> <command...>
# Returns 0 the moment <command> succeeds, 1 if the budget runs out. The poll
# interval ramps 2ms -> 20ms: conditions that clear immediately (the common
# case) cost one extra check, a slow one does not spin a core, and the interval
# is capped low enough that the ramp itself never adds a visible delay.
vfio_wait() {
    local budget="$1"; shift
    local deadline=$(( $(vfio_now_ms) + budget )) nap=0.002
    while :; do
        "$@" && return 0
        [ "$(vfio_now_ms)" -lt "$deadline" ] || return 1
        vfio_nap "$nap"
        case "$nap" in
            0.002) nap=0.005 ;;
            0.005) nap=0.010 ;;
            *)     nap=0.020 ;;
        esac
    done
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

# Function-level reset. A QEMU that was killed rather than shut down can leave
# the card mid-transaction; the host driver then binds and finds dead silicon,
# which is the "only a power cycle brings it back" failure. Must be called while
# the function is unbound from every driver.
pci_reset() {
    local addr="$1" f="/sys/bus/pci/devices/$1/reset"
    [ -w "$f" ] || { vfio_log "$addr: no reset node, skipping FLR"; return 1; }
    if pci_driver_of "$addr" >/dev/null 2>&1; then
        vfio_warn "$addr: still bound to $(pci_driver_of "$addr"); not resetting"
        return 1
    fi
    if echo 1 >"$f" 2>/dev/null; then
        vfio_log "$addr: function reset OK"
        return 0
    fi
    vfio_warn "$addr: function reset failed"
    return 1
}

# --------------------------------------------------------------------------
# kernel module helpers
# --------------------------------------------------------------------------

mod_loaded() { lsmod 2>/dev/null | awk '{print $1}' | grep -qx -- "$1"; }

mod_users() { lsmod 2>/dev/null | awk -v m="$1" '$1==m {for(i=4;i<=NF;i++) printf "%s ", $i}'; }

# Retry because refcounts drop asynchronously after the session dies. The retry
# loop doubles as the readiness check for the whole teardown: a failing
# modprobe -r is cheap and returns immediately, so polling it is a faster and
# more honest "is userspace off the GPU yet" test than sleeping a fixed two
# seconds and hoping. Budget is in milliseconds.
_mod_rmmod_quiet() { modprobe -r "$1" 2>/dev/null; }

mod_unload() {
    local m="$1" budget="${2:-3000}"
    mod_loaded "$m" || return 0
    if vfio_wait "$budget" _mod_rmmod_quiet "$m"; then
        vfio_log "unloaded module $m"
        return 0
    fi
    vfio_warn "could not unload $m within ${budget}ms (in use by: $(mod_users "$m"))"
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
    local secs="${1:-10}"
    if vfio_wait $(( secs * 1000 )) fb_present; then
        vfio_log "framebuffer present: $(cat /sys/class/graphics/fb0/name 2>/dev/null)"
        return 0
    fi
    vfio_warn "no framebuffer appeared within ${secs}s"
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

# Never signal ourselves or anything we are running under - libvirtd is an
# ancestor of a hook process, and killing it takes the VM start with it.
protected_pids() {
    local safe="" p=$$
    while [ -n "$p" ] && [ "$p" -gt 1 ] 2>/dev/null; do
        safe="$safe $p"
        p="$(awk '{print $4}' "/proc/$p/stat" 2>/dev/null)"
    done
    printf '%s\n' "$safe"
}

# pids holding an open fd on $1. Walks /proc directly so it needs neither lsof
# nor fuser. A trailing slash means "anything under this directory"; without one
# the match is exact, so /dev/vfio/8 does not also catch /dev/vfio/80.
proc_fd_holders() {
    local want="$1" p l t
    for p in /proc/[0-9]*; do
        [ -d "$p/fd" ] || continue
        for l in "$p/fd"/*; do
            [ -L "$l" ] || continue
            t="$(readlink "$l" 2>/dev/null)" || continue
            t="${t% (deleted)}"
            if [ "$t" = "$want" ] || { [ "${want%/}" != "$want" ] && [ "${t#"$want"}" != "$t" ]; }; then
                basename "$p"
                break
            fi
        done
    done
}

gpu_holders() {
    local nodes=() n
    for n in /dev/nvidia* /dev/dri/card* /dev/dri/renderD*; do
        [ -e "$n" ] && nodes+=("$n")
    done
    [ "${#nodes[@]}" -gt 0 ] || return 0

    local safe p raw pids=""
    safe="$(protected_pids)"

    if command -v fuser >/dev/null 2>&1; then
        raw="$(fuser "${nodes[@]}" 2>/dev/null | tr -s ' ' '\n')"
    elif command -v lsof >/dev/null 2>&1; then
        raw="$(lsof -t "${nodes[@]}" 2>/dev/null)"
    else
        return 0
    fi

    for p in $raw; do
        case "$p" in ''|*[!0-9]*) continue ;; esac
        case " $safe " in *" $p "*) continue ;; esac
        case " $pids " in *" $p "*) continue ;; esac   # a pid holds several nodes
        pids="$pids $p"
    done
    printf '%s\n' "${pids# }"
}

_no_gpu_holders() { [ -z "$(gpu_holders)" ]; }

kill_gpu_holders() {
    if ! command -v fuser >/dev/null 2>&1 && ! command -v lsof >/dev/null 2>&1; then
        vfio_warn "neither fuser nor lsof available; cannot evict GPU holders"
        return 0
    fi

    local pids
    pids="$(gpu_holders)"
    [ -n "$pids" ] || return 0

    vfio_log "evicting processes holding the GPU: $pids"
    # shellcheck disable=SC2086
    kill -TERM $pids 2>/dev/null
    # Escalate the instant the last fd is gone rather than on a fixed grace
    # period; a compositor that exits cleanly does so in tens of milliseconds.
    vfio_wait 2000 _no_gpu_holders && return 0

    pids="$(gpu_holders)"
    [ -n "$pids" ] || return 0
    vfio_log "still holding the GPU after SIGTERM, killing: $pids"
    # shellcheck disable=SC2086
    kill -KILL $pids 2>/dev/null
    vfio_wait 2000 _no_gpu_holders || vfio_warn "GPU still held by: $(gpu_holders)"
    return 0
}

# --------------------------------------------------------------------------
# state
# --------------------------------------------------------------------------

state_set()  { printf '%s\n' "$2" >"$VFIO_STATE_DIR/$1"; }
state_get()  { cat "$VFIO_STATE_DIR/$1" 2>/dev/null; }
state_has()  { [ -e "$VFIO_STATE_DIR/$1" ]; }
state_drop() { rm -f "$VFIO_STATE_DIR/$1"; }

# --------------------------------------------------------------------------
# guest list / user configuration
# --------------------------------------------------------------------------
# vms.conf lives in the desktop user's home, so guests can be added without
# root and it can be carried in a dotfiles repo like any other config. It is
# therefore PARSED, NEVER SOURCED: sourcing a file the user can write from a
# hook that libvirtd runs as root would be a straight local privilege
# escalation, and "anything that runs as you can silently own root at the next
# VM start" is too high a price for shell syntax in a list of names. Nothing
# read out of it reaches a shell as code - guest names are only ever
# string-compared. Shell-syntax overrides go in kvm.conf, which is root-owned
# and sourced.
#
# Format, one directive per line, '#' starts a comment:
#   vm <domain-name>      guest these hooks act on ('*' matches every guest)
# A bare line with no keyword is treated as 'vm <line>'.
#
# Search order, first readable file wins:
#   $VFIO_VM_LIST                                   (kvm.conf, explicit path)
#   ~$VFIO_USER/.config/vfio-passthrough/vms.conf   (kvm.conf, by user name)
#   /home/*/.config/vfio-passthrough/vms.conf       (autodetected)
#   /etc/libvirt/hooks/vms.conf                     (system-wide fallback)

VFIO_VM_LIST_RELPATH=".config/vfio-passthrough/vms.conf"
VFIO_VM_LIST_SYSTEM="/etc/libvirt/hooks/vms.conf"

# Resolved once at the bottom of this file, after kvm.conf has had its say.
_vfio_resolve_vm_list() {
    local p home hits=()

    if [ -n "${VFIO_VM_LIST:-}" ]; then
        printf '%s\n' "$VFIO_VM_LIST"
        return 0
    fi

    if [ -n "${VFIO_USER:-}" ]; then
        home="$(getent passwd "$VFIO_USER" 2>/dev/null | cut -d: -f6)"
        if [ -n "$home" ] && [ -r "$home/$VFIO_VM_LIST_RELPATH" ]; then
            printf '%s\n' "$home/$VFIO_VM_LIST_RELPATH"
            return 0
        fi
        vfio_warn "VFIO_USER=$VFIO_USER has no readable ~/$VFIO_VM_LIST_RELPATH"
    fi

    for p in /home/*/"$VFIO_VM_LIST_RELPATH" "/root/$VFIO_VM_LIST_RELPATH"; do
        [ -r "$p" ] && hits+=("$p")
    done
    if [ "${#hits[@]}" -gt 1 ]; then
        vfio_warn "several users have a vms.conf (${hits[*]}); using ${hits[0]} - set VFIO_USER in kvm.conf to pick"
    fi
    if [ "${#hits[@]}" -gt 0 ]; then
        printf '%s\n' "${hits[0]}"
        return 0
    fi

    printf '%s\n' "$VFIO_VM_LIST_SYSTEM"
}

vfio_conf_values() {
    local want="$1" file="$VFIO_VM_LIST_FILE" line key val
    [ -r "$file" ] || return 0
    while IFS= read -r line || [ -n "$line" ]; do
        line="${line%%#*}"
        line="${line#"${line%%[![:space:]]*}"}"
        line="${line%"${line##*[![:space:]]}"}"
        [ -n "$line" ] || continue
        key="${line%%[[:space:]]*}"
        case "$key" in
            vm) val="${line#"$key"}"
                val="${val#"${val%%[![:space:]]*}"}"
                ;;
            *)  key=vm; val="$line" ;;
        esac
        [ "$key" = "$want" ] && [ -n "$val" ] && printf '%s\n' "$val"
    done <"$file"
    return 0
}

# Does this domain get the passthrough treatment?
vfio_guest_listed() {
    local want="$1" v seen=0
    while IFS= read -r v; do
        seen=1
        [ "$v" = "*" ] && return 0
        [ "$v" = "$want" ] && return 0
    done < <(vfio_conf_values vm)
    [ "$seen" = 0 ] && vfio_warn "no guests configured in $VFIO_VM_LIST_FILE"
    return 1
}

# Optional overrides, root-owned and sourced as shell. Anything set here wins
# over auto-detection, including where the guest list is read from.
[ -r /etc/libvirt/hooks/kvm.conf ] && . /etc/libvirt/hooks/kvm.conf

VFIO_VM_LIST_FILE="$(_vfio_resolve_vm_list)"

return 0
