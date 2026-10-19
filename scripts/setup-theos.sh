#!/bin/sh
# Installs Theos, the Linux iOS toolchain and an iOS SDK into $THEOS (default ~/theos), user-level
# only: no sudo. Idempotent. System packages first (Fedora):
#   sudo dnf install -y fakeroot perl rsync zip git xz
set -eu
export THEOS=${THEOS:-$HOME/theos}
ARCH=$(uname -m)

for tool in fakeroot perl rsync git xz curl make; do
  command -v "$tool" >/dev/null || { echo "missing: $tool (see the dnf line at the top of this script)"; exit 1; }
done

if [ ! -d "$THEOS/.git" ]; then
  git clone --recursive https://github.com/theos/theos.git "$THEOS"
fi

if [ ! -x "$THEOS/toolchain/linux/iphone/bin/clang" ]; then
  mkdir -p "$THEOS/toolchain"
  curl -sfL "https://github.com/L1ghtmann/llvm-project/releases/latest/download/iOSToolchain-$ARCH.tar.xz" \
    | tar -xJf - -C "$THEOS/toolchain/"
fi
"$THEOS/toolchain/linux/iphone/bin/clang" --version | head -1

if ! ls "$THEOS/sdks" 2>/dev/null | grep -q 'iPhoneOS16.*\.sdk'; then
  "$THEOS/bin/install-sdk" iPhoneOS16.5
fi
ls "$THEOS/sdks"
echo "ok: export THEOS=$THEOS (the Makefile defaults to it)"
