import io

import pytest

from client import agent_client as ac


def test_frame_roundtrip():
    buf = io.BytesIO(ac.encode_frame({"cmd": "screen", "x": "è😀"}))
    assert ac.read_frame(buf.read) == {"cmd": "screen", "x": "è😀"}


def test_rejects_oversized_frame():
    data = (ac.MAX_FRAME + 1).to_bytes(4, "big") + b"{}"
    with pytest.raises(ValueError, match="too large"):
        ac.read_frame(io.BytesIO(data).read)


SECRET = bytes(31) + b"\x01"


def test_id_and_key_differ():
    assert ac.host_id(SECRET) != ac.host_key(SECRET).hex()


def test_pairing_code_vector():
    # pinned: the agent (Objective-C) must derive the same code from the same secret
    assert ac.pairing_code(SECRET) == PAIRING_CODE


def test_mac_vector():
    assert ac.auth_mac(SECRET, bytes.fromhex("00" * 16)) == MAC


def test_auth_message_never_contains_secret_or_key():
    msg = ac.auth_message("chocobo", SECRET, bytes(16))
    flat = repr(msg)
    assert SECRET.hex() not in flat and ac.host_key(SECRET).hex() not in flat


# computed from the PROTOCOL.md definitions with hashlib directly, not with the client
PAIRING_CODE = "485206"
MAC = "4659c30f597d8c02fe307813b7c840df29bc9c37800a8b0f49fd3ac1f0f38b6a"
