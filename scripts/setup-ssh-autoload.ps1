#!/usr/bin/env pwsh
# =============================================================================
# setup-ssh-autoload.ps1
# Artix Linux (dinit + turnstile) — SSH key auto-load at login, zero interaction
# =============================================================================
# What this creates:
#   ~/.ssh/.key_pass              — passphrase file          (chmod 400)
#   ~/.local/bin/ssh-askpass      — askpass helper            (chmod 700)
#   ~/.local/bin/ssh-key-load     — key loader script         (chmod 700)
#   ~/.config/dinit.d/ssh-key-load — dinit user service
#
# Security note:
#   Everything runs as your own UID. Linux cannot prevent you (the file owner)
#   from chmod-ing your own files. chmod 400 stops editors, file managers, and
#   accidental reads — it is a deterrent, not a hard barrier. True isolation
#   would require a dedicated system user, which is incompatible with user-space
#   services. This is the best achievable without elevated privileges.
# =============================================================================

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
    Write-Host "  [✗] $msg" -ForegroundColor Red
    exit 1
}

function Confirm-Overwrite([string]$path) {
    if (Test-Path $path) {
        $ans = Read-Host "  '$path' already exists. Overwrite? [y/N]"
        if ($ans -notmatch '^[Yy]$') {
            Write-Host "  Skipping." -ForegroundColor DarkGray
            return $false
        }
    }
    return $true
}

function Set-FileContent([string]$path, [string]$content, [string]$chmod) {
    # Write without trailing newline issues; use UTF-8 no BOM
    [System.IO.File]::WriteAllText($path, $content, [System.Text.UTF8Encoding]::new($false))
    & chmod $chmod $path
}

# ── Input ─────────────────────────────────────────────────────────────────────

Write-Host ""
Write-Host "SSH Key Auto-Load Setup" -ForegroundColor White
Write-Host "━━━━━━━━━━━━━━━━━━━━━━━" -ForegroundColor DarkGray
Write-Host ""

# Key name (filename inside ~/.ssh/ — no path, no extension)
$defaultKeyName = $env:USER          # your username is the default
$keyNameInput   = Read-Host "SSH key name (file in ~/.ssh/) [$defaultKeyName]"
$keyName        = if ([string]::IsNullOrWhiteSpace($keyNameInput)) { $defaultKeyName } else { $keyNameInput.Trim() }
$SSH_KEY        = "$HOME/.ssh/$keyName"

if (!(Test-Path $SSH_KEY)) {
    Write-Fatal "Key not found: $SSH_KEY"
}

# Passphrase — read securely, never touches disk as plaintext via normal means
Write-Host ""
$secPass = Read-Host -Prompt "  SSH key passphrase (input hidden)" -AsSecureString
$bstr    = [System.Runtime.InteropServices.Marshal]::SecureStringToBSTR($secPass)
$PASS    = [System.Runtime.InteropServices.Marshal]::PtrToStringBSTR($bstr)
[System.Runtime.InteropServices.Marshal]::ZeroFreeBSTR($bstr)

if ([string]::IsNullOrEmpty($PASS)) {
    Write-Fatal "Passphrase cannot be empty (key is unprotected — use ssh-add directly)."
}

# ── Derived paths ─────────────────────────────────────────────────────────────

$PASS_FILE   = "$HOME/.ssh/.key_pass"
$ASKPASS     = "$HOME/.local/bin/ssh-askpass"
$LOADER      = "$HOME/.local/bin/ssh-key-load"
$SERVICE_DIR = "$HOME/.config/dinit.d"
$SERVICE     = "$SERVICE_DIR/ssh-key-load"
$LOG_FILE    = "/tmp/ssh-key-load.log"

# ── Create directories ────────────────────────────────────────────────────────

foreach ($d in @("$HOME/.ssh", "$HOME/.local/bin", $SERVICE_DIR)) {
    if (!(Test-Path $d)) {
        New-Item -ItemType Directory -Path $d -Force | Out-Null
        Write-Step "Created directory: $d"
    }
}

# ── 1. Passphrase file (chmod 400 — owner read-only) ─────────────────────────

