# crappytouch protocol v1

How a computer talks to the agent: how to reach it, how to pair and authenticate, and every
command with its request, reply and errors. `client/agent_client.py` implements all of it (Python
stdlib, ~100 lines) and is the reference when this file and the code disagree.

## 1. Reaching the agent

The agent listens on **127.0.0.1:7330 on the phone** — not on the network. The computer reaches it
over USB through **usbmuxd** (built into macOS; the `usbmuxd` package on Linux):

1. Connect to the Unix socket `/var/run/usbmuxd`.
2. Send a `ListDevices` request; take the `DeviceID` of a device whose `ConnectionType` is `USB`.
3. Send `Connect` with that `DeviceID` and `PortNumber` = 7330 **in network byte order**
   (`socket.htons(7330)`). Reply `Number` 0 = connected; anything else = nothing listening (agent not
   installed, or SpringBoard not running it).
4. From then on the same socket is a raw TCP stream to the agent.

usbmuxd messages are a 16-byte little-endian header (`length` incl. header, `version` 1, `type` 8 =
plist, `tag`) followed by an XML plist. `client/usbmux.py` does steps 1–3 in ~50 lines.

## 2. Framing

Every message in both directions is one **frame**:

```
+-------------------------+---------------------------------+
| length: uint32, big end | body: `length` bytes, UTF-8 JSON |
+-------------------------+---------------------------------+
```

- The body is always a JSON **object**. Anything else (invalid JSON, an array, a string) closes the
  connection.
- Maximum body: **16 MiB** after authentication, **64 KiB** before. A larger length closes the
  connection without reading the body.
- Requests are `{"cmd": "<name>", ...}`. Replies are `{"ok": true, ...}` or `{"error": "<reason>"}`.
- Every command gets exactly one reply, in order, **except `touch`**, which never replies.

## 3. Connection lifecycle

```
computer                                   agent (in SpringBoard)
   | ---- usbmuxd Connect(7330) ------------> |
   | <--- {"hello":1,"nonce":"…","addr":…} -- |   sent at once, fresh random nonce
   | ---- {"cmd":"auth", …} ----------------> |   or "pair" first if this computer is new
   | <--- {"ok":true} ----------------------- |
   | ---- any command … --------------------> |
```

### hello

Sent by the agent as soon as the connection opens:

```json
{"hello": 1, "nonce": "9f1c0e…(32 hex chars = 16 random bytes)", "addr": "127.0.0.1"}
```

`hello` is the protocol version. `nonce` is new for every connection; the `auth` MAC is computed over
its 16 **bytes** (hex-decoded), not over the hex string. `addr` is the address the agent is bound
to; it is always `127.0.0.1`.

### Before authentication

- Only `pair` and `auth` are accepted. Any other command → `{"error":"auth required"}`, then the
  connection is closed.
- 10 s without receiving data closes the connection.
- At most 8 connections at once (authenticated or not); more are closed as soon as they're accepted.

## 4. Keys and pairing

### The computer's secret

The computer keeps one random **32-byte secret per phone** (the reference client stores it in
`~/.config/scrcrappy/agent-<udid>.key`, mode 600, created on first use). Everything is derived from
it:

| Value | Definition | Sent? |
|---|---|---|
| `id` | hex of SHA-256(`"scrcrappy-id"` ‖ secret) | in every `auth` |
| `key` | SHA-256(`"scrcrappy-key"` ‖ secret), 32 bytes | never; both sides compute it |
| `code` | first 3 bytes of SHA-256(secret) as a big-endian integer, mod 1 000 000, as 6 digits with leading zeros | shown, never sent |
| `mac` | hex of HMAC-SHA256(`key`, nonce bytes) | in `auth` |

`‖` is byte concatenation; the prefixes are ASCII. Test vectors (also pinned in
`tests/test_client.py`) for secret = 31 zero bytes then `01`, nonce = 16 zero bytes:

```
id   5f89c743a17296e717fb3599210a10deb168f2fdc7874688ac9fa8a96a19afe3
key  8105f42425afb2b1dfe09ac447b965cc464c209efe5f05785bebdc6264b95bb5
code 485206
mac  4659c30f597d8c02fe307813b7c840df29bc9c37800a8b0f49fd3ac1f0f38b6a
```

