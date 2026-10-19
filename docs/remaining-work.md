# Remaining work (as of 2026-10-19)

What is still to be built for jailbreak input, and what else is open across both repos. This is a
status + acceptance-criteria document; the detailed design and step-by-step plan it builds on are:

- Design: `docs/superpowers/specs/2026-10-19-scrcrappy-agent-design.md` (approved)
- Plan: `docs/superpowers/plans/2026-10-19-scrcrappy-agent.md` (Tasks 1–2 done)
- Wire protocol: `PROTOCOL.md`
- Acceptance tests: `tests/test_conformance.py` (run with `.venv/bin/pytest -m phone -s`)

## Where things stand

| Piece | State |
|---|---|
| Toolchain (Theos + iOS 16.5 SDK on Fedora, no sudo) | Done — `scripts/setup-theos.sh` |
| Rootless package build | Done — `make package` → `packages/*.deb` (2 files under `/var/jb`) |
| Dev install over USB | Done — `scripts/install.sh` (password typed by the user, never stored) |
| Skeleton tweak installed on the iPhone 8 | Installed (`install ok installed`); **loading into SpringBoard not yet confirmed** (its log line never reached `idevicesyslog`) |
| Reference client + pure tests | Done — `client/agent_client.py`, 6 tests pass |
| Conformance suite | Written; fails at the first test (nothing listens on port 7330 yet) |
| Agent features (Tasks 3–8) | **Not started** |
| scrcrappy integration | **Not started** (building blocks `usbmux.py`, `geometry.to_device` are on scrcrappy `master`) |

Test phone: iPhone 8, iOS 16.7.1, Dopamine (rootless) with ElleKit, Tweak Injection on, OpenSSH
installed.

## 1. scrcrappy-agent (this repo)

Each item is done when its conformance tests pass against the real phone and the manual check, if
any, has been seen working.

### 1.1 Server and auth gate (plan Task 3)
- Listens on 127.0.0.1:7330 only, started from SpringBoard; also serves as the "tweak is loaded"
  signal that the log line failed to give.
- On connect sends `hello` with protocol version, a fresh random nonce and the bound address.
- Before authentication only `auth` and `pair` are accepted; anything else → `auth required` and
  the connection is closed. Malformed frames, non-object JSON and lengths over 16 MiB close the
  connection; SpringBoard must never crash or hang because of a client.
- `auth` checks the host id against the stored hosts and the HMAC of the nonce in constant time.
- Tests: hello, command-before-auth, garbage, huge length, unknown host, bad mac.

### 1.2 Pairing prompt (plan Task 4)
- `pair` shows an alert in SpringBoard naming the computer and the 6-digit code; Allow stores the
  host, Deny or 30 s without an answer refuses.
- Only one pending alert; a second `pair` while one is open gets `busy` (no alert spam).
- Hosts file in the agent's own state dir, private to the `mobile` user; revocation = delete it.
- Tests (with taps): deny, busy, allow-then-auth.

### 1.3 Touch (plan Task 5)
- `touch` events with finger, phase and position as fractions of the portrait screen; no reply.
- Learns what it needs from the first real touch after a reboot; until then `screen` reports
  `touch_ready: false` and touches are dropped without errors.
- Fingers still down when a client disconnects are released.
- Tests: touch keeps the connection usable, fingers released on disconnect. Manual: tap opens an
  app, drag scrolls, two-finger pinch zooms.

### 1.4 Keys, text, clipboard (plan Task 6)
- `key` (HID usage + modifiers), `text` (any Unicode, typed via the pasteboard and a paste
  shortcut, the user's previous clipboard restored afterwards), `clipboard_get` / `clipboard_set`.
- Tests: clipboard round trip with emoji, text restores the clipboard, key ok. Manual: accented
  text and emoji appear in Notes; Backspace deletes.

### 1.5 Screen info and screenshot (plan Task 7)
- `screen`: size in points, scale, interface orientation, plus `touch_ready` and `fingers_down`.
- `screenshot`: lossless PNG of the real screen (real status bar), base64 in the reply.
- Tests: screen info shape, screenshot is a PNG of the screen's pixel size.

### 1.6 Packaging and docs (plan Task 8)
- `control` metadata, README (what it does and deliberately doesn't, security model, install,
  pairing, revocation, dev loop), final `PROTOCOL.md`; version bump; arm64 + arm64e builds.

### Must hold throughout (from the design's anti-goals)
- Not reachable from the network; nothing usable by an app on the phone without the user's Allow.
- No shell commands, no root path (no sudoers, setuid, re-signed apps), no injection outside
  SpringBoard, no install scripts touching other packages.

## 2. scrcrappy integration (scrcrappy repo)

- **Backend `--mouse agent`**: connect with `usbmux.connect(7330)`, vendor
  `client/agent_client.py`, pair on first use (show the code in the terminal and the window),
  authenticate afterwards. Clear errors when the agent isn't installed / not paired / denied.
- **Input**: window clicks/drags → `touch` via `geometry.to_device` (absolute, no cursor
  following); Ctrl+drag → two-finger pinch; wheel → short swipe; keys → `key`; release held
  fingers and keys on focus loss.
- **Rotation**: read orientation from `screen`; confirm `ROTATION_BY_ORIENTATION` for the two
  landscape directions on the phone (marked `ponytail:` in `geometry.py`).
- **Toolbar in agent mode**: Paste via `text`; **Copy** enabled (phone clipboard → computer);
  new **Screenshot** button saving a PNG; the custom AssistiveTouch buttons stay BLE/ESP32-only
  (what the agent shows instead is still to be decided by the user).
- Tests: backend unit tests against a fake agent speaking the protocol; manual run on the phone.

## 3. Other open items

Tracked in scrcrappy's `TODO.md`; summary:

- Later: full terminal over SSH through the USB tunnel; hardware buttons (Home, lock, volume) and
  opening apps through the agent.
- BLE: link-speed experiment (advertise as a mouse again to get back to 8 ms reports); mouse wheel
  doesn't scroll iOS Settings lists; long vertical moves land 5–10 % short; paste limited to US
  ASCII; optional `--ctrl-as-cmd`.
- Verify: tooltip window stealing focus on some window managers; ESP32 firmware on real hardware;
  macOS end to end.
