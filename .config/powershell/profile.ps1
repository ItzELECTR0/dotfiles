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

# If not running interactively, don't do anything
if ($Host.Name -ne "ConsoleHost") { return }

# -------------------------------------------
# MODULES
# -------------------------------------------

# PSReadLine bootstrap
if (-not (Get-Module -ListAvailable -Name PSReadLine)) {
    Write-Host "PSReadLine not found. Installing..." -ForegroundColor Yellow

    # Ensure NuGet provider/PSGallery trust so it installs non-interactively
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
}

Set-PSReadLineKeyHandler -Key Tab -Function MenuComplete

# -------------------------------------------
# DEFINE VARIABLES
# -------------------------------------------

[bool]$adminAccess

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

# Define PATH & environment variables
# Only prepend what is missing, so re-sourcing this profile does not stack duplicates
$existingPath = $env:PATH -split ':'
$prependPath = @("$HOME/.local/share/pnpm", "$HOME/.local/bin") | Where-Object { $existingPath -notcontains $_ }
if ($prependPath) { $env:PATH = ($prependPath -join ':') + ':' + $env:PATH }
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

# Define podman socket
$env:DOCKER_HOST = "unix:///run/user/1000/podman/podman.sock"

# Define SI (base 1000) sizes for coreutils
$env:BLOCK_SIZE = "si"

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
Set-Alias updocker Start-DockerContainerUpdate
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

# -------------------------------------------
# FASTFETCH & USER DISPLAY
# -------------------------------------------

