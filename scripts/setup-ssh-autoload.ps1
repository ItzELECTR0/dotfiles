#!/usr/bin/env pwsh
# =============================================================================
# setup-ssh-autoload.ps1
# SSH key auto-load at login, zero interaction — init-agnostic
# =============================================================================
# Supported service managers (detected at runtime, same probe order as
# /etc/libvirt/hooks/vfio-lib.sh):
#
#   systemd   Arch                ~/.config/systemd/user/ssh-key-load.service
#   dinit     Artix + turnstile   ~/.config/dinit.d/ssh-key-load
#   s6        Artix + turnstile   <scandir>/ssh-key-load/run
#   runit     Artix + turnstile   <scandir>/ssh-key-load/run
#   openrc    Artix               no user-session supervisor upstream, so the
#   none                          XDG autostart entry is used instead
#
# Files created either way:
#   ~/.ssh/.key_pass               passphrase file       (chmod 400)
#   ~/.local/bin/ssh-askpass       askpass helper        (chmod 700)
#   ~/.local/bin/ssh-key-load      key loader script     (chmod 700)
#   ~/.local/state/ssh-key-load.log
#
# Parameters:
#   -KeyName <name>   file in ~/.ssh/ to load           (default: $USER)
#   -Init <name>      override detection: systemd|dinit|runit|s6|openrc|none
#   -Autostart        also install the XDG autostart entry, whatever the init
#   -Force            overwrite existing files without asking
#   -NoEnable         write the files but do not enable/start the service
#
# Security note:
#   Everything runs as your own UID. Linux cannot prevent you (the file owner)
#   from chmod-ing your own files. chmod 400 stops editors, file managers, and
#   accidental reads — it is a deterrent, not a hard barrier. True isolation
#   would require a dedicated system user, which is incompatible with user-space
#   services. This is the best achievable without elevated privileges.
# =============================================================================

[CmdletBinding()]
param(
    [string]$KeyName,
    [ValidateSet('auto', 'systemd', 'dinit', 'runit', 's6', 'openrc', 'none')]
    [string]$Init = 'auto',
    [switch]$Autostart,
    [switch]$Force,
    [switch]$NoEnable
)

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

# ── Helpers ──────────────────────────────────────────────────────────────────

function Write-Step([string]$msg) {
    Write-Host "  [+] $msg" -ForegroundColor Cyan
}
function Write-Warn([string]$msg) {
    Write-Host "  [!] $msg" -ForegroundColor Yellow
}
function Write-Fatal([string]$msg) {
    Write-Host "  [x] $msg" -ForegroundColor Red
    exit 1
}

function Test-Cmd([string]$name) {
    return $null -ne (Get-Command $name -CommandType Application -ErrorAction SilentlyContinue)
}

# Run a native command, discard all output, report success.
function Test-Run {
    param([string]$exe, [string[]]$cmdArgs)
    if (-not (Test-Cmd $exe)) { return $false }
    try { & $exe @cmdArgs *> $null } catch { return $false }
    return $LASTEXITCODE -eq 0
}

function Confirm-Overwrite([string]$path) {
    if ((Test-Path $path) -and -not $Force) {
        $ans = Read-Host "  '$path' already exists. Overwrite? [y/N]"
        if ($ans -notmatch '^[Yy]$') {
            Write-Host "  Skipping." -ForegroundColor DarkGray
            return $false
        }
    }
    return $true
}

function Set-FileContent([string]$path, [string]$content, [string]$chmod) {
    $dir = Split-Path -Parent $path
    if ($dir -and !(Test-Path $dir)) { New-Item -ItemType Directory -Path $dir -Force | Out-Null }
    # UTF-8 no BOM, LF only, always newline-terminated
    $content = ($content -replace "`r`n", "`n")
    if (-not $content.EndsWith("`n")) { $content += "`n" }
    [System.IO.File]::WriteAllText($path, $content, [System.Text.UTF8Encoding]::new($false))
    & chmod $chmod $path
}

