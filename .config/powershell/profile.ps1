# ---------------------------------------------------ELECTRO----------------------------------------------------------
#                                                                                                                     
#    o__ __o     o              o    o__ __o         o__ __o      o         o    o__ __o__/_   o            o         
#   <|     v\   <|>            <|>  <|     v\       /v     v\    <|>       <|>  <|    v       <|>          <|>        
#   / \     <\  / \            / \  / \     <\     />       <\   < >       < >  < >           / \          / \        
#   \o/     o/  \o/            \o/  \o/     o/    _\o____         |         |    |            \o/          \o/        
#    |__  _<|/   |              |    |__  _<|          \_\__o__   o__/_ _\__o    o__/_         |            |         
#    |          < >            < >   |       \               \    |         |    |            / \          / \        
#   <o>          \o    o/\o    o/   <o>       \o   \         /   <o>       <o>  <o>           \o/          \o/        
#    |            v\  /v  v\  /v     |         v\   o       o     |         |    |             |            |         
#   / \            <\/>    <\/>     / \         <\  <\__ __/>    / \       / \  / \  _\o__/_  / \ _\o__/_  / \ _\o__/_
#
# ---------------------------------------------------ELECTRO----------------------------------------------------------

if ($Host.Name -ne 'ConsoleHost') { return }

# -------------------------------------------
# MODULES
# -------------------------------------------

$modulePath = Join-Path $PSScriptRoot 'Modules'
$modulePaths = $env:PSModulePath -split [IO.Path]::PathSeparator
if ($modulePath -notin $modulePaths) {
    $env:PSModulePath = (@($modulePath) + $modulePaths) -join [IO.Path]::PathSeparator
}

# PSReadLine bootstrap
if (-not (Get-Module -ListAvailable -Name PSReadLine)) {
    Write-Host 'PSReadLine not found. Installing...' -ForegroundColor Yellow
    if (-not (Get-PackageProvider -Name NuGet -ErrorAction SilentlyContinue)) {
        Install-PackageProvider -Name NuGet -Force -Scope CurrentUser | Out-Null
    }
    try {
        Install-Module -Name PSReadLine -Scope CurrentUser -Force -SkipPublisherCheck -AllowPrerelease -AllowClobber -ErrorAction Stop
    }
    catch {
        Write-Warning "Failed to install PSReadLine: $_"
    }
}

Import-Module PSReadLine -ErrorAction SilentlyContinue
if (Get-Module PSReadLine) {
    Set-PSReadLineOption -EditMode Emacs
    Set-PSReadLineOption -PredictionSource History
    Set-PSReadLineOption -PredictionViewStyle ListView
    Set-PSReadLineOption -HistorySearchCursorMovesToEnd
    Set-PSReadLineKeyHandler -Key Tab -Function MenuComplete
}

# -------------------------------------------
# DEFINE VARIABLES
# -------------------------------------------

if ($env:TERM -and -not $env:DISPLAY -and -not $env:WAYLAND_DISPLAY) {
    $env:show_distro = 'Arch Linux'
}

# Check for root/doas privileges
$adminAccess = $false
try { $adminAccess = (id -u) -eq 0 } catch { $adminAccess = $false }
$username = $env:USER
$systemname = [System.Net.Dns]::GetHostName()

# Define PATH & environment variables
$existingPath = $env:PATH -split ':'
$prependPath = @("$HOME/.local/share/pnpm", "$HOME/.local/bin") | Where-Object { $existingPath -notcontains $_ }
if ($prependPath) { $env:PATH = ($prependPath -join ':') + ':' + $env:PATH }
$env:PNPM_HOME = "$HOME/.local/share/pnpm"
$documentsFolder = "$HOME/Documents"
$logFilePath = "$documentsFolder/PowerShell/Logs/profile.log"
$tempFolder = '/tmp'
$env:EDITOR = 'edit'
$env:USE_CCACHE = 1
$env:CCACHE_EXEC = '/usr/bin/ccache'
# lazydocker connects to Podman's Docker-compatible API socket through DOCKER_HOST.
$env:DOCKER_HOST = 'unix:///run/user/1000/podman/podman.sock'
$env:BLOCK_SIZE = 'si'

# -------------------------------------------
# CLEAR EVERYTHING BEFORE TAKING ACTION
# -------------------------------------------

Clear-Host

# -------------------------------------------
# LIST POWERSHELL VERSION
# -------------------------------------------

Write-Host "PowerShell $($PSVersionTable.PSVersion)"

