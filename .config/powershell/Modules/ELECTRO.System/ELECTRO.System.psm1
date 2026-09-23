function Show-Clients {
    hyprctl clients
}

function Show-Monitors {
    hyprctl monitors
}

function Show-Devices {
    hyprctl devices
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

function Clear-CustOTALogs {
    foreach ($basePath in "$HOME/.containers", "$HOME/.podman", "$HOME/.docker") {
        $logPath = Join-Path $basePath 'CustOTA/logs'
        if (Test-Path $logPath) {
            Remove-Item -Path (Join-Path $logPath '*') -Recurse -Force -ErrorAction SilentlyContinue
        }
    }
    Write-Output 'CustOTA logs cleared from the available container directories.'
}

function wineprefix($prefix, $cmd, $args) {
    & { $env:WINEPREFIX=$prefix; & $cmd $args }
}

function Test-PodmanComposeProject {
    param([Parameter(Mandatory)][string]$Path)

    foreach ($fileName in 'compose.yaml', 'compose.yml', 'docker-compose.yaml', 'docker-compose.yml') {
        if (Test-Path (Join-Path $Path $fileName)) { return $true }
    }

    return $false
}

function Start-PodmanContainerUpdate {
    param(
        [string]$BasePath = "$HOME/.containers"
    )
    
    $containers = @(
        "Jellyfin",
        "Matrix",
        "SearXNG",
        "Vaultwarden"
    )
    
    $basePaths = @($BasePath, "$HOME/.containers", "$HOME/.podman", "$HOME/.docker") | Select-Object -Unique
    $projects = @(
        foreach ($container in $containers) {
            foreach ($root in $basePaths) {
                $containerPath = Join-Path $root $container
                if ((Test-Path $containerPath) -and (Test-PodmanComposeProject $containerPath)) {
                    [pscustomobject]@{ Name = $container; Path = $containerPath }
                    break
                }
            }
        }
    )

    $totalSteps = $projects.Count * 3
    $currentStep = 0
    
    Write-Host "Starting Podman container updates..." -ForegroundColor Cyan
    Write-Host ""
    
    # Phase 1: Stop all containers
    Write-Host "Phase 1: Stopping containers..." -ForegroundColor Yellow
    foreach ($project in $projects) {
        $currentStep++
        $container = $project.Name
        $containerPath = $project.Path
        
        Write-Progress -Activity "Updating Podman Containers" -Status "Stopping $container" -PercentComplete (($currentStep / $totalSteps) * 100)
        
        Push-Location $containerPath
        try {
            podman-compose down 2>&1 | Out-Null
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
    foreach ($project in $projects) {
        $currentStep++
        $container = $project.Name
        $containerPath = $project.Path
        
        Write-Progress -Activity "Updating Podman Containers" -Status "Pulling images for $container" -PercentComplete (($currentStep / $totalSteps) * 100)
        
        Push-Location $containerPath
        try {
            podman-compose pull 2>&1 | Out-Null
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
    foreach ($project in $projects) {
        $currentStep++
        $container = $project.Name
        $containerPath = $project.Path
        
        Write-Progress -Activity "Updating Podman Containers" -Status "Starting $container" -PercentComplete (($currentStep / $totalSteps) * 100)
        
        Push-Location $containerPath
        try {
            podman-compose up -d 2>&1 | Out-Null
            Write-Host "  ✓ $container started" -ForegroundColor Green
        }
        catch {
            Write-Error "  ✗ $container failed to start: $($_.Exception.Message)"
        }
        finally {
            Pop-Location
        }
    }
    
    Write-Progress -Activity "Updating Podman Containers" -Completed
    Write-Host ""
    Write-Host "All containers updated" -ForegroundColor Green
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

Export-ModuleMember -Function *
