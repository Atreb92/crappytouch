# crappytouch

A SpringBoard tweak for rootless jailbreaks (built for iOS 15–16; tested on an iPhone 8, iOS 16.7.1,
Dopamine) that lets a computer running
[scrcrappy](https://github.com/Atreb92/scrcrappy) control the iPhone over USB.

## What it does

- **Touch**: taps, drags and multi-finger gestures at exact positions.
- **Keys**: any keyboard key with modifiers, and the phone's buttons: Home, app switcher, lock,
  volume.
- **Text**: any Unicode (accents, emoji) typed into the focused field, via paste.
- **Clipboard**: read and write the phone's clipboard text.
- **Screen**: size, scale and orientation, and lossless PNG screenshots with the real status bar.
- **Apps**: list the installed apps (with the PID of the running ones) and open one by bundle
  identifier.
- **Open URL**: open a link or deeplink (`https:`, `tel:`, `maps:`, app schemes).
- **Keep awake**: optionally stop the phone auto-locking while a computer is connected (Settings ›
  crappytouch).

## What it deliberately doesn't do

- Nothing over Wi-Fi or the network: it listens on `127.0.0.1` only, reached over USB.
- No shell commands, scripts, file access, app installs or settings changes.
- No code outside SpringBoard; no root, sudo rules, setuid binaries or re-signed apps; the install
  touches no other package's files.

## Security model

- Every connection must authenticate with an HMAC of a fresh random challenge, using a key derived
  from a secret only the paired computer has.
- A new computer can only pair when the user taps **Allow** on the phone, in an alert that names the
  computer and shows a 6-digit code to compare with the one on the computer. One alert at a time;
  pairing is refused while the phone is locked.
- So: other devices on the network can't reach the agent at all, and an app on the phone can connect
  to `127.0.0.1:7330` but can do nothing without passing that prompt.

## Using it

1. Install the package (below) and open scrcrappy with the agent backend.
2. **Pair**: unlock the phone. The first time, the phone asks *Allow “‹computer›” to control this
   iPhone?* — check that the code matches the one scrcrappy shows, then tap **Allow**.
3. **After each reboot, touch the screen once** before the computer can send touches (the agent
   learns the touchscreen from that touch). A respring doesn't need it.

Expected prompts from iOS 16, not from the agent:

- **Paste**: typing text (scrcrappy's Paste) shows *Allow Paste* in the app. To stop it for an app:
  Settings › ‹app› › Paste from Other Apps › Allow. The pasted text stays on the phone's clipboard.
- **Copy**: reading the phone's clipboard (scrcrappy's Copy) asks on the phone first when another app
  put the text there; the computer waits up to 30 s for the answer.

**Forget all paired computers**: delete `/var/jb/var/mobile/Library/crappytouch/hosts.plist`
on the phone (e.g. over SSH). Each computer has to pair again.

**Talking to it from your own code**: see [`PROTOCOL.md`](PROTOCOL.md) — every command, with
examples — and the reference client `client/agent_client.py` (Python stdlib).

## Build (Fedora)

```sh
sudo dnf install -y fakeroot perl rsync zip git xz
scripts/setup-theos.sh      # Theos + iOS toolchain + iOS 16.5 SDK into ~/theos
make package                # debug build: packages/com.atreb92.crappytouch_<version>-<n>+debug_iphoneos-arm64.deb
make package FINALPACKAGE=1 # release build (optimized, stripped): com.atreb92.crappytouch_<version>_iphoneos-arm64.deb
```

Both contain arm64 and arm64e.

## Install on the phone

Needs OpenSSH on the phone (Sileo). Run this **in your own terminal** — sudo on the phone asks for
your password, which is never stored:

```sh
scripts/install.sh          # copies the newest .deb over USB, dpkg -i, resprings
```

## Tests

```sh
.venv/bin/pytest                      # pure client tests, no phone needed
.venv/bin/pytest -m phone -s          # conformance suite against the phone over USB
```

The conformance suite runs in file order. The pairing tests ask you to tap **Deny**, **Deny**, then
**Allow** on the phone (`-s` shows the prompts); later tests need this computer paired. Run them with
the phone unlocked. Two tests change the phone's clipboard.

Logs: `idevicesyslog -m crappytouch`.

## Licence

MIT, see [LICENSE](LICENSE).

## Credits

- ZXTouch: showed how touches can be injected from SpringBoard on a jailbroken iPhone. crappytouch
  follows the same approach as a clean rewrite and contains none of its code.