# ── Init system detection ────────────────────────────────────────────────────
# Same probe order as vfio-lib.sh: the *running* init decides, never the set of
# installed binaries alone — Artix boxes routinely have several inits installed.

function Get-InitSystem {
    if ($Init -ne 'auto') { return $Init }

    if ((Test-Path '/run/systemd/system') -and (Test-Cmd 'systemctl')) { return 'systemd' }

    if (Test-Cmd 'dinitctl') {
        if ((Test-Path '/run/dinitctl') -or (Test-Run 'pgrep' @('-x', 'dinit'))) { return 'dinit' }
    }
    if ((Test-Cmd 's6-rc') -and (Test-Path '/run/s6-rc')) { return 's6' }
    if ((Test-Cmd 'sv') -and ((Test-Path '/run/runit') -or (Test-Path '/etc/runit'))) { return 'runit' }
    if (Test-Cmd 'rc-service') { return 'openrc' }

    return 'none'
}

# Is a *user-session* service manager of this flavour actually running for us?
# Turnstile only starts one for the graphical/seat session, and openrc has none
# at all, so this is what decides between a native unit and the autostart entry.
function Test-UserManager([string]$init) {
    $rt = if ($env:XDG_RUNTIME_DIR) { $env:XDG_RUNTIME_DIR } else { "/run/user/$(& id -u)" }
    switch ($init) {
        'systemd' { return (Test-Path "$rt/systemd/private") -or (Test-Run 'systemctl' @('--user', 'show', '--property=Version')) }
        'dinit' { return (Test-Run 'dinitctl' @('--user', 'list')) }
        'runit' { return (Test-Run 'pgrep' @('-u', "$(& id -u)", '-x', 'runsvdir')) }
        's6' { return (Test-Run 'pgrep' @('-u', "$(& id -u)", '-x', 's6-svscan')) }
        default { return $false }
    }
}

# Does the user manager know a service by this name? Used to decide whether the
# generated unit may declare a dependency on ssh-agent — declaring one that does
# not exist is a hard load error under dinit.
function Test-UserService([string]$init, [string]$name) {
    switch ($init) {
        'systemd' { return (Test-Run 'systemctl' @('--user', 'cat', '--', $name)) }
        'dinit' { return (Test-Run 'dinitctl' @('--user', 'status', $name)) }
        default { return $false }
    }
}

# runit/s6 supervise a scan directory. Ask the running supervisor which one it
# is instead of guessing — turnstile, runit-user and hand-rolled setups all pick
# different paths.
function Get-UserScanDir([string]$init) {
    $proc = if ($init -eq 's6') { 's6-svscan' } else { 'runsvdir' }
    if (Test-Cmd 'pgrep') {
        try {
            $lines = & pgrep -u (& id -u) -a -x $proc 2>$null
            foreach ($l in @($lines)) {
                $parts = @($l -split '\s+')
                for ($i = $parts.Count - 1; $i -ge 1; $i--) {
                    if ($parts[$i] -like '/*' -and (Test-Path -PathType Container $parts[$i])) {
                        return $parts[$i]
                    }
                }
            }
        }
        catch { }
    }
    $cfg = if ($env:XDG_CONFIG_HOME) { $env:XDG_CONFIG_HOME } else { "$HOME/.config" }
    $rt = if ($env:XDG_RUNTIME_DIR) { $env:XDG_RUNTIME_DIR } else { "/run/user/$(& id -u)" }
    foreach ($d in @("$cfg/service", "$HOME/.local/share/service", "$HOME/service", "$HOME/.service", "$rt/service")) {
        if (Test-Path -PathType Container $d) { return $d }
    }
    return "$cfg/service"
}

# ── Input ─────────────────────────────────────────────────────────────────────

Write-Host ""
Write-Host "SSH Key Auto-Load Setup" -ForegroundColor White
Write-Host "-----------------------" -ForegroundColor DarkGray
Write-Host ""

