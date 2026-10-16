# The checks scripts/sign-release.ps1 runs before it signs anything.
# Dot-sourced: this file only defines functions. They live apart so that
# release-checks.Tests.ps1 can run them on throwaway repositories, with
# no key and no network:
#
#   Invoke-Pester scripts

# Throws unless origin is the repository on github.com, over https or
# ssh. The URL is git's own, insteadOf rewrites applied, so a rule that
# sends github.com to a mirror is caught too.
#
# $TestOrigin is for tests only: release-checks.Tests.ps1, and the dry
# run of gerfaut-meta through GERFAUT_SIGN_TEST_ORIGIN. It names one
# file:// URL that origin may be instead of github.com, and nothing
# else: set by mistake on a clone of GitHub, it fails the run.
function Assert-OriginUrl {
    param(
        [Parameter(Mandatory)][AllowEmptyString()][string]$Url,
        [Parameter(Mandatory)][string]$Slug,
        [string]$TestOrigin
    )
    if ($TestOrigin) {
        if ($TestOrigin -notmatch '^file://') { throw "GERFAUT_SIGN_TEST_ORIGIN must be a file:// URL, not $TestOrigin" }
        if ($Url -cne $TestOrigin) { throw "origin is $Url, not the test origin $TestOrigin" }
        Write-Warning "test run: origin is $Url, not github.com"
        return
    }
    $github = "^(https://github\.com/|git@github\.com:|ssh://git@github\.com/)$([regex]::Escape($Slug))(\.git)?/?$"
    if ($Url -cnotmatch $github) { throw "origin is $Url, not github.com/$Slug" }
}

# The commit a release tag names, once this clone and GitHub agree on
# it: the tag names the same commit here and on GitHub, and main, as
# fetched from origin and as GitHub has it, holds that commit. GitHub's
# side comes from its API, never from origin alone. A tag moved after
# the push, or one that names a commit main never took in, stops the
# signature here. GitHub protects `v*` tags as well; this is the second
# barrier, the one on the machine that signs.
function Get-ReleaseCommit {
    param(
        [Parameter(Mandatory)][string]$RepoDir,
        [Parameter(Mandatory)][string]$Tag,
        [Parameter(Mandatory)][string]$Slug,
        [string]$TestOrigin
    )
    $url = git -C $RepoDir remote get-url origin 2>$null
    if ($LASTEXITCODE -ne 0) { throw "$RepoDir has no remote named origin" }
    Assert-OriginUrl -Url $url -Slug $Slug -TestOrigin $TestOrigin

    # Each answer must be one commit id and nothing else: -join turns a
    # second line into a mismatch rather than a list to filter.
    $local = (git -C $RepoDir rev-parse --verify --quiet "refs/tags/${Tag}^{commit}") -join "`n"
    if ($LASTEXITCODE -ne 0 -or $local -notmatch '^[0-9a-f]{40}$') {
        throw "no tag $Tag in this clone: fetch it (git fetch origin tag $Tag), check that it names the commit you meant to release, then run this again"
    }
    # The commits endpoint peels an annotated tag down to its commit.
    $published = (gh api --hostname github.com "repos/$Slug/commits/refs/tags/$Tag" --jq .sha) -join "`n"
    if ($LASTEXITCODE -ne 0 -or $published -notmatch '^[0-9a-f]{40}$') { throw "GitHub gave no commit for the tag $Tag of $Slug" }
    if ($published -ne $local) {
        throw "$Tag names $local in this clone but $published on GitHub: the tag moved"
    }

    git -C $RepoDir fetch --quiet --no-tags origin "+refs/heads/main:refs/remotes/origin/main"
    if ($LASTEXITCODE -ne 0) { throw "git fetch origin main failed" }
    $fetched = (git -C $RepoDir rev-parse --verify --quiet "refs/remotes/origin/main^{commit}") -join "`n"
    $main = (gh api --hostname github.com "repos/$Slug/commits/refs/heads/main" --jq .sha) -join "`n"
    if ($LASTEXITCODE -ne 0 -or $main -notmatch '^[0-9a-f]{40}$') { throw "GitHub gave no commit for the main branch of $Slug" }
    if ($fetched -ne $main) {
        throw "main is $fetched as fetched from origin but $main on GitHub: run this again if main just moved"
    }
    # Against the commit just checked, with no replace ref of this clone
    # rewriting history on the way.
    git -C $RepoDir --no-replace-objects merge-base --is-ancestor $local $main
    switch ($LASTEXITCODE) {
        0 { return $local }
        1 { throw "$Tag names $local, which is not on the main branch of $Slug" }
        default { throw "git merge-base failed on $local" }
    }
}

