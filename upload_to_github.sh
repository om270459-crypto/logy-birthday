#!/usr/bin/env bash
# upload_to_github.sh
# Usage:
#   ./upload_to_github.sh /path/to/project https://github.com/USERNAME/REPO.git
# Optional env vars before running:
#   GIT_USER_NAME="Your Name"
#   GIT_USER_EMAIL="you@example.com"

set -euo pipefail

if [ "$#" -lt 2 ]; then
  echo "Usage: $0 /path/to/project https://github.com/USERNAME/REPO.git"
  exit 1
fi

PROJECT_PATH="$1"
REPO_URL="$2"

# Optional global config (comment out if not wanted)
if [ -n "${GIT_USER_NAME:-}" ]; then
  git config --global user.name "$GIT_USER_NAME"
fi
if [ -n "${GIT_USER_EMAIL:-}" ]; then
  git config --global user.email "$GIT_USER_EMAIL"
fi

# Enter project directory
if [ ! -d "$PROJECT_PATH" ]; then
  echo "Error: path not found: $PROJECT_PATH"
  exit 1
fi
cd "$PROJECT_PATH"

# Init repo if needed
if [ ! -d .git ]; then
  echo "Initializing new git repository..."
  git init
else
  echo "Using existing git repository."
fi

# Ensure branch main exists and is checked out
if git show-ref --verify --quiet refs/heads/main; then
  git checkout main
else
  git checkout -b main
fi

# Add remote origin if not present; otherwise set-url (keeps remote name 'origin')
if git remote get-url origin >/dev/null 2>&1; then
  echo "Remote 'origin' exists. Setting URL to provided repo URL..."
  git remote set-url origin "$REPO_URL"
else
  echo "Adding remote 'origin'..."
  git remote add origin "$REPO_URL"
fi

# Add all and commit (if there are changes)
git add .
# Check if there is anything to commit
if git diff --cached --quiet && git ls-files --others --exclude-standard --no-empty-directory | grep -q .; then
  # There are untracked files but no staged changes (this case won't happen because we added .)
  :
fi

# If nothing to commit, still create an initial empty commit message won't run; handle gracefully
if git diff --cached --quiet && git diff --quiet HEAD; then
  # No staged changes and no changes in working tree: skip commit
  echo "No changes to commit."
else
  git commit -m "first commit" || echo "No changes to commit (commit skipped)."
fi

# Ask for GitHub username (login) and PAT (hidden)
read -p "GitHub username (login, e.g. om270459-crypto): " GH_USER
# Read token silently
read -s -p "Personal Access Token (PAT) (input hidden): " GH_TOKEN
echo
if [ -z "$GH_TOKEN" ]; then
  echo "Error: token is empty. Aborting."
  exit 1
fi

# Prepare push URL that includes token (we will NOT keep token in remote)
# Normalize REPO_URL (remove any protocol+user part first)
# Examples to handle:
#  - https://github.com/USER/REPO.git
#  - https://someuser@github.com/USER/REPO.git
#  - git@github.com:USER/REPO.git  -> convert to https
ORIG="$REPO_URL"

# If URL is SSH style, convert to HTTPS
if [[ "$ORIG" =~ ^git@([^:]+):(.+)$ ]]; then
  HOST="${BASH_REMATCH[1]}"
  PATH_PART="${BASH_REMATCH[2]}"
  CLEAN_URL="https://$HOST/$PATH_PART"
else
  # Remove any user@ part in https://user@github.com/...
  CLEAN_URL="${ORIG#*://}"
  # if CLEAN_URL contained a user@, remove it
  if [[ "$CLEAN_URL" == *"@"* ]]; then
    CLEAN_URL="${CLEAN_URL#*@}"
  fi
  CLEAN_URL="https://${CLEAN_URL}"
fi

# Ensure .git suffix exists
if [[ "$CLEAN_URL" != *.git ]]; then
  CLEAN_URL="${CLEAN_URL%.git}.git"
fi

# Build push URL with credentials (note: token used only here)
PUSH_URL="https://${GH_USER}:${GH_TOKEN}@${CLEAN_URL#https://}"

echo "Pushing to remote (using provided token)..."

# Push using temporary URL (doesn't change stored origin)
# We'll call git push with that URL explicitly
git push "$PUSH_URL" main:main -u

# After successful push, restore origin to the clean URL without token
git remote set-url origin "$CLEAN_URL"

echo "Push complete. Remote 'origin' now set to: $CLEAN_URL"
echo "IMPORTANT: If this token was temporary, revoke it in GitHub settings when done."
