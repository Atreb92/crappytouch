# scrcrappy-agent protocol v1

- Frame: 4-byte big-endian length + UTF-8 JSON object. Max 16 MiB.
- Agent → on connect: `{"hello": 1, "nonce": "<32 hex>", "addr": "127.0.0.1"}` (`addr` = the address the agent is bound to).
- Before auth: frames over 64 KiB, or 10 s without data, close the connection. At most 8 connections at once; more are closed on accept.
- `{"cmd":"auth","host":"<name>","id":"<hex id>","mac":"<hex HMAC-SHA256(key, nonce bytes)>"}` (id / key derived as in Global Constraints) → `{"ok":true}` | `{"error":"unknown host"}` | `{"error":"bad mac"}`; a failed auth closes the connection (one try per nonce).
- `{"cmd":"pair","host":"<name>","secret":"<64 hex>"}` → alert "Allow ‹name› to control this iPhone? Code ‹code›"; `code` = first 3 bytes of sha256(secret) as int % 1 000 000, zero-padded 6 digits → `{"ok":true}` | `{"error":"denied"}` (Deny or 30 s) | `{"error":"busy"}` (another pairing pending) | `{"error":"locked"}` (phone locked: unlock it first, no alert is shown) | `{"error":"bad host name"}` (empty or over 64 chars) | `{"error":"bad secret"}`. The connection stays open; authenticate on a new one.
- After auth only:
  - `{"cmd":"touch","events":[{"finger":1..10,"phase":"down|move|up","x":0..1,"y":0..1}]}` — **no reply** (latency). Events in one command are one multi-finger update. `down` on a finger already down = `move`; `move`/`up` on a finger not down are ignored; x/y are clamped to 0..1; invalid events are dropped. Fingers a connection still holds when it closes are lifted. Until the agent has seen one real touch since boot (`touch_ready: false`), touches are dropped.
  - `{"cmd":"key","usage":<HID usage>,"modifiers":<bits>}` — press+release, reply `{"ok":true}` | `{"error":"bad key"}` (usage not 1..0xFFFF, modifiers not 0..255). `modifiers` is the HID modifier byte (bit 0 left Ctrl, 1 left Shift, 2 left Alt, 3 left Cmd, 4–7 right Ctrl/Shift/Alt/Cmd), held around the key; optional, default 0.
  - `{"cmd":"text","text":"…"}` — pasteboard set + Cmd+V → `{"ok":true}`. The text stays on the pasteboard (the previous one is not restored): iOS 16 shows "Allow Paste" for an injected paste, and changing the pasteboard would dismiss it. Settings › ‹app› › Paste from Other Apps › Allow stops the prompt for that app.
  - `{"cmd":"clipboard_get"}` → `{"ok":true,"text":"…"}` | `{"error":"clipboard timeout"}` (not readable within 30 s, e.g. iOS is waiting on a paste permission); `{"cmd":"clipboard_set","text":"…"}` → `{"ok":true}`.
  - `{"cmd":"screen"}` → `{"ok":true,"width":<points>,"height":<points>,"scale":<n>,"orientation":<UIInterfaceOrientation>,"touch_ready":<bool>,"fingers_down":<n>}`.
  - `{"cmd":"screenshot"}` → `{"ok":true,"png":"<base64>"}`.
  - Unknown command → `{"error":"unknown command"}`.
  - Any command before auth → `{"error":"auth required"}` and connection closed.
- Coordinates are fractions of the portrait screen (0..1), so the host never needs device units.

## Host keys

- State dir `/var/jb/var/mobile/Library/scrcrappy-agent/` (mode 700, owner mobile): `hosts.plist` = { id: {name, key} } with id = hex SHA-256("scrcrappy-id" + secret) and key = SHA-256("scrcrappy-key" + secret) — distinct, so the id sent in `auth` never reveals the HMAC key.
