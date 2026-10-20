# Remaining work (as of 2026-10-19)

What is still to be built for jailbreak input, and what else is open across both repos. This is a
status + acceptance-criteria document; the detailed design and step-by-step plan it builds on are:

- Design: `docs/superpowers/specs/2026-10-19-crappytouch-design.md` (approved)
- Plan: `docs/superpowers/plans/2026-10-19-crappytouch.md` (Tasks 1–8 done)
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
| Agent features | Tasks 3–8 done (v0.2.0) |
| scrcrappy integration | Done (2026-10-19/20) — `--mouse agent`, plus AI control (`scrcrappy agent …` CLI and MCP); see §2 |

Test phone: iPhone 8, iOS 16.7.1, Dopamine (rootless) with ElleKit, Tweak Injection on, OpenSSH
installed.

## 1. crappytouch (this repo)

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

### 1.6 Packaging and docs (plan Task 8) — done (v0.2.0; `PROTOCOL.md` is the full interface guide)
- `control` metadata, README (what it does and deliberately doesn't, security model, install,
  pairing, revocation, dev loop), final `PROTOCOL.md`; version bump; arm64 + arm64e builds.

### Must hold throughout (from the design's anti-goals)
- Not reachable from the network; nothing usable by an app on the phone without the user's Allow.

## 2. scrcrappy integration (scrcrappy repo) — done

Built and merged on scrcrappy `master` (2026-10-19/20), verified on the iPhone 8:

- **Backend `--mouse agent`** (or Input › Agent in scrcrappy's Settings): the client is vendored as
  `scrcrappy/agent_client.py`; pairs on first use (code in the terminal), authenticates afterwards,
  clear errors when the agent isn't installed, the pairing is denied, or usbmuxd doesn't answer. The
  connection is reopened when qvh switches the phone's USB configuration or SpringBoard resprings.
- **Input**: clicks/drags → `touch` at the exact spot; Ctrl+drag → pinch; wheel → short swipe; keys →
  `key` (held keys repeat); fingers and modifiers released on focus loss.
- **Rotation**: `ROTATION_BY_ORIENTATION` now matches the phone (3 → 270, 4 → 90, as the screenshot
  notes above say). Landscape taps still to be checked by hand (scrcrappy `TODO.md`).
- **Toolbar in agent mode**: Paste (via `text`), Copy (phone clipboard → computer), Screenshot (PNG,
  upright), Home, App switcher, Lock. Volume buttons left out by the user's choice.
- **AI control** (added on top): `scrcrappy agent --screenshot | --tap | --long-press | --swipe |
  --type | --clipboard` (one action per call, JSON out, percent coordinates), and an MCP server inside
  the scrcrappy window for both agent and Bluetooth/ESP32 modes. Typing uses `key` when a US layout can
  type the text, `text` (paste) otherwise.
- Tests: unit tests against a fake agent in scrcrappy's suite; manual runs on the phone.

Known limits seen from scrcrappy: `clipboard_get` and the paste behind `text` can trigger *Allow Paste*,
which can't be answered remotely; usbmuxd can wedge (lockdown error -8) after scrcrappy's USB reset while
the phone is locked.

## 2b. Planned: list and open apps (agent mode only, added 2026-10-20)

- Agent: `apps` (like `frida-ps -Uai`: identifier, name, PID when running) and `open` by bundle
  identifier, with errors for unknown apps and a locked phone. Plan Task 9: **done** (0.3.0, verified
  on the iPhone 8).
- scrcrappy: `scrcrappy agent --apps` / `--open <id>` and MCP tools `list_apps` / `open_app`.
  Plan Task 10.

## 2c. Done after the agent shipped (0.4.0, 0.5.0; verified on the iPhone 8)

- **Keep awake while connected (0.4.0)**: a *Keep Awake While Connected* switch in Settings ›
  crappytouch. The agent holds an `SBIdleTimerGlobalCoordinator` disable assertion while ≥1
  authenticated computer is connected; released on disconnect. Adds a PreferenceLoader bundle
  (`layout/…`, `Depends: … preferenceloader`) with the scrcrappy icon.
- **open_url (0.5.0)**: `{"cmd":"open_url","url":…}` via `-[UIApplication openURL:options:
  completionHandler:]` from SpringBoard. Verified: `https:`, `tel:`, `sms:`, app schemes
  (`music://`, `maps://?q=…`). iOS-restricted schemes like `prefs:root=…` correctly return
  `open failed` (LaunchServices blocks third-party `prefs:` deep links; `open com.apple.Preferences`
  still works).
- **Clipboard prompt — investigated, left as is**: dumped every pasteboard class in SpringBoard. The
  copy prompt behind `clipboard_get` can't be removed safely — every daemon read of cross-app data
  takes an *authentication message*, which is exactly what raises *Allow Paste*; no prompt-free read
  exists. Only a forged auth message or patching the pasteboard daemon would suppress it, both of
  which defeat the privacy gate / break "no code outside SpringBoard". The paste prompt behind `text`
  can instead be avoided by typing characters directly via IOKit (not yet built).

## 3. Other open items

- **Sileo repo (later, after the agent is verified)**: static repo (`.deb` + `Packages*` from
  `dpkg-scanpackages` + `Release` from `apt-ftparchive`), e.g. on GitHub Pages; a
  `scripts/make-repo.sh` to regenerate it from the `FINALPACKAGE=1` build. Open decisions: public or
  not, the `Maintainer` field (now just `scrcrappy`), where to host.
- **Release build verified (2026-10-19, iPhone 8)**: v0.2.0 `FINALPACKAGE=1` — full conformance suite
  (17 phone tests) in one go, plus swipe, tap, Home, typing by keys, paste with accents/emoji (Allow
  Paste), Backspace.
- **Still to check**: Home / app switcher on the iPhone X (Face ID); arm64e is untested (no arm64e
  phone; the Linux toolchain builds it with the old ABI).

Tracked in scrcrappy's `TODO.md`; summary:

- Later: full terminal over SSH through the USB tunnel; opening apps through the agent.
- BLE: link-speed experiment (advertise as a mouse again to get back to 8 ms reports); mouse wheel
  doesn't scroll iOS Settings lists; long vertical moves land 5–10 % short; paste limited to US
  ASCII; optional `--ctrl-as-cmd`.
- Verify: tooltip window stealing focus on some window managers; ESP32 firmware on real hardware;
  macOS end to end.
