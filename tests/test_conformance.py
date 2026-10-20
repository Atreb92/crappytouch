"""Conformance suite: runs against the real agent on the USB-connected iPhone.

    .venv/bin/pytest -m phone -s        (-s: some tests ask you to tap Allow / Deny on the phone)

Tests run in file order: the pairing tests approve this computer, later tests rely on that.
"""
import base64
import secrets
import socket
import struct
import time

import pytest

from client import agent_client as ac
from client import usbmux

pytestmark = pytest.mark.phone
HOST = socket.gethostname()


@pytest.fixture(scope="module")
def udid():
    devices = usbmux.devices()
    if not devices:
        pytest.skip("no iPhone over USB")
    return next(iter(devices))


@pytest.fixture(scope="module")
def secret(udid):
    return ac.load_secret(udid)


def connect() -> ac.Agent:
    return ac.Agent.connect()


def closed(sock: socket.socket) -> bool:
    sock.settimeout(3)
    try:
        return sock.recv(1) == b""
    except (ConnectionResetError, socket.timeout):
        return True


# --- Task 3: server and auth gate

def test_hello_has_nonce_and_loopback_address():
    a = connect()
    assert a.hello["hello"] == 1
    assert len(a.hello["nonce"]) == 32 and int(a.hello["nonce"], 16) >= 0
    assert a.hello["addr"] == "127.0.0.1"
    a.close()


def test_command_before_auth_refused_and_closed():
    a = connect()
    with pytest.raises(ac.AgentError, match="auth required"):
        a.request({"cmd": "screen"})
    assert closed(a.sock)


def test_garbage_closes_connection():
    a = connect()
    a.sock.sendall(struct.pack(">I", 5) + b"nope!")
    assert closed(a.sock)


def test_huge_length_closes_connection():
    a = connect()
    a.sock.sendall(struct.pack(">I", 0x7FFFFFFF))
    assert closed(a.sock)


def test_unknown_host_refused():
    a = connect()
    with pytest.raises(ac.AgentError, match="unknown host"):
        a.auth(HOST, secrets.token_bytes(32))


# --- Task 4: pairing (taps on the phone)

def test_pair_deny():
    s = secrets.token_bytes(32)
    print(f"\n>>> On the phone: tap DENY (code {ac.pairing_code(s)})")
    a = connect()
    with pytest.raises(ac.AgentError, match="denied"):
        a.pair(HOST + "-deny-test", s)


def test_second_pair_while_pending_is_busy():
    s1, s2 = secrets.token_bytes(32), secrets.token_bytes(32)
    print(f"\n>>> On the phone: an alert appears (code {ac.pairing_code(s1)}): tap DENY")
    a1, a2 = connect(), connect()
    a1.sock.sendall(ac.encode_frame({"cmd": "pair", "host": HOST + "-busy-1", "secret": s1.hex()}))
    time.sleep(1)
    with pytest.raises(ac.AgentError, match="busy"):
        a2.pair(HOST + "-busy-2", s2)
    with pytest.raises(ac.AgentError, match="denied"):
        if "error" in (reply := ac.read_frame(a1.sock.recv)):
            raise ac.AgentError(reply["error"])


def test_pair_allow_then_auth_ok(secret):
    a = connect()
    try:
        a.auth(HOST, secret)
        return  # already paired from an earlier run
    except ac.AgentError:
        pass
    print(f"\n>>> On the phone: tap ALLOW (code {ac.pairing_code(secret)})")
    connect().pair(HOST, secret)
    connect().auth(HOST, secret)


def test_bad_mac_refused(secret):
    a = connect()
    msg = ac.auth_message(HOST, secret, a.nonce)
    msg["mac"] = "00" * 32
    with pytest.raises(ac.AgentError, match="bad mac"):
        a.request(msg)


# --- authenticated features

@pytest.fixture
def agent(secret):
    a = connect()
    a.auth(HOST, secret)
    yield a
    a.close()


def test_screen_info_shape(agent):  # Task 7 (and touch_ready / fingers_down for Task 5)
    r = agent.request({"cmd": "screen"})
    assert r["width"] > 0 and r["height"] > 0 and r["scale"] >= 1
    assert r["orientation"] in (1, 2, 3, 4)
    assert isinstance(r["touch_ready"], bool) and r["fingers_down"] == 0


