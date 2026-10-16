# Sign a release on this machine. CI attaches unsigned APKs to the draft;
# this script signs the ones the Release run built with the app's release
# key, checks the certificate and the payload, swaps them into the draft
# under their final names, then hashes the signed files into a SHA256SUMS
# manifest and signs that with minisign. Neither key ever leaves this
# machine. CI only ever builds.
#
# Anyone who can write to the repository can change a draft, not the
# artifact of a finished run. So nothing is signed unless the tag names
# the same commit in this clone and on GitHub, a commit of main; a
# successful Release run started by the push of the tag, at that commit,
# left the three APKs in its artifact; and the draft holds those very
# files, byte for byte, and nothing else. What gets signed is the
# artifact's copy.
#
# The keystore path, its password, the key alias and the key password
# come from android/key.properties (untracked), the file the Gradle build
# reads. Passwords reach apksigner through the environment, never through
# the command line. Needs: gh, git, minisign, a JDK (JAVA_HOME or java on
# PATH), the Android SDK build-tools (ANDROID_HOME, ANDROID_SDK_ROOT or
# the default install location) and Python 3 for reproducible/compare.py.
#
# Usage:  pwsh scripts/sign-release.ps1 v0.1.0
#         (works on the draft release before you click Publish; safe to
#         run again if it stopped halfway; run it from a clone that has
#         the tag, see Get-ReleaseCommit)

param([Parameter(Mandatory)][string]$Tag)
$ErrorActionPreference = "Stop"
$slug = "gerfaut-wallet/gerfaut-mobile"
. (Join-Path $PSScriptRoot "release-checks.ps1")

# SHA-256 of the release signing certificate, as `apksigner verify
# --print-certs` prints it. Every APK that goes up is checked against it,
# so a keystore that is not the release one fails here and not on the
# phones that already run Gerfaut under this certificate.
$ExpectedCertSha256 = "de91a0e0c151290a0c9b34507e58d0bd0e99cdd7db41adc65b60a7c68e0ff0a7"

$repo = Split-Path $PSScriptRoot -Parent

# Runs a native command and fails on a non-zero exit code, which
# $ErrorActionPreference alone does not do.
function Invoke-Native([string]$Command, [string[]]$Arguments) {
    & $Command @Arguments
    if ($LASTEXITCODE -ne 0) {
        throw "$([System.IO.Path]::GetFileName($Command)) failed with exit code $LASTEXITCODE"
    }
}

function Find-Java {
    if ($env:JAVA_HOME) {
        $java = Join-Path $env:JAVA_HOME "bin/java.exe"
        if (Test-Path -LiteralPath $java) { return $java }
    }
    $onPath = Get-Command java -ErrorAction SilentlyContinue
    if ($onPath) { return $onPath.Source }
    throw "java not found - point JAVA_HOME at a JDK"
}

# The newest build-tools of the SDK. apksigner.bat is a wrapper around
# this jar that re-parses its arguments through cmd.exe on the way, so
# the jar is run directly.
function Find-ApkSigner {
    $roots = @($env:ANDROID_HOME, $env:ANDROID_SDK_ROOT, (Join-Path $env:LOCALAPPDATA "Android/Sdk")) |
        Where-Object { $_ -and (Test-Path -LiteralPath (Join-Path $_ "build-tools")) }
    foreach ($root in $roots) {
        $jar = Get-ChildItem (Join-Path $root "build-tools") -Directory |
            Sort-Object { [version]($_.Name -replace '[^0-9.].*$', '') } -Descending |
            ForEach-Object { Join-Path $_.FullName "lib/apksigner.jar" } |
            Where-Object { Test-Path -LiteralPath $_ } |
            Select-Object -First 1
        if ($jar) { return $jar }
    }
    throw "apksigner.jar not found - install the Android SDK build-tools"
}

# The subset of java.util.Properties the Gradle build relies on: one
# `key=value` per line, `#` comments, backslash escapes in the value.
function Read-JavaProperties([string]$Path) {
    $props = @{}
    foreach ($line in Get-Content -LiteralPath $Path) {
        $line = $line.Trim()
        if ($line -eq "" -or $line.StartsWith("#") -or $line.StartsWith("!")) { continue }
        $split = $line.IndexOfAny([char[]]"=:")
        if ($split -lt 0) { continue }
        $key = $line.Substring(0, $split).Trim()
        $raw = $line.Substring($split + 1).TrimStart()
        $props[$key] = [regex]::Replace($raw, '\\(u[0-9A-Fa-f]{4}|.)', {
            param($match)
            $escaped = $match.Groups[1].Value
            if ($escaped.StartsWith("u")) { return [string][char][Convert]::ToInt32($escaped.Substring(1), 16) }
            switch ($escaped) {
                "t" { "`t" }
                "n" { "`n" }
                "r" { "`r" }
                "f" { "`f" }
                default { $escaped }
            }
        })
    }
    return $props
}

