# xray-cfg

My personal proxy setup for 2 XRay VLESS outbounds. Why did I built it:

- No GUI, no tray app, just works foreground. Internet without headaches like good old times.
- Writes itself in autostart and schedulers
- Route Russian-ip-only sites through one proxy, restricted (by government or website owners) websites through another, most traffic goes direct.
- Automatic domain routing with daily updates on runetfreedom datasets.
- DNS-over-HTTPS to 1.1.1.1
- Seamless hosting on github, credentials protected via ejson
- Has teardown (uninstall), testing and other scripts
- Works on Linux (systemd) and Windows (sing-box + WinTun). MacOS support incoming

## Prerequisites & Secrets

**Linux:** `xray`, `ejson`, `jq`, `python3`
**Windows:** `ejson` in PATH, PowerShell 5.1+, run as Administrator

Secrets (proxy credentials, sudo password) are stored encrypted in `secrets.ejson`.

## Linux

```sh
make setup       # install and start proxy
make teardown    # stop proxy
make test        # run integration tests
make restart     # teardown + setup
make status      # systemctl status xray
make logs        # follow xray journal
make flush-dns   # flush systemd-resolved cache
make update-geodata
```

## Windows

Run from an elevated PowerShell prompt (`make` via Git Bash or equivalent):

```sh
make setup          # install and start proxy (registers Scheduled Task for boot)
make teardown       # stop proxy and clean up
make test           # run integration tests
make cycle          # full cycle: setup → test → teardown → verify direct
make restart        # teardown + setup
make status         # show scheduled tasks and running processes
make logs           # tail xray error log
make flush-dns      # ipconfig /flushdns
make update-geodata
```

## Managing Domains

Route a domain through a specific proxy:

```sh
make add-domain                              # interactive prompt
make add-domain domain=kremlin.ru proxy=proxy_ru  # inline example - route via Russian proxy
make remove-domain domain=kremlin.ru
```

Makefile dispatches to the right script per OS. Both restart the proxy to apply changes.

## Roadmap

- **Linux:** move scripts into `linux/` subfolder (parallel with `windows/`)
- **macOS:** fully working version

## Notes

- `twitch.tv` needs proxy to bypass country restriction; CDN should stay direct
- `eth0.me` and `ident.me` are test-only domains for verifying proxy routing
