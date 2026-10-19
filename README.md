# scrcrappy-agent

SpringBoard tweak (rootless jailbreaks) that lets a computer running
[scrcrappy](../scrcrappy) control the iPhone over USB: touches, keys, clipboard, screen info,
screenshots. Nothing else: no shell, no network access, no injection into apps.

Security model: listens on 127.0.0.1 only (reached over USB through usbmuxd); every connection
must authenticate; a new computer must be approved with an on-phone *Allow* prompt. See
`PROTOCOL.md` and `docs/superpowers/specs/`.

## Build (Fedora)

```sh
sudo dnf install -y fakeroot perl rsync zip git xz
scripts/setup-theos.sh      # Theos + iOS toolchain + SDK into ~/theos
make package                # packages/dev.scrcrappy.agent_*.deb
```

## Install on the phone (development)

Needs OpenSSH on the phone (Sileo). In your own terminal (sudo asks for the phone password):

```sh
scripts/install.sh
```
