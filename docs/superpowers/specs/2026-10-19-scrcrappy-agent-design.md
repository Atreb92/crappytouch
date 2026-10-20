# scrcrappy-agent (design)

## Intent

scrcrappy mirrors an iPhone and controls it from a computer. On a non-jailbroken phone it drives
an AssistiveTouch cursor through a Bluetooth mouse (approximate, ~15 ms report pace). On a
jailbroken phone it should tap exactly where you click, type, and sync the clipboard.

The obvious existing tweak, ZXTouch Rootless, was audited (2026-10-19) and **rejected**: an
unauthenticated TCP socket on all interfaces lets anyone on the Wi-Fi and any app on the phone run
shell commands, inject input, read the clipboard and take screenshots; its installer adds a
passwordless sudo rule, re-signs its app with broad entitlements, injects into every app and ships
unsigned binaries. The user does mobile security testing, so apps on the phone may be hostile.

scrcrappy-agent is our own small tweak: only what scrcrappy needs, reachable only by a computer the
user approved on the phone.

## Goals

1. Touch injection at exact coordinates, multitouch (down / move / up per finger).
2. Text: insert text into the focused field; delete backward.
3. Clipboard: read and write the phone's general pasteboard (text).
4. Screen info: size (in the units touches use) and interface orientation.
5. Screenshot pull: lossless PNG of the real screen (real status bar, unlike the QuickTime stream).
6. **Pairing with an on-phone prompt** (user decision): first connection from a computer shows
   an alert on the phone "Allow ‹computer name› to control this iPhone? Code ‹6 digits›"; the same
   code is shown by scrcrappy. Allow → the computer is remembered; Deny / no answer in 30 s →
   refused.
7. A small, versioned, documented protocol so scrcrappy and the agent evolve independently.

## Non-goals

- Scripts, OCR, image matching, touch recording, web dashboard, Shortcuts integration.
- Hardware buttons (Home, lock, volume) and opening apps: later (SpringBoard can do them).
- Wi-Fi access: USB only.

## Anti-goals (failure even if it works)

- Anything reachable from the network, or usable by an app on the phone without the user's Allow.
- Any path to root, sudoers entries, setuid binaries, re-signed apps with extra entitlements.
- Code injected into processes other than SpringBoard (no `com.apple.UIKit` filter).
- Install scripts that change other packages' files.

## Constraints

- Phone: iPhone 8 (A11) on iOS 16.7.1 with Dopamine (rootless, `/var/jb`); also expected to run on
  the user's iPhone X with Dopamine. arm64 (not arm64e) must be built; arm64e too for newer phones.
- Built with **Theos on Fedora** into a rootless `.deb`; a setup script installs the toolchain and
  an iOS SDK. Licence: **MIT** — the touch-injection *technique* (IOHIDEvent digitizer events
  dispatched in SpringBoard) is reimplemented, no ZXTouch (GPLv3) code is copied.
- Transport: TCP on **127.0.0.1** only, fixed port (proposal: 7330), reached from the computer
  through usbmuxd (`scrcrappy/usbmux.py` already does this, verified on the phone).
- Host side has no new dependencies: Python stdlib (`hmac`, `hashlib`, `secrets`).

## Pairing and authentication (user chose the on-phone prompt)

- The computer has a random 32-byte secret per phone, stored
  `~/.config/scrcrappy/agent-<udid>.key` (mode 600).
- **Pair** (first time / unknown computer): client sends its name and the secret; the agent shows
  the alert with a 6-digit code derived from the secret (e.g. first 6 digits of
  SHA-256(secret)), scrcrappy prints/shows the same code. On Allow the agent stores
  SHA-256(secret) and the name in its hosts file; on Deny/timeout it closes the connection.
- **Every later connection**: agent sends a random nonce; client answers HMAC-SHA256(secret, nonce);
  agent compares (constant time) against stored hosts. No command is accepted before that.
- Only one pairing alert at a time; repeated pair requests while one is pending are refused
  (no alert spam from a hostile local app).
- Revocation: a "Forget all computers" path — v1: delete the agent's hosts file (documented);
  a settings UI is a later nicety.

Threat model check: network attackers can't reach 127.0.0.1; local apps can connect but can't pass
the HMAC without a secret, and can't get one without the user tapping Allow on a prompt that names
the computer and shows a code the user can compare with scrcrappy.

## Protocol (sketch; builder finalizes and documents it in the repo)

Length-prefixed binary frames or newline-delimited JSON, versioned in the first message
(`hello` with protocol version). Commands: `pair`, `auth`, `touch` (list of {finger, phase, x, y}),
`text`, `delete`, `clipboard_get`, `clipboard_set`, `screen` (size + orientation), `screenshot`
(PNG bytes). Touch is fire-and-forget (no reply) to keep latency low; everything else replies.

## Decisions left to the builder

- Frame format, port number, exact alert wording, hosts-file location under `/var/jb`.
- How the alert is presented from SpringBoard (e.g. `UIAlertController` on a SpringBoard window).
- How screen size units and orientation are obtained (match what IOHIDEvent digitizer expects).
- PNG capture API (e.g. `UIGetScreenImage`-style private API or IOSurface of the framebuffer).
- arm64/arm64e build matrix, versioning, release process.

## scrcrappy side (separate work in the scrcrappy repo, after the agent exists)

- New `--mouse agent` backend: touches from window events (tap, drag, pinch), typing via the
  agent's text commands, pill **Copy** enabled (phone → computer clipboard), **Paste** via
  clipboard_set + paste or text insert, **Screenshot** button saving PNG.
- Existing pieces to reuse: `usbmux.connect`, `geometry.to_device`, the toolbar.
- `zxtouch.py` (written before the audit) is superseded and should be removed.

## Addendum (2026-10-20): listing and opening apps (user-approved, agent mode only)

- `apps`: every app that can be opened, like `frida-ps -Uai`: bundle identifier, display name, and
  the PID when it is running. No system daemons or other non-app processes.
- `open` with a bundle identifier: brings that app to the front, the way tapping its icon would.
  Clear errors for an unknown identifier and for a locked phone (iOS won't open apps over the lock
  screen). Like every other command, only after pairing and auth.
- No new reach: a paired computer can already tap any icon; this saves hunting for it.
- Not in Bluetooth/ESP32 mode (user decision), even though the phone's installation service could
  list apps without the agent.