### pair — first time on this phone

```json
{"cmd": "pair", "host": "chocobo", "secret": "<64 hex chars>"}
```

The phone shows **"Allow “chocobo” to control this iPhone?"** with the 6-digit `code`. Show the same
code on the computer so the user can compare them. The reply arrives when the user answers:

| Reply | Meaning |
|---|---|
| `{"ok":true}` | Allowed; the phone stored `id` and `key` (never the secret) |
| `{"error":"denied"}` | Deny tapped, or no answer within 30 s |
| `{"error":"busy"}` | Another pairing alert is already on screen; no second alert is shown |
| `{"error":"locked"}` | The phone is locked; no alert is shown. Unlock it and retry |
| `{"error":"bad host name"}` | `host` is empty or over 64 characters |
| `{"error":"bad secret"}` | `secret` isn't 64 hex characters |
| `{"error":"can't save host"}` | Allowed, but the hosts file couldn't be written |

The connection stays open but is **still unauthenticated**: open a new connection (fresh nonce) and
`auth`.

### auth — every connection

```json
{"cmd": "auth", "host": "chocobo", "id": "<id>", "mac": "<mac over this connection's nonce>"}
```

| Reply | Meaning |
|---|---|
| `{"ok":true}` | Authenticated; all commands below are now accepted |
| `{"error":"unknown host"}` | No paired computer has this `id` → `pair` first |
| `{"error":"bad mac"}` | Known `id`, wrong `mac` (wrong secret, or MAC not over this nonce) |

A failed `auth` closes the connection: one try per nonce. `host` is only used in the phone's log.

A typical client: connect, `auth`; on `unknown host`, connect again, `pair`, then connect again and
`auth`.

## 5. Commands (after `auth`)

Coordinates are **fractions of the portrait screen**: x 0 = left, 1 = right; y 0 = top, 1 = bottom,
with the phone held upright (Home button at the bottom) whatever the current orientation. The
computer never needs device units.

### touch — no reply

```json
{"cmd": "touch", "events": [{"finger": 1, "phase": "down", "x": 0.5, "y": 0.5}]}
```

- `finger` 1..10, `phase` `down` | `move` | `up`, `x` / `y` numbers (clamped to 0..1). `up` may omit `x` / `y`:
  the finger lifts where it was.
- All events in one command are delivered as **one multi-finger update**: a pinch step is one
  command with a `move` for each finger. If a command has several events for the *same* finger
  (a `down` and an `up`, say), they are applied in order, one update each, so a tap fits in one
  command.
- `down` on a finger that is already down counts as `move`. `move` or `up` on a finger that isn't
  down is ignored. Invalid events are dropped silently.
- Fingers a connection still holds down when it closes are lifted automatically. So are fingers it
  holds while it sends nothing for 10 s (the connection stays open): to hold longer, repeat a
  `move` now and then.
- **No reply, ever**, to keep latency low. To check where things stand, send `screen`: replies come
  in order, so its `fingers_down` reflects every earlier `touch`.
- After the phone boots, the agent needs to see **one real touch** on the screen before it can
  inject any (`screen` → `touch_ready: false`); until then touches are dropped. A respring doesn't
  reset this.

Examples — a tap, a drag, a two-finger pinch out:

```json
{"cmd":"touch","events":[{"finger":1,"phase":"down","x":0.14,"y":0.93}]}
{"cmd":"touch","events":[{"finger":1,"phase":"up","x":0.14,"y":0.93}]}

{"cmd":"touch","events":[{"finger":1,"phase":"down","x":0.8,"y":0.5}]}
{"cmd":"touch","events":[{"finger":1,"phase":"move","x":0.5,"y":0.5}]}
{"cmd":"touch","events":[{"finger":1,"phase":"up","x":0.2,"y":0.5}]}

{"cmd":"touch","events":[{"finger":1,"phase":"down","x":0.5,"y":0.45},{"finger":2,"phase":"down","x":0.5,"y":0.55}]}
{"cmd":"touch","events":[{"finger":1,"phase":"move","x":0.5,"y":0.3},{"finger":2,"phase":"move","x":0.5,"y":0.7}]}
{"cmd":"touch","events":[{"finger":1,"phase":"up","x":0.5,"y":0.3},{"finger":2,"phase":"up","x":0.5,"y":0.7}]}
```

