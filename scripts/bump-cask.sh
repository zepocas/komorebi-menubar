#!/usr/bin/env bash
# Points the Homebrew cask at a published release: downloads the release zip, computes its
# sha256, writes Casks/komorebi-menubar.rb into a local clone of zepocas/homebrew-tap and
# commits it. Pushing is left to you.
# Usage: scripts/bump-cask.sh 0.1     (release v0.1 must already have its zip attached)
set -euo pipefail
cd "$(dirname "$0")/.."

VERSION="${1:?usage: scripts/bump-cask.sh <version, e.g. 0.1>}"
VERSION="${VERSION#v}"
TAP_DIR="${TAP_DIR:-$HOME/code/homebrew-tap}"
URL="https://github.com/zepocas/komorebi-menubar/releases/download/v$VERSION/KomorebiMenubar-$VERSION.zip"

[[ -d "$TAP_DIR/.git" ]] || git clone git@github.com:zepocas/homebrew-tap.git "$TAP_DIR"

TMP="$(mktemp -d)"
trap 'rm -rf "$TMP"' EXIT
echo "Downloading $URL"
curl -fsSL -o "$TMP/app.zip" "$URL"
SHA256="$(shasum -a 256 "$TMP/app.zip" | cut -d' ' -f1)"

mkdir -p "$TAP_DIR/Casks"
sed -e "s|@VERSION@|$VERSION|g" -e "s|@SHA256@|$SHA256|g" packaging/komorebi-menubar.rb.in \
    > "$TAP_DIR/Casks/komorebi-menubar.rb"

git -C "$TAP_DIR" add Casks/komorebi-menubar.rb
git -C "$TAP_DIR" commit -m "komorebi-menubar $VERSION"
echo "Committed komorebi-menubar $VERSION (sha256 $SHA256). Push with: git -C $TAP_DIR push"
