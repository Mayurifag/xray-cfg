# xray-cfg

My personal proxy setup for 2 XRay VLESS outbounds. Why did I built it:

- No GUI, just works. Internet without headaches like good old times.
- Automatic domain routing with daily community-driven geodata updates.
- Writes itself in autostart and schedulers
- Route Russian-ip-only sites through one proxy, blocked sites through another, most traffic goes direct.
- Seamless hosting on github, credentials protected via ejson
- Has teardown (uninstall) and testing scripts
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

Run from an elevated PowerShell prompt:

```powershell
.\windows\setup.ps1           # install and start proxy (registers Scheduled Task for boot)
.\windows\teardown.ps1        # stop proxy and clean up
.\windows\test.ps1 -Mode all  # run integration tests
.\windows\cycle.ps1           # full cycle: setup → test → teardown → verify direct
```

## Managing Domains

Route a domain through a specific proxy:

```sh
make add-domain                              # interactive prompt
make add-domain domain=kremlin.ru proxy=proxy_ru  # inline example - route via Russian proxy
make remove-domain domain=kremlin.ru
```

Cross-platform: Makefile dispatches to `add_domain.sh` on Linux, `windows/add_domain.ps1` on Windows.
Both restart the proxy seamlessly to apply changes.

## Roadmap

- **Linux:** move scripts into `linux/` subfolder (parallel with `windows/`)
- **macOS:** fully working version

## Notes

- `twitch.tv` needs proxy to bypass country restriction; CDN should stay direct
- `eth0.me` and `ident.me` are test-only domains for verifying proxy routing