Send moves at about the screen's rate (every ~16 ms); a 70–100 ms gap between `down` and `up` makes
a reliable tap.

### key — a key or a phone button

```json
{"cmd": "key", "usage": 42}
{"cmd": "key", "usage": 25, "modifiers": 8}
{"cmd": "key", "page": 12, "usage": 64}
```

Presses and releases one key → `{"ok":true}` | `{"error":"bad key"}` (page or usage not 1..0xFFFF,
modifiers not 0..255).

- `page` (optional, default 7): HID usage page. **7** = keyboard keys, **0x0C** = phone buttons.
- `usage`: HID usage on that page (USB HID Usage Tables). Keyboard usages are **key positions**, not
  characters: the phone turns them into characters with its own hardware-keyboard layout setting
  (Settings › General › Keyboard › Hardware Keyboard).
- `modifiers` (optional, default 0): held around the key. Bit 0 left Ctrl, 1 left Shift, 2 left
  Alt/Option, 3 left Cmd, 4–7 the right-hand Ctrl, Shift, Alt, Cmd.

Useful values:

| What | page | usage | modifiers |
|---|---|---|---|
| a … z | 7 | 0x04 … 0x1D | 0x02 for capitals |
| 1 … 9, 0 | 7 | 0x1E … 0x27 | |
| Return / Escape / Backspace / Tab / Space | 7 | 0x28 / 0x29 / 0x2A / 0x2B / 0x2C | |
| → ← ↓ ↑ | 7 | 0x4F / 0x50 / 0x51 / 0x52 | |
| Cmd+V / Cmd+C / Cmd+A | 7 | 0x19 / 0x06 / 0x04 | 0x08 |
| Home | 0x0C | 0x40 | |
| App switcher | 0x0C | 0x40 twice, ~0.15 s apart | |
| Lock (side/top button) | 0x0C | 0x30 | |
| Volume up / down | 0x0C | 0xE9 / 0xEA | |

The phone buttons were checked on an iPhone 8 (Home button); not yet on a Face ID iPhone.

### text — type any text

```json
{"cmd": "text", "text": "àèìòù ñ 😀"}
```

→ `{"ok":true}` | `{"error":"bad text"}` (not a string) | `{"error":"can't type"}`.

Puts the text on the phone's clipboard and sends Cmd+V to the focused field, so any Unicode works.
The text **stays on the clipboard** (the previous clipboard is not restored). iOS shows **"Allow
Paste"** for this paste because it doesn't come from a real keyboard, and changing the clipboard
again would dismiss that prompt. Setting the app's *Paste from Other Apps* to *Allow* (Settings ›
‹app›) stops the prompt for that app. For single key presses, `key` never prompts.

### clipboard_get / clipboard_set

```json
{"cmd": "clipboard_get"}
{"cmd": "clipboard_set", "text": "hello"}
```

- `clipboard_get` → `{"ok":true,"text":"…"}` (`""` if the clipboard holds no text) |
  `{"error":"clipboard timeout"}`. If another app put the text there, iOS asks on the phone before
  the agent may read it; the reply waits for that answer, **up to 30 s**, then times out.
- `clipboard_set` → `{"ok":true}` | `{"error":"bad text"}`. Never prompts.

### screen

```json
{"cmd": "screen"}
```

→

```json
{"ok": true, "width": 375, "height": 667, "scale": 2, "orientation": 1,
 "touch_ready": true, "fingers_down": 0}
```

- `width` / `height`: the screen in **portrait** points, whatever the orientation; × `scale` = pixels.
- `orientation`: the frontmost app's interface orientation — 1 portrait, 2 upside down,
  3 landscape right (Home button on the right), 4 landscape left (Home button on the left).
- `touch_ready`: whether `touch` works yet (see touch). `fingers_down`: fingers currently held, from
  all connections.

### screenshot

```json
{"cmd": "screenshot"}
```

→ `{"ok":true,"png":"<base64>"}` | `{"error":"screenshot failed"}`.

