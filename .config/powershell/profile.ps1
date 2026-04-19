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

if ($Host.Name -eq 'ConsoleHost' -and [Environment]::GetCommandLineArgs() -match '-Command') {
    return
}

Set-PSReadLineKeyHandler -Key Tab -Function MenuComplete

# -------------------------------------------
# DEFINE VARIABLES
# -------------------------------------------

[bool]$adminAccess

# If not running interactively, don't do anything
if ($Host.Name -ne "ConsoleHost") { return }

# Check if running in a TTY
if ($env:TERM -and -not $env:DISPLAY -and -not $env:WAYLAND_DISPLAY) {
    $env:show_distro = "Artix Linux"
}

# Check for root/doas privileges
try { $adminAccess = (id -u) -eq 0 } catch { $adminAccess = $false }

# Define Username
$username = $env:USER

# Define System/Host Name
$systemname = [System.Net.Dns]::GetHostName()

# Define PATH
$env:PATH = "$HOME/.local/share/pnpm:$HOME/.local/bin:" + $env:PATH
$env:PNPM_HOME = "$HOME/.local/share/pnpm"

# Define path to Documents Folder
$documentsFolder = "$HOME/Documents"

# Define path to Log File
$logFilePath = "$documentsFolder/PowerShell/Logs/profile.log"

# Define Temporary Files Folder
$tempFolder = "/tmp"

# Define Editor
$env:EDITOR = "edit"

# Define ccache
$env:USE_CCACHE = 1
$env:CCACHE_EXEC = "/usr/bin/ccache"

# -------------------------------------------
# GENERAL FUNCTIONS
# -------------------------------------------

# Function to get user confirmation
function Get-UserConfirmation {
    param (
        [string]$confirmMessage,
        [string]$refuseMessage,
        [string]$promptMessage
    )
    $confirmMessage = $confirmMessage.ToLower()
    $refuseMessage = $refuseMessage.ToLower()
    
    while ($true) {
        $confirmation = Read-Host $promptMessage
        $confirmation = $confirmation.ToLower()
        if ($confirmation -eq $confirmMessage) {
            return $true
        } elseif ($confirmation -eq $refuseMessage) {
            return $false
        } else {
            Write-LogOutput "Invalid input. Please enter $confirmMessage or $refuseMessage"
        }
    }
}

# Function to get user input with default value
function Get-UserInput {
    param (
        [bool]$noDefault = $false,
        [bool]$hideInput = $false,
        [string]$promptMessage,
        [string]$defaultValue
    )

    if ($hideInput) {
        do {
            $secureInput = Read-Host -AsSecureString "$promptMessage"
            $userInput = [Runtime.InteropServices.Marshal]::PtrToStringAuto([Runtime.InteropServices.Marshal]::SecureStringToBSTR($secureInput))
            $secureInput.Dispose()
            if ([string]::IsNullOrWhiteSpace($userInput)) {
                Write-Host "No input provided. Please try again."
            }
        } while ([string]::IsNullOrWhiteSpace($userInput))
    } else {
        if ($noDefault) {
            do {
                $userInput = Read-Host "$promptMessage"
                if ([string]::IsNullOrWhiteSpace($userInput)) {
                    Write-Host "No input provided. Please try again."
                }
            } while ([string]::IsNullOrWhiteSpace($userInput))
        } else {
            $userInput = Read-Host "$promptMessage (Default: '$defaultValue')"
            if ([string]::IsNullOrWhiteSpace($userInput)) {
                $userInput = $defaultValue
            }
        }
    }

    return $userInput
}

# Function to log messages
function Write-LogOutput {
    param (
        [string]$message,
        [string]$level = "INFO"
    )

    if (-Not (Test-Path -Path $logFilePath)) {
        $logDirectory = Split-Path -Parent $logFilePath
        if (-Not (Test-Path -Path $logDirectory)) {
            New-Item -ItemType Directory -Path $logDirectory -Force | Out-Null
        }
        New-Item -ItemType File -Path $logFilePath -Force | Out-Null
    }

    $timestamp = Get-Date -Format "yyyy-MM-dd HH:mm:ss"
    "$timestamp [$level] - $message" | Out-File -Append -FilePath $logFilePath
    Write-Host $message
}