$INIT_FORCED = $Init -ne 'auto'
$INIT_SYS = Get-InitSystem
$HAS_MANAGER = Test-UserManager $INIT_SYS
Write-Step "init system: $INIT_SYS$(if ($INIT_FORCED) { ' (forced)' })"
if ($HAS_MANAGER) {
    Write-Step "user service manager: running"
}
else {
    Write-Warn "no $INIT_SYS user-session manager running — falling back to XDG autostart"
}

# Key name (filename inside ~/.ssh/ — no path, no extension)
if ([string]::IsNullOrWhiteSpace($KeyName)) {
    $defaultKeyName = $env:USER          # your username is the default
    $keyNameInput = Read-Host "SSH key name (file in ~/.ssh/) [$defaultKeyName]"
    $KeyName = if ([string]::IsNullOrWhiteSpace($keyNameInput)) { $defaultKeyName } else { $keyNameInput.Trim() }
}
$SSH_KEY = "$HOME/.ssh/$KeyName"

if (!(Test-Path $SSH_KEY)) {
    Write-Fatal "Key not found: $SSH_KEY"
}

# Passphrase — read securely, never touches disk as plaintext via normal means
Write-Host ""
$secPass = Read-Host -Prompt "  SSH key passphrase (input hidden)" -AsSecureString
$bstr = [System.Runtime.InteropServices.Marshal]::SecureStringToBSTR($secPass)
$PASS = [System.Runtime.InteropServices.Marshal]::PtrToStringBSTR($bstr)
[System.Runtime.InteropServices.Marshal]::ZeroFreeBSTR($bstr)

if ([string]::IsNullOrEmpty($PASS)) {
    Write-Fatal "Passphrase cannot be empty (key is unprotected — use ssh-add directly)."
}

# ── Derived paths ─────────────────────────────────────────────────────────────

$CFG_HOME = if ($env:XDG_CONFIG_HOME) { $env:XDG_CONFIG_HOME } else { "$HOME/.config" }
$SVC_NAME = 'ssh-key-load'
$PASS_FILE = "$HOME/.ssh/.key_pass"
$ASKPASS = "$HOME/.local/bin/ssh-askpass"
$LOADER = "$HOME/.local/bin/ssh-key-load"
$LOG_FILE = "$HOME/.local/state/ssh-key-load.log"
$AUTOSTART_FILE = "$CFG_HOME/autostart/${SVC_NAME}.desktop"

# ── Create directories ────────────────────────────────────────────────────────

foreach ($d in @("$HOME/.ssh", "$HOME/.local/bin", "$HOME/.local/state")) {
    if (!(Test-Path $d)) {
        New-Item -ItemType Directory -Path $d -Force | Out-Null
        Write-Step "Created directory: $d"
    }
}
& chmod 700 "$HOME/.ssh"

# ── 1. Passphrase file (chmod 400 — owner read-only) ─────────────────────────

Write-Host ""
if (Confirm-Overwrite $PASS_FILE) {
    # An existing 400 file cannot be rewritten in place; drop it first.
    if (Test-Path $PASS_FILE) { Remove-Item -Force $PASS_FILE }
    Set-FileContent $PASS_FILE $PASS "400"
    Write-Step "Passphrase file written:  $PASS_FILE  (chmod 400)"
}

# Wipe plaintext passphrase from memory ASAP
$PASS = $null
[System.GC]::Collect()

# ── 2. Askpass helper (chmod 700) ─────────────────────────────────────────────
# ssh-add calls this program to retrieve the passphrase.
# It simply prints the stored passphrase to stdout.

$ASKPASS_CONTENT = @"
#!/bin/sh
# ssh-askpass helper — called by ssh-add to fetch the key passphrase.
# Not meant to be invoked directly.
exec cat -- '$PASS_FILE'
"@

if (Confirm-Overwrite $ASKPASS) {
    Set-FileContent $ASKPASS $ASKPASS_CONTENT "700"
    Write-Step "Askpass helper written:   $ASKPASS  (chmod 700)"
}

