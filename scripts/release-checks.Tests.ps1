# Pester tests for release-checks.ps1, on throwaway git repositories
# under TestDrive: no key, no network, no GitHub. Needs Pester 5 or
# later (Install-Module Pester -Scope CurrentUser; Windows ships 3.4):
#
#   Invoke-Pester scripts

BeforeAll {
    . (Join-Path $PSScriptRoot "release-checks.ps1")

    function Invoke-Git {
        git @args
        if ($LASTEXITCODE -ne 0) { throw "git $args failed" }
    }

    # A bare repository standing in for GitHub, a clone the release is
    # tagged from, and the clone that signs, which has fetched nothing
    # yet but main.
    function New-Repositories([string]$Slug) {
        $base = Join-Path $TestDrive ([guid]::NewGuid())
        $bare = Join-Path $base "$Slug.git"
        Invoke-Git init --quiet --bare --initial-branch=main $bare
        $url = "file:///" + ($bare -replace '\\', '/').TrimStart('/')
        $author = Join-Path $base "author"
        Invoke-Git clone --quiet $url $author 2>$null
        Invoke-Git -C $author commit --quiet --allow-empty -m one
        Invoke-Git -C $author push --quiet origin main 2>$null
        $signer = Join-Path $base "signer"
        Invoke-Git clone --quiet --no-tags $url $signer 2>$null
        return @{ Author = $author; Signer = $signer }
    }

    function Get-Head([string]$Dir) { git -C $Dir rev-parse HEAD }
}

Describe "Get-ReleaseCommit" {
    BeforeAll {
        # The user's own settings (hooks, signed commits) stay out.
        $savedGlobal = $env:GIT_CONFIG_GLOBAL
        $savedNoSystem = $env:GIT_CONFIG_NOSYSTEM
        $env:GIT_CONFIG_GLOBAL = Join-Path $TestDrive "gitconfig"
        $env:GIT_CONFIG_NOSYSTEM = "1"
        Set-Content -LiteralPath $env:GIT_CONFIG_GLOBAL -Value "[user]`n`tname = Test`n`temail = test@example.invalid"
        $slug = "gerfaut-wallet/gerfaut-mobile"
    }
    AfterAll {
        $env:GIT_CONFIG_GLOBAL = $savedGlobal
        $env:GIT_CONFIG_NOSYSTEM = $savedNoSystem
    }
    BeforeEach {
        $repos = New-Repositories $slug
        $author = $repos.Author
        $signer = $repos.Signer
    }

    It "returns the commit a tag on main names" {
        Invoke-Git -C $author tag v0.1.0
        Invoke-Git -C $author push --quiet origin v0.1.0 2>$null
        Invoke-Git -C $signer fetch --quiet origin tag v0.1.0
        Get-ReleaseCommit -RepoDir $signer -Tag v0.1.0 -Slug $slug | Should -Be (Get-Head $author)
    }

    It "returns the commit, not the tag object, for an annotated tag" {
        Invoke-Git -C $author tag -a -m "Gerfaut 0.1.0" v0.1.0
        Invoke-Git -C $author push --quiet origin v0.1.0 2>$null
        Invoke-Git -C $signer fetch --quiet origin tag v0.1.0
        Get-ReleaseCommit -RepoDir $signer -Tag v0.1.0 -Slug $slug | Should -Be (Get-Head $author)
    }

    It "fetches main to find a commit this clone has not seen on it" {
        Invoke-Git -C $author commit --quiet --allow-empty -m two
        Invoke-Git -C $author tag v0.1.0
        $tagged = Get-Head $author
        Invoke-Git -C $author commit --quiet --allow-empty -m three
        Invoke-Git -C $author push --quiet origin main v0.1.0 2>$null
        Invoke-Git -C $signer fetch --quiet origin tag v0.1.0
        git -C $signer merge-base --is-ancestor $tagged origin/main
        $LASTEXITCODE | Should -Be 1
        Get-ReleaseCommit -RepoDir $signer -Tag v0.1.0 -Slug $slug | Should -Be $tagged
    }

    It "refuses a tag that moved on GitHub after this clone fetched it" {
        Invoke-Git -C $author tag v0.1.0
        Invoke-Git -C $author push --quiet origin v0.1.0 2>$null
        Invoke-Git -C $signer fetch --quiet origin tag v0.1.0
        Invoke-Git -C $author commit --quiet --allow-empty -m two
        Invoke-Git -C $author tag --force v0.1.0 2>$null
        Invoke-Git -C $author push --quiet --force origin main v0.1.0 2>$null
        { Get-ReleaseCommit -RepoDir $signer -Tag v0.1.0 -Slug $slug } | Should -Throw "*the tag moved*"
    }

    It "refuses a tag that names a commit outside main" {
        Invoke-Git -C $author switch --quiet --create side
        Invoke-Git -C $author commit --quiet --allow-empty -m side
        Invoke-Git -C $author tag v0.1.0
        Invoke-Git -C $author push --quiet origin v0.1.0 2>$null
        Invoke-Git -C $signer fetch --quiet origin tag v0.1.0
        { Get-ReleaseCommit -RepoDir $signer -Tag v0.1.0 -Slug $slug } | Should -Throw "*not on the main branch*"
    }

    It "refuses a tag this clone does not have" {
        Invoke-Git -C $author tag v0.1.0
        Invoke-Git -C $author push --quiet origin v0.1.0 2>$null
        { Get-ReleaseCommit -RepoDir $signer -Tag v0.1.0 -Slug $slug } | Should -Throw "*no tag v0.1.0 in this clone*"
    }

    It "refuses a tag GitHub does not have" {
        Invoke-Git -C $signer tag v0.1.0
        { Get-ReleaseCommit -RepoDir $signer -Tag v0.1.0 -Slug $slug } | Should -Throw "*has no tag v0.1.0*"
    }

    It "refuses a clone of another repository" {
        Invoke-Git -C $author tag v0.1.0
        Invoke-Git -C $author push --quiet origin v0.1.0 2>$null
        Invoke-Git -C $signer fetch --quiet origin tag v0.1.0
        { Get-ReleaseCommit -RepoDir $signer -Tag v0.1.0 -Slug "gerfaut-wallet/gerfaut-desktop" } | Should -Throw "*not gerfaut-wallet/gerfaut-desktop*"
    }
}