# Function to log errors
function Write-LogError {
    param (
        [string]$message,
        [string]$level = "ERROR"
    )

    if (-Not (Test-Path -Path $logFilePath)) {
        $logDirectory = Split-Path -Parent $logFilePath
        if (-Not (Test-Path -Path $logDirectory)) {
            New-Item -ItemType Directory -Path $logDirectory -Force | Out-Null
        }
        New-Item -ItemType File -Path $logFilePath -Force | Out-Null
    }

    $timestamp = Get-Date -Format "yyyy-MM-dd HH:mm:ss"
    "$timestamp [$level] - $message" | Out-File -Append -FilePath $logFilePath
    Write-Error $message
}

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

# EDITOR SHORTCUTS
Set-Alias code codium-insiders
Set-Alias cc codex
Set-Alias lgit lazygit
Set-Alias top btop
Set-Alias resesh Restart-Session
Set-Alias profile Edit-Profile
Set-Alias hyprconf Edit-Hyprland
Set-Alias wayconf Edit-WayBar
Set-Alias anyconf Edit-AnyRun
Set-Alias logs Edit-Logs

# GIT SHORTCUTS
Set-Alias commit Start-Git-Commit
Set-Alias clone Start-Git-Clone
Set-Alias pull Start-Git-Pull
Set-Alias push Start-Git-Push
Set-Alias status Start-Git-Status

# HYPRLAND SHORTCUTS
Set-Alias clients Show-Clients
Set-Alias monitors Show-Monitors
Set-Alias devices Show-Devices

# DEVELOPMENT
Set-Alias elts Start-ELTS
Set-Alias twaos Start-TWAOS

# INFORMATION
Set-Alias ff fastfetch
Set-Alias nf neofetch

# MAINTENANCE
Set-Alias updboot Update-System
Set-Alias updocker Start-DockerContainerUpdate
Set-Alias updfeishin Update-Feishin
Set-Alias updeur Update-ElectricAUR
Set-Alias updflat Update-Flatpak
Set-Alias updsys Upgrade-System
Set-Alias updstub Update-EFIstub

# MEDIA
Set-Alias mediactl Start-MediaManagement
Set-Alias ytvid Start-YTDLP-Video
Set-Alias ytaud Start-YTDLP-Audio
Set-Alias ytsub Start-YTDLP-Subtitles

# POWER
Set-Alias poweroff Stop-Computer
Set-Alias flatline Stop-Computer -Force
Set-Alias reboot Restart-Computer
Set-Alias reboot-samurai Restart-Computer -Force

# UTILITIES
Set-Alias menu Show-Menu
Set-Alias vencord Start-Vencord
Set-Alias open Open-Directory

# -------------------------------------------
# FASTFETCH & USER DISPLAY
# -------------------------------------------

Write-Host ""
if ($Host.UI.RawUI.KeyAvailable -eq $false) {
    if (Get-Command fastfetch -ErrorAction SilentlyContinue) {
        fastfetch --size-binary-prefix si
    } elseif (Get-Command neofetch -ErrorAction SilentlyContinue) {
        neofetch
    }
}

if (-not ($adminAccess)) {
    Write-Host ""
    Write-Host "Running as user $username"
    Write-Host "Powered by $env:show_distro (btw)"
}

if ($adminAccess) {
    Write-Host ""
    Write-Host "Running with Root Privileges"
    Write-Host "Powered by $env:show_distro (btw)"
}
Write-Host ""

# -------------------------------------------
# CUSTOM FUNCTIONS
# -------------------------------------------

function Get-Out {
    exit
}

