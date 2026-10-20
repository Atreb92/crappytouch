# Review Fixes Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Add a per-computer revoke UI in Settings, fix three touch bugs, harden pairing prompts, and pin the build toolchain.

**Architecture:** Small edits to the existing tweak (`src/Pairing.m`, `src/Touch.m`, `src/Server.m`, `src/Auth.m`) plus one new Theos prefs-bundle target that edits `hosts.plist` through the same `Auth.m` and tells the tweak over a Darwin notification to drop live sessions of revoked computers. Tests are the phone conformance suite (`tests/test_conformance.py`, `-m phone`); there is no host-side ObjC test harness.

**Tech Stack:** Objective-C (Theos tweak, rootless, iOS 15+), PreferenceLoader/Preferences.framework, pytest + `client/agent_client.py`.

**Spec:** `docs/superpowers/specs/2026-10-20-review-fixes-design.md`

## Global Constraints

- Rootless Dopamine/ElleKit; `TARGET := iphone:clang:16.5:15.0`, `ARCHS := arm64 arm64e` (Makefile).
- No new dependency, no background process, no protocol additions; every behaviour change is written into `PROTOCOL.md`.
- Existing scrcrappy clients keep working: any message sequence valid today stays valid.
- `hosts.plist` stays `{ id: {name, key} }`, file mode 0600, dir mode 0700 (`Auth.m`).
- Constants: held-finger read timeout 10 s; pairing prompt timeout stays 30 s.
- Out of scope: review findings 4, 5, 8, 9, 10; concerns 1, 2, 5.
- Phone tests: run `.venv/bin/pytest -m phone -s -k <name>`; build/install with `make package install` (needs a real terminal, see `scripts/install.sh`). Default `pytest` (host-only) must still pass.

## Review Focus

- A `touch` message with down for finger 1 and down for finger 2 is still one HID event (the same-finger split must not split different fingers).
- An `up` for a finger that isn't down, with or without coordinates, is ignored and doesn't crash or disturb other fingers.
- Host names with `\n`, `\t`, `\x7f` are all refused with `bad host name`; ordinary names with spaces/Unicode still pair.
- `hosts.plist` missing or empty: the Settings list shows "No computers paired", and removing an unknown id returns NO without writing.
- Revoking a computer that has two live connections closes both, and leaves other computers' connections open.

---

### Task 1: Pairing hardening (control characters, late Allow)

**Files:**
- Modify: `src/Server.m:139` (name validation)
- Modify: `src/Pairing.m:74-81` (late Allow)
- Test: `tests/test_conformance.py` (after `test_pair_deny`)

**Interfaces:**
- Consumes: none.
- Produces: `pair` with a name containing any `NSCharacterSet.controlCharacterSet` member returns `{"error":"bad host name"}` with no prompt shown.

- [ ] **Step 1: Write the failing test** `test_pair_name_with_control_chars_refused` in `tests/test_conformance.py`: for each of `"evil\nCode 000000 matches"`, `"tab\there"`, `"del\x7f"`, `connect().pair(HOST + name, secrets.token_bytes(32))` raises `ac.AgentError` matching `bad host name` (no tap needed). Also `test_pair_name_with_space_and_unicode_is_prompted` is NOT added (needs a tap; covered by the existing `test_pair_allow_then_auth_ok`, whose `HOST` may contain spaces).
- [ ] **Step 2: Run it, expect FAIL** (agent currently shows a prompt / times out): `.venv/bin/pytest -m phone -s -k control_chars`
- [ ] **Step 3: Implement** in `Server.m`'s `pair` branch: add `|| [name rangeOfCharacterFromSet:NSCharacterSet.controlCharacterSet].location != NSNotFound` to the existing `bad host name` condition.
- [ ] **Step 4: Late Allow.** In `CTPair` (`Pairing.m`), declare `__block BOOL allowedFinal`, set `allowedFinal = allowed;` inside the second `dispatch_sync` block right after `decided = YES;`, and use `allowedFinal` instead of `allowed` in the `error` expression. No automated test: the window is milliseconds wide (the alert is dismissed on timeout), so it is covered by review only.
- [ ] **Step 5: Build, install, run** `.venv/bin/pytest -m phone -s -k "control_chars or pair"` (tap Deny/Allow as prompted). Expected: PASS.
- [ ] **Step 6: Commit** `git commit -m "Pairing: reject control chars in host names; a late Allow tap pairs nothing"` (include the attribution line).

---

### Task 2: Touch fixes