Describe "Find-ReleaseRun" {
    BeforeAll {
        $commit = "1" * 40
        $other = "2" * 40
    }

    It "returns the run at the commit the tag names" {
        Mock gh {
            $global:LASTEXITCODE = 0
            "[{`"databaseId`":11,`"headSha`":`"$other`"},{`"databaseId`":12,`"headSha`":`"$commit`"}]"
        }
        Find-ReleaseRun -Slug gerfaut-wallet/gerfaut-mobile -Tag v0.1.0 -Commit $commit | Should -Be 12
        # A list such as databaseId,headSha reaches the mock as an array
        # and gh as one argument.
        Should -Invoke gh -Times 1 -Exactly -ParameterFilter {
            ($args | ForEach-Object { $_ -join "," }) -join " " -eq
                "run list --repo gerfaut-wallet/gerfaut-mobile --workflow release.yml --event push --branch v0.1.0 --status success --json databaseId,headSha"
        }
    }

    It "refuses when no successful run of the push is at that commit" {
        Mock gh {
            $global:LASTEXITCODE = 0
            "[{`"databaseId`":11,`"headSha`":`"$other`"}]"
        }
        { Find-ReleaseRun -Slug gerfaut-wallet/gerfaut-mobile -Tag v0.1.0 -Commit $commit } | Should -Throw "*no successful Release run*"
    }

    It "refuses when there is no run at all" {
        Mock gh { $global:LASTEXITCODE = 0; "[]" }
        { Find-ReleaseRun -Slug gerfaut-wallet/gerfaut-mobile -Tag v0.1.0 -Commit $commit } | Should -Throw "*no successful Release run*"
    }
}

Describe "Assert-ExactNames" {
    BeforeAll {
        $want = "a.deb", "b.exe", "c.zip"
    }

    It "accepts the same names in another order" {
        { Assert-ExactNames -Have "c.zip", "a.deb", "b.exe" -Want $want -What "draft" } | Should -Not -Throw
    }

    It "refuses a file too many" {
        { Assert-ExactNames -Have "a.deb", "b.exe", "c.zip", "d.msi" -Want $want -What "draft" } | Should -Throw "*unexpected: d.msi*"
    }

    It "refuses a missing file" {
        { Assert-ExactNames -Have "a.deb", "c.zip" -Want $want -What "draft" } | Should -Throw "*missing: b.exe*"
    }

    It "refuses a name given twice" {
        { Assert-ExactNames -Have "a.deb", "b.exe", "c.zip", "c.zip" -Want $want -What "list" } | Should -Throw "*more than once: c.zip*"
    }

    It "refuses a name that differs only in case" {
        { Assert-ExactNames -Have "A.deb", "b.exe", "c.zip" -Want $want -What "draft" } | Should -Throw "*unexpected: A.deb*"
    }

    It "refuses an empty draft" {
        { Assert-ExactNames -Have @() -Want $want -What "draft" } | Should -Throw "*missing: a.deb*"
    }
}

