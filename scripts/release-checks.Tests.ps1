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
