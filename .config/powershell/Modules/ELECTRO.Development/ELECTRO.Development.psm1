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
