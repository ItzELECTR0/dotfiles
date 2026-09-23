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

function Start-MediaManagement {
    bash -c "$HOME/.dotfiles/scripts/mediactl.sh"
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

Export-ModuleMember -Function *