Write-Host ""
if ($Host.UI.RawUI.KeyAvailable -eq $false) {
    if (Get-Command fastfetch -ErrorAction SilentlyContinue) {
        fastfetch
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

function df { /usr/bin/df --si @args }
function du { /usr/bin/du --si @args }

function Start-CustomClear {
    Clear-Host
    Write-Host "PowerShell $($PSVersionTable.PSVersion)"
    Write-Host ""
    if ($Host.UI.RawUI.KeyAvailable -eq $false) {
        if (Get-Command fastfetch -ErrorAction SilentlyContinue) {
            fastfetch
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

function Start-Removing {
    # Behave exactly like rm
    if ($args.Count -eq 0) {
        & /usr/bin/rm
        return
    }

    $arguments = [string[]]$args
    $recursive = $false
    $oneFileSystem = $false
    $afterSeparator = $false
    $rmArguments = [System.Collections.Generic.List[string]]::new()
    $rmArguments.Add('--verbose')

    $targets = [System.Collections.Generic.List[string]]::new()

    foreach ($argument in $arguments) {
        if (-not $afterSeparator -and $argument -eq '--') {
            $afterSeparator = $true
            $rmArguments.Add('--')
            continue
        }

        if ($afterSeparator) {
            $targets.Add($argument)
            continue
        }

        if ($argument -eq '-') {
            $targets.Add($argument)
            continue
        }

        # Long options
        if ($argument.StartsWith('--')) {
            if ($argument -eq '--recursive') {
                $recursive = $true
            }

            if ($argument -eq '--one-file-system') {
                $oneFileSystem = $true
            }

            $rmArguments.Add($argument)
            continue
        }

        # Short options
        if ($argument.StartsWith('-')) {
            if ($argument.Length -gt 1 -and $argument.Substring(1) -match '[rR]') {
                $recursive = $true
            }

            $rmArguments.Add($argument)
            continue
        }

        # Normal operand
        $targets.Add($argument)
    }

    $resolvedTargets = [System.Collections.Generic.List[string]]::new()

    foreach ($target in $targets) {
        $resolved = @()

        if ($target.IndexOfAny([char[]]'*?[]') -ge 0) {
            $resolved = @(
                Get-Item -Path $target -Force -ErrorAction SilentlyContinue |
                ForEach-Object FullName
            )
        }
        else {
            try {
                $resolved = @(
                    Get-Item -LiteralPath $target -Force -ErrorAction Stop |
                    ForEach-Object FullName
                )
            }
            catch {
                # Leave inaccessible targets alone
            }
        }

        if ($resolved.Count -gt 0) {
            foreach ($path in $resolved) {
                $resolvedTargets.Add($path)
                $rmArguments.Add($path)
            }
        }
        else {
            $resolvedTargets.Add($target)
            $rmArguments.Add($target)
        }
    }

    $activity = 'Removing'

    # Count work before starting rm
    Write-Progress `
        -Activity $activity `
        -Status 'Counting items...'

    [long]$total = 0
    $countUnknown = $false

    foreach ($target in $resolvedTargets) {
        if ($recursive -and $target -eq '/') {
            $countUnknown = $true
            continue
        }

        if ($recursive) {
            $findArguments = [System.Collections.Generic.List[string]]::new()
            $findArguments.Add('-P')

            if ($oneFileSystem) {
                $findArguments.Add('-xdev')
            }

            $findArguments.Add('--')
            $findArguments.Add($target)
            $findArguments.Add('-printf')
            $findArguments.Add('x')

            $countText = (
                & /usr/bin/find @findArguments 2>$null |
                & /usr/bin/wc -c
            ).Trim()

            if ($countText -match '^\d+$') {
                $total += [long]$countText
            }
            else {
                $countUnknown = $true
            }
        }
        else {
            $total++
        }
    }

    [long]$removed = 0

    & /usr/bin/env LC_ALL=C /usr/bin/rm @rmArguments 2>&1 |
        ForEach-Object {
            $line = $_.ToString()

            if ($line -match '^\s*removed(?: directory)?\s+') {
                $removed++

                if ($total -gt 0) {
                    $percent = [math]::Min(
                        100,
                        [math]::Floor(($removed * 100.0) / $total)
                    )

                    Write-Progress `
                        -Activity $activity `
                        -Status "$removed / $total items removed" `
                        -PercentComplete $percent
                }
                else {
                    Write-Progress `
                        -Activity $activity `
                        -Status "$removed item(s) removed..."
                }
            }
            else {
                Write-Host $line
            }
        }

    $exitCode = $LASTEXITCODE

    if ($total -gt 0) {
        Write-Progress `
            -Activity $activity `
            -Status "$removed / $total items removed" `
            -PercentComplete 100 `
            -Completed
    }
    else {
        Write-Progress `
            -Activity $activity `
            -Completed
    }

    # Preserve $LASTEXITCODE
    $global:LASTEXITCODE = $exitCode
}

function Start-Git-Commit {
    param (
        [Parameter(Mandatory, Position = 0)]
        [string]$Title,

        # Every extra quoted string becomes another paragraph of the message body
        [Parameter(ValueFromRemainingArguments)]
        [string[]]$Description
    )

    $commitArgs = @("commit", "-m", $Title)

    foreach ($line in $Description) {
        if (-not [string]::IsNullOrWhiteSpace($line)) {
            $commitArgs += @("-m", $line)
        }
    }

    git @commitArgs
}

function Start-Git-Clone {
    param (
        [Parameter(Mandatory, Position = 0)]
        [string]$Repository,

        # Optional target folder for the clone
        [Parameter(Position = 1)]
        [string]$Directory,

        [switch]$gh,
        [switch]$gl,

        # Anything else is handed straight to git clone
        [Parameter(ValueFromRemainingArguments)]
        [string[]]$GitArgs
    )

    if ($gh) {
        $url = "git@github.com:$Repository"
    } elseif ($gl) {
        $url = "git@gitlab.com:$Repository"
    } else {
        $url = $Repository
    }

    $cloneArgs = @("clone", $url)

    if ($Directory) { $cloneArgs += $Directory }
    if ($GitArgs)   { $cloneArgs += $GitArgs }

    git @cloneArgs
}

function Start-Git-Merge {
    param (
        [Parameter(Mandatory, Position = 0)]
        [string]$Branch,

        # Anything else is handed straight to git merge
        [Parameter(ValueFromRemainingArguments)]
        [string[]]$GitArgs
    )

    git rev-parse --is-inside-work-tree 2>$null | Out-Null
    if ($LASTEXITCODE -ne 0) {
        Write-Error "Not inside a git repository."
        return
    }

    $currentBranch = git rev-parse --abbrev-ref HEAD
    if ($LASTEXITCODE -ne 0) {
        Write-Error "Could not determine the current branch."
        return
    }

    if ($Branch -eq $currentBranch) {
        Write-Error "Already on '$Branch'. Nothing to merge."
        return
    }

    # Resolve the source: local branch first, then a unique remote-tracking branch
    $source = $Branch

    git rev-parse --verify --quiet "refs/heads/$Branch" | Out-Null
    if ($LASTEXITCODE -ne 0) {
        $remoteMatches = @(git for-each-ref --format='%(refname:short)' "refs/remotes/*/$Branch")

        if ($remoteMatches.Count -eq 1) {
            $source = $remoteMatches[0]
            Write-Host "No local branch '$Branch'. Using '$source'." -ForegroundColor Yellow
        } elseif ($remoteMatches.Count -gt 1) {
            Write-Error ("Branch '$Branch' is ambiguous across remotes: " + ($remoteMatches -join ', '))
            return
        } else {
            Write-Error "Branch '$Branch' not found locally or on any remote."
            return
        }
    }

    Write-Host "Merging '$source' into '$currentBranch'..." -ForegroundColor Cyan

    $mergeArgs = @("merge", $source)
    if ($GitArgs) { $mergeArgs += $GitArgs }

    git @mergeArgs

    if ($LASTEXITCODE -eq 0) {
        Write-Host "Merged '$source' into '$currentBranch'." -ForegroundColor Green
    } else {
        Write-Host "Merge did not complete cleanly. Resolve conflicts, then run 'git merge --continue' or 'git merge --abort'." -ForegroundColor Red
    }
}

function Switch-Git-Origin {
    param (
        [Parameter(Position = 0)]
        [string]$Target,

        [switch]$gh,
        [switch]$gl
    )

    git rev-parse --is-inside-work-tree 2>$null | Out-Null
    if ($LASTEXITCODE -ne 0) {
        Write-Error "Not inside a git repository."
        return
    }

    $currentUrl = git remote get-url origin 2>$null
    if ($LASTEXITCODE -ne 0) { $currentUrl = $null }

    # Report what origin currently is
    if ([string]::IsNullOrWhiteSpace($Target)) {
        if ($currentUrl) {
            Write-Host "origin  $currentUrl"
        } else {
            Write-Host "No 'origin' remote set." -ForegroundColor Yellow
        }
        return
    }

    if ($gh -and $gl) {
        Write-Error "Pick one of -gh or -gl, not both."
        return
    }

    if ($gh) {
        $remoteHost = "github.com"
    } elseif ($gl) {
        $remoteHost = "gitlab.com"
    } else {
        $remoteHost = $null
    }

    if (-not $remoteHost) {
        $newUrl = $Target
    }
    else {
        if ($Target -match '/') {
            # `owner/repo` taken at face value
            $slug = $Target.Trim('/')
        }
        else {
            # Username only
            if (-not $currentUrl) {
                Write-Error "No 'origin' remote to take the repository name from. Pass <user>/<repo> instead."
                return
            }
            if ($currentUrl -notmatch '[:/]([^/:]+)/([^/]+?)(?:\.git)?$') {
                Write-Error "Could not parse owner/repo out of '$currentUrl'. Pass <user>/<repo> instead."
                return
            }

            $currentOwner = $Matches[1]
            $repoName     = $Matches[2]
            $slug         = "$Target/$repoName"

            if ($Target -eq $currentOwner) {
                Write-Error "origin already points at '$slug'."
                return
            }

            $parent   = $null
            $isFork   = $false
            $verified = $false

            if ($gh -and (Get-Command gh -ErrorAction SilentlyContinue)) {
                $json = gh api "repos/$slug" 2>$null
                if ($LASTEXITCODE -ne 0) {
                    Write-Error "'$Target' has no fork of '$repoName' on GitHub (repos/$slug not found)."
                    return
                }
                $info     = $json | ConvertFrom-Json
                $isFork   = [bool]$info.fork
                $parent   = $info.parent.full_name
                $verified = $true
            }
            elseif ($gl -and (Get-Command glab -ErrorAction SilentlyContinue)) {
                $encoded = $slug -replace '/', '%2F'
                $json = glab api "projects/$encoded" 2>$null
                if ($LASTEXITCODE -ne 0) {
                    Write-Error "'$Target' has no fork of '$repoName' on GitLab (projects/$slug not found)."
                    return
                }
                $info     = $json | ConvertFrom-Json
                $parent   = $info.forked_from_project.path_with_namespace
                $isFork   = [bool]$parent
                $verified = $true
            }
            else {
                # Fall back to proving the remote merely exists with no API client
                git ls-remote --exit-code "git@${remoteHost}:$slug" 2>$null | Out-Null
                if ($LASTEXITCODE -ne 0) {
                    Write-Error "'$Target' has no repository named '$repoName' on $remoteHost."
                    return
                }
                Write-Host "Repository exists, but fork status could not be verified (no API client)." -ForegroundColor Yellow
            }

            if ($verified) {
                if (-not $isFork) {
                    Write-Host "Warning: '$slug' exists but is not marked as a fork. Switching anyway." -ForegroundColor Yellow
                } elseif ($parent -and $parent -ne "$currentOwner/$repoName") {
                    Write-Host "Warning: '$slug' is a fork of '$parent', not of '$currentOwner/$repoName'. Switching anyway." -ForegroundColor Yellow
                }
            }
        }

        $newUrl = "git@${remoteHost}:$slug"
    }

    if ($currentUrl -eq $newUrl) {
        Write-Host "origin already set to $newUrl"
        return
    }

    if ($currentUrl) {
        git remote set-url origin $newUrl
    } else {
        git remote add origin $newUrl
    }

    if ($LASTEXITCODE -ne 0) {
        Write-Error "Failed to update the origin remote."
        return
    }

    if ($currentUrl) { Write-Host "old  $currentUrl" -ForegroundColor DarkGray }
    Write-Host "new  $newUrl" -ForegroundColor Green
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

# No param block on purpose: it would bind '-b' to a parameter name and swallow it
function Start-Git-Checkout {
    git checkout @args
}

function Start-Compressing {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory, Position = 0)]
        [string]$InputFile,

        [Parameter(Position = 1)]
        [double]$TargetSizeMiB = 20,

        [Parameter(Position = 2)]
        [int]$AudioBitrate = 160,

        # h264: safe default for Discord; h265: ~25% more efficient;
        [ValidateSet('h264', 'h265')]
        [string]$Codec = 'h265',

        [ValidateSet('auto', 'nvenc', 'cpu')]
        [string]$Encoder = 'auto',

        [ValidateSet('resolution', 'framerate')]
        [string]$Prefer = 'resolution',

        [int]$MinHeight = 1080,
        [int]$MaxHeight = 0,
        [int]$Height = 0,       # pin resolution
        [double]$MaxFps = 0,

        [ValidateRange(0, 10)]
        [double]$MarginPercent = 1.0,

        [ValidateRange(1, 6)]
        [int]$Attempts = 4,

        [string]$OutputFile
    )

    $ErrorActionPreference = 'Stop'
    $PSNativeCommandUseErrorActionPreference = $false
    $IC = [cultureinfo]::InvariantCulture

    function ConvertTo-Num([string]$s) {
        $v = 0.0
        if ($s -and $s -ne 'N/A' -and [double]::TryParse($s, 'Float', $IC, [ref]$v)) { return $v }
        return 0.0
    }
    function Get-Rate([string]$r) {
        if (-not $r) { return 0.0 }
        $p = $r -split '/'
        if ($p.Count -eq 2) {
            $d = ConvertTo-Num $p[1]
            if ($d -ne 0) { return (ConvertTo-Num $p[0]) / $d }
            return 0.0
        }
        return ConvertTo-Num $r
    }

    foreach ($bin in 'ffmpeg', 'ffprobe') {
        if (-not (Get-Command $bin -ErrorAction SilentlyContinue)) { throw "$bin not found in PATH" }
    }
    if (-not (Test-Path -LiteralPath $InputFile)) { throw "Input file not found: $InputFile" }
    $src = (Resolve-Path -LiteralPath $InputFile).Path

    $meta = (& ffprobe -v error -print_format json -show_format -show_streams -i $src | Out-String) | ConvertFrom-Json
    $vs = @($meta.streams | Where-Object { $_.codec_type -eq 'video' })[0]
    $audioCount = @($meta.streams | Where-Object { $_.codec_type -eq 'audio' }).Count
    if (-not $vs) { throw "No video stream in '$src'" }

    $duration = 0.0
    foreach ($d in @($meta.format.duration, $vs.duration)) {
        $t = ConvertTo-Num ([string]$d)
        if ($t -gt 0) { $duration = $t; break }
    }
    if ($duration -le 0) { throw "Could not determine duration of '$src'" }

    $srcW = [int]$vs.width
    $srcH = [int]$vs.height
    $srcFps = Get-Rate $vs.avg_frame_rate
    if ($srcFps -le 0) { $srcFps = Get-Rate $vs.r_frame_rate }
    if ($srcFps -le 0) { $srcFps = 60 }

    $nvencName = if ($Codec -eq 'h265') { 'hevc_nvenc' } else { 'h264_nvenc' }
    $cpuName   = if ($Codec -eq 'h265') { 'libx265' }    else { 'libx264' }
    $useNvenc = switch ($Encoder) {
        'nvenc' { $true }
        'cpu'   { $false }
        default { (& ffmpeg -hide_banner -encoders 2>&1 | Out-String) -match [regex]::Escape($nvencName) }
    }

    $limitBytes = [long][math]::Floor($TargetSizeMiB * 1MB)
    $budget     = [long][math]::Floor($limitBytes * (1 - $MarginPercent / 100))
    $audioBps   = if ($audioCount -gt 0) { $AudioBitrate * 1000 * $audioCount } else { 0 }
    $overhead   = [long]($budget * 0.006) + 8192

    $videoBps = [long](((($budget - $overhead) * 8) / $duration) - $audioBps)
    if ($videoBps -lt 60000) {
        throw ("Target of {0} MiB is too small for {1:N1}s with {2} kbps audio." -f $TargetSizeMiB, $duration, $AudioBitrate)
    }

    if ($Height -gt 0) { $MinHeight = $Height; $MaxHeight = $Height }
    $minH = [math]::Min($MinHeight, $srcH)
    $maxH = if ($MaxHeight -gt 0) { [math]::Min($MaxHeight, $srcH) } else { $srcH }
    if ($minH -gt $maxH) { $minH = $maxH }

    $heights = @(@(2160, 1440, 1080, 900, 720, 600, 540, 480) |
        Where-Object { $_ -le $maxH -and $_ -ge $minH })
    if ($heights.Count -eq 0) { $heights = @($maxH) }

    $fpsList = if ($MaxFps -gt 0) { @([math]::Min($srcFps, $MaxFps)) }
               elseif ($srcFps -ge 50) { @($srcFps, [math]::Round($srcFps / 2)) }
               else { @($srcFps) }

    $candidates = @()
    if ($Prefer -eq 'resolution') {
        foreach ($h in $heights) { foreach ($f in $fpsList) { $candidates += , @($h, $f) } }
    } else {
        foreach ($f in $fpsList) { foreach ($h in $heights) { $candidates += , @($h, $f) } }
    }

    $bppTarget = if ($Codec -eq 'h265') { 0.035 } else { 0.060 }
    $pick = $candidates[-1]
    foreach ($c in $candidates) {
        $w = [math]::Round($srcW * $c[0] / $srcH)
        if (($videoBps / ($w * $c[0] * $c[1])) -ge $bppTarget) { $pick = $c; break }
    }
    $outH = [int]$pick[0]
    $outFps = [double]$pick[1]
    $outW = 2 * [math]::Round($srcW * $outH / $srcH / 2)
    $bpp = $videoBps / ($outW * $outH * $outFps)

    $filters = @()
    if ([math]::Abs($outFps - $srcFps) -gt 0.01) { $filters += "fps=$($outFps.ToString($IC))" }
    if ($outH -ne $srcH) { $filters += "scale=-2:${outH}:flags=lanczos" }
    $vfArgs = if ($filters.Count) { @('-vf', ($filters -join ',')) } else { @() }

    # tag colour only if the source left it unspecified
    $colorArgs = @()
    if (-not $vs.color_primaries -or $vs.color_primaries -eq 'unknown') {
        $colorArgs = @('-color_primaries', 'bt709', '-color_trc', 'bt709', '-colorspace', 'bt709')
    }

    $gop = [int][math]::Round($outFps * 2)
    $keyintMin = [int][math]::Round($outFps)

    if (-not $OutputFile) {
        $base = [IO.Path]::GetFileNameWithoutExtension($src)
        $OutputFile = Join-Path (Get-Location).Path "$base-compressed.mp4"
    }
    $tmpOut  = "$OutputFile.part.mp4"
    $passlog = Join-Path ([IO.Path]::GetTempPath()) "startcompress-$PID-$(Get-Random)"

    function Build-Args([long]$bv, [bool]$nvenc, [bool]$safe, [int]$passNo) {
        $a = @('-hide_banner', '-loglevel', 'error', '-stats', '-y')
        if ($nvenc) { $a += @('-hwaccel', 'cuda') }
        $a += @('-i', $src, '-map', '0:v:0')
        if ($audioCount -gt 0) { $a += @('-map', '0:a?') }
        $a += @('-sn', '-dn', '-map_chapters', '-1')
        $a += $vfArgs

        if ($nvenc) {
            $a += @('-c:v', $nvencName, '-preset', 'p6', '-tune', 'hq',
                    '-rc', 'vbr', '-multipass', 'fullres',
                    '-b:v', "$bv",
                    '-maxrate', "$([long]($bv * 1.6))",
                    '-bufsize', "$([long]($bv * 3))")
            if (-not $safe) {
                $a += @('-rc-lookahead', '32', '-spatial-aq', '1', '-temporal-aq', '1', '-aq-strength', '8')
                if ($Codec -eq 'h264' -and $outH -le 1080) { $a += @('-level', '4.2') }
            }
        } else {
            $a += @('-c:v', $cpuName, '-preset', 'medium', '-b:v', "$bv")
            if ($Codec -eq 'h265') { $a += @('-x265-params', "pass=${passNo}:stats=$passlog") }
            else { $a += @('-pass', "$passNo", '-passlogfile', $passlog) }
        }

        $a += @('-pix_fmt', 'yuv420p', '-fps_mode', 'cfr',
                '-g', "$gop", '-keyint_min', "$keyintMin", '-bf', '2')
        $a += @('-profile:v', $(if ($Codec -eq 'h265') { 'main' } else { 'high' }))
        if ($Codec -eq 'h265') { $a += @('-tag:v', 'hvc1') }
        $a += $colorArgs

        if ($passNo -eq 1 -and -not $nvenc) {
            $a += @('-an', '-f', 'null', '/dev/null')
        } else {
            if ($audioCount -gt 0) { $a += @('-c:a', 'aac', '-b:a', "${AudioBitrate}k", '-ac', '2') }
            else { $a += '-an' }
            $a += @('-video_track_timescale', '90000',
                    '-movflags', '+faststart+negative_cts_offsets',
                    $tmpOut)
        }
        return $a
    }

    Write-Host ("source: {0}x{1} @ {2:N2} fps, {3:N1}s, {4:N1} MiB" -f `
        $srcW, $srcH, $srcFps, $duration, ((Get-Item -LiteralPath $src).Length / 1MB))
    Write-Host ("plan:   {0}x{1} @ {2:N0} fps, {3}, {4:N4} bpp (want >= {5:N3})" -f `
        $outW, $outH, $outFps, $(if ($useNvenc) { $nvencName } else { $cpuName }), $bpp, $bppTarget)
    if ($bpp -lt $bppTarget) {
        Write-Warning "Bitrate is below what this codec needs at this size. Expect visible blocking."
    }

    $bestSize = 0L
    $safeMode = $false

    try {
        for ($i = 1; $i -le $Attempts; $i++) {
            Write-Host ("[{0}/{1}] asking for {2} kbps video ..." -f $i, $Attempts, [long]($videoBps / 1000)) -ForegroundColor Cyan

            if ($useNvenc) {
                & ffmpeg @(Build-Args $videoBps $true $safeMode 2)
                if ($LASTEXITCODE -ne 0 -and -not $safeMode) {
                    Write-Warning 'NVENC rejected the advanced options; retrying without them.'
                    $safeMode = $true
                    & ffmpeg @(Build-Args $videoBps $true $true 2)
                }
                if ($LASTEXITCODE -ne 0) {
                    Write-Warning 'NVENC failed; falling back to CPU encoding.'
                    $useNvenc = $false
                }
            }
            if (-not $useNvenc) {
                & ffmpeg @(Build-Args $videoBps $false $false 1)
                if ($LASTEXITCODE -eq 0) { & ffmpeg @(Build-Args $videoBps $false $false 2) }
            }
            if ($LASTEXITCODE -ne 0) { throw "ffmpeg exited with code $LASTEXITCODE" }

            $size = (Get-Item -LiteralPath $tmpOut).Length
            Write-Host ("      got {0:N2} MiB ({1:N1}% of limit)" -f ($size / 1MB), (100.0 * $size / $limitBytes))

            if ($size -le $limitBytes -and $size -gt $bestSize) {
                Move-Item -LiteralPath $tmpOut -Destination $OutputFile -Force
                $bestSize = $size
            } else {
                Remove-Item -LiteralPath $tmpOut -Force -ErrorAction SilentlyContinue
            }

            if ($size -le $limitBytes -and $size -ge $budget * 0.97) { break }
            if ($i -eq $Attempts) { break }

            # measure the encoder's actual delivery and solve for the next request
            $actualVideoBps = ConvertTo-Num ((& ffprobe -v error -select_streams v:0 `
                -show_entries stream=bit_rate -of csv=p=0 -i $OutputFile 2>$null | Out-String).Trim())
            if ($actualVideoBps -le 0) { $actualVideoBps = $videoBps }
            $k = [math]::Min(2.0, [math]::Max(0.5, $actualVideoBps / $videoBps))

            $nonVideo = $size - ($actualVideoBps * $duration / 8)
            if ($nonVideo -lt 0) { $nonVideo = $audioBps * $duration / 8 }

            $next = [long](((($budget - $nonVideo) * 8) / $duration) / $k)
            if ($next -lt 60000) { $next = 60000 }
            if ([math]::Abs($next - $videoBps) -lt ($videoBps * 0.01)) {
                if ($size -le $limitBytes) { break }
                $next = [long]($videoBps * 0.95)
            }
            $videoBps = $next
        }
    }
    finally {
        Remove-Item -LiteralPath $tmpOut -Force -ErrorAction SilentlyContinue
        Get-ChildItem "$passlog*" -ErrorAction SilentlyContinue | Remove-Item -Force -ErrorAction SilentlyContinue
    }

    if ($bestSize -eq 0) {
        throw "Could not get under $TargetSizeMiB MiB in $Attempts attempts. Try -MaxFps 30 or a lower -AudioBitrate."
    }

    Write-Host ("done: {0} ({1:N2} MiB, {2:N1}% of limit)" -f `
        $OutputFile, ($bestSize / 1MB), (100.0 * $bestSize / $limitBytes)) -ForegroundColor Green
    Get-Item -LiteralPath $OutputFile
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

function Edit-DCLI {
    & codium-insiders "$HOME/.config/dcli"
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

function Start-macOS {
    cd $HOME/.osx-kvm
    bash -c "$HOME/.osx-kvm/OpenCore-Boot.sh"
}

function Mount-macOS {
    bash -c "$HOME/.dotfiles/scripts/macmount.sh"
}

function Mount-Windows {
    param(
        [string]$Path,
        [switch]$Live,
        [switch]$Umount
    )

    $mountArgs = @()

    if ($Path) {
        $resolved = Resolve-Path -Path $Path -ErrorAction SilentlyContinue
        if (-not $resolved) {
            Write-Error "Image not found: $Path"
            return
        }
        $mountArgs += @("--path", $resolved.Path)
    }

    if ($Live)   { $mountArgs += "--live" }
    if ($Umount) { $mountArgs += "--umount" }

    & bash "$HOME/.dotfiles/scripts/winmount.sh" @mountArgs
}

function Start-MediaManagement {
    bash -c "$HOME/.dotfiles/scripts/mediactl.sh"
}

function Start-SteamDepotBuild {
    bash -c "$HOME/.dotfiles/scripts/build-steam-packages.sh"
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

function Start-YTDLP-Playlist {
    param (
        [Parameter(Mandatory = $true)]
        [string]$url,
        [string]$Name
    )

    if ([string]::IsNullOrWhiteSpace($Name)) {
        $outputTemplate = "%(playlist_title)s/%(playlist_index)s - %(title)s.%(ext)s"
    }
    else {
        $outputTemplate = "$Name/%(playlist_index)s - %(title)s.%(ext)s"
    }

    yt-dlp `
        -f "bestvideo+bestaudio" `
        --merge-output-format mkv `
        --recode-video mkv `
        --yes-playlist `
        -o $outputTemplate `
        --postprocessor-args "ffmpeg:-c:v hevc_nvenc -preset p7 -cq 20 -c:a flac" `
        $url
}

function Install-ADB {
    param (
        [string]$apk
    )

    adb install --bypass-low-target-sdk-block $apk
}

function Restart-Session {
    # Replace this process instead of spawning a child inside it. Spawning nests
    # shells, re-inherits the already-mutated environment (PATH grows every
    # restart) and throws away the child's exit code.
    $pwshPath = (Get-Process -Id $PID).Path

    if ($IsLinux -or $IsMacOS) {
        if (-not ('Libc.Native' -as [type])) {
            Add-Type -Namespace Libc -Name Native -MemberDefinition @'
[DllImport("libc", SetLastError = true)]
public static extern int execv(string path, IntPtr[] argv);

[DllImport("libc", SetLastError = true)]
public static extern int chdir(string path);
'@
        }

        # Set-Location moves PowerShell's location but not the process working
        # directory, and exec keeps the latter. Sync them so the new shell opens
        # where this one actually was.
        $location = Get-Location
        if ($location.Provider.Name -eq 'FileSystem' -and $location.ProviderPath) {
            if ([Libc.Native]::chdir($location.ProviderPath) -ne 0) {
                Write-Warning "Could not change directory to '$($location.ProviderPath)'; the new shell may start elsewhere."
            }
        }

        # execv needs a NULL-terminated char*[]; marshalling a plain string[] fails
        $argv = @($pwshPath, '-NoLogo')
        $ptrs = [IntPtr[]]::new($argv.Count + 1)
        for ($i = 0; $i -lt $argv.Count; $i++) {
            $ptrs[$i] = [Runtime.InteropServices.Marshal]::StringToHGlobalAnsi($argv[$i])
        }
        $ptrs[$argv.Count] = [IntPtr]::Zero

        [Libc.Native]::execv($pwshPath, $ptrs) | Out-Null

        # Only reached if execv failed
        Write-Warning "execv failed (errno $([Runtime.InteropServices.Marshal]::GetLastWin32Error())). Falling back to a nested shell."
    }

    & $pwshPath -NoLogo
    exit $LASTEXITCODE
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
        [string]$BasePath = "$HOME/.docker"
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
    Write-Host "All containers updated" -ForegroundColor Green
}

function Update-Feishin {
    [CmdletBinding()]
    param(
        [string]$RepoPath = "$HOME/Development/Repositories/github/feishin",
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

function Update-AUR {
    paru -S --rebuild=all $(pacman -Qm | awk '$1 ~ /-git$/ {print $1}')
}

function Update-AURgitPackage {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)]
        [string]$PackageName,

        [switch]$CleanBuild,
        [switch]$ClearSource,
        [switch]$NoConfirm
    )

    begin {
        function Test-CommandExists {
            param([string]$Name)
            return $null -ne (Get-Command $Name -ErrorAction SilentlyContinue)
        }

        $AurHelper = $null

        if (Test-CommandExists "paru") {
            $AurHelper = "paru"
        }
        elseif (Test-CommandExists "yay") {
            $AurHelper = "yay"
        }
        else {
            throw "Neither paru nor yay is installed or available in PATH."
        }

        foreach ($cmd in @("git", "makepkg")) {
            if (-not (Test-CommandExists $cmd)) {
                throw "$cmd is not installed or not in PATH."
            }
        }

        Write-Host "Using AUR helper: $AurHelper" -ForegroundColor DarkGray
    }

    process {
        Write-Host "Updating AUR package: $PackageName" -ForegroundColor Cyan

        $cacheDir = Join-Path $HOME ".cache/$AurHelper/clone/$PackageName"

        if (-not (Test-Path $cacheDir)) {
            Write-Host "Package cache does not exist. Cloning/building fresh..." -ForegroundColor Yellow

            $aurArgs = @("-S"; "--needed"; $PackageName)
            if ($NoConfirm) { $aurArgs += "--noconfirm" }

            & $AurHelper @aurArgs

            if ($LASTEXITCODE -ne 0) {
                throw "$AurHelper failed to install $PackageName"
            }

            return
        }

        Push-Location $cacheDir

        try {
            # PKGBUILD repo update
            Write-Host "Pulling latest PKGBUILD changes..." -ForegroundColor Yellow

            & git fetch --all --prune
            & git reset --hard HEAD
            & git clean -fdx --exclude=src

            & git pull --rebase

            if ($LASTEXITCODE -ne 0) {
                Write-Host "Warning: git pull failed (network issue?). Rebuilding with existing PKGBUILD." -ForegroundColor Yellow
            }

            # Source update (best-effort)
            Write-Host "Fetching upstream sources..." -ForegroundColor Yellow

            $fetchArgs = @("-o"; "--noprepare")
            if ($NoConfirm) { $fetchArgs += "--noconfirm" }

            & makepkg @fetchArgs

            if ($LASTEXITCODE -ne 0) {
                Write-Host "Warning: source fetch failed (network issue?). Rebuilding with existing sources." -ForegroundColor Yellow
            }

            # Optional cleanup
            if ($CleanBuild) {
                Write-Host "Cleaning old build artifacts..." -ForegroundColor Yellow

                if (Test-Path "pkg") {
                    Remove-Item "pkg" -Recurse -Force -ErrorAction SilentlyContinue
                }

                Get-ChildItem -Force |
                    Where-Object { $_.Name -match '\.pkg\.tar' } |
                    Remove-Item -Force -ErrorAction SilentlyContinue
            }

            if ($ClearSource) {
                Write-Host "Clearing source directory..." -ForegroundColor Yellow

                if (Test-Path "src") {
                    Remove-Item "src" -Recurse -Force -ErrorAction SilentlyContinue
                }
            }

            # Build (no install)
            Write-Host "Building package..." -ForegroundColor Green

            # Drop -e if source was cleared
            $makepkgArgs = if ($ClearSource) {
                @("-s"; "--force")
            } else {
                @("-se"; "--force")
            }
            if ($NoConfirm) { $makepkgArgs += "--noconfirm" }

            & makepkg @makepkgArgs

            if ($LASTEXITCODE -ne 0) {
                throw "makepkg build failed for $PackageName"
            }

            $builtPackages = Get-ChildItem -Force |
                Where-Object { $_.Name -match '\.pkg\.tar' } |
                Select-Object -ExpandProperty FullName

            if (-not $builtPackages) {
                throw "Build appeared to succeed but no .pkg.tar file was found in $cacheDir"
            }

            # Install
            Write-Host "Installing built package(s)..." -ForegroundColor Green

            $pacmanArgs = @("-U")
            if ($NoConfirm) { $pacmanArgs += "--noconfirm" }
            $pacmanArgs += $builtPackages

            & doas pacman @pacmanArgs

            if ($LASTEXITCODE -ne 0) {
                Write-Host ""
                Write-Host "Installation failed for $PackageName." -ForegroundColor Red
                Write-Host "The built package(s) are still available at:" -ForegroundColor Yellow

                $builtPackages | ForEach-Object { Write-Host "  $_" -ForegroundColor Yellow }

                Write-Host ""
                Write-Host "To retry installation manually:" -ForegroundColor DarkGray
                Write-Host "  doas pacman -U $($builtPackages -join ' ')" -ForegroundColor DarkGray

                throw "pacman failed to install $PackageName (exit $LASTEXITCODE)"
            }

            # Post-install cleanup (only on success)
            Write-Host "Cleaning up built package artifacts..." -ForegroundColor DarkGray

            $builtPackages | ForEach-Object {
                Remove-Item $_ -Force -ErrorAction SilentlyContinue
            }

            Write-Host "Successfully updated $PackageName" -ForegroundColor Green
        }
        finally {
            Pop-Location
        }
    }
}

function Update-ElectricAUR {
    param (
        [string]$RepoPath = "$HOME/Development/Repositories/electric-aur",
        [string]$RepoName = "electric-aur"
    )

    if (-not (Test-Path $RepoPath)) {
        Write-Error "Path does not exist: $RepoPath"
        return
    }

    Push-Location $RepoPath

    $repoDb = "$RepoName.db.tar.gz"

    $packages = Get-ChildItem -Filter "*.pkg.tar.*"

    if ($packages.Count -eq 0) {
        Write-Warning "No packages found."
        Pop-Location
        return
    }

    if (Test-Path $repoDb) {
        Write-Host "Cleaning old entries from repo..."

        $currentEntries = tar -xOf $repoDb */desc 2>$null |
            Select-String "%NAME%" -Context 0,1 |
            ForEach-Object { $_.Context.PostContext[0].Trim() }

        $currentPkgNames = $packages | ForEach-Object {
            tar -xOf $_ .PKGINFO 2>$null |
            Select-String "^pkgname = " |
            ForEach-Object { ($_ -split " = ")[1].Trim() }
        }

        $currentPkgNames = $currentPkgNames | Sort-Object -Unique

        foreach ($entry in $currentEntries) {
            if ($entry -notin $currentPkgNames) {
                Write-Host "Removing stale package: $entry"
                repo-remove $repoDb $entry | Out-Null
            }
        }
    }

    Write-Host "Adding/updating packages..."

    repo-add $repoDb ($packages | ForEach-Object { $_.Name })

    Write-Host "Repository updated: $repoDb"

    Pop-Location
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
    param (
        [switch]$open, [switch]$o,
        [switch]$gemini, [switch]$g,
        [switch]$og, [switch]$go
    )

    $doOpen   = $open -or $o -or $og -or $go
    $doGemini = $gemini -or $g -or $og -or $go

    Set-Location "$HOME/Development/Projects/Unity/SIP/TWAOS"
    Start-CustomClear
    Write-LogOutput "Welcome to the wonderful repository of Sip!"
    Write-Host "Here's what's changed:`n"; git status; Write-Host ""

    if ($doOpen)   { code . }

    if ($doGemini) { agy }
}

function Start-RustyPaint {
    param (
        [switch]$open, [switch]$o,
        [switch]$gemini, [switch]$g,
        [switch]$og, [switch]$go
    )

    $doOpen   = $open -or $o -or $og -or $go
    $doGemini = $gemini -or $g -or $og -or $go

    Set-Location "$HOME/Development/Projects/Rust/RustyPaint"
    Start-CustomClear
    Write-LogOutput "Welcome to the rusting repository of Paint3D!"
    Write-Host "Here's what's changed:`n"; git status; Write-Host ""

    if ($doOpen)   { code . }

    if ($doGemini) { agy }
}

function Start-ELTS {
    param (
        [switch]$open, [switch]$o,
        [switch]$run,  [switch]$r,
        [switch]$gemini, [switch]$g,
        [switch]$or, [switch]$ro,
        [switch]$og, [switch]$go,
        [switch]$up, [switch]$down,
        [switch]$u, [switch]$d,
        [switch]$ud, [switch]$du
    )

    $doOpen   = $open -or $o -or $or -or $ro -or $og -or $go
    $doRun    = $run  -or $r -or $or -or $ro
    $doGemini = $gemini -or $g -or $og -or $go
    $doUp     = $u -or $up
    $doDown     = $d -or $down
    $doDocker = $u -and $d -or $du -or $ud

    Set-Location "$HOME/Development/Projects/Web/electris.net"
    Start-CustomClear
    Write-LogOutput "Welcome! Heart like a pen, On paper it bleeds."
    Write-Host "Here's what's changed:`n"; git status; Write-Host ""

    if ($doOpen)   { code . }

    if ($doRun)    { npm run dev }

    if ($doGemini) { agy }

    if ($doUp) {
        docker compose build
        docker compose up -d
        docker system prune -f
    }

    if ($doDown) { docker compose down }

    if ($doDocker) {
        docker compose down
        docker compose build
        docker compose up -d
        docker system prune -f
    }
}