# The id of the successful run of the Release workflow that the push of
# the tag started, at the commit the tag names. Anyone who can write to
# the repository can change a draft, not the artifacts of a finished
# run, so these are what the draft is held against.
function Find-ReleaseRun {
    param(
        [Parameter(Mandatory)][string]$Slug,
        [Parameter(Mandatory)][string]$Tag,
        [Parameter(Mandatory)][string]$Commit
    )
    $runs = gh run list --repo $Slug --workflow release.yml --event push --branch $Tag --status success --json databaseId,headSha
    if ($LASTEXITCODE -ne 0) { throw "gh run list failed" }
    $run = @(($runs -join "`n") | ConvertFrom-Json | Where-Object { $_.headSha -eq $Commit })[0]
    if (-not $run) { throw "no successful Release run for the push of $Tag at $Commit" }
    return $run.databaseId
}

# Throws unless $Have holds the names in $Want, each once, and nothing
# else; the message lists what is missing, unexpected or doubled.
function Assert-ExactNames {
    param(
        [AllowEmptyCollection()][string[]]$Have,
        [Parameter(Mandatory)][string[]]$Want,
        [Parameter(Mandatory)][string]$What
    )
    $problems = @(
        $Want | Where-Object { $_ -cnotin $Have } | ForEach-Object { "missing: $_" }
        $Have | Where-Object { $_ -cnotin $Want } | ForEach-Object { "unexpected: $_" }
        $Have | Group-Object -CaseSensitive | Where-Object Count -gt 1 | ForEach-Object { "more than once: $($_.Name)" }
    )
    if ($problems) { throw "$What`n  $($problems -join "`n  ")" }
}

# The three APKs of a release, one per architecture, under the names
# reproducible/entrypoint.sh gives them.
function Get-UnsignedApkNames([string]$Tag) {
    foreach ($abi in "arm64-v8a", "armeabi-v7a", "x86_64") { "gerfaut-$Tag-android-$abi-unsigned.apk" }
}

# The name an APK takes in the release once it is signed.
function Get-SignedApkName([string]$Unsigned) { $Unsigned -replace '-unsigned\.apk$', '.apk' }

# What the Release run left in its artifact: the three unsigned APKs
# and the SHA256SUMS the build wrote, nothing else, each APK with the
# hash the list gives it.
function Assert-ReleaseArtifact {
    param(
        [Parameter(Mandatory)][string]$Dir,
        [Parameter(Mandatory)][string]$Tag
    )
    $apks = @(Get-UnsignedApkNames $Tag)
    $root = (Resolve-Path -LiteralPath $Dir).Path
    $files = @(Get-ChildItem -LiteralPath $root -Recurse -File | ForEach-Object { [System.IO.Path]::GetRelativePath($root, $_.FullName) })
    Assert-ExactNames -Have $files -Want ($apks + "SHA256SUMS") -What "the artifact of the Release run does not hold exactly the three APKs of $Tag and their SHA256SUMS"

    $names = @()
    $listed = @{}
    foreach ($line in Get-Content -LiteralPath (Join-Path $root "SHA256SUMS")) {
        if ($line -notmatch '^([0-9a-f]{64})  (\S+)$') { throw "unexpected line in the SHA256SUMS of the run: $line" }
        $names += $Matches[2]
        $listed[$Matches[2]] = $Matches[1]
    }
    Assert-ExactNames -Have $names -Want $apks -What "the SHA256SUMS of the run does not list the three APKs, once each"
    foreach ($name in $apks) {
        $have = (Get-FileHash -LiteralPath (Join-Path $root $name) -Algorithm SHA256).Hash.ToLower()
        if ($have -ne $listed[$name]) { throw "$name in the artifact does not match the SHA256SUMS of the run" }
    }
}

# What the draft may hold: for each architecture the unsigned APK the
# Release workflow attached, the signed one an earlier run of
# sign-release.ps1 swapped in, or both when that run stopped halfway;
# and the SHA256SUMS pair of such a run. Anything else, or an
# architecture with no APK at all, and the draft is not one to sign.
function Assert-DraftAssets {
    param(
        [AllowEmptyCollection()][string[]]$Names,
        [Parameter(Mandatory)][string]$Tag
    )
    $unsigned = @(Get-UnsignedApkNames $Tag)
    $allowed = $unsigned + @($unsigned | ForEach-Object { Get-SignedApkName $_ }) + "SHA256SUMS", "SHA256SUMS.minisig"
    $problems = @(
        $Names | Where-Object { $_ -cnotin $allowed } | ForEach-Object { "unexpected: $_" }
        $unsigned | Where-Object { $_ -cnotin $Names -and (Get-SignedApkName $_) -cnotin $Names } | ForEach-Object { "missing: $_" }
    )
    if ($problems) { throw "the $Tag draft is not the one the Release workflow made`n  $($problems -join "`n  ")" }
}

# Throws unless the two files are the same bytes.
function Assert-SameBytes {
    param(
        [Parameter(Mandatory)][string]$Path,
        [Parameter(Mandatory)][string]$Reference,
        [Parameter(Mandatory)][string]$What
    )
    $have = (Get-FileHash -LiteralPath $Path -Algorithm SHA256).Hash.ToLower()
    $want = (Get-FileHash -LiteralPath $Reference -Algorithm SHA256).Hash.ToLower()
    if ($have -ne $want) { throw "$What has SHA-256 $have, not $want" }
}
