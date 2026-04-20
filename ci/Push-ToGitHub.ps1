param(
    [string]$RepoName = "webtoon-lens-ios",
    [ValidateSet("private", "public")]
    [string]$Visibility = "private"
)

$ErrorActionPreference = "Stop"

function Invoke-AllowFailure {
    param(
        [Parameter(Mandatory = $true)]
        [scriptblock]$Command
    )

    $previousErrorActionPreference = $ErrorActionPreference
    $hadNativePreference = Test-Path variable:PSNativeCommandUseErrorActionPreference
    if ($hadNativePreference) {
        $previousNativePreference = $PSNativeCommandUseErrorActionPreference
        $PSNativeCommandUseErrorActionPreference = $false
    }

    try {
        $ErrorActionPreference = "Continue"
        & $Command
        return $LASTEXITCODE
    }
    finally {
        $ErrorActionPreference = $previousErrorActionPreference
        if ($hadNativePreference) {
            $PSNativeCommandUseErrorActionPreference = $previousNativePreference
        }
    }
}

if (-not (Get-Command git -ErrorAction SilentlyContinue)) {
    throw "Git is missing. Install it with: winget install Git.Git"
}

if (-not (Get-Command gh -ErrorAction SilentlyContinue)) {
    throw "GitHub CLI is missing. Install it with: winget install GitHub.cli"
}

Push-Location (Resolve-Path "$PSScriptRoot\..")
try {
    if (-not (Test-Path ".git")) {
        git init
    }

    if ([string]::IsNullOrWhiteSpace((git config user.name))) {
        $githubUser = gh api user --jq .login
        git config user.name $githubUser
    }

    if ([string]::IsNullOrWhiteSpace((git config user.email))) {
        $githubUser = git config user.name
        git config user.email "$githubUser@users.noreply.github.com"
    }

    git add .

    $hasCommit = (Invoke-AllowFailure { git rev-parse --verify HEAD *> $null }) -eq 0

    $hasStagedChanges = (Invoke-AllowFailure { git diff --cached --quiet }) -ne 0
    if ($hasStagedChanges) {
        git commit -m "Add Webtoon Lens iOS"
    } elseif (-not $hasCommit) {
        git commit --allow-empty -m "Initial commit"
    }

    if ((Invoke-AllowFailure { gh auth status *> $null }) -ne 0) {
        gh auth login
    }

    $visibilityFlag = if ($Visibility -eq "public") { "--public" } else { "--private" }
    $createExit = Invoke-AllowFailure { gh repo create $RepoName $visibilityFlag --source . --remote origin --push }
    if ($createExit -ne 0) {
        $owner = gh api user --jq .login
        $repoUrl = "https://github.com/$owner/$RepoName.git"
        if ((git remote) -contains "origin") {
            git remote set-url origin $repoUrl
        } else {
            git remote add origin $repoUrl
        }
        git push -u origin HEAD
    }
}
finally {
    Pop-Location
}