function Start-CustomClear {
    Clear-Host
    Write-Host "PowerShell $($PSVersionTable.PSVersion)"
    Write-Host ""
    if ($Host.UI.RawUI.KeyAvailable -eq $false) {
        if (Get-Command fastfetch -ErrorAction SilentlyContinue) {
            fastfetch --size-binary-prefix si
        } elseif (Get-Command neofetch -ErrorAction SilentlyContinue) {
            neofetch
        }
    }
    if (-not ($adminAccess)) {
        Write-Host ""
        Write-Host "Running as user $username"
        Write-Host "Powered by $env:show_distro (btw)"
    }

    if ($adminAccess) {
        Write-Host ""
        Write-Host "Running with Root Privileges"
        Write-Host "Powered by $env:show_distro (btw)"
    }
    Write-Host ""
}

function Start-Git-Commit {
    param (
        [Parameter(Mandatory)]
        [string]$Title,

        [Parameter()]
        [string]$Description
    )

    if ($Description) {
        git commit -m $Title -m $Description
    } else {
        git commit -m $Title
    }
}

function Start-Git-Clone {
    param (
        [Parameter(Mandatory)]
        [string]$Repository,
        [switch]$gh,
        [switch]$gl
    )

    if ($gh) {
        git clone git@github.com:$Repository
    } elseif ($gl) {
        git clone git@gitlab.com:$Repository
    } else {
        git clone $Repository
    }
}

function Start-Git-Pull {
    git pull
}

function Start-Git-Push {
    git push
}

function Start-Git-Status {
    git status
}

function hostname {
    [System.Net.Dns]::GetHostName()
}

function Switch-AudioTracks {
    param([string]$FilePath)

    $tmp = "$FilePath.tmp.mkv"

    ffmpeg -i $FilePath -map 0:v -map 0:a:1 -map 0:a:0 -map 0:s? -map 0:t? -c copy -map_metadata 0 $tmp

    if ($LASTEXITCODE -eq 0) {
        Remove-Item $FilePath
        Rename-Item $tmp $FilePath
    } else {
        Write-Error "ffmpeg failed, original file untouched."
        Remove-Item -ErrorAction SilentlyContinue $tmp
    }
}

function Switch-AudioTracks-Batch {
    param(
        [string]$RootPath,
        [string]$Extension = "mkv"
    )

    $files = Get-ChildItem -Path $RootPath -Recurse -Filter "*.$Extension"
    $total = $files.Count
    $current = 0
    $failed = @()

    foreach ($file in $files) {
        $current++
        $FilePath = $file.FullName
        $tmp = "$FilePath.tmp.$Extension"

        Write-Host "[$current/$total] Processing: $FilePath"

        ffmpeg -i $FilePath `
            -map 0:v `
            -map 0:a:1 `
            -map 0:a:0 `
            -map 0:s? `
            -map 0:t? `
            -c copy `
            -map_metadata 0 `
            $tmp 2>&1 | Out-Null

        if ($LASTEXITCODE -eq 0) {
            Remove-Item $FilePath
            Rename-Item $tmp $FilePath
            Write-Host "  Done." -ForegroundColor Green
        } else {
            Write-Error "  Failed: $FilePath"
            $failed += $FilePath
            Remove-Item -ErrorAction SilentlyContinue $tmp
        }
    }

    Write-Host "`n--- Batch Complete ---"
    Write-Host "Succeeded: $($total - $failed.Count)/$total"

    if ($failed.Count -gt 0) {
        Write-Host "Failed files:" -ForegroundColor Red
        $failed | ForEach-Object { Write-Host "  $_" -ForegroundColor Red }
    }
}

function Show-Clients {
    hyprctl clients
}

function Show-Monitors {
    hyprctl monitors
}

function Show-Devices {
    hyprctl devices
}

function Edit-Profile {
    & codium-insiders "$HOME/.config/powershell/profile.ps1"
}

function Edit-Hyprland {
    & codium-insiders "$HOME/.config/hypr"
}

function Edit-WayBar {
    & codium-insiders "$HOME/.config/waybar"
}

function Edit-Logs {
    & codium-insiders $logFilePath
}