def test_touch_no_reply_and_connection_stays_usable(agent):  # Task 5
    # bottom-right corner of the screen (status/home-indicator free area on most screens): harmless
    for phase in ("down", "up"):
        agent.send({"cmd": "touch", "events": [{"finger": 1, "phase": phase, "x": 0.98, "y": 0.5}]})
    assert agent.request({"cmd": "screen"})["fingers_down"] == 0


def test_disconnect_releases_fingers(secret):  # Task 5
    a = connect()
    a.auth(HOST, secret)
    a.send({"cmd": "touch", "events": [{"finger": 2, "phase": "down", "x": 0.98, "y": 0.5}]})
    time.sleep(0.2)
    a.close()
    time.sleep(0.5)
    b = connect()
    b.auth(HOST, secret)
    assert b.request({"cmd": "screen"})["fingers_down"] == 0


def test_clipboard_roundtrip(agent):  # Task 6
    agent.request({"cmd": "clipboard_set", "text": "scrcrappy è😀"})
    assert agent.request({"cmd": "clipboard_get"})["text"] == "scrcrappy è😀"


def test_text_leaves_text_on_clipboard(agent):  # Task 6: restoring would dismiss iOS's "Allow Paste" prompt
    agent.request({"cmd": "text", "text": "x"})
    assert agent.request({"cmd": "clipboard_get"})["text"] == "x"


def test_key_returns_ok(agent):  # Task 6
    assert agent.request({"cmd": "key", "usage": 0xE1, "modifiers": 0})["ok"] is True  # left shift: no effect


def test_key_bad_page_refused(agent):  # buttons use page 0x0C; out-of-range pages are refused
    with pytest.raises(ac.AgentError, match="bad key"):
        agent.request({"cmd": "key", "page": 0x10000, "usage": 0x40})


def test_screenshot_is_png_of_screen_size(agent):  # Task 7
    info = agent.request({"cmd": "screen"})
    png = base64.b64decode(agent.request({"cmd": "screenshot"})["png"])
    assert png[:8] == b"\x89PNG\r\n\x1a\n"
    w, h = struct.unpack(">II", png[16:24])
    expected = {(info["width"] * info["scale"], info["height"] * info["scale"]),
                (info["height"] * info["scale"], info["width"] * info["scale"])}
    assert (w, h) in expected


# --- Task 9: list and open apps

def test_apps_lists_settings(agent):
    apps = agent.apps()
    ids = [a["id"] for a in apps]
    assert len(ids) == len(set(ids))
    settings = next(a for a in apps if a["id"] == "com.apple.Preferences")
    assert settings["name"]
    assert all(isinstance(a.get("pid", 1), int) for a in apps)


def test_open_unknown_app_errors(agent):
    with pytest.raises(ac.AgentError, match="unknown app"):
        agent.open_app("com.example.not-installed")


def test_open_url_bad_errors(agent):
    with pytest.raises(ac.AgentError, match="bad url"):
        agent.open_url("not a url")


def test_open_url_returns_ok(agent):  # manual: Safari opens the page
    agent.open_url("https://example.com")


def test_open_settings_runs_it(agent):
    agent.open_app("com.apple.Preferences")
    time.sleep(2)
    settings = next(a for a in agent.apps() if a["id"] == "com.apple.Preferences")
    assert settings.get("pid", 0) > 0


@pytest.mark.locked
def test_open_while_locked_says_locked(agent, request):
    if "locked" not in request.config.getoption("markexpr"):
        pytest.skip("manual: lock the phone, then run with -m locked")
    with pytest.raises(ac.AgentError, match="locked"):
        agent.open_app("com.apple.Preferences")


# --- keep awake while connected (Settings › scrcrappy-agent)

@pytest.mark.awake
def test_keep_awake_while_connected(agent, request):
    if "awake" not in request.config.getoption("markexpr"):
        pytest.skip("manual: Auto-Lock 30 s, switch on, phone unlocked, then run with -m awake")
    time.sleep(45)  # past Auto-Lock, without touching the phone
    agent.open_app("com.apple.Preferences")  # "locked" if the phone locked meanwhile