**Files:**
- Modify: `src/Touch.m:106-135` (`CTTouch`)
- Modify: `src/Server.m` (`ReadExact`, `ReadFrame`, post-auth loop at ~149-162, `SetReadTimeout`)
- Modify: `PROTOCOL.md` (touch section ~139-170)
- Test: `tests/test_conformance.py` (after `test_touch_no_reply_and_connection_stays_usable`)

**Interfaces:**
- Consumes: none.
- Produces: `static NSDictionary *ReadFrame(int fd, uint32_t max, BOOL *idle)` in `Server.m`: `*idle` is set YES only when the read timed out with zero bytes of the 4-byte length read (return value nil); a timeout mid-frame still means close.

- [ ] **Step 1: Write failing tests** (finger 3, x=0.98 y=0.5, the harmless corner used by existing touch tests):
  - `test_touch_up_without_coordinates_releases`: send `down` (finger 3, with x/y), then `{"finger":3,"phase":"up"}` (no x/y), `agent.request({"cmd":"screen"})["fingers_down"] == 0`.
  - `test_held_finger_released_after_silence`: send `down` finger 3, `time.sleep(12)`, then `agent.request({"cmd":"screen"})` succeeds (connection still open) and `["fingers_down"] == 0`.
  - `test_down_and_up_in_one_message_leaves_nothing_down`: one message `[down, up]` for finger 3 → `fingers_down == 0` (guards the split from leaving state wrong; the lost-tap symptom itself is checked manually in Step 7).
- [ ] **Step 2: Run, expect the first two to FAIL** (`fingers_down == 1`): `.venv/bin/pytest -m phone -s -k "without_coordinates or after_silence or one_message"`
- [ ] **Step 3: `CTTouch` same-finger split.** In the event loop, before applying an event for finger `i` where `masks[i] != 0`, call `Dispatch(masks)` and zero `masks` (`any` stays tracked). Different fingers in one message must still produce one `Dispatch`.
- [ ] **Step 4: `up` without coordinates.** Require valid `x`/`y` only for `down`/`move`; for `up` use `Fraction()` results only if not NaN, otherwise keep `fingers[i].x/y`. An `up` for a finger not down remains ignored.
- [ ] **Step 5: Stalled client.** Change `ReadExact`/`ReadFrame` per the Interfaces block (timeout = `errno` `EAGAIN`/`EWOULDBLOCK` with `got == 0` at the length prefix). In the post-auth loop set `SetReadTimeout(fd, held.count ? HELD_TIMEOUT_S : 0)` before each read (`#define HELD_TIMEOUT_S 10`); when `idle` is YES, call `CTTouchRelease(held)` and continue the loop instead of returning. Also set `SO_SNDTIMEO` to 10 s after auth so a client that stops reading can't block the thread forever (add `SetWriteTimeout` next to `SetReadTimeout`).
- [ ] **Step 6: `PROTOCOL.md`:** in the touch section, document: `up` may omit `x`/`y`; several events for one finger in a message are applied in order; with a finger held and no message for 10 s the agent lifts all held fingers (send a `move` periodically to hold longer). Section 7 is updated in Task 5.
- [ ] **Step 7: Build, install, run** the three tests above plus `-k touch` — expected PASS. Manual: open Settings on the phone and, with a small script using `Agent.send`, send a single message `[down, up]` on a visible row; expect the row to open (the pre-fix behaviour loses the tap).
- [ ] **Step 8: Commit** `git commit -m "Touch: same-finger events keep order, up needs no coordinates, held fingers lift after 10 s of silence"` (include the attribution line).

---

### Task 3: Pin Theos, toolchain and SDK

**Files:**
- Modify: `scripts/setup-theos.sh`

**Interfaces:**
- Consumes/Produces: none. Pins are variables at the top of the script: `THEOS_REV`, `TOOLCHAIN_TAG`, `TOOLCHAIN_SHA256_x86_64`, `TOOLCHAIN_SHA256_aarch64`, `SDKS_REV`.

