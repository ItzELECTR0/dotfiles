$script:username = $env:USER
$script:adminAccess = $false
try { $script:adminAccess = (id -u) -eq 0 } catch { $script:adminAccess = $false }
$script:logFilePath = Join-Path $HOME 'Documents/PowerShell/Logs/profile.log'

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

function hostname {
    [System.Net.Dns]::GetHostName()
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

function Test-Environment {
    $powershellDirectory = Split-Path (Split-Path $PSScriptRoot -Parent) -Parent
    $modulesDirectory = Join-Path $powershellDirectory 'Modules'
    $profilePath = Join-Path $powershellDirectory 'profile.ps1'
    $issues = [System.Collections.Generic.List[string]]::new()

    foreach ($path in @($profilePath) + @(Get-ChildItem $modulesDirectory -Recurse -File -Include '*.psm1', '*.psd1' | ForEach-Object FullName)) {
        $tokens = $null
        $parseErrors = $null
        [System.Management.Automation.Language.Parser]::ParseFile($path, [ref]$tokens, [ref]$parseErrors) | Out-Null
        foreach ($parseError in $parseErrors) {
            $issues.Add(('{0}:{1}: {2}' -f $path, $parseError.Extent.StartLineNumber, $parseError.Message))
        }
    }

    foreach ($manifest in Get-ChildItem $modulesDirectory -Directory | ForEach-Object { Join-Path $_.FullName ($_.Name + '.psd1') }) {
        $moduleName = [IO.Path]::GetFileNameWithoutExtension($manifest)
        if (Get-Module -Name $moduleName) { continue }

        try {
            Import-Module $manifest -DisableNameChecking -ErrorAction Stop
        }
        catch {
            $issues.Add(('{0}: {1}' -f $manifest, $_.Exception.Message))
        }
        finally {
            Remove-Module $moduleName -ErrorAction SilentlyContinue
        }
    }

    if ($issues.Count) {
        $issues | ForEach-Object { Write-Error $_ }
        return $false
    }

    Write-Host 'PowerShell profile and modules are error-free.' -ForegroundColor Green
    return $true
}

function Test-All {
    $environmentPassed = Test-Environment
    $projectDirectories = foreach ($root in "$HOME/.containers", "$HOME/.podman", "$HOME/.docker") {
        if (Test-Path $root) {
            Get-ChildItem $root -Directory
        }
    }
    $composePassed = $true

    foreach ($project in $projectDirectories) {
        if (-not (Test-PodmanComposeProject -Path $project.FullName)) {
            Write-Error "No Compose file found in '$($project.FullName)'."
            $composePassed = $false
        }
    }

    if (-not $projectDirectories) {
        Write-Error 'No container project directories found.'
        $composePassed = $false
    }

    return $environmentPassed -and $composePassed
}

Export-ModuleMember -Function *
