# scrcrappy-agent protocol v1

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

## Host keys

- State dir `/var/jb/var/mobile/Library/scrcrappy-agent/` (mode 700, owner mobile): `hosts.plist` = { id: {name, key} } with id = hex SHA-256("scrcrappy-id" + secret) and key = SHA-256("scrcrappy-key" + secret) — distinct, so the id sent in `auth` never reveals the HMAC key.