# ── 3. Key loader script (chmod 700) ─────────────────────────────────────────
# Init-agnostic on purpose: it makes no assumption about which manager started
# it, or about inheriting a login environment. Everything it needs it finds.

$LOADER_CONTENT = @"
#!/bin/bash
# ssh-key-load — add the SSH key to ssh-agent with zero user interaction.
#
# Generated by setup-ssh-autoload.ps1. Started by a systemd/dinit/runit/s6 user
# service or an XDG autostart entry, depending on the host's init. Safe to run
# by hand at any time; it is idempotent.
set -uo pipefail

KEY='$SSH_KEY'
ASKPASS_BIN='$ASKPASS'
PASS_FILE='$PASS_FILE'
LOG='$LOG_FILE'

mkdir -p "`$(dirname "`$LOG")" 2>/dev/null

log() {
    printf '%s [ssh-key-load] %s\n' "`$(date '+%Y-%m-%d %H:%M:%S')" "`$*" >>"`$LOG" 2>/dev/null
    printf '[ssh-key-load] %s\n' "`$*" >&2
    command -v logger >/dev/null 2>&1 && logger -t ssh-key-load -- "`$*"
    return 0
}
die() { log "ERROR: `$*"; exit 1; }

[ -r "`$KEY" ]         || die "key not readable: `$KEY"
[ -x "`$ASKPASS_BIN" ] || die "askpass helper missing: `$ASKPASS_BIN"

_uid="`$(id -u)"
_rt="`${XDG_RUNTIME_DIR:-/run/user/`$_uid}"

# ── Locate SSH_AUTH_SOCK ─────────────────────────────────────────────────────
# User services under any init may start outside the login environment, so the
# inherited value is treated as a hint, not a guarantee: a stale socket path is
# worse than none. Probe every layout in common use, newest match wins.
# Usable = the path is a socket and an agent answers on it. ssh-add exit 2 means
# "could not connect"; 0 (has keys) and 1 (empty agent) both mean it is alive.
_sock_ok() {
    local _rc
    [ -S "`$1" ] || return 1
    SSH_AUTH_SOCK="`$1" ssh-add -l >/dev/null 2>&1
    _rc=`$?
    [ "`$_rc" -ne 2 ]
}

if [ -n "`${SSH_AUTH_SOCK:-}" ] && ! _sock_ok "`$SSH_AUTH_SOCK"; then
    log "inherited SSH_AUTH_SOCK is dead (`$SSH_AUTH_SOCK), re-probing"
    unset SSH_AUTH_SOCK
fi

if [ -z "`${SSH_AUTH_SOCK:-}" ]; then
    _candidates=(
        "`$_rt/ssh-agent.socket"        # systemd ssh-agent.service, dinit/turnstile
        "/run/user/`$_uid/ssh-agent.socket"
        "`$_rt/gcr/ssh"                 # gcr-ssh-agent (current gnome-keyring)
        "`$_rt/keyring/ssh"             # gnome-keyring
        "`$_rt/ssh-agent"               # some runit/s6 user services
        "`$HOME/.ssh/agent.sock"        # custom symlink
        "/tmp/ssh-agent-`$_uid.sock"
    )
    # Classic `ssh-agent` with no -a picks a random /tmp path; take the newest
    # one we own.
    while IFS= read -r _s; do
        [ -n "`$_s" ] && _candidates+=("`$_s")
    done < <(find /tmp -maxdepth 2 -type s -uid "`$_uid" -name 'agent.*' -path '/tmp/ssh-*' -printf '%T@ %p\n' 2>/dev/null \
             | sort -rn | cut -d' ' -f2-)

    for _s in "`${_candidates[@]}"; do
        if _sock_ok "`$_s"; then
            export SSH_AUTH_SOCK="`$_s"
            log "using agent socket: `$_s"
            break
        fi
    done
