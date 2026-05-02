# proxies-cfg

Personal TUN-based transparent proxy setup. Single binary
([shtorm-7/sing-box-extended](https://github.com/shtorm-7/sing-box-extended) —
upstream sing-box has no `xhttp` transport), driven entirely from subscription
URLs.

- No GUI, no tray app — runs as a system service.
- Auto-installed in autostart (systemd / LaunchDaemon / Scheduled Task).
- Two outbounds + direct: route Russian-only sites through one, blocked sites
  through another, everything else direct.
- Outbound configs come from **subscription URLs** (one per outbound). 
  Re-fetched on every `setup`.
- runetfreedom geoip + geosite lists, refreshed daily, converted at install time
  to sing-box JSON rule-sets.
- Currently supports hysteria2 and VLESS/xhttp/Reality.
- DNS-over-HTTPS to 1.1.1.1 / 8.8.8.8.
- Credentials (sub URLs, sudo passwords) encrypted via `ejson`.
- Linux (systemd), macOS (LaunchDaemon), Windows (Scheduled Task) — same
  `proxies.conf`, same Python build pipeline.

## Subscription format

Each outbound's `sub_url` returns base64-encoded plaintext containing one or
more `proxy://...` URIs (one per line). The first URI is parsed.

Supported schemes: `hysteria2://`, `vless://`. Both `ws`/`grpc` transports
recognised; `xhttp` requires the `sing-box-extended` fork which is used in this 
repo.

### Dropped URI fields

| Field          | Scheme    | Why                                               |
| -------------- | --------- | ------------------------------------------------- |
| `fp=<browser>` | hysteria2 | uTLS can't wrap QUIC; sing-box errors if set      |
| `fm=<json>`    | hysteria2 | duplicates `obfs=` + `obfs-password=`             |
| `spx=<path>`   | vless     | sing-box-extended Reality has no `spider_x` field |

All three are anti-detection polish, not auth — connections still succeed.

## Prerequisites

| OS      | Required                                                                         |
| ------- | -------------------------------------------------------------------------------- |
| Linux   | `ejson`, `python3` (3.9+), `curl`, `systemd`                                     |
| macOS   | `ejson`, `python3`, brew `curl` for HTTP/3 tests                                 |
| Windows | `ejson`, Python 3.9+ in `PATH`, `make`                                           |

### macOS: disable Touch ID for sudo (one-time)

Setup/teardown/test feed the sudo password from `secrets.ejson` via
`sudo -S -k`. macOS PAM puts Touch ID (`pam_tid.so`) ahead of stdin auth, so
`sudo` pops a dialog every run. Disable for sudo only:

~~~sh
sudo cp /etc/pam.d/sudo_local /etc/pam.d/sudo_local.bak.proxiescfg
sudo sed -i '' 's|^auth       sufficient     pam_tid.so|# auth       sufficient     pam_tid.so|' /etc/pam.d/sudo_local
~~~

Restore: `sudo cp /etc/pam.d/sudo_local.bak.proxiescfg /etc/pam.d/sudo_local`.

## Usage

| Command               | Description                                |
| --------------------- | ------------------------------------------ |
| `make setup`          | install + start proxy                      |
| `make teardown`       | stop + remove proxy                        |
| `make restart`        | teardown + setup                           |
| `make test`           | integration tests                          |
| `make cycle`          | setup → test → teardown → verify direct    |
| `make status`         | show proxy status                          |
| `make logs`           | follow proxy log                           |
| `make flush-dns`      | flush DNS cache                            |
| `make update-geodata` | refresh runetfreedom .dat → JSON rule-sets |
| `make generate-config`| print sing-box config to stdout (inspection) |

## Domains

~~~sh
make add-domain domain=kremlin.ru proxy=proxy_ru
make remove-domain domain=kremlin.ru
make add-domain   # interactive prompt
~~~

Edits `proxies.conf` then restarts the proxy.

## Suggested shell aliases

~~~sh
export PROXIES_CFG="$HOME/Code/proxies-cfg"
alias proxy-cd='cd "$PROXIES_CFG"'
alias proxy-setup='make -C "$PROXIES_CFG" setup'
alias proxy-teardown='make -C "$PROXIES_CFG" teardown'
alias proxy-restart='make -C "$PROXIES_CFG" restart'
alias proxy-test='make -C "$PROXIES_CFG" test'
alias proxy-cycle='make -C "$PROXIES_CFG" cycle'
alias proxy-status='make -C "$PROXIES_CFG" status'
alias proxy-logs='make -C "$PROXIES_CFG" logs'
alias proxy-flush-dns='make -C "$PROXIES_CFG" flush-dns'
alias proxy-geodata='make -C "$PROXIES_CFG" update-geodata'
proxy-add() { make -C "$PROXIES_CFG" add-domain    domain="$1" proxy="${2:-proxy_it}"; }
proxy-rm()  { make -C "$PROXIES_CFG" remove-domain domain="$1"; }
alias proxy-remove='proxy-rm'
~~~

PowerShell ($PROFILE):

~~~powershell
$ProxiesCfg = "$HOME\Code\proxies-cfg"
function proxy-cd        { Set-Location $ProxiesCfg }
function proxy-setup     { make -C $ProxiesCfg setup }
function proxy-teardown  { make -C $ProxiesCfg teardown }
function proxy-restart   { make -C $ProxiesCfg restart }
function proxy-test      { make -C $ProxiesCfg test }
function proxy-cycle     { make -C $ProxiesCfg cycle }
function proxy-status    { make -C $ProxiesCfg status }
function proxy-logs      { make -C $ProxiesCfg logs }
function proxy-flush-dns { make -C $ProxiesCfg flush-dns }
function proxy-geodata   { make -C $ProxiesCfg update-geodata }
function proxy-add($d, $p = 'proxy_it') { make -C $ProxiesCfg add-domain    domain=$d proxy=$p }
function proxy-rm($d)                   { make -C $ProxiesCfg remove-domain domain=$d }
function proxy-remove($d)               { proxy-rm $d }
~~~

## Notes

- IPv4-only by design. ISP and proxy servers lack IPv6, so DNS is pinned to
  `strategy: ipv4_only`. Don't switch until both ends gain IPv6.
- `twitch.tv` needs proxy for country restriction; CDN stays direct.
- `eth0.me` / `ident.me` are test-only domains for verifying routing.
- Subscription panels rate-limit. One fetch per `setup` is fine; rapid
  successive fetches return 403 for ~30s.

## TODO

- Verify `make cycle` on Windows.
- Verify `make cycle` on Linux.
- Once both above are green, drop legacy `xray*` cleanup from
  `linux/teardown.sh`, `macos/common.sh` (`LEGACY_LABELS`),
  `windows/teardown.ps1` (`tasksToRemove` xray entries).
- Rename repo directory: `mv ~/Code/xray-cfg ~/Code/proxies-cfg`. Update remote
  if applicable: `git remote set-url origin <new-url>`.
