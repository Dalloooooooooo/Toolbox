#!/bin/zsh
# Publishes a new Toolbox version on GitHub.
#
#   scripts/release.sh 1.1 "What's new in this version"
#   scripts/release.sh 1.1 "What's new" --important "Fixes a security issue"
#
# Regular versions only show up when users open Toolbox's settings (or install automatically, if they
# enabled it). With --important users also get a notification, once (the message is optional).
# Requires: GitHub CLI signed in (gh auth login) and the usual signing certificate — updates are only
# installed when they are signed with the same certificate as the copy already installed.
set -euo pipefail
ROOT="${0:A:h:h}"
cd "$ROOT"

VERSION="${1:-}"
NOTES="${2:-Toolbox $VERSION}"
PLIST=Toolbox/Resources/Info.plist
PB=/usr/libexec/PlistBuddy
SIGN_IDENTITY="${SIGN_IDENTITY:-SwitchTab Local Signing}"
GH="$(command -v gh || echo /opt/homebrew/bin/gh)"

fail() { echo "$1" >&2; exit 1; }

[[ -n "$VERSION" ]] || fail 'Usage: scripts/release.sh 1.1 "notes" [--important "message"]'
if [[ "${3:-}" == "--important" ]]; then
  # hidden marker in the notes: GitHub doesn't render it, Toolbox reads it (see Updater.parse)
  NOTES="$NOTES

<!-- toolbox:importante: ${4:-An update is recommended.} -->"
elif [[ -n "${3:-}" ]]; then
  fail "Unknown option: $3 (did you mean --important?)"
fi

"$GH" auth status >/dev/null 2>&1 || fail "Sign in to GitHub first: gh auth login"
security find-identity -p codesigning | grep -q "$SIGN_IDENTITY" ||
  fail "Missing signing certificate \"$SIGN_IDENTITY\": without it, updates would be rejected."
REPO=$($PB -c 'Print :ToolboxGitHubRepo' "$PLIST")
"$GH" release view "v$VERSION" --repo "$REPO" >/dev/null 2>&1 && fail "Version v$VERSION already exists"

BUILD_NUMBER=$(( $($PB -c 'Print :CFBundleVersion' "$PLIST") + 1 ))
$PB -c "Set :CFBundleShortVersionString $VERSION" -c "Set :CFBundleVersion $BUILD_NUMBER" "$PLIST"
scripts/build.sh   # also installs it on this Mac; set UNIVERSAL=1 to add Intel (needs an SDK that still supports it)

codesign --verify --deep --strict build/Toolbox.app
mkdir -p dist
ZIP="dist/Toolbox-$VERSION.zip"
rm -f "$ZIP"
ditto -c -k --keepParent build/Toolbox.app "$ZIP"   # ditto preserves signatures and attributes

# the version number is part of the published code: commit, push and tag the release on that commit
if git rev-parse --git-dir >/dev/null 2>&1; then
  git add "$PLIST"
  git diff --cached --quiet || git commit -q -m "Toolbox $VERSION"
  git -c credential.helper= -c credential.helper="!$GH auth git-credential" push -q origin HEAD
fi
"$GH" release create "v$VERSION" "$ZIP" --repo "$REPO" --title "Toolbox $VERSION" --notes "$NOTES" \
  --target "$(git rev-parse HEAD 2>/dev/null || echo main)"
echo "Published Toolbox $VERSION: https://github.com/$REPO/releases/tag/v$VERSION"
[[ "${3:-}" == "--important" ]] && echo "Marked as important: users will get a notification within 12 hours."
