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

function Start-Git-Checkout {
    git checkout @args
}

Export-ModuleMember -Function *