function Open-Directory {
    param (
        [string]$Path = "."
    )

    if (Get-Command xdg-open -ErrorAction SilentlyContinue) {
        Start-Process "xdg-open" -ArgumentList $Path
    } else {
        Write-LogOutput "xdg-open not found. Cannot open directory in file manager."
    }
}

function Start-MediaManagement {
    bash -c "$HOME/.scripts/mediactl.sh"
}

function Install-Icon {
    param(
        [Parameter(Mandatory=$true)]
        [string]$SourcePath
    )

    if (-not (Test-Path $SourcePath)) {
        Write-Error "File not found: $SourcePath"
        return
    }

    $extension    = [System.IO.Path]::GetExtension($SourcePath).ToLower()
    $baseName     = [System.IO.Path]::GetFileNameWithoutExtension($SourcePath).ToLower() -replace '\s+', '-'
    $iconBaseDir  = Join-Path $env:HOME ".local/share/icons/hicolor"
    $resolutions  = @(256, 192, 128, 96, 72, 64, 48, 40, 32, 24, 20, 16, 13)
    $tmpDir       = [System.IO.Path]::GetTempPath()

    $rasterExtensions = @('.png', '.jpg', '.jpeg', '.bmp', '.gif', '.webp', '.tiff', '.tif', '.tga', '.xpm')
    $vectorExtensions = @('.svg', '.svgz')

    if (-not (Test-Path $iconBaseDir)) {
        New-Item -ItemType Directory -Path $iconBaseDir -Force | Out-Null
    }

    # ── Find next collision-free iteration number ────────────────────────────
    $iteration = 0
    do {
        $collision = $false
        foreach ($res in $resolutions) {
            if (Test-Path (Join-Path $iconBaseDir "${res}x${res}/apps/$baseName.$iteration.png")) {
                $collision = $true; break
            }
        }
        if (-not $collision -and ($vectorExtensions -contains $extension)) {
            if (Test-Path (Join-Path $iconBaseDir "scalable/apps/$baseName.$iteration.svg")) {
                $collision = $true
            }
        }
        if ($collision) { $iteration++ }
    } while ($collision)

    # ── EXE → extract embedded ICO, then process as ICO ─────────────────────
    $tempIco = $null
    if ($extension -eq '.exe') {
        $tempIco = Join-Path $tmpDir "$baseName.$iteration.ico"
        Write-Host "Extracting icon from $SourcePath..."
        wrestool -x -t 14 "$SourcePath" -o "$tempIco" 2>$null
        if (-not (Test-Path $tempIco)) {
            Write-Error "Failed to extract icon from exe file"
            return
        }
        $extension  = '.ico'
        $SourcePath = $tempIco
    }

    # ── ICO → split frames and place those that match standard sizes ─────────
    if ($extension -eq '.ico') {
        Write-Host "Processing ICO: $SourcePath"
        $framePrefix = Join-Path $tmpDir "$baseName.$iteration"
        magick "$SourcePath" "${framePrefix}-%d.png" 2>$null

        $frames = @(Get-ChildItem $tmpDir -Filter "$baseName.$iteration-*.png")

        # Fall back for single-frame ICOs (ImageMagick omits the index suffix)
        if ($frames.Count -eq 0) {
            $singlePng = "${framePrefix}-0.png"
            magick "$SourcePath" "$singlePng" 2>$null
            if (Test-Path $singlePng) { $frames = @(Get-Item $singlePng) }
        }

        if ($frames.Count -eq 0) {
            Write-Error "No images could be extracted from the ICO file"
            if ($tempIco) { Remove-Item $tempIco -ErrorAction SilentlyContinue }
            return
        }

        foreach ($frame in $frames) {
            $dims = magick identify -format "%wx%h" $frame.FullName 2>$null
            if ($dims -match '^(\d+)x(\d+)$') {
                $w = [int]$Matches[1]; $h = [int]$Matches[2]
                if ($w -eq $h -and $resolutions -contains $w) {
                    $resDir = Join-Path $iconBaseDir "${w}x${w}/apps"
                    if (-not (Test-Path $resDir)) {
                        New-Item -ItemType Directory -Path $resDir -Force | Out-Null
                    }
                    Move-Item $frame.FullName (Join-Path $resDir "$baseName.$iteration.png") -Force
                    Write-Host "Placed ${w}x${w} icon → $resDir"
                } else {
                    Write-Host "Skipping ${w}x${h} frame (non-standard size)"
                    Remove-Item $frame.FullName -ErrorAction SilentlyContinue
                }
            }
        }

        if ($tempIco) { Remove-Item $tempIco -ErrorAction SilentlyContinue }
        Write-Host "Icon installation complete: $baseName.$iteration"
        return
    }

    # ── SVG → copy to scalable/apps and rasterize all sizes ─────────────────
    if ($vectorExtensions -contains $extension) {
        $scalableDir = Join-Path $iconBaseDir "scalable/apps"
        if (-not (Test-Path $scalableDir)) {
            New-Item -ItemType Directory -Path $scalableDir -Force | Out-Null
        }
        Copy-Item $SourcePath (Join-Path $scalableDir "$baseName.$iteration.svg") -Force
        Write-Host "Placed SVG → $scalableDir"

        Write-Host "Rasterizing SVG to all standard sizes..."
        foreach ($res in $resolutions) {
            $resDir = Join-Path $iconBaseDir "${res}x${res}/apps"
            if (-not (Test-Path $resDir)) {
                New-Item -ItemType Directory -Path $resDir -Force | Out-Null
            }
            $target = Join-Path $resDir "$baseName.$iteration.png"
            magick -background none -density 300 "$SourcePath" -resize "${res}x${res}" "$target" 2>$null
            if (Test-Path $target) { Write-Host "Placed ${res}x${res} icon → $resDir" }
        }

        Write-Host "Icon installation complete: $baseName.$iteration"
        return
    }

    # resize to all standard sizes
    if ($rasterExtensions -contains $extension) {
        Write-Host "Resizing $SourcePath to all standard icon sizes..."
        foreach ($res in $resolutions) {
            $resDir = Join-Path $iconBaseDir "${res}x${res}/apps"
            if (-not (Test-Path $resDir)) {
                New-Item -ItemType Directory -Path $resDir -Force | Out-Null
            }
            $target = Join-Path $resDir "$baseName.$iteration.png"
            # Lanczos resize preserving aspect ratio, transparent-padded to exact square
            magick "$SourcePath" -filter Lanczos -resize "${res}x${res}" `
                -background none -gravity center -extent "${res}x${res}" `
                "$target" 2>$null
            if (Test-Path $target) { Write-Host "Placed ${res}x${res} icon → $resDir" }
        }

        Write-Host "Icon installation complete: $baseName.$iteration"
        return
    }

    Write-Error ("Unsupported file type: '$extension'. Supported types: " +
        ".exe  .ico  .svg .svgz  .png .jpg .jpeg .bmp .gif .webp .tiff .tif .tga .xpm")
}

