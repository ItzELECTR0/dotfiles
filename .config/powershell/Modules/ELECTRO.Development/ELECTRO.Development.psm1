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

function Start-TWAOS {
    param (
        [switch]$open, [switch]$o
    )

    $doOpen = $open -or $o

    Set-Location "$HOME/Development/Projects/Unity/SIP/TWAOS"
    Start-CustomClear
    Write-LogOutput "Welcome to the wonderful repository of Sip!"
    Write-Host "Here's what's changed:`n"; git status; Write-Host ""

    if ($doOpen)   { code . }
}

function Start-RustyPaint {
    param (
        [switch]$open, [switch]$o,
        [switch]$run, [switch]$r,
        [switch]$or, [switch]$ro
    )

    $doOpen = $open -or $o -or $or -or $ro
    $doRun  = $run -or $r -or $or -or $ro

    Set-Location "$HOME/Development/Projects/Rust/RustyPaint"
    Start-CustomClear
    Write-LogOutput "Welcome to the rusting repository of Paint3D!"
    Write-Host "Here's what's changed:`n"; git status; Write-Host ""

    if ($doOpen)   { code . }
    if ($doRun)    { cargo run -p rustypaint }
}

function Start-ELTS {
    param (
        [switch]$open, [switch]$o,
        [switch]$run,  [switch]$r,
        [switch]$or, [switch]$ro,
        [switch]$down,
        [switch]$u, [switch]$p, [switch]$podman,
        [switch]$pu, [switch]$up
    )

    $doRun    = $run  -or $r -or $or -or $ro
    $doOpen   = $open -or $o -or $or -or $ro
    $doUp     = $u
    $doDown   = $down
    $doPodman = $p -or $podman -or $pu -or $up

    Set-Location "$HOME/Development/Projects/Web/electris.net"
    Start-CustomClear
    Write-LogOutput "Welcome! Heart like a pen, On paper it bleeds."
    Write-Host "Here's what's changed:`n"; git status; Write-Host ""

    if ($doOpen)   { code . }

    if ($doRun)    { npm run dev }

    if ($doUp) {
        podman-compose build
        podman-compose up -d
        podman system prune -f
    }

    if ($doDown) { podman-compose down }

    if ($doPodman) {
        podman-compose down
        podman-compose build
        podman-compose up -d
        podman system prune -f
    }
}

Export-ModuleMember -Function *