- [ ] **Step 1: Collect known-good values** from the setup that builds the shipped `.deb`: `git -C ~/theos rev-parse HEAD` and `git -C ~/theos/sdks rev-parse HEAD` (if `sdks` is a separate checkout; otherwise find how `install-sdk` fetches and pin that source), and for the toolchain the release tag whose `iOSToolchain-$ARCH.tar.xz` yields the same `clang --version` as the installed one; compute its `sha256sum`. If the installed toolchain's tag can't be identified, take the current latest tag, build the repo once with it, and pin that.
- [ ] **Step 2: Edit the script:** after clone, `git -C "$THEOS" checkout "$THEOS_REV" && git -C "$THEOS" submodule update --init --recursive`; download the tagged URL to a temp file in `$THEOS/toolchain`, `echo "$sha  file" | sha256sum -c -` (abort on mismatch) before `tar -xJf`; pass the pinned SDK revision to `install-sdk` (env or checkout, per what Step 1 found).
- [ ] **Step 3: Verify.** `sh -n scripts/setup-theos.sh`. Then in a scratch dir run `THEOS=$SCRATCH/theos scripts/setup-theos.sh` and expect `ok: export THEOS=...`. Then change one hex digit of a pinned hash in a copy and expect the copy to abort with a checksum failure and no extracted toolchain.
- [ ] **Step 4: Commit** `git commit -m "setup-theos: pin Theos, toolchain (sha256) and SDK"` (include the attribution line).

---

### Task 4: Revoke core: host list/remove and dropping live sessions

**Files:**
- Modify: `src/Auth.h`, `src/Auth.m`
- Modify: `src/Server.m` (`ServeClient`, `CTServerStart`)
- Test: `tests/test_conformance.py`

**Interfaces:**
- Consumes: none.
- Produces (in `Auth.h`, used by the prefs bundle in Task 5):
  - `NSArray<NSDictionary *> *CTAuthListHosts(void);` — `@[@{@"id": NSString, @"name": NSString}, ...]` sorted by name; `@[]` if the file is missing or unreadable.
  - `BOOL CTAuthRemoveHost(NSString *hostID);` — NO (and no write) if the id isn't present or the write fails; YES after rewriting `hosts.plist` at mode 0600 without it.
  - `#define CT_REVOKED_NOTIFICATION "com.atreb92.crappytouch.revoked"` (Darwin notification name).

- [ ] **Step 1: Write the failing test** `test_revoked_host_is_disconnected_and_refused` (phone, manual, `-s`): pair a fresh secret as `HOST + "-revoke-test"` (prompt: tap Allow), keep two authenticated connections open, print `>>> In Settings > crappytouch swipe-delete "<name>" and confirm`, poll up to 90 s until both sockets read EOF (`closed()` helper), then assert `connect().auth(name, secret)` raises `ac.AgentError` matching `unknown host`, and that a connection authenticated as `HOST` (the normal `secret` fixture) is still usable (`screen` request succeeds).
- [ ] **Step 2: Implement `CTAuthListHosts` and `CTAuthRemoveHost`** in `Auth.m`, reusing `HostsPath()` and the write/chmod sequence from `CTAuthAddHost` (factor the write into one static helper used by both).
- [ ] **Step 3: Track live sessions in `Server.m`.** A `static NSMutableDictionary<NSNumber *, NSString *> *live` (fd → host id) guarded by `@synchronized(live)`; add after auth succeeds, remove in the `@finally` of the post-auth loop. In `CTServerStart` register a Darwin observer (`CFNotificationCenterGetDarwinNotifyCenter`, name `CT_REVOKED_NOTIFICATION`) whose handler collects ids from `CTAuthListHosts()` and calls `shutdown(fd, SHUT_RDWR)` for every live fd whose host id is no longer present. `shutdown` makes the connection thread's read fail, which already runs the held-finger release and awake bookkeeping.
- [ ] **Step 4: Build and install; Task 5's UI is needed to run the test end to end,** so for now check with a temporary manual removal: `ssh` in, delete one entry from `hosts.plist`, `notifyutil -p com.atreb92.crappytouch.revoked`, and expect both connections of that host to close while another host's stays open.
- [ ] **Step 5: Commit** `git commit -m "Auth: list/remove hosts; Server drops live sessions of revoked hosts"` (include the attribution line).

---

### Task 5: Prefs bundle: Paired Computers list with swipe-to-revoke

**Files:**
- Create: `crappytouchprefs/Makefile`, `crappytouchprefs/Resources/Info.plist`, `crappytouchprefs/Resources/Root.plist`, `crappytouchprefs/CTRootListController.h`, `crappytouchprefs/CTRootListController.m`
- Modify: `Makefile` (add the subproject), `layout/Library/PreferenceLoader/Preferences/crappytouch.plist`, `PROTOCOL.md` (section 7), `README.md` (revoke instructions if the README mentions deleting `hosts.plist`)
- Test: `tests/test_conformance.py::test_revoked_host_is_disconnected_and_refused` (from Task 4)

