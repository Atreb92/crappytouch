#!/usr/bin/env bash
# Publish release debs as a flat APT repo in repo/ (GitHub Pages: main branch, /docs).
# Usage: scripts/mkrepo.sh [deb...]   default: newest release (non-debug) deb in packages/
# Needs only ar, tar, xz, bzip2, sha256sum, md5sum (no dpkg on Fedora).
set -euo pipefail
cd "$(dirname "$0")/.."

repo=repo
mkdir -p "$repo/debs"

if [ $# -eq 0 ]; then
  newest=$(ls -t packages/com.atreb92.crappytouch_*_iphoneos-arm64.deb 2>/dev/null | grep -v '+debug' | head -1 || true)
  [ -n "$newest" ] || { echo "no release deb in packages/; run: make package FINALPACKAGE=1" >&2; exit 1; }
  set -- "$newest"
fi
cp "$@" "$repo/debs/"

: > "$repo/Packages"
for deb in "$repo"/debs/*.deb; do
  m=$(ar t "$deb" | grep ^control.tar); ctl=$(ar p "$deb" "$m" | tar -x$([ "${m##*.}" = xz ] && echo J || echo z)O ./control)
  printf '%s\nFilename: debs/%s\nSize: %s\nMD5sum: %s\nSHA256: %s\n\n' \
    "${ctl%$'\n'}" "$(basename "$deb")" "$(stat -c %s "$deb")" \
    "$(md5sum < "$deb" | cut -d' ' -f1)" "$(sha256sum < "$deb" | cut -d' ' -f1)" >> "$repo/Packages"
done
xz -kf9 "$repo/Packages"
bzip2 -kf "$repo/Packages"

cat > "$repo/Release" <<REL
Origin: crappytouch
Label: crappytouch
Suite: stable
Version: 1.0
Codename: ios
Architectures: iphoneos-arm64
Components: main
Description: crappytouch, the scrcrappy phone-side agent
REL
touch "$repo/.nojekyll"
echo "repo updated in $repo/ ($(grep -c '^Package:' "$repo/Packages") package(s))"