function Sync-Mods {
    $clientModsPath = "/home/ELECTRO/Gaming/Minecraft/Modrinth/profiles/ClientLTS/mods"
    $serverModsPath = "/home/ELECTRO/Gaming/Minecraft/Modrinth/profiles/ServerLTS/mods"

    $disabledFiles = Get-ChildItem -Path $clientModsPath -Filter "*.disabled"

    foreach ($disabledFile in $disabledFiles) {
        $originalName = $disabledFile.Name -replace '\.disabled$', ''
        $serverFile = Join-Path -Path $serverModsPath -ChildPath $originalName
        if (Test-Path $serverFile) {
            Rename-Item -Path $disabledFile.FullName -NewName $originalName
            Write-Host "Enabled: $originalName"
        }
    }

    Write-Host "Done!"
}

function Start-Vencord {
    bash -c 'sh -c "$(curl -sS https://vencord.dev/install.sh)"'
}

function Start-YTDLP-Video {
    param (
        $url
    )
    
    yt-dlp -f "bestvideo+bestaudio" --merge-output-format mkv --recode-video mkv --no-playlist --postprocessor-args "ffmpeg:-c:v hevc_nvenc -preset p7 -cq 20 -c:a flac" $url
}

function Start-YTDLP-Audio {
    param (
        $url
    )
    yt-dlp -f "bestaudio" --extract-audio --audio-format flac --extractor-args "youtube:skip=translated_subs" --no-playlist $url
}