fi

# ── Last resort: run our own agent ───────────────────────────────────────────
# openrc and bare-init setups have no ssh-agent service to depend on. Bind it to
# a fixed path so login shells can pick the same socket up (see the profile
# snippet printed by the setup script).
if [ -z "`${SSH_AUTH_SOCK:-}" ]; then
    _own="`$_rt/ssh-agent.socket"
    [ -d "`$_rt" ] || _own="/tmp/ssh-agent-`$_uid.sock"
    rm -f "`$_own"
    if ssh-agent -a "`$_own" >/dev/null 2>&1; then
        export SSH_AUTH_SOCK="`$_own"
        log "no agent found; started one at `$_own"
    else
        die "no ssh-agent socket found and starting one failed"
    fi
fi

# ── Skip if the key is already loaded ────────────────────────────────────────
# Match on fingerprint, not on the comment column: the comment is whatever was
# baked into the key, which usually is not its path.
_fp="`$(ssh-keygen -lf "`$KEY.pub" 2>/dev/null | awk '{print `$2}')"
[ -n "`$_fp" ] || _fp="`$(ssh-keygen -lf "`$KEY" 2>/dev/null | awk '{print `$2}')"
if [ -n "`$_fp" ] && ssh-add -l 2>/dev/null | awk '{print `$2}' | grep -qxF "`$_fp"; then
    log "key already present in agent, nothing to do"
    exit 0
fi

# ── Check the stored passphrase before touching ssh-add ──────────────────────
# ssh-add re-runs SSH_ASKPASS in a loop until it gets a passphrase that works or
# an empty answer. Our helper always hands back the same string, so a stale
# passphrase file makes ssh-add spin forever rather than fail — verified against
# OpenSSH 10.4. Check it here, and keep a timeout below as the backstop.
_pass_ok=unknown
if command -v ssh-keygen >/dev/null 2>&1; then
    if ssh-keygen -y -P "`$(cat -- "`$PASS_FILE" 2>/dev/null)" -f "`$KEY" >/dev/null 2>&1; then
        _pass_ok=yes
    else
        _pass_ok=no
    fi
fi
[ "`$_pass_ok" = no ] && die "the passphrase in `$PASS_FILE does not unlock `$KEY — re-run setup-ssh-autoload.ps1"

# ── Load the key ─────────────────────────────────────────────────────────────
export SSH_ASKPASS="`$ASKPASS_BIN"
export SSH_ASKPASS_REQUIRE=force     # never fall back to a TTY prompt
export DISPLAY="`${DISPLAY:-:0}"     # pre-8.4 ssh-add refuses askpass without it

log "adding `$KEY to agent"
if timeout 30 ssh-add "`$KEY" </dev/null >/dev/null 2>&1; then
    log "done"
    exit 0
fi
_rc=`$?
if [ "`$_rc" -eq 124 ]; then
    die "ssh-add timed out — the stored passphrase is probably wrong for this key type"
fi
die "ssh-add failed (exit `$_rc)"
"@

if (Confirm-Overwrite $LOADER) {
    Set-FileContent $LOADER $LOADER_CONTENT "700"
    Write-Step "Loader script written:    $LOADER  (chmod 700)"
}

# ── 4. Service unit for the detected init ────────────────────────────────────

$UNIT_PATH = $null
$ENABLE_CMDS = @()
$STATUS_CMD = $null