function Assert-ReleaseCertificate([string]$Apk) {
    $name = [System.IO.Path]::GetFileName($Apk)
    $report = & $java -jar $apksigner verify --print-certs $Apk 2>&1 | Out-String
    if ($LASTEXITCODE -ne 0) { throw "apksigner verify failed on ${name}:`n$report" }
    $digests = @([regex]::Matches($report, 'Signer #\d+ certificate SHA-256 digest: ([0-9a-f]{64})') |
        ForEach-Object { $_.Groups[1].Value })
    if ($digests.Count -ne 1 -or $digests[0] -ne $ExpectedCertSha256) {
        throw "$name is not signed by the release certificate (found: $($digests -join ', '))"
    }
}

if ($Tag -notmatch '^v\d+\.\d+\.\d+$') { throw "not a release tag: $Tag" }
foreach ($tool in "gh", "git", "minisign") {
    if (-not (Get-Command $tool -ErrorAction SilentlyContinue)) {
        throw "$tool not found - install it first"
    }
}
$python = (Get-Command python, python3 -ErrorAction SilentlyContinue | Select-Object -First 1).Source
if (-not $python) { throw "python not found - reproducible/compare.py needs Python 3" }
$java = Find-Java
$apksigner = Find-ApkSigner
$compare = Join-Path $repo "reproducible/compare.py"
if (-not (Test-Path -LiteralPath $compare)) { throw "missing $compare" }

$propertiesFile = Join-Path $repo "android/key.properties"
if (-not (Test-Path -LiteralPath $propertiesFile)) {
    throw "android/key.properties not found - the release key is configured there, see android/app/build.gradle.kts"
}
$props = Read-JavaProperties $propertiesFile
foreach ($key in "storeFile", "storePassword", "keyAlias", "keyPassword") {
    if (-not $props[$key]) { throw "android/key.properties: $key is missing" }
}
# Gradle resolves a relative storeFile against android/app, the module
# that declares the signing config.
$storeFile = $props.storeFile
if (-not [System.IO.Path]::IsPathRooted($storeFile)) {
    $storeFile = Join-Path $repo "android/app" $storeFile
}
if (-not (Test-Path -LiteralPath $storeFile -PathType Leaf)) {
    throw "android/key.properties: storeFile does not point at a file"
}

Write-Output "checking what $Tag names..."
# GERFAUT_SIGN_TEST_ORIGIN is for tests only: see Assert-OriginUrl.
$commit = Get-ReleaseCommit -RepoDir $repo -Tag $Tag -Slug $slug -TestOrigin $env:GERFAUT_SIGN_TEST_ORIGIN
Write-Output "  $Tag is $commit here and on GitHub, a commit of main"

$dir = Join-Path ([System.IO.Path]::GetTempPath()) "gerfaut-mobile-sign-$Tag"
if (Test-Path $dir) { Remove-Item -Recurse -Force $dir }
$builtDir = Join-Path $dir "built"
$draftDir = Join-Path $dir "draft"
$signedDir = Join-Path $dir "signed"
$checkDir = Join-Path $dir "check"
foreach ($sub in $builtDir, $draftDir, $signedDir, $checkDir) { New-Item -ItemType Directory $sub | Out-Null }

$run = Find-ReleaseRun -Slug $slug -Tag $Tag -Commit $commit
Write-Output "downloading the APKs Release run $run built..."
Invoke-Native gh @("run", "download", $run, "--repo", $slug, "--name", "gerfaut-android-unsigned", "--dir", $builtDir)
Assert-ReleaseArtifact -Dir $builtDir -Tag $Tag
$unsigned = @(Get-UnsignedApkNames $Tag)

Write-Output "checking the $Tag draft against them..."
$release = gh release view $Tag --repo $slug --json "isDraft,assets" | ConvertFrom-Json
if ($LASTEXITCODE -ne 0 -or -not $release) { throw "gh release view $Tag failed" }
if (-not $release.isDraft) { throw "$Tag is published already; this script only touches drafts" }
$attached = @($release.assets | ForEach-Object { $_.name })
Assert-DraftAssets -Names $attached -Tag $Tag
$apksAttached = @($attached | Where-Object { $_ -like "*.apk" })
Invoke-Native gh (@("release", "download", $Tag, "--repo", $slug, "--dir", $draftDir) +
    @($apksAttached | ForEach-Object { "--pattern", $_ }))
