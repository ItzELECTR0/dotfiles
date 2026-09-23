function Edit-Profile {
    & codium-insiders "$HOME/.config/powershell" "$HOME/.config/powershell/profile.ps1"
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
    & codium-insiders (Join-Path $HOME 'Documents/PowerShell/Logs/profile.log')
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

function Start-Vencord {
    bash -c 'sh -c "$(curl -sS https://vencord.dev/install.sh)"'
}

function Install-ADB {
    param (
        [string]$apk
    )

    adb install --bypass-low-target-sdk-block $apk
}

Export-ModuleMember -Function *