**Interfaces:**
- Consumes: `CTAuthListHosts`, `CTAuthRemoveHost`, `CT_REVOKED_NOTIFICATION` from Task 4.
- Produces: `@interface CTRootListController : PSListController` (bundle `crappytouchprefs`, installed to the rootless PreferenceBundles directory by Theos's `bundle.mk`).

- [ ] **Step 1: Bundle skeleton.** `crappytouchprefs/Makefile`: `BUNDLE_NAME = crappytouchprefs`, `crappytouchprefs_FILES = CTRootListController.m ../src/Auth.m`, `crappytouchprefs_FRAMEWORKS = UIKit Security`, `crappytouchprefs_PRIVATE_FRAMEWORKS = Preferences`, `crappytouchprefs_INSTALL_PATH = /Library/PreferenceBundles`, `-fobjc-arc`, same `TARGET`/`ARCHS`/scheme as the top-level Makefile (include `$(THEOS_MAKE_PATH)/bundle.mk`). Top-level `Makefile`: `SUBPROJECTS += crappytouchprefs` and `include $(THEOS_MAKE_PATH)/aggregate.mk` after `tweak.mk`. `Info.plist` sets `CFBundleIdentifier com.atreb92.crappytouchprefs` and `NSPrincipalClass CTRootListController`.
- [ ] **Step 2: `Root.plist`** (Preferences specifier format): the existing Keep Awake group/switch moved here unchanged (same `defaults` `com.atreb92.crappytouch`, key `keepAwake`, `PostNotification com.atreb92.crappytouch.prefs`, footer text), then an empty `PSGroupCell` "Paired Computers" whose specifiers are built in code.
- [ ] **Step 3: `CTRootListController`** `-specifiers`: load `Root.plist` via `[self loadSpecifiersFromPlistName:@"Root" target:self]`, then append one `PSSpecifier` per `CTAuthListHosts()` entry (label = name, `cell` `PSTitleValueCell`, host id stored as a specifier property `hostID`), or footer text "No computers paired" when the list is empty. Enable swipe-to-delete (`tableView:canEditRowAtIndexPath:` true only for host rows, `commitEditingStyle:`): present a `UIAlertController` "Revoke “name”?" / "It will need to be paired again." with Revoke (destructive) and Cancel; on Revoke call `CTAuthRemoveHost(id)`; if YES post the Darwin notification (`CFNotificationCenterPostNotification` on the Darwin center) and reload specifiers; if NO show an error alert "Couldn't revoke". Host names are shown via `specifier.name` only (never interpolated into format strings).
- [ ] **Step 4: Link from PreferenceLoader.** Replace the plist body with an `entry` dict: `bundle crappytouchprefs`, `cell PSLinkCell`, `detail CTRootListController`, `label crappytouch`, `icon crappytouch.png`, keeping the `Filter` behaviour of the tweak's own plist untouched (that file is `crappytouch.plist` at the repo root, not this one). Remove the `items` array from the PreferenceLoader plist (now in `Root.plist`).
- [ ] **Step 5: Sandbox check (spec: must verify first).** Build and install, open Settings → crappytouch, and confirm the paired list renders (read works). Revoke the throwaway host from Task 4's test. If the Preferences app can't read or write `hosts.plist` (empty list when paired hosts exist, or "Couldn't revoke"), apply the smallest fallback: the tweak performs the removal (bundle posts a request notification per action, with the host id passed through a small request file in a directory the Preferences app can write), and record the fallback in the spec's "File access" paragraph. Expected without fallback: works.
- [ ] **Step 6: Run** `.venv/bin/pytest -m phone -s -k revoked` and follow the prompts. Expected PASS. Also run the full `.venv/bin/pytest -m phone -s` and default `.venv/bin/pytest`.
- [ ] **Step 7: Docs.** `PROTOCOL.md` section 7: replace "Revoke all computers by deleting that file" with "Revoke a computer in Settings › crappytouch › Paired Computers (swipe left); deleting the file still revokes all." Note that revoking also disconnects its live sessions. Update the README if it documents the old manual step.
- [ ] **Step 8: Commit** `git commit -m "Settings: Paired Computers list with swipe-to-revoke"` (include the attribution line).

---

## Self-review notes

- Spec coverage: Goal 1 → Tasks 4–5; Goal 2 → Task 2; Goal 3 (control chars, late Allow) → Task 1; Goal 4 → Task 3. Non-goals untouched.
- `ReadFrame(..., BOOL *idle)` is defined in Task 2 and is the only signature change; every other caller in `Server.m` (pre-auth loop) passes `NULL`.
- Release/version bump and republishing `repo/` (`scripts/mkrepo.sh`) are deliberately not in this plan.
