#!/bin/sh
# Installs Theos, the Linux iOS toolchain and an iOS SDK into $THEOS (default ~/theos), user-level
# only: no sudo. Idempotent. System packages first (Fedora):
#   sudo dnf install -y fakeroot perl rsync zip git xz
set -eu
export THEOS=${THEOS:-$HOME/theos}
ARCH=$(uname -m)

# Pinned: the versions that build the shipped .deb. Bump deliberately; hashes are of the release assets.
THEOS_REV=304e0799973e8145f32e4ca2de6c747a84b758ce
TOOLCHAIN_TAG=test-210562a
SDK_TAG=master-146e41f
SDK_SHA256=5e0fd3f01266cce4ce012d4a99b38eb56578fca40d09edc81cd83dee958202fb
case $ARCH in
  x86_64) TOOLCHAIN_SHA256=a72a7a577e2fbe2838b6b5e9c72034fa7d114af96f0e1d4b016f18730ce4056e ;;
  aarch64|arm64) ARCH=aarch64; TOOLCHAIN_SHA256=9051e9d531de5e511f0fab40d925d625bc6efe7ed9dce821d179c09de9bc690b ;;
  *) echo "no pinned toolchain for $ARCH"; exit 1 ;;
esac

# Download $1 to $2, abort unless its sha256 is $3.
fetch() {
  curl -sfL "$1" -o "$2"
  echo "$3  $2" | sha256sum -c - >/dev/null || { rm -f "$2"; echo "checksum mismatch: $1"; exit 1; }
}

for tool in fakeroot perl rsync git xz curl make; do
  command -v "$tool" >/dev/null || { echo "missing: $tool (see the dnf line at the top of this script)"; exit 1; }
done

if [ ! -d "$THEOS/.git" ]; then
  git clone https://github.com/theos/theos.git "$THEOS"
fi
git -C "$THEOS" cat-file -e "$THEOS_REV^{commit}" 2>/dev/null || git -C "$THEOS" fetch -q origin
git -C "$THEOS" checkout -q "$THEOS_REV"
git -C "$THEOS" submodule update -q --init --recursive

if [ ! -x "$THEOS/toolchain/linux/iphone/bin/clang" ]; then
  mkdir -p "$THEOS/toolchain"
  tmp=$(mktemp)
  fetch "https://github.com/L1ghtmann/llvm-project/releases/download/$TOOLCHAIN_TAG/iOSToolchain-$ARCH.tar.xz" "$tmp" "$TOOLCHAIN_SHA256"
  tar -xJf "$tmp" -C "$THEOS/toolchain/"
  rm -f "$tmp"
fi
"$THEOS/toolchain/linux/iphone/bin/clang" --version | head -1

if ! ls "$THEOS/sdks" 2>/dev/null | grep -q 'iPhoneOS16.*\.sdk'; then
  mkdir -p "$THEOS/sdks"
  tmp=$(mktemp)
  fetch "https://github.com/theos/sdks/releases/download/$SDK_TAG/iPhoneOS16.5.sdk.tar.xz" "$tmp" "$SDK_SHA256"
  tar -xJf "$tmp" -C "$THEOS/sdks"
  rm -f "$tmp"
fi
ls "$THEOS/sdks"
echo "ok: export THEOS=$THEOS (the Makefile defaults to it)"
