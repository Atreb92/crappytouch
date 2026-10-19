# Remaining work (as of 2026-10-19)

What is still to be built for jailbreak input, and what else is open across both repos. This is a
status + acceptance-criteria document; the detailed design and step-by-step plan it builds on are:

- Design: `docs/superpowers/specs/2026-10-19-scrcrappy-agent-design.md` (approved)
- Plan: `docs/superpowers/plans/2026-10-19-scrcrappy-agent.md` (Tasks 1–7 done)
- Wire protocol: `PROTOCOL.md`
- Acceptance tests: `tests/test_conformance.py` (run with `.venv/bin/pytest -m phone -s`)

## Where things stand

| Piece | State |
|---|---|
| Toolchain (Theos + iOS 16.5 SDK on Fedora, no sudo) | Done — `scripts/setup-theos.sh` |
| Rootless package build | Done — `make package` → `packages/*.deb` (2 files under `/var/jb`) |
| Dev install over USB | Done — `scripts/install.sh` (password typed by the user, never stored) |
| Tweak loads into SpringBoard on the iPhone 8 | Confirmed (server answers on 7330) |
| Reference client + pure tests | Done — `client/agent_client.py`, 6 tests pass |
| Conformance suite | all pass on the phone (Tasks 3–7) |
| Agent features | Tasks 3–7 done; Task 8 (packaging, docs) **not started** |
| scrcrappy integration | **Not started** (building blocks `usbmux.py`, `geometry.to_device` are on scrcrappy `master`) |

Test phone: iPhone 8, iOS 16.7.1, Dopamine (rootless) with ElleKit, Tweak Injection on, OpenSSH
installed.

## 1. scrcrappy-agent (this repo)

Each item is done when its conformance tests pass against the real phone and the manual check, if
any, has been seen working.

### 1.1 Server and auth gate (plan Task 3) — done
- Listens on 127.0.0.1:7330 only, started from SpringBoard; also serves as the "tweak is loaded"
  signal that the log line failed to give.
- On connect sends `hello` with protocol version, a fresh random nonce and the bound address.
- Before authentication only `auth` and `pair` are accepted; anything else → `auth required` and
  the connection is closed. Malformed frames, non-object JSON and lengths over 16 MiB close the
  connection; SpringBoard must never crash or hang because of a client.
- `auth` checks the host id against the stored hosts and the HMAC of the nonce in constant time.
- Tests: hello, command-before-auth, garbage, huge length, unknown host, bad mac.

### 1.2 Pairing prompt (plan Task 4) — done
- `pair` shows an alert in SpringBoard naming the computer and the 6-digit code; Allow stores the
  host, Deny or 30 s without an answer refuses.
- Only one pending alert; a second `pair` while one is open gets `busy` (no alert spam).
- Hosts file in the agent's own state dir, private to the `mobile` user; revocation = delete it.
- Tests (with taps): deny, busy, allow-then-auth.
- Also refuses with `locked` while the phone is locked (no alert on the lock screen).

### 1.3 Touch (plan Task 5) — done (tap, swipe, pinch seen working)
- `touch` events with finger, phase and position as fractions of the portrait screen; no reply.
- Learns what it needs from the first real touch after a reboot; until then `screen` reports
  `touch_ready: false` and touches are dropped without errors.
- Fingers still down when a client disconnects are released.
- Tests: touch keeps the connection usable, fingers released on disconnect. Manual: tap opens an
  app, drag scrolls, two-finger pinch zooms.

### 1.4 Keys, text, clipboard (plan Task 6) — done (accents/emoji pasted into Notes, Backspace deleted)
- `key` (HID usage + modifiers), `text` (any Unicode, typed via the pasteboard and a paste
  shortcut; the text stays on the clipboard, see below), `clipboard_get` / `clipboard_set`.
- iOS 16 shows "Allow Paste" for the injected paste (it can tell the Cmd+V isn't a real keyboard's).
  Decided 2026-10-19: no clipboard restore (it dismissed the prompt); per app, Settings › Paste from
  Other Apps › Allow stops the prompt.
- Tests: clipboard round trip with emoji, text leaves its text on the clipboard, key ok. Manual: accented
  text and emoji appear in Notes; Backspace deletes.

### 1.4b Buttons (added 2026-10-19, was "later") — done
- `key` with `page: 0x0C`: Home, double Home = app switcher, lock, volume — all seen working on the
  iPhone 8. **Not yet checked on a Face ID iPhone** (the iPhone X): Home / switcher should behave like a
  keyboard's Home key there, but confirm.

### 1.5 Screen info and screenshot (plan Task 7) — done
- `screen`: size in points, scale, interface orientation, plus `touch_ready` and `fingers_down`.
- `screenshot`: lossless PNG of the real screen (real status bar), base64 in the reply.
- Tests: screen info shape, screenshot is a PNG of the screen's pixel size.

### 1.6 Packaging and docs (plan Task 8)
- `control` metadata, README (what it does and deliberately doesn't, security model, install,
  pairing, revocation, dev loop), final `PROTOCOL.md`; version bump; arm64 + arm64e builds.

### Must hold throughout (from the design's anti-goals)
- Not reachable from the network; nothing usable by an app on the phone without the user's Allow.

## 2. scrcrappy integration (scrcrappy repo)

- **Backend `--mouse agent`**: connect with `usbmux.connect(7330)`, vendor
  `client/agent_client.py`, pair on first use (show the code in the terminal and the window),
  authenticate afterwards. Clear errors when the agent isn't installed / not paired / denied.
- **Input**: window clicks/drags → `touch` via `geometry.to_device` (absolute, no cursor
  following); Ctrl+drag → two-finger pinch; wheel → short swipe; keys → `key`; release held
  fingers and keys on focus loss.
- **Rotation**: read orientation from `screen`; check `ROTATION_BY_ORIENTATION` in `geometry.py`
  against what the phone showed (2026-10-19, iPhone 8, Notes): Home button on the right → `orientation` 3,
  Home on the left → 4. Screenshots stay 750×1334 (panel portrait) in every orientation; the app's
  top edge is on the image's right for 3 (rotate 90° counter-clockwise to show upright) and on its
  left for 4 (rotate 90° clockwise).
- **Buttons in agent mode**: Home, app switcher, lock, volume via `key` page 0x0C (agent side done).
- **Toolbar in agent mode**: Paste via `text`; **Copy** enabled (phone clipboard → computer);
  new **Screenshot** button saving a PNG; the custom AssistiveTouch buttons stay BLE/ESP32-only
  (what the agent shows instead is still to be decided by the user).
- Tests: backend unit tests against a fake agent speaking the protocol; manual run on the phone.

## 3. Other open items

Tracked in scrcrappy's `TODO.md`; summary:

- Later: full terminal over SSH through the USB tunnel; opening apps through the agent.
- BLE: link-speed experiment (advertise as a mouse again to get back to 8 ms reports); mouse wheel
  doesn't scroll iOS Settings lists; long vertical moves land 5–10 % short; paste limited to US
  ASCII; optional `--ctrl-as-cmd`.
- Verify: tooltip window stealing focus on some window managers; ESP32 firmware on real hardware;
  macOS end to end.
