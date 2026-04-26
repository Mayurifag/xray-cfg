# xray-cfg

Personal proxy setup using 2 VLESS outbounds.

- No GUI, no tray app, just works foreground. Internet without headaches like 
  good old times.
- Writes itself in autostart and schedulers
- Route Russian-ip-only sites through one proxy, restricted (by government or 
  website owners) websites through another, most traffic goes direct.
- Automatic domain routing with daily updates on runetfreedom datasets.
- DNS-over-HTTPS to 1.1.1.1
- Seamless hosting on github, credentials protected via ejson
- Has teardown (uninstall), testing and other scripts
- Works on Linux (systemd) and Windows (sing-box + WinTun). MacOS support incoming

## Prerequisites

**Linux:** `xray`, `ejson`, `jq`, `python3`  
**Windows:** `ejson`, `make` in PATH, Administrator account

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

## Suggested aliases

Replace `XRAY_CFG` path if needed:

~~~sh
export XRAY_CFG="$HOME/Code/xray-cfg"
alias xray-cd='cd "$XRAY_CFG"'
alias xray-setup='make -C "$XRAY_CFG" setup'
alias xray-teardown='make -C "$XRAY_CFG" teardown'
alias xray-restart='make -C "$XRAY_CFG" restart'
alias xray-test='make -C "$XRAY_CFG" test'
alias xray-cycle='make -C "$XRAY_CFG" cycle'
alias xray-status='make -C "$XRAY_CFG" status'
alias xray-logs='make -C "$XRAY_CFG" logs'
alias xray-flush-dns='make -C "$XRAY_CFG" flush-dns'
alias xray-geodata='make -C "$XRAY_CFG" update-geodata'
xray-add()    { make -C "$XRAY_CFG" add-domain    domain="$1" proxy="${2:-proxy_it}"; }
xray-rm()     { make -C "$XRAY_CFG" remove-domain domain="$1"; }
alias xray-remove='xray-rm'
~~~

Drop into `$PROFILE` (PowerShell, Windows) — replace `$XrayCfg` path:

~~~powershell
$XrayCfg = "$HOME\Code\xray-cfg"
function xray-cd        { Set-Location $XrayCfg }
function xray-setup     { make -C $XrayCfg setup }
function xray-teardown  { make -C $XrayCfg teardown }
function xray-restart   { make -C $XrayCfg restart }
function xray-test      { make -C $XrayCfg test }
function xray-cycle     { make -C $XrayCfg cycle }
function xray-status    { make -C $XrayCfg status }
function xray-logs      { make -C $XrayCfg logs }
function xray-flush-dns { make -C $XrayCfg flush-dns }
function xray-geodata   { make -C $XrayCfg update-geodata }
function xray-add($d, $p = 'proxy_it') { make -C $XrayCfg add-domain    domain=$d proxy=$p }
function xray-rm($d)                   { make -C $XrayCfg remove-domain domain=$d }
function xray-remove($d)               { xray-rm $d }
~~~

## Roadmap

- **Linux:** move scripts into `linux/` subfolder (parallel with `windows/`)
- **macOS:** fully working version

## Notes

- `twitch.tv` needs proxy for country restriction; CDN should stay direct
- `eth0.me` / `ident.me` are test-only domains for verifying routing
- IPv4-only by design. ISP does not deliver IPv6, and the proxy servers do not 
  have IPv6 outbound either, so IPv6-only domains (e.g. `ntc.party` AAAA
  `2a02:e00:ffec:4b8::1`) are unreachable from this setup. xray DNS is pinned 
  to `queryStrategy: UseIPv4`; do not switch to `UseIP` until both ends gain 
  IPv6.
