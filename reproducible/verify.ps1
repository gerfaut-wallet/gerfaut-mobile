# Windows wrapper around reproducible/verify.sh.
#
#   pwsh reproducible/verify.ps1
#   pwsh reproducible/verify.ps1 --twice
#
# Docker Desktop and Git for Windows are the only requirements; the build
# itself runs inside the Linux container, so nothing on this machine ends
# up in the artifacts.

$ErrorActionPreference = "Stop"

$bash = Get-Command bash.exe -ErrorAction SilentlyContinue
if (-not $bash) {
    $candidates = @(
        "$env:ProgramFiles\Git\bin\bash.exe",
        "${env:ProgramFiles(x86)}\Git\bin\bash.exe",
        "$env:LOCALAPPDATA\Programs\Git\bin\bash.exe"
    )
    $found = $candidates | Where-Object { Test-Path $_ } | Select-Object -First 1
    if (-not $found) {
        throw "bash not found - install Git for Windows (https://git-scm.com/download/win)"
    }
    $bash = $found
} else {
    $bash = $bash.Source
}

$script = Join-Path $PSScriptRoot "verify.sh"
& $bash -lc "'$($script -replace '\', '/')' $($args -join ' ')"
if ($LASTEXITCODE -ne 0) { exit $LASTEXITCODE }
