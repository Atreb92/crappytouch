# scrcrappy-agent Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** A SpringBoard tweak for rootless jailbreaks that lets a paired computer (over USB) inject touches and keys, read/write the clipboard, read screen info and pull PNG screenshots — nothing else.

**Architecture:** Theos tweak loaded only into SpringBoard. A GCD-driven TCP server on 127.0.0.1:7330 speaks length-prefixed JSON frames. Every connection starts with hello/nonce; nothing but `auth`/`pair` is accepted until HMAC auth succeeds; `pair` shows an Allow/Deny alert. Device code is verified by a **conformance test suite** (Python stdlib, runs on the computer against the real phone over usbmux) written before each feature — the device can't run unit tests, the conformance suite is the TDD loop.

**Tech Stack:** Theos (Linux toolchain + iOS 16 SDK), Objective-C, IOKit IOHIDEvent (private), CommonCrypto; host: Python 3.11+ stdlib.

**Spec:** `docs/superpowers/specs/2026-10-19-scrcrappy-agent-design.md`

## Global Constraints

- Inject into **SpringBoard only** (`Filter = { Bundles = ("com.apple.springboard"); }`).
- Listen on **127.0.0.1:7330** only. No files outside the agent's own state dir, no sudo/setuid, no postinst that touches other packages.
- State dir `/var/jb/var/mobile/Library/scrcrappy-agent/` (mode 700, owner mobile): `hosts.plist` = { id: {name, key} } with id = hex SHA-256("scrcrappy-id" + secret) and key = SHA-256("scrcrappy-key" + secret) — distinct, so the id sent in `auth` never reveals the HMAC key.
- Package: rootless (`THEOS_PACKAGE_SCHEME=rootless`), archs `arm64 arm64e`, id `dev.scrcrappy.agent`, MIT.

## Protocol v1 (decided here; documented in `PROTOCOL.md` by Task 1)

- Frame: 4-byte big-endian length + UTF-8 JSON object. Max 16 MiB.
- Agent → on connect: `{"hello": 1, "nonce": "<32 hex>"}`.
- `{"cmd":"auth","host":"<name>","id":"<hex id>","mac":"<hex HMAC-SHA256(key, nonce bytes)>"}` (id / key derived as in Global Constraints) → `{"ok":true}` | `{"error":"unknown host"}` | `{"error":"bad mac"}`.
- `{"cmd":"pair","host":"<name>","secret":"<64 hex>"}` → alert "Allow ‹name› to control this iPhone? Code ‹code›"; `code` = first 3 bytes of sha256(secret) as int % 1 000 000, zero-padded 6 digits → `{"ok":true}` | `{"error":"denied"}` (Deny or 30 s) | `{"error":"busy"}` (another pairing pending).
- After auth only:
  - `{"cmd":"touch","events":[{"finger":1..10,"phase":"down|move|up","x":0..1,"y":0..1}]}` — **no reply** (latency).
  - `{"cmd":"key","usage":<HID usage>,"modifiers":<bits>}` — press+release, reply `{"ok":true}`.
  - `{"cmd":"text","text":"…"}` — pasteboard set + Cmd+V, previous pasteboard restored after 0.5 s → `{"ok":true}`.
  - `{"cmd":"clipboard_get"}` → `{"ok":true,"text":"…"}`; `{"cmd":"clipboard_set","text":"…"}` → `{"ok":true}`.
  - `{"cmd":"screen"}` → `{"ok":true,"width":<points>,"height":<points>,"scale":<n>,"orientation":<UIInterfaceOrientation>}`.
  - `{"cmd":"screenshot"}` → `{"ok":true,"png":"<base64>"}`.
  - Any command before auth → `{"error":"auth required"}` and connection closed.
- Coordinates are fractions of the portrait screen (0..1), so the host never needs device units.

## Review Focus

1. Unauthenticated client sends commands / garbage / huge length prefix → error + close, SpringBoard never crashes. (Task 3 conformance)
2. A second `pair` while an alert is pending → `busy`, no second alert. (Task 4)
3. Touch before the sender ID is known (fresh reboot, no real touch yet) → no crash; reply-less touches dropped; `screen` reply carries `"touch_ready": false`. (Task 5)
4. Client disconnects mid-touch (finger down) → agent sends touch-up for held fingers. (Task 5)
5. `text` with emoji / accents / 10 KB text → typed exactly; user's clipboard restored. (Task 6)

---

### Task 1: Toolchain, empty tweak, dev install loop

**Files:** `scripts/setup-theos.sh`, `scripts/usb-forward.py` (127.0.0.1:2222 → phone port 22 via usbmuxd, stdlib), `Makefile`, `control`, `Tweak.x` (logs "scrcrappy-agent loaded" from SpringBoard), `PROTOCOL.md`, `README.md`, `LICENSE` (MIT), `.gitignore`.

