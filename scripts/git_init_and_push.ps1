<#
Helper to initialize a git repo, create initial commit, and push to GitHub.
Usage (from repo root):
  pwsh .\scripts\git_init_and_push.ps1 -RemoteUrl 'https://github.com/crawfordalexgit/NationalsTracking.git' -CommitMessage 'Initial commit: CI + pages + serve helper' -Branch 'main'

This script will:
 - `git init` if needed
 - set user.name and user.email (if not set, it prompts)
 - add a remote named 'origin' (if absent) and set the URL if different
 - stage all files and commit with the provided message
 - push to the remote branch (creates branch if needed)

Note: You must have `git` installed and be authenticated (e.g., with GitHub CLI, credential manager, or SSH keys).
#>
param(
  [Parameter(Mandatory=$true)] [string] $RemoteUrl,
  [string] $CommitMessage = 'Initial commit: add CI/Pages/serve helper',
  [string] $Branch = 'main'
)

function Fail($msg){ Write-Error $msg; exit 1 }

if (-not (Get-Command git -ErrorAction SilentlyContinue)) { Fail 'git is not installed or not in PATH. Install git and retry.' }

# Init repo if necessary
if (-not (Test-Path .git)) {
  git init || Fail 'git init failed'
  Write-Host 'Initialized new git repository.' -ForegroundColor Green
}

# Ensure branch exists locally
try { git rev-parse --verify $Branch >/dev/null 2>&1; } catch { git checkout -b $Branch }

# Set user.name/email if missing
$uname = git config user.name; $uemail = git config user.email
if (-not $uname) {
  $uname = Read-Host 'Enter git user.name to use for commits (e.g., "Alex Crawford")'
  git config user.name "$uname"
}
if (-not $uemail) {
  $uemail = Read-Host 'Enter git user.email to use for commits (e.g., "alex@example.com")'
  git config user.email "$uemail"
}

# Add remote if needed
$existing = git remote get-url origin 2>$null
if ($existing) {
  if ($existing -ne $RemoteUrl) {
    Write-Host "Remote 'origin' exists (currently $existing). Updating to $RemoteUrl" -ForegroundColor Yellow
    git remote set-url origin $RemoteUrl || Fail 'Failed to set remote URL'
  } else { Write-Host "Remote 'origin' already configured." -ForegroundColor Green }
} else {
  git remote add origin $RemoteUrl || Fail 'Failed to add remote origin'
  Write-Host "Added remote 'origin' -> $RemoteUrl" -ForegroundColor Green
}

# Stage and commit
git add . || Fail 'git add failed'
$hasChanges = git status --porcelain
if (-not $hasChanges) { Write-Host 'No changes to commit.'; exit 0 }

git commit -m "$CommitMessage" || Fail 'git commit failed'

# Push (set upstream if first push)
try {
  git push -u origin $Branch
} catch {
  Write-Warning 'git push failed. Try running the following commands manually:'
  Write-Host "  git push -u origin $Branch"
  exit 1
}

Write-Host 'Push complete. Check your GitHub repo and Actions tab for workflow runs.' -ForegroundColor Green