foreach ($name in $unsigned) {
    $built = Join-Path $builtDir $name
    if ($name -cin $attached) {
        Assert-SameBytes -Path (Join-Path $draftDir $name) -Reference $built -What "$name in the draft"
        Write-Output "  ok  $name is the file run $run built"
    }
    # Swapped in by an earlier run of this script that stopped halfway:
    # it must be the same build, signed with the same key. It is replaced
    # below all the same.
    $earlier = Get-SignedApkName $name
    if ($earlier -cin $attached) {
        $path = Join-Path $draftDir $earlier
        Assert-ReleaseCertificate $path
        Invoke-Native $python @($compare, "--signed", $path, $built)
        Write-Output "  ok  $earlier, from an earlier run, is the file run $run built, signed"
    }
}

$env:GERFAUT_KS_PASS = $props.storePassword
$env:GERFAUT_KEY_PASS = $props.keyPassword
try {
    foreach ($name in $unsigned) {
        $final = Get-SignedApkName $name
        $in = Join-Path $builtDir $name
        $out = Join-Path $signedDir $final
        Write-Output "signing $final..."
        # With v1 off, apksigner adds no zip entry at all: it only inserts
        # an APK signing block, so every entry stays exactly where the
        # container put it. v1 is only needed below API 24, and minSdk
        # here is 24.
        # v4 is a separate .idsig file for adb incremental installs, and
        # nothing here ships one.
        Invoke-Native $java @(
            "-jar", $apksigner, "sign",
            "--ks", $storeFile,
            "--ks-pass", "env:GERFAUT_KS_PASS",
            "--ks-key-alias", $props.keyAlias,
            "--key-pass", "env:GERFAUT_KEY_PASS",
            "--v1-signing-enabled", "false",
            "--v2-signing-enabled", "true",
            "--v3-signing-enabled", "true",
            "--v4-signing-enabled", "false",
            "--out", $out, $in)
        Assert-ReleaseCertificate $out
        # This asserts that signing left the payload alone, entry for
        # entry: what goes up is what CI built, plus a signature.
        Invoke-Native $python @($compare, "--signed", $out, $in)
    }
}
finally {
    Remove-Item Env:GERFAUT_KS_PASS, Env:GERFAUT_KEY_PASS -ErrorAction SilentlyContinue
}

Write-Output "swapping the signed APKs into the draft..."
$signed = @($unsigned | ForEach-Object { Get-SignedApkName $_ })
Invoke-Native gh (@("release", "upload", $Tag, "--repo", $slug, "--clobber") +
    @($signed | ForEach-Object { Join-Path $signedDir $_ }))
foreach ($name in $unsigned | Where-Object { $_ -cin $attached }) {
    Invoke-Native gh @("release", "delete-asset", $Tag, $name, "--repo", $slug, "--yes")
}
# The manifest about to be signed lists these files: the draft must hold
# them, as they left this machine, and nothing else but an earlier
# SHA256SUMS pair, which is replaced below.
$release = gh release view $Tag --repo $slug --json "assets" | ConvertFrom-Json
if ($LASTEXITCODE -ne 0 -or -not $release) { throw "gh release view $Tag failed" }
$after = @($release.assets | ForEach-Object { $_.name } | Where-Object { $_ -cnotin "SHA256SUMS", "SHA256SUMS.minisig" })
Assert-ExactNames -Have $after -Want $signed -What "after the swap, the draft does not hold exactly the three signed APKs"
Invoke-Native gh (@("release", "download", $Tag, "--repo", $slug, "--dir", $checkDir) +
    @($signed | ForEach-Object { "--pattern", $_ }))
foreach ($name in $signed) {
    Assert-SameBytes -Path (Join-Path $checkDir $name) -Reference (Join-Path $signedDir $name) -What "$name in the draft"
}

# sha256sum -c compatible manifest: "<hash>  <name>", sorted, lowercase.
$files = Get-ChildItem $signedDir -File -Filter *.apk | Sort-Object Name
$manifest = ($files | ForEach-Object {
    "{0}  {1}" -f (Get-FileHash $_.FullName -Algorithm SHA256).Hash.ToLower(), $_.Name
}) -join "`n"
$sums = Join-Path $dir "SHA256SUMS"
[System.IO.File]::WriteAllText($sums, $manifest + "`n")
Write-Output $manifest

Write-Output "signing (minisign will ask for your key password)..."
Invoke-Native minisign @("-Sm", $sums, "-t", "Gerfaut Android $Tag")

Invoke-Native gh @("release", "upload", $Tag, "--repo", $slug, $sums, "$sums.minisig", "--clobber")
Remove-Item -Recurse -Force $dir
Write-Output "done: $($files.Count) signed APKs, SHA256SUMS + SHA256SUMS.minisig attached to $Tag."
Write-Output "review the draft on GitHub, then click Publish."