function Start-YTDLP-Subtitles {
    param (
        $url
    )
    yt-dlp --skip-download --write-sub --write-auto-sub --extractor-args "youtube:skip=auto_translated_subs" --no-playlist --sub-langs all --convert-subs ass $url
}

function Install-ADB {
    param (
        [string]$apk
    )

    adb install --bypass-low-target-sdk-block $apk
}

function Restart-Session {
    $p = Get-Process -Id $PID
    $p | Select-Object -ExpandProperty Path | ForEach-Object { Invoke-Command { & "$_" } -NoNewScope }

    If ($p.Parent.Name -eq $p.Name -and !($p.MainWindowTitle))
    {
        Stop-Process -Id $p.Parent.Id -Force
    }
}

function Clear-CustOTALogs {
    Remove-Item -Path "$HOME/Docker/CustOTA/logs/*" -Recurse -Force -ErrorAction SilentlyContinue
    Write-Output "All files in ~/Docker/CustOTA/logs have been deleted."
}

function wineprefix($prefix, $cmd, $args) {
    & { $env:WINEPREFIX=$prefix; & $cmd $args }
}

function Start-DockerContainerUpdate {
    param(
        [string]$BasePath = "$HOME/Docker"
    )
    
    $containers = @(
        "Jellyfin",
        "Matrix",
        "SearXNG",
        "Vaultwarden"
    )
    
    $totalSteps = $containers.Count * 3
    $currentStep = 0
    
    Write-Host "Starting Docker container updates..." -ForegroundColor Cyan
    Write-Host ""
    
    # Phase 1: Stop all containers
    Write-Host "Phase 1: Stopping containers..." -ForegroundColor Yellow
    foreach ($container in $containers) {
        $currentStep++
        $containerPath = Join-Path $BasePath $container
        
        if (-not (Test-Path $containerPath) -or -not (Test-Path (Join-Path $containerPath "docker-compose.yml"))) {
            Write-Warning "Skipping $container - path or compose file not found"
            continue
        }
        
        Write-Progress -Activity "Updating Docker Containers" -Status "Stopping $container" -PercentComplete (($currentStep / $totalSteps) * 100)
        
        Push-Location $containerPath
        try {
            docker compose down 2>&1 | Out-Null
            Write-Host "  ✓ $container stopped" -ForegroundColor Green
        }
        catch {
            Write-Error "  ✗ $container failed to stop: $($_.Exception.Message)"
        }
        finally {
            Pop-Location
        }
    }
    
    Clear-CustOTALogs
    Write-Host ""
    
    # Phase 2: Pull all images
    Write-Host "Phase 2: Pulling images..." -ForegroundColor Yellow
    foreach ($container in $containers) {
        $currentStep++
        $containerPath = Join-Path $BasePath $container
        
        if (-not (Test-Path $containerPath) -or -not (Test-Path (Join-Path $containerPath "docker-compose.yml"))) {
            continue
        }
        
        Write-Progress -Activity "Updating Docker Containers" -Status "Pulling images for $container" -PercentComplete (($currentStep / $totalSteps) * 100)
        
        Push-Location $containerPath
        try {
            docker compose pull 2>&1 | Out-Null
            Write-Host "  ✓ $container images pulled" -ForegroundColor Green
        }
        catch {
            Write-Error "  ✗ $container failed to pull: $($_.Exception.Message)"
        }
        finally {
            Pop-Location
        }
    }
    
    Write-Host ""
    
    # Phase 3: Start all containers
    Write-Host "Phase 3: Starting containers..." -ForegroundColor Green
    foreach ($container in $containers) {
        $currentStep++
        $containerPath = Join-Path $BasePath $container
        
        if (-not (Test-Path $containerPath) -or -not (Test-Path (Join-Path $containerPath "docker-compose.yml"))) {
            continue
        }
        
        Write-Progress -Activity "Updating Docker Containers" -Status "Starting $container" -PercentComplete (($currentStep / $totalSteps) * 100)
        
        Push-Location $containerPath
        try {
            docker compose up -d 2>&1 | Out-Null
            Write-Host "  ✓ $container started" -ForegroundColor Green
        }
        catch {
            Write-Error "  ✗ $container failed to start: $($_.Exception.Message)"
        }
        finally {
            Pop-Location
        }
    }
    
    Write-Progress -Activity "Updating Docker Containers" -Completed
    Write-Host ""
    Write-Host "All containers updated" -ForegroundColor Green -BackgroundColor Black
}