A lossless PNG of the screen at full resolution, including the real status bar. It is always the
panel's **portrait** shape (`width × scale` by `height × scale`, e.g. 750 × 1334). In landscape the
app's content is turned inside it: rotate the image **90° counter-clockwise** for orientation 3 and
**90° clockwise** for 4 to show it upright (180° for 2).

### apps — list the apps that can be opened

```json
{"cmd": "apps"}
```

→ `{"ok":true,"apps":[{"id":"com.apple.Preferences","name":"Settings","pid":412}, …]}`

Every app SpringBoard can open (like `frida-ps -Uai`), sorted by name: bundle identifier, display
name, and `pid` only while the app is running. No daemons or other non-app processes. A few system
apps without a home-screen icon are included (e.g. Siri, `com.apple.webapp`).

`apps` and `open` are new in agent 0.3.0; an older agent replies `{"error":"unknown command"}` to
both, so a computer can tell it needs updating. Reference client: `Agent.apps()` returns the list,
`Agent.open_app(id)` raises `AgentError` with the error string.

### open — bring an app to the front

```json
{"cmd": "open", "id": "com.apple.mobilenotes"}
```

→ `{"ok":true}` | `{"error":"unknown app"}` (not installed, or hidden) | `{"error":"locked"}` (iOS
won't open apps over the lock screen; unlock first) | `{"error":"open failed"}`.

Like tapping its icon: launches the app if needed. The reply comes once SpringBoard has started the
switch, before the app has finished drawing.

### open_url — open a URL or deeplink

```json
{"cmd": "open_url", "url": "https://example.com"}
```

→ `{"ok":true}` | `{"error":"bad url"}` (not a URL, or no scheme) | `{"error":"locked"}` |
`{"error":"open failed"}` (nothing handles it, or no answer in 5 s).

Like tapping a link: opens `https:`, `tel:`, `sms:`, `maps:`, app deeplinks, etc. in whatever app
handles the scheme. iOS blocks a few schemes for third parties (notably `prefs:` Settings deep
links), which come back as `open failed`; use `open` with `com.apple.Preferences` to open Settings
itself. Reference client: `Agent.open_url(url)`. New in agent 0.5.0.

### Anything else

An unknown `cmd` → `{"error":"unknown command"}`; a request without a string `cmd` →
`{"error":"missing cmd"}`. The connection stays open.

## 6. Example (Python, with the reference client)

```python
import socket
from client import agent_client as ac, usbmux

udid = next(iter(usbmux.devices()))
secret = ac.load_secret(udid)                 # created on first use
host = socket.gethostname()

a = ac.Agent.connect()                        # usbmuxd → 7330, reads hello
try:
    a.auth(host, secret)
except ac.AgentError:                         # "unknown host": pair once
    print("Code on the phone should be", ac.pairing_code(secret))
    ac.Agent.connect().pair(host, secret)     # waits for Allow / Deny
    a = ac.Agent.connect()
    a.auth(host, secret)

print(a.request({"cmd": "screen"}))
a.send({"cmd": "touch", "events": [{"finger": 1, "phase": "down", "x": 0.5, "y": 0.5}]})
a.send({"cmd": "touch", "events": [{"finger": 1, "phase": "up", "x": 0.5, "y": 0.5}]})
a.request({"cmd": "key", "page": 0x0C, "usage": 0x40})   # Home

for app in a.apps():                          # like frida-ps -Uai
    print(f"{app.get('pid', ''):>6}  {app['name']:<28} {app['id']}")
a.open_app("com.apple.mobilenotes")           # AgentError("locked") on the lock screen
```

## 7. On the phone

- Paired computers live in `/var/jb/var/mobile/Library/crappytouch/hosts.plist` (directory mode
  700, file mode 600, owner `mobile`): `{ id: {name, key} }`. **Revoke a computer** in Settings ›
  crappytouch › Paired Computers (swipe left): it is removed from the file and its open connections
  are closed. Deleting the file revokes all computers; they'll need to pair again.
- `touch.plist` in the same directory caches the touchscreen's ID for the current boot.
- The agent logs to the system log with the prefix `crappytouch:` (`idevicesyslog -m
  crappytouch`).
