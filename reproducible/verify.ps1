# Windows wrapper around reproducible/verify.sh.
#
#   pwsh reproducible/verify.ps1
#   pwsh reproducible/verify.ps1 --twice
#
# Docker Desktop and Git for Windows are the only requirements; the build
# itself runs inside the Linux container, so nothing on this machine ends
# up in the artifacts.

$ErrorActionPreference = "Stop"

# Git Bash first, and only then whatever `bash` is on PATH. On a machine
# with WSL installed, PATH answers with C:\Windows\System32\bash.exe: a
# Linux shell that cannot open a C:\ path, so it would fail on the very
# first line with "No such file or directory".
$candidates = @(
    "$env:ProgramFiles\Git\bin\bash.exe",
    "${env:ProgramFiles(x86)}\Git\bin\bash.exe",
    "$env:LOCALAPPDATA\Programs\Git\bin\bash.exe"
)
$bash = $candidates | Where-Object { Test-Path $_ } | Select-Object -First 1
if (-not $bash) {
    $onPath = Get-Command bash.exe -ErrorAction SilentlyContinue
    if ($onPath -and $onPath.Source -notlike "$env:SystemRoot\System32\*") {
        $bash = $onPath.Source
    }
}
if (-not $bash) {
    throw "Git Bash not found - install Git for Windows (https://git-scm.com/download/win)"
}

# `.Replace` and not `-replace`: the latter takes a regular expression,
# and a lone backslash is not one — it throws before bash is ever called.
$script = (Join-Path $PSScriptRoot "verify.sh").Replace('\', '/')
& $bash -lc "'$script' $($args -join ' ')"
if ($LASTEXITCODE -ne 0) { exit $LASTEXITCODE }