function Update-Feishin {
    [CmdletBinding()]
    param(
        [string]$RepoPath = "$HOME/Development/Repositories/feishin",
        [switch]$Gitless
    )
    
    if (-not (Test-Path $RepoPath)) {
        Write-Error "Repository not found at $RepoPath"
        return
    }
    
    Write-Host "Checking for Feishin updates..." -ForegroundColor Cyan

    $isInstalled = Test-Path "/opt/feishin"

    Push-Location $RepoPath
    try {
        if (-not $Gitless) {
            $fetchOutput = git fetch origin 2>&1
            if ($LASTEXITCODE -ne 0) {
                $fetchText = $fetchOutput -join "`n"
                if ($fetchText -match "Permission denied|Could not read from remote|Host key verification failed|no such identity|publickey") {
                    Write-Error "SSH authentication failed. Did you run 'ssh-add'?"
                } else {
                    Write-Error "git fetch failed: $fetchText"
                }
                return
            }
            
            $currentBranch = git rev-parse --abbrev-ref HEAD
            $currentCommit = git rev-parse HEAD
            $remoteCommit = git rev-parse "origin/$currentBranch"
            
            if ($isInstalled -and $currentCommit -eq $remoteCommit) {
                Write-Host "✓ Feishin is already up to date!" -ForegroundColor Green
                return
            }
            
            if ($isInstalled -and -not ($currentCommit -eq $remoteCommit)) {
                Write-Host "New commits found. Starting build process..." -ForegroundColor Yellow
            } elseif (-not $isInstalled) {
                Write-Host "Feishin not installed. Starting build process..." -ForegroundColor Yellow
            }
            
            Write-Host "`nPulling latest changes..." -ForegroundColor Cyan
            git pull
        }
        else {
            Write-Host "Gitless mode: skipping Git fetch and pull." -ForegroundColor Cyan
        }
        
        Write-Host "`nInstalling dependencies..." -ForegroundColor Cyan
        pnpm install
        
        Write-Host "`nBuilding application..." -ForegroundColor Cyan
        pnpm run package:linux
        
        Set-Location dist
        
        if ($isInstalled) {
            Write-Host "`nInstalling Feishin update..." -ForegroundColor Cyan
        }else {
            Write-Host "`nInstalling Feishin..." -ForegroundColor Cyan
        }
        
        doas rm -rf /opt/feishin
        doas mv linux-unpacked /opt/feishin

        if (-not (Test-Path "/usr/bin/feishin")) {
            Write-Host "`nCreating symlink..." -ForegroundColor Cyan
            doas ln -s /opt/feishin/feishin /usr/bin/feishin
        }
        
        Set-Location ..
        Write-Host "`nCleaning up..." -ForegroundColor Cyan
        Remove-Item -Recurse -Force dist
        Remove-Item -Recurse -Force out
        git checkout HEAD -- "org.jeffvli.feishin.metainfo.xml"
        
        if ($isInstalled) {
            Write-Host "`n✓ Feishin successfully updated!" -ForegroundColor Green
        } else {
            Write-Host "`n✓ Feishin successfully installed!" -ForegroundColor Green
        }
        
    }
    catch {
        Write-Error "An error occurred during the update process: $_"
    }
    finally {
        Pop-Location
    }
}

