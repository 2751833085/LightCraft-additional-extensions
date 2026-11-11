#!/usr/bin/env bash
# Build LightCraft with the additional extensions applied (macOS, Linux).
#
#   scripts/build.sh              build the app: <work>/lightcraft/target/release/lightcraft
#   scripts/build.sh --package    also package it with upstream's scripts:
#                                 macOS  -> a .dmg holding LightCraft.app (ad-hoc signed)
#                                 Linux  -> a .tar.gz (FHS tree; --formats lets you pick others)
#   scripts/build.sh --work DIR   where the sources and fonts go (default: ./build)
#
# What it does: fetches the upstream release named in upstream.lock, checks it is the pinned
# commit, applies patches/*.patch on a fresh branch, fetches the pinned craft-fonts (without them
# Chinese text renders as empty boxes) and builds. Re-running starts from the release again, so
# changes made by hand inside <work>/lightcraft are discarded.
#
# Needs: git, a Rust toolchain (rustup; the workspace needs Rust 1.95 or newer) and, on macOS,
# the Xcode command line tools.
set -euo pipefail

HERE="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
# shellcheck source=../upstream.lock
. "$HERE/upstream.lock"

WORK="$HERE/build"
PACKAGE=0
FORMATS="tar"
while [[ $# -gt 0 ]]; do
  case "$1" in
    --package) PACKAGE=1; shift ;;
    --work) WORK="$2"; shift 2 ;;
    --formats) FORMATS="$2"; shift 2 ;;
    -h | --help) sed -n '2,17p' "$0"; exit 0 ;;
    *) echo "unknown argument: $1" >&2; exit 2 ;;
  esac
done

for tool in git cargo; do
  command -v "$tool" >/dev/null || { echo "error: $tool is not installed" >&2; exit 1; }
done

mkdir -p "$WORK"
WORK="$(cd "$WORK" && pwd)"
SRC="$WORK/lightcraft"

echo "==> LightCraft $UPSTREAM_TAG"
if [[ ! -d "$SRC/.git" ]]; then
  git init -q "$SRC"
  git -C "$SRC" remote add origin "$UPSTREAM_REPO"
fi
git -C "$SRC" fetch -q --depth 1 origin "refs/tags/$UPSTREAM_TAG:refs/tags/$UPSTREAM_TAG"
actual="$(git -C "$SRC" rev-list -n 1 "$UPSTREAM_TAG")"
if [[ "$actual" != "$UPSTREAM_COMMIT" ]]; then
  echo "error: $UPSTREAM_TAG is $actual upstream, not the pinned $UPSTREAM_COMMIT" >&2
  exit 1
fi

echo "==> applying $(ls "$HERE"/patches/*.patch | wc -l | tr -d ' ') patches"
git -C "$SRC" am --abort >/dev/null 2>&1 || true
git -C "$SRC" checkout -q --force -B lcx "$UPSTREAM_TAG"
git -C "$SRC" clean -qfd
git -C "$SRC" -c user.name="LightCraft additional extensions" -c user.email="noreply@example.invalid" \
  am -q --3way "$HERE"/patches/*.patch

FONTS="$WORK/craft-fonts"
if [[ ! -f "$FONTS/fonts/manifest.txt" ]]; then
  echo "==> craft-fonts $CRAFT_FONTS_REV"
  rm -rf "$FONTS"
  git clone -q --no-checkout "$CRAFT_FONTS_REPO" "$FONTS"
  git -C "$FONTS" checkout -q --detach "$CRAFT_FONTS_REV"
fi
export CRAFT_FONTS_DIR="$FONTS"
# fail the build rather than ship a UI whose Chinese is empty boxes
export CRAFT_FONTS_REQUIRED=1

cd "$SRC"
if (( PACKAGE )); then
  case "$(uname -s)" in
    Darwin)
      arch="$(uname -m)"
      [[ "$arch" == arm64 ]] && arch=aarch64
      packaging/macos/package.sh --arch "$arch"
      echo "==> done: the .dmg is in $SRC/dist/release (open it and drag LightCraft to Applications)"
      ;;
    Linux)
      packaging/linux/package.sh --formats "$FORMATS"
      echo "==> done: packages are in $SRC/dist/release"
      ;;
    *)
      echo "error: --package supports macOS and Linux here; on Windows use scripts/build.ps1" >&2
      exit 2
      ;;
  esac
else
  cargo build --release -p lightcraft
  echo "==> done: $SRC/target/release/lightcraft"
fi