- [ ] `setup-theos.sh`: installs Theos to `~/theos` (official install script), the Linux iOS toolchain and an iOS 16.x SDK into `~/theos/sdks`; idempotent.
- [ ] `make package` produces `packages/dev.scrcrappy.agent_*_iphoneos-arm64.deb` (rootless).
- [ ] User (one-time): install OpenSSH from Sileo. Dev loop: `scripts/usb-forward.py &` then `make do THEOS_DEVICE_IP=127.0.0.1 THEOS_DEVICE_PORT=2222` installs + resprings.
- [ ] Verify on phone: SpringBoard log contains "scrcrappy-agent loaded" (`ssh … log show --last 1m --predicate 'process == "SpringBoard"' | grep scrcrappy` or oslog equivalent).
- [ ] Commit `build: theos skeleton and USB dev loop`.

### Task 2: Conformance harness + reference client

**Files:** `client/agent_client.py` (stdlib: usbmux connect, frames, auth, pair, commands; key file `~/.config/scrcrappy/agent-<udid>.key`), `tests/conformance.py` (pytest, marks `phone` for tests needing the phone + manual taps), `tests/test_client.py` (pure: frame encode/decode, code derivation, HMAC vector).

- [ ] Pure tests first (RED → GREEN): `test_frame_roundtrip`, `test_rejects_oversized_frame`, `test_pairing_code_vector` (secret `00…01` → fixed code, value computed once and pinned), `test_mac_vector`, `test_id_and_key_differ`.
- [ ] Conformance tests written now, all failing until later tasks: hello, auth-required, garbage, pair-busy, auth after pair, touch, key, text, clipboard, screen, screenshot.
- [ ] Commit `test: protocol client and conformance suite`.

### Task 3: Server + hello + auth gate

**Files:** `src/Server.{h,m}` (GCD socket on 127.0.0.1:7330, one serial queue per client, frame reader with 16 MiB cap), `src/Auth.{h,m}` (nonce via `SecRandomCopyBytes`, HMAC via CommonCrypto, constant-time compare, hosts.plist load/save), `Tweak.x` starts server after SpringBoard finishes launching.

- [ ] Conformance GREEN: `test_hello_has_nonce`, `test_command_before_auth_refused_and_closed`, `test_garbage_and_huge_length_close_connection`, `test_unknown_host_refused`, `test_listens_on_loopback_only` (agent reports bound address in hello as `"addr":"127.0.0.1"`).
- [ ] Commit `feat: localhost server with auth gate`.

### Task 4: Pairing alert

**Files:** `src/Pairing.{h,m}` (alert on a dedicated `UIWindow` at alert level in SpringBoard, Allow/Deny, 30 s timeout, single pending pair).

- [ ] Conformance (manual tap): `test_pair_allow_then_auth_ok` (tester taps Allow; client then authenticates on a new connection), `test_pair_deny`, `test_second_pair_while_pending_is_busy`.
- [ ] Commit `feat: on-phone pairing prompt`.

### Task 5: Touch injection

**Files:** `src/Touch.{h,m}`: digitizer parent (hand) event + child finger events, normalized x/y, dispatch via `IOHIDEventSystemClientDispatchEvent`; sender ID learned from the first real digitizer event after boot (event-system callback), cached in memory + state dir with boot time; held-finger tracking for disconnect cleanup.

- [ ] Conformance: `test_touch_no_reply_and_connection_stays_usable`, `test_screen_reports_touch_ready`, `test_disconnect_releases_fingers` (agent log/state probe via `screen` → `"fingers_down":0`).
- [ ] Manual (with scrcrappy video): tap an app icon opens it; drag scrolls; two-finger pinch zooms a photo.
- [ ] Commit `feat: touch injection`.

### Task 6: Keys, text, clipboard

**Files:** `src/Keyboard.{h,m}` (IOHIDEventCreateKeyboardEvent usage page 7, modifiers as separate key events), `src/Clipboard.{h,m}` (UIPasteboard generalPasteboard on main queue).

- [ ] Conformance: `test_clipboard_roundtrip` (incl. emoji), `test_text_restores_clipboard`, `test_key_returns_ok`; manual: text with accents/emoji appears in Notes; Backspace (usage 0x2A) deletes.
- [ ] Commit `feat: keys, text via paste, clipboard`.

### Task 7: Screen info + screenshot

**Files:** `src/Screen.{h,m}` (UIScreen mainScreen bounds/scale, SpringBoard interface orientation; screenshot via `_UICreateScreenUIImage()` → PNG).

- [ ] Conformance: `test_screen_info_shape`, `test_screenshot_is_png_of_screen_size` (PNG signature, dimensions = width×scale by height×scale, or rotated).
- [ ] Commit `feat: screen info and screenshot`.

### Task 8: Package polish + docs

- [ ] `control` (name, description, depends `mobilesubstrate | ellekit`, MIT), `README.md` (what it does / doesn't, security model, install, pairing, revoke = delete `hosts.plist`, dev loop), `PROTOCOL.md` final.
- [ ] Commit `docs: readme and protocol`.