# -------------------------------------------
# DEFINE PROMPT
# -------------------------------------------

## This one is a backup when OhMyPosh isn't here
#function prompt {
#    $path = $(Get-Location)
#    "$username@$systemname $path> "
#}

oh-my-posh init pwsh --config ~/.config/oh-my-posh/themes/darkblood.json | Invoke-Expression

# -------------------------------------------
# INVOKE ZOXIDE
# -------------------------------------------

Invoke-Expression (& { (zoxide init --cmd cd powershell | Out-String) })

# -------------------------------------------
# ALIASES
# -------------------------------------------

# ADB
Set-Alias adb-install Install-ADB

# JAVA
Set-Alias gradlew ./gradlew

# CUSTOM CONFIGS
Set-Alias q Get-Out
Set-Alias quit Get-Out
Set-Alias clear Start-CustomClear
Set-Alias c Clear-Host
Set-Alias rm Start-Removing

# EDITOR SHORTCUTS
Set-Alias code codium-insiders
Set-Alias cc claude
Set-Alias gemini agy
Set-Alias lgit lazygit
Set-Alias top btop
Set-Alias resesh Restart-Session
Set-Alias profile Edit-Profile
Set-Alias hyprconf Edit-Hyprland
Set-Alias archconf Edit-DCLI
Set-Alias logs Edit-Logs
Set-Alias lazypod lazydocker

# GIT SHORTCUTS
Set-Alias commit Start-Git-Commit
Set-Alias clone Start-Git-Clone
Set-Alias merge Start-Git-Merge
Set-Alias origin Switch-Git-Origin
Set-Alias pull Start-Git-Pull
Set-Alias push Start-Git-Push
Set-Alias status Start-Git-Status
Set-Alias checkout Start-Git-Checkout

# HYPRLAND SHORTCUTS
Set-Alias clients Show-Clients
Set-Alias monitors Show-Monitors
Set-Alias devices Show-Devices

# DEVELOPMENT
Set-Alias elts Start-ELTS
Set-Alias twaos Start-TWAOS
Set-Alias rspt Start-RustyPaint
Set-Alias macOS Start-macOS
Set-Alias macmount Mount-macOS
Set-Alias winmount Mount-Windows
Set-Alias depotbuild Start-SteamDepotBuild

# INFORMATION
Set-Alias ff fastfetch
Set-Alias nf neofetch
Set-Alias sysinf hyprsysteminfo

# MAINTENANCE
Set-Alias updboot Update-System
Set-Alias updpod Start-PodmanContainerUpdate
Set-Alias updfeishin Update-Feishin
Set-Alias updaur Update-AUR
Set-Alias rebuild Update-AURgitPackage
Set-Alias updeur Update-ElectricAUR
Set-Alias updflat Update-Flatpak
Set-Alias updsys Upgrade-System
Set-Alias updstub Update-EFIstub

# MEDIA
Set-Alias mediactl Start-MediaManagement
Set-Alias ytvid Start-YTDLP-Video
Set-Alias ytaud Start-YTDLP-Audio
Set-Alias ytsub Start-YTDLP-Subtitles
Set-Alias ytlist Start-YTDLP-Playlist
Set-Alias compress Start-Compressing

# POWER
Set-Alias poweroff Stop-Computer
Set-Alias flatline Stop-Computer -Force
Set-Alias reboot Restart-Computer
Set-Alias reboot-samurai Restart-Computer -Force

# UTILITIES
Set-Alias menu Show-Menu
Set-Alias icoinst Install-Icon
Set-Alias vencord Start-Vencord
Set-Alias open Open-Directory

# TESTING
Set-Alias testenv Test-Environment
Set-Alias testcompose Test-PodmanComposeProject
Set-Alias testall Test-All

# -------------------------------------------
# FASTFETCH & USER DISPLAY
# -------------------------------------------

Write-Host ''
if ($Host.UI.RawUI.KeyAvailable -eq $false) {
    if (Get-Command fastfetch -ErrorAction SilentlyContinue) {
        fastfetch
    } elseif (Get-Command neofetch -ErrorAction SilentlyContinue) {
        neofetch
    }
}

if (-not $adminAccess) {
    Write-Host ''
    Write-Host "Running as user $username"
    Write-Host "Powered by $env:show_distro (btw)"
}

if ($adminAccess) {
    Write-Host ''
    Write-Host 'Running with Root Privileges'
    Write-Host "Powered by $env:show_distro (btw)"
}
Write-Host ''