if ($HAS_MANAGER) {
    switch ($INIT_SYS) {

        'systemd' {
            $UNIT_PATH = "$CFG_HOME/systemd/user/${SVC_NAME}.service"
            # Wants= is a soft dependency: harmless when openssh ships no
            # ssh-agent.service, and correct ordering when it does.
            $unit = @"
# systemd user service — SSH key auto-loader
# Created by setup-ssh-autoload.ps1

[Unit]
Description=Load SSH key into ssh-agent
After=ssh-agent.service
Wants=ssh-agent.service

[Service]
Type=oneshot
RemainAfterExit=yes
ExecStart=$LOADER

[Install]
WantedBy=default.target
"@
            if (Confirm-Overwrite $UNIT_PATH) {
                Set-FileContent $UNIT_PATH $unit "644"
                Write-Step "systemd user unit:        $UNIT_PATH"
            }
            $ENABLE_CMDS = @(
                @('systemctl', @('--user', 'daemon-reload')),
                @('systemctl', @('--user', 'enable', '--now', "${SVC_NAME}.service"))
            )
            $STATUS_CMD = "systemctl --user status ${SVC_NAME}.service"
        }

        'dinit' {
            $UNIT_PATH = "$CFG_HOME/dinit.d/$SVC_NAME"
            New-Item -ItemType Directory -Path "$CFG_HOME/dinit.d/boot.d" -Force | Out-Null
            # dinit refuses to load a service that depends on an unknown one, so
            # the ssh-agent line is only emitted when that service really exists.
            $dep = if (Test-UserService 'dinit' 'ssh-agent') { "waits-for = ssh-agent`n" } else { "" }
            $unit = @"
# Dinit user service — SSH key auto-loader
# Created by setup-ssh-autoload.ps1

type = scripted
command = $LOADER
logfile = $LOG_FILE
restart = false
$dep
"@
            if (Confirm-Overwrite $UNIT_PATH) {
                Set-FileContent $UNIT_PATH $unit "644"
                Write-Step "dinit user service:       $UNIT_PATH"
                if ($dep -eq "") { Write-Warn "no user 'ssh-agent' dinit service found; loader will find or start an agent itself" }
            }
            $ENABLE_CMDS = @(@('dinitctl', @('--user', 'enable', $SVC_NAME)))
            $STATUS_CMD = "dinitctl --user status $SVC_NAME"
        }

        { $_ -in 'runit', 's6' } {
            $scan = Get-UserScanDir $INIT_SYS
            $UNIT_PATH = "$scan/$SVC_NAME/run"
            # Both supervisors restart their run script forever, so a one-shot
            # has to take itself down once the work is done. runsv/s6-supervise
            # both cd into the service directory first, hence $PWD. Which command
            # does that is decided here, not at runtime: both create a
            # supervise/ directory, so there is nothing to sniff for later.
            $down = if ($INIT_SYS -eq 's6') { 's6-svc -d' } else { 'sv down' }
            $downAlt = if ($INIT_SYS -eq 's6') { 'sv down' } else { 's6-svc -d' }
            $unit = @"
#!/bin/sh
# $INIT_SYS user service — SSH key auto-loader
# Created by setup-ssh-autoload.ps1
exec 2>&1

'$LOADER'

# One-shot: stop supervising instead of respawning in a loop.
$down "`$PWD" 2>/dev/null || $downAlt "`$PWD" 2>/dev/null

# Reached only if the supervisor could not be told to stop; idle instead of
# hot-looping the loader.
exec sleep infinity
"@
            if (Confirm-Overwrite $UNIT_PATH) {
                Set-FileContent $UNIT_PATH $unit "755"
                Write-Step "$INIT_SYS user service:       $UNIT_PATH"
            }
            if ($INIT_SYS -eq 's6') {
                $ENABLE_CMDS = @(@('s6-svscanctl', @('-a', $scan)))
                $STATUS_CMD = "s6-svstat $scan/$SVC_NAME"
            }
            else {
                # runsvdir rescans on its own every 5s; nudging it is optional.
                $ENABLE_CMDS = @()
                $STATUS_CMD = "sv status $scan/$SVC_NAME"
            }
        }
    }
}

# ── 5. XDG autostart entry ───────────────────────────────────────────────────
# The portable path: openrc has no user-session supervisor, and on any init a
# graphical session that does not go through the user manager still honours it.
# Keyed off "did a unit actually get written", so an init with no branch above
# can never end up with nothing installed.

