# Review fixes: revoke UI, touch robustness, pairing hardening, pinned toolchain

Date: 2026-10-20. Source: an external review of the repo (no malware found; a list of robustness and
hardening gaps). This round covers review findings 1, 2, 3, 6, 7 and concerns 3 and 4. The rest are
explicitly deferred (see Non-goals).

## Intent

crappytouch is a SpringBoard tweak that lets one trusted computer (scrcrappy) drive the phone over
127.0.0.1:7330. The tweak is fine for that purpose, but today a user cannot take access back, a flaky
computer can leave the screen stuck pressed, and a local app can nag the user with pairing prompts.
The goal is to make the tweak safe to leave installed: the user can always revoke a computer, the
screen can't get stuck, and pairing prompts can't be spammed or spoofed with fake text.

## Goals

1. **Revoke UI.** Settings → crappytouch lists every paired computer by name. Swipe to delete (with a
   confirmation); a revoked computer is disconnected immediately and can't log in again.
2. **Touch fixes** (review 1, 2, 3):
   - A single `touch` message may contain a down and an up (or up then down) for the same finger;
     each is delivered as its own HID event in order. No lost taps, no up-then-down turned into a drag.
   - An `up` without `x`/`y` releases the finger at its last position instead of being dropped.
   - A computer that goes silent or stalls while a finger is held does not leave the screen pressed.
3. **Pairing hardening** (review 6, 7):
   - Computer names containing control characters (newline etc.) are rejected, so a name can't forge
     extra lines in the alert.
   - A tap on Allow that arrives after the 30 s timeout does not pair the computer.
4. **Pinned build setup** (concern 4): `scripts/setup-theos.sh` installs fixed, checksummed versions.

## Non-goals

- Review 4 (connection-slot exhaustion before login), 5 (no cooldown after Deny; dropped by the user), 8 (clipboard queue), 9 (screenshot memory),
  10 (`CTClipboardSet` doc/thread). Deferred.
- Concern 1/2 (fake prompts from local apps, power of a paired computer) and concern 5 (`install.sh`
  trusts the phone SSH key on first use). Accepted/documented, not changed.
- Per-computer permissions, an audit log, or renaming computers.

## Anti-goals

- Revoke must not require touching files over SSH.
- A touch-protocol change that breaks existing scrcrappy clients. All changes are
  backward-compatible: any message sequence valid today stays valid and means the same thing, except
  where today's behaviour is the bug.
- No new dependency or background process.

## Design

### 1. Revoke

- **New Theos `bundle` target** (`crappytouchprefs`, a `PSListController` subclass), installed under the
  rootless PreferenceBundles path. The existing PreferenceLoader entry
  (`layout/Library/PreferenceLoader/Preferences/crappytouch.plist`) becomes a link to the bundle.
  The bundle's `Root.plist` keeps the existing Keep Awake switch (same defaults domain and
  notification, so behaviour is unchanged) and adds a "Paired Computers" group.
- **List:** one row per entry in `hosts.plist`, showing `name`. Empty state: footer text "No computers
  paired". Swipe-to-delete → confirm alert ("Revoke “name”? It will need to be paired again.") →
  remove the entry, rewrite `hosts.plist` (mode 0600, same as `CTAuthAddHost`), post the Darwin
  notification `com.atreb92.crappytouch.revoked`.
- **File access:** the bundle edits `hosts.plist` directly (via the same path as `CTStatePath`; the
  directory is `$ROOT/var/mobile/Library/crappytouch`, owned by mobile). Revoke logic lives in
  `Auth.m` (`CTAuthListHosts`, `CTAuthRemoveHost`) and is compiled into both the tweak and the bundle,
  so the plist format stays defined in one place.
  **Must be verified on a device first:** that the Preferences app can read/write that file. If the
  sandbox forbids it, fall back to the tweak performing the removal: the bundle posts one Darwin
  notification per removal request via a small request file the sandbox does allow, or the list/remove
  runs behind a distinct notification name per action. The builder picks the smallest working fallback
  and records it here.
- **Tweak side:** `Auth` already re-reads `hosts.plist` on every login, so a revoked computer can't log
  in again with no further work. For live sessions, `Server` records each authenticated connection's
  host id (the `id` from the `auth` message) and, on the `revoked` notification, re-reads
  `hosts.plist` and `shutdown()`s every connection whose id is gone (same teardown path as a client
  disconnect, so held fingers are released and the awake counter is balanced).
- **Pairing a new computer** is unchanged.

### 2. Touch

All in `src/Touch.m` `CTTouch` and `src/Server.m`.

- **Same finger twice in one message:** process events in order; when an event targets a finger that
  already has bits in the pending `masks` array, `Dispatch(masks)` first and clear it, then apply the
  event. A message with N events for N different fingers is still one HID event.
- **Up without coordinates:** `x`/`y` are required for `down` and `move` only; for `up` a missing or
  invalid value keeps the finger's last `x`/`y`.
- **Stalled computer while held:** while `held` is non-empty the read has a timeout (default 10 s,
  *design call*, one constant). On timeout, release all held fingers (`CTTouchRelease`) and carry on
  reading. This costs a long press that sends nothing for 10 s; clients must repeat a `move` to hold
  longer. Document this in `PROTOCOL.md`. Writes get a send timeout (`SO_SNDTIMEO`, same order of
  magnitude) so a computer that stops reading can't block the connection thread indefinitely.
  Idle connections with no fingers down keep no timeout, as now.
  `ReadFrame` must distinguish "timed out" from "closed/bad frame" for this.

### 3. Pairing

All in `src/Pairing.m` and the `pair` branch of `src/Server.m`.

- **Control characters:** `Server.m` rejects names with any `NSCharacterSet.controlCharacterSet`
  member (plus the existing empty / over-64 checks) with `bad host name`. One check covers the alert
  and the Revoke list, which show the same name.
- **Late Allow:** in `CTPair`, read `allowed` into a local inside the second `dispatch_sync` block,
  after setting `decided = YES`, and use that local at line 81. This closes the window where a tap
  runs between the semaphore timeout and the cleanup block.

### 4. Pinned setup

`scripts/setup-theos.sh`:
- Theos: `git checkout <sha>` after clone/fetch, with `--recurse-submodules` update.
- Toolchain: download a specific release tag (not `latest`), verify `sha256sum -c` before extracting.
  One hash per supported arch (`x86_64`, `aarch64`).
- SDK: pin the theos/sdks revision used by `install-sdk`.
- Pins are a few variables at the top of the script. The values are taken from the setup that currently
  builds the shipped `.deb`, so they are known to work.

## Constraints

- Rootless Dopamine/ElleKit setup, iOS 15+, arm64/arm64e (see Makefile). No private-API surface added
  beyond what the tweak already uses.
- There are no protocol additions; `PROTOCOL.md` is updated with every behaviour change (the held-finger
  timeout).
- `tests/` (pytest conformance and client tests) must keep passing; add cases there for the protocol
  changes that are testable without a phone (control-character name, up without coordinates). Touch delivery, revoke UI and the pairing race are verified on a device.

## Left to the builder

- Prefs-bundle layout, strings, and exact `Root.plist` shape.
- Whether the sandbox fallback in "File access" is needed, and which one.
- Exact timeout constants (defaults above).
- Order of work. Suggested: pairing fixes (control chars, late Allow) → touch fixes → pinning → revoke (largest, needs a device).
