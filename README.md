# xray-cfg

Personal proxy setup using 2 VLESS outbounds.

- No GUI, no tray app, just works foreground. Internet without headaches like good old times.
- Writes itself in autostart and schedulers
- Route Russian-ip-only sites through one proxy, restricted (by government or website owners) websites through another, most traffic goes direct.
- Automatic domain routing with daily updates on runetfreedom datasets.
- DNS-over-HTTPS to 1.1.1.1
- Seamless hosting on github, credentials protected via ejson
- Has teardown (uninstall), testing and other scripts
- Works on Linux (systemd) and Windows (sing-box + WinTun). MacOS support incoming

## Prerequisites

**Linux:** `xray`, `ejson`, `jq`, `python3`  
**Windows:** `ejson` in PATH, PowerShell 5.1+, run as Administrator

## Usage

Same `make` commands on both platforms:

| Command               | Description                             |
| --------------------- | --------------------------------------- |
| `make setup`          | install and start proxy                 |
| `make teardown`       | stop and remove proxy                   |
| `make restart`        | teardown + setup                        |
| `make test`           | integration tests                       |
| `make cycle`          | setup → test → teardown → verify direct |
| `make status`         | show proxy status                       |
| `make logs`           | follow proxy log                        |
| `make flush-dns`      | flush DNS cache                         |
| `make update-geodata` | download latest geoip/geosite data      |

## Domains

~~~sh
make add-domain domain=kremlin.ru proxy=proxy_ru
make remove-domain domain=kremlin.ru
make add-domain   # interactive prompt
~~~

## Roadmap

- **Linux:** move scripts into `linux/` subfolder (parallel with `windows/`)
- **macOS:** fully working version

## Notes

- `twitch.tv` needs proxy for country restriction; CDN should stay direct
- `eth0.me` / `ident.me` are test-only domains for verifying routing