Write-Host ""
if (Confirm-Overwrite $PASS_FILE) {
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
#!/bin/bash
# ssh-askpass helper — called by ssh-add to fetch the key passphrase.
# Not meant to be invoked directly.
exec cat -- '$PASS_FILE'
"@

if (Confirm-Overwrite $ASKPASS) {
    Set-FileContent $ASKPASS $ASKPASS_CONTENT "700"
    Write-Step "Askpass helper written:   $ASKPASS  (chmod 700)"
}

# ── 3. Key loader script (chmod 700) ─────────────────────────────────────────

$LOADER_CONTENT = @"
#!/bin/bash
# ssh-key-load — run by dinit user service on login.
# Adds the SSH key to ssh-agent with zero user interaction.
set -euo pipefail

KEY='$SSH_KEY'
ASKPASS_BIN='$ASKPASS'

# ── Locate SSH_AUTH_SOCK ──────────────────────────────────────────────────────
# Dinit user services may not inherit the login environment directly.
# We probe the standard socket locations used by common ssh-agent setups.
if [[ -z "`${SSH_AUTH_SOCK:-}" ]]; then
    _uid=`$(id -u)
    declare -a _candidates=(
        "/run/user/`$_uid/ssh-agent.socket"   # dinit ssh-agent service
        "/run/user/`$_uid/keyring/ssh"         # gnome-keyring / gcr
        "/tmp/ssh-agent-`$_uid.sock"           # manual launch fallback
        "`$HOME/.ssh/agent.sock"               # custom symlink fallback
    )
    for _sock in "`${_candidates[@]}"; do
        if [[ -S "`$_sock" ]]; then
            export SSH_AUTH_SOCK="`$_sock"
            break
        fi
    done
fi

if [[ -z "`${SSH_AUTH_SOCK:-}" ]]; then
    echo "[ssh-key-load] ERROR: SSH_AUTH_SOCK not found. Is ssh-agent running?" >&2
    echo "Tried: `${_candidates[*]}" >&2
    exit 1
fi

# ── Skip if key is already loaded ────────────────────────────────────────────
if ssh-add -l 2>/dev/null | grep -qF "`$KEY"; then
    echo "[ssh-key-load] Key already present in agent, skipping."
    exit 0
fi

# ── Load the key ─────────────────────────────────────────────────────────────
export SSH_ASKPASS="`$ASKPASS_BIN"
export SSH_ASKPASS_REQUIRE=force   # Never fall back to a TTY prompt

echo "[ssh-key-load] Adding `$KEY to agent..."
ssh-add "`$KEY"
echo "[ssh-key-load] Done."
"@

if (Confirm-Overwrite $LOADER) {
    Set-FileContent $LOADER $LOADER_CONTENT "700"
    Write-Step "Loader script written:    $LOADER  (chmod 700)"
}

# ── 4. Dinit user service ─────────────────────────────────────────────────────
# type = scripted  → run once and exit (not a daemon)
# The 'after' directive ensures we run after the standard user boot chain.
# If you have an explicit 'ssh-agent' dinit service, change the after line to:
#     after = ssh-agent
# and add:
#     depends-on = ssh-agent

$SERVICE_CONTENT = @"
# Dinit user service — SSH key auto-loader
# Created by setup-ssh-autoload.ps1

type = scripted
command = $LOADER
logfile = $LOG_FILE
depends-on = ssh-agent
"@

if (Confirm-Overwrite $SERVICE) {
    Set-FileContent $SERVICE $SERVICE_CONTENT "600"
    Write-Step "Dinit service written:    $SERVICE"
}

# ── Summary ──────────────────────────────────────────────────────────────────

Write-Host ""
Write-Host "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━" -ForegroundColor DarkGray
Write-Host " Setup complete." -ForegroundColor Green
Write-Host "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━" -ForegroundColor DarkGray
Write-Host ""
Write-Host " Files created:" -ForegroundColor White
Write-Host "   $PASS_FILE  (400 — owner read-only)" -ForegroundColor DarkGray
Write-Host "   $ASKPASS  (700)" -ForegroundColor DarkGray
Write-Host "   $LOADER  (700)" -ForegroundColor DarkGray
Write-Host "   $SERVICE" -ForegroundColor DarkGray
Write-Host ""
Write-Host " Enable the service (runs once at next login):" -ForegroundColor White
Write-Host "   dinitctl --user enable ssh-key-load" -ForegroundColor Yellow
Write-Host "   dinitctl --user start  ssh-key-load   # test it now without logging out" -ForegroundColor Yellow
Write-Host ""
Write-Host " Check the log after start:" -ForegroundColor White
Write-Host "   cat $LOG_FILE" -ForegroundColor Yellow
Write-Host ""
Write-Host " If ssh-agent is itself a dinit service, edit the 'after' line" -ForegroundColor DarkGray
Write-Host " in $SERVICE to 'depends-on = <your-agent-service>'." -ForegroundColor DarkGray
Write-Host ""
Write-Host " SECURITY REMINDER" -ForegroundColor DarkRed
Write-Host " $PASS_FILE is chmod 400 (no write, no group/other read)." -ForegroundColor DarkGray
Write-Host " As the file owner you can still chmod it yourself — that's" -ForegroundColor DarkGray
Write-Host " unavoidable in user-space. The permission stops editors and" -ForegroundColor DarkGray
Write-Host " other processes from casually reading it." -ForegroundColor DarkGray
Write-Host ""
