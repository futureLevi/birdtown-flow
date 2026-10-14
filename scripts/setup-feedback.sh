#!/usr/bin/env bash
# One-time setup for the feedback shortcut (⌃⌥F): makes the private repository feedback notes
# are filed in, gives it the "feedback" label, and copies a GitHub token to the clipboard to
# paste into Birdtown Flow › Settings › About › Send feedback.
#
#   scripts/setup-feedback.sh [owner/name]      default: futureLevi/birdtown-flow-feedback
#
# The repository is private because a note carries the text of your recent dictations. The
# token is the GitHub CLI's own login for the repository's owner, which needn't be the active
# gh account; logging that account out of gh revokes it, and Settings will then say GitHub
# didn't accept the token. Run this again for a new one.
set -euo pipefail

repo="${1:-futureLevi/birdtown-flow-feedback}"
owner="${repo%%/*}"

if ! command -v gh >/dev/null; then
  echo "This needs the GitHub CLI: brew install gh" >&2
  exit 1
fi
if ! token=$(gh auth token --hostname github.com --user "$owner" 2>/dev/null) || [ -z "$token" ]; then
  echo "gh isn't logged in as $owner. Run: gh auth login (and choose $owner), then this again." >&2
  exit 1
fi

if GH_TOKEN="$token" gh repo view "$repo" >/dev/null 2>&1; then
  echo "Using $repo."
else
  GH_TOKEN="$token" gh repo create "$repo" --private \
    --description "Notes said with Birdtown Flow's feedback shortcut"
  echo "Created $repo (private)."
fi

GH_TOKEN="$token" gh label create feedback --repo "$repo" --force --color 5319E7 \
  --description "Said with Birdtown Flow's feedback shortcut" >/dev/null
echo "Label \"feedback\" is ready."

printf '%s' "$token" | pbcopy
cat <<MSG

A GitHub token for $owner is on your clipboard. In Birdtown Flow open Settings › About,
paste it under Send feedback › GitHub token, and press Save. Notes already said go then.
MSG
