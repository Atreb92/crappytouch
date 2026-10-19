#!/usr/bin/env python3
"""Forward 127.0.0.1:<local> to <port> on the USB-connected iPhone (default 2222 -> 22, for SSH)."""
import socket
import sys
import threading
from pathlib import Path

sys.path.insert(0, str(Path(__file__).resolve().parent.parent))
from client import usbmux  # noqa: E402


def pipe(a: socket.socket, b: socket.socket) -> None:
    try:
        while data := a.recv(65536):
            b.sendall(data)
    except OSError:
        pass
    finally:
        a.close()
        b.close()


def main() -> None:
    local, remote = (int(sys.argv[1]), int(sys.argv[2])) if len(sys.argv) == 3 else (2222, 22)
    srv = socket.create_server(("127.0.0.1", local))
    print(f"forwarding 127.0.0.1:{local} -> iPhone:{remote} (Ctrl+C to stop)", flush=True)
    while True:
        client, _ = srv.accept()
        try:
            phone = usbmux.connect(remote)
        except OSError as e:
            print(f"error: {e}", file=sys.stderr)
            client.close()
            continue
        for a, b in ((client, phone), (phone, client)):
            threading.Thread(target=pipe, args=(a, b), daemon=True).start()


if __name__ == "__main__":
    main()