function Update-EFIstub {
    $tmp = "/tmp/systemd.pkg.tar.zst"
    $url = "https://geo.mirror.pkgbuild.com/core/os/x86_64/" +
       (curl -s https://geo.mirror.pkgbuild.com/core/os/x86_64/ |
        grep -oP 'systemd-[0-9][^"]+pkg.tar.zst' |
        sort -V |
        tail -n 1)

    if (-not $url) {
        Write-Error "Failed to fetch systemd package URL"
        return
    }

    Write-Host "Downloading..." -NoNewline
    curl -fsL $url -o $tmp
    if ($LASTEXITCODE -eq 0) {
    Write-Host " done"
    } else {
        Write-Host " failed"
        Write-Error "Download failed"
        return
    }

    doas mkdir -p /usr/lib/systemd/boot/efi

    if (Test-Path /usr/lib/systemd/boot/efi/linuxx64.efi.stub) {
        Write-Host "EFI stub found. Replacing..."
        doas rm -f /usr/lib/systemd/boot/efi/linuxx64.efi.stub
    }else {
        Write-Host "EFI stub does not exist. Extracting..."
    }

    doas tar -I zstd -xf $tmp -C /usr/lib/systemd/boot/efi --strip-components=5 usr/lib/systemd/boot/efi/linuxx64.efi.stub

    Remove-Item $tmp
    Write-Host "EFI stub updated."
}

function Update-ElectricAUR {
    param (
        [string]$RepoRoot = "$HOME/Development/.electric-aur",
        [string]$DbName = "electric-aur.db.tar.gz"
    )

    # Resolve absolute path for pacman
    $RepoRoot = (Resolve-Path $RepoRoot).Path

    # Collect all package files recursively
    $pkgFiles = Get-ChildItem -Path $RepoRoot -Recurse -Filter *.pkg.tar.zst | ForEach-Object { $_.FullName }

    if (-not $pkgFiles) {
        Write-Warning "No .pkg.tar.zst packages found under $RepoRoot"
        return
    }

    # Build full path to database file
    $dbPath = Join-Path $RepoRoot $DbName

    # Run repo-add
    Write-Host "Updating repository database at $dbPath..."
    & repo-add $dbPath $pkgFiles

    Write-Host "Repository database updated successfully."
}

function Update-Flatpak {
    flatpak update
    flatpak uninstall --unused
}

function Update-DKMS {
    foreach ($kernel in (Get-ChildItem /lib/modules/).Name) {
        Write-Host "=== Building DKMS for: $kernel ==="
        doas dkms autoinstall -k $kernel
    }
}

function Update-System {
    Update-DKMS
    doas mkinitcpio -P
    doas grub-mkconfig -o /boot/grub/grub.cfg
}

function Upgrade-System {
    paru -Syyu --noconfirm
    Update-DKMS
    doas mkinitcpio -P
    doas grub-mkconfig -o /boot/grub/grub.cfg
}

function Start-TWAOS {
    Set-Location "$HOME/Development/Projects/TWAOS"
    Start-CustomClear
    Write-LogOutput "Welcome to the wonderful repository of Sip!"
    Write-Host "Here's what's changed:"
    Write-Host ""
    git status
    Write-Host ""
}

function Start-ELTS {
    param (
        [switch]$open, [switch]$o,
        [switch]$run,  [switch]$r,
        [switch]$gemini, [switch]$g,
        [switch]$or, [switch]$ro,
        [switch]$og, [switch]$go
    )

    cd "$HOME/Development/Projects/electris.net"
    Start-CustomClear
    Write-LogOutput "Welcome! Heart like a pen, On paper it bleeds."
    Write-Host "Here's what's changed:`n"; git status; Write-Host ""

    $doOpen   = $open -or $o -or $or -or $ro -or $og -or $go
    $doRun    = $run  -or $r -or $or -or $ro
    $doGemini = $gemini -or $g -or $og -or $go

    if ($doOpen)   { code . }
    if ($doRun)    { npm run dev }
    if ($doGemini) { gemini }
}
