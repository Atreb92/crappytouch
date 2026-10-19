#!/bin/sh
# Install the newest packages/*.deb on the USB-connected iPhone and respring.
# Run it in your own terminal: sudo on the phone asks for your password (never stored).
# Needs OpenSSH on the phone; uses scripts/usb-forward.py on 127.0.0.1:2222.
set -eu
cd "$(dirname "$0")/.."
DEB=$(ls -t packages/*.deb | head -1)
USER_AT=${PHONE_USER:-mobile}@127.0.0.1
python3 scripts/usb-forward.py 2222 22 >/dev/null 2>&1 &
FWD=$!
trap 'kill $FWD 2>/dev/null || true' EXIT
sleep 0.5
SSH="-p 2222 -o StrictHostKeyChecking=accept-new"
scp -P 2222 -o StrictHostKeyChecking=accept-new "$DEB" "$USER_AT:/tmp/scrcrappy-agent.deb"
ssh -t $SSH "$USER_AT" "sudo dpkg -i /tmp/scrcrappy-agent.deb && rm /tmp/scrcrappy-agent.deb && killall -9 SpringBoard"
echo "installed $DEB"