$USE_AUTOSTART = $Autostart -or ($null -eq $UNIT_PATH)

if ($USE_AUTOSTART) {
    $desktop = @"
[Desktop Entry]
Type=Application
Name=SSH Key Auto-Load
Comment=Add the SSH key to ssh-agent at session start
Exec=$LOADER
Terminal=false
NoDisplay=true
X-GNOME-Autostart-enabled=true
"@
    if (Confirm-Overwrite $AUTOSTART_FILE) {
        Set-FileContent $AUTOSTART_FILE $desktop "644"
        Write-Step "XDG autostart entry:      $AUTOSTART_FILE"
    }
}

# ── 6. Enable it ─────────────────────────────────────────────────────────────

if (-not $NoEnable -and $ENABLE_CMDS.Count -gt 0) {
    Write-Host ""
    foreach ($c in $ENABLE_CMDS) {
        $exe = $c[0]; $a = $c[1]
        if (Test-Run $exe $a) {
            Write-Step "ran: $exe $($a -join ' ')"
        }
        else {
            Write-Warn "failed: $exe $($a -join ' ')  — run it by hand"
        }
    }
}

# ── Summary ──────────────────────────────────────────────────────────────────

Write-Host ""
Write-Host "------------------------------------------" -ForegroundColor DarkGray
Write-Host " Setup complete — init: $INIT_SYS" -ForegroundColor Green
Write-Host "------------------------------------------" -ForegroundColor DarkGray
Write-Host ""
Write-Host " Files created:" -ForegroundColor White
Write-Host "   $PASS_FILE  (400 — owner read-only)" -ForegroundColor DarkGray
Write-Host "   $ASKPASS  (700)" -ForegroundColor DarkGray
Write-Host "   $LOADER  (700)" -ForegroundColor DarkGray
if ($UNIT_PATH) { Write-Host "   $UNIT_PATH" -ForegroundColor DarkGray }
if ($USE_AUTOSTART) { Write-Host "   $AUTOSTART_FILE" -ForegroundColor DarkGray }
Write-Host ""
Write-Host " Test it now, without logging out:" -ForegroundColor White
Write-Host "   $LOADER" -ForegroundColor Yellow
if ($STATUS_CMD) {
    Write-Host "   $STATUS_CMD" -ForegroundColor Yellow
}
if ($INIT_SYS -eq 'runit' -and $HAS_MANAGER) {
    Write-Host "   # runsvdir picks the new service up within ~5s" -ForegroundColor DarkGray
}
Write-Host ""
Write-Host " Log:" -ForegroundColor White
Write-Host "   tail -f $LOG_FILE" -ForegroundColor Yellow
Write-Host ""
Write-Host " If no ssh-agent service exists on this init, the loader starts its" -ForegroundColor DarkGray
Write-Host " own agent. Point your shells at the same socket:" -ForegroundColor DarkGray
Write-Host '   $env:SSH_AUTH_SOCK = "$env:XDG_RUNTIME_DIR/ssh-agent.socket"   # pwsh profile' -ForegroundColor Yellow
Write-Host '   export SSH_AUTH_SOCK="${XDG_RUNTIME_DIR}/ssh-agent.socket"     # sh/bash' -ForegroundColor Yellow
Write-Host ""
Write-Host " Re-run on another machine — detection is automatic. Force one with:" -ForegroundColor DarkGray
Write-Host "   ./setup-ssh-autoload.ps1 -Init dinit" -ForegroundColor Yellow
Write-Host ""
Write-Host " SECURITY REMINDER" -ForegroundColor DarkRed
Write-Host " $PASS_FILE is chmod 400 (no write, no group/other read)." -ForegroundColor DarkGray
Write-Host " As the file owner you can still chmod it yourself — that's" -ForegroundColor DarkGray
Write-Host " unavoidable in user-space. The permission stops editors and" -ForegroundColor DarkGray
Write-Host " other processes from casually reading it." -ForegroundColor DarkGray
Write-Host ""