Describe "Assert-ReleaseArtifact" {
    BeforeEach {
        $dir = Join-Path $TestDrive ([guid]::NewGuid())
        New-Item -ItemType Directory $dir | Out-Null
        $lines = foreach ($name in Get-UnsignedApkNames v0.1.0) {
            Set-Content -LiteralPath (Join-Path $dir $name) -Value "apk $name" -NoNewline
            "{0}  {1}" -f (Get-FileHash -LiteralPath (Join-Path $dir $name) -Algorithm SHA256).Hash.ToLower(), $name
        }
        Set-Content -LiteralPath (Join-Path $dir "SHA256SUMS") -Value $lines
    }

    It "accepts the three APKs and the SHA256SUMS the build wrote" {
        { Assert-ReleaseArtifact -Dir $dir -Tag v0.1.0 } | Should -Not -Throw
    }

    It "refuses a file too many" {
        Set-Content -LiteralPath (Join-Path $dir "gerfaut-v0.1.0-android-riscv64-unsigned.apk") -Value "x"
        { Assert-ReleaseArtifact -Dir $dir -Tag v0.1.0 } | Should -Throw "*unexpected: gerfaut-v0.1.0-android-riscv64-unsigned.apk*"
    }

    It "refuses the APKs of another tag" {
        { Assert-ReleaseArtifact -Dir $dir -Tag v0.1.1 } | Should -Throw "*missing: gerfaut-v0.1.1-android-arm64-v8a-unsigned.apk*"
    }

    It "refuses an APK that does not match the SHA256SUMS of the run" {
        Add-Content -LiteralPath (Join-Path $dir "gerfaut-v0.1.0-android-x86_64-unsigned.apk") -Value "changed"
        { Assert-ReleaseArtifact -Dir $dir -Tag v0.1.0 } | Should -Throw "*x86_64-unsigned.apk in the artifact does not match*"
    }
}

Describe "Assert-DraftAssets" {
    BeforeAll {
        $unsigned = @(Get-UnsignedApkNames v0.1.0)
        $signed = @($unsigned | ForEach-Object { Get-SignedApkName $_ })
    }

    It "names the three APKs as the build does" {
        $unsigned | Should -Be @(
            "gerfaut-v0.1.0-android-arm64-v8a-unsigned.apk",
            "gerfaut-v0.1.0-android-armeabi-v7a-unsigned.apk",
            "gerfaut-v0.1.0-android-x86_64-unsigned.apk")
        $signed[0] | Should -Be "gerfaut-v0.1.0-android-arm64-v8a.apk"
    }

    It "accepts the draft the Release workflow made" {
        { Assert-DraftAssets -Names $unsigned -Tag v0.1.0 } | Should -Not -Throw
    }

    It "accepts a draft an earlier run left halfway" {
        $names = $unsigned[0], $signed[0], $signed[1], $signed[2], "SHA256SUMS", "SHA256SUMS.minisig"
        { Assert-DraftAssets -Names $names -Tag v0.1.0 } | Should -Not -Throw
    }

    It "refuses a file too many" {
        { Assert-DraftAssets -Names ($unsigned + "gerfaut-v0.1.0-android-universal.apk") -Tag v0.1.0 } | Should -Throw "*unexpected: gerfaut-v0.1.0-android-universal.apk*"
    }

    It "refuses an APK of another tag" {
        { Assert-DraftAssets -Names ($unsigned + "gerfaut-v0.0.9-android-arm64-v8a-unsigned.apk") -Tag v0.1.0 } | Should -Throw "*unexpected: gerfaut-v0.0.9*"
    }

    It "refuses a draft with an architecture missing" {
        { Assert-DraftAssets -Names $unsigned[0], $unsigned[2] -Tag v0.1.0 } | Should -Throw "*missing: gerfaut-v0.1.0-android-armeabi-v7a-unsigned.apk*"
    }
}

Describe "Assert-SameBytes" {
    BeforeAll {
        $built = Join-Path $TestDrive "built.apk"
        [System.IO.File]::WriteAllBytes($built, [byte[]](1..255))
    }

    It "accepts the same bytes" {
        $copy = Join-Path $TestDrive "copy.apk"
        Copy-Item -LiteralPath $built $copy
        { Assert-SameBytes -Path $copy -Reference $built -What "the APK in the draft" } | Should -Not -Throw
    }

    It "refuses an APK that differs from the artifact by one byte" {
        $bytes = [byte[]](1..255)
        $bytes[100] = 0
        $changed = Join-Path $TestDrive "changed.apk"
        [System.IO.File]::WriteAllBytes($changed, $bytes)
        { Assert-SameBytes -Path $changed -Reference $built -What "the APK in the draft" } | Should -Throw "the APK in the draft has SHA-256 *"
    }
}
