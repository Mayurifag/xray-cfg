# proxies-cfg

TUN-based transparent proxy on Linux, macOS, Windows. Single binary
[`shtorm-7/sing-box-extended`](https://github.com/shtorm-7/sing-box-extended)
(upstream sing-box lacks `xhttp` transport). Outbound configs are pulled from
**subscription URLs** at every `setup`; nothing about the wire protocol is
hard-coded.

## Code Style

Only comment non-obvious behaviour — things that would surprise a reader who
understands the language and tools.

## Authentication

**Linux:** Sudo password stored in `secrets.ejson`. Retrieve:
```sh
ejson decrypt secrets.ejson | python3 -c "import sys,json; print(json.load(sys.stdin)['sudo_password'], end='')"
```
Use `printf 'PASSWORD\n' | sudo -S -k COMMAND`. The `-k` flag forces fresh
authentication. `pam_faillock` active — 3 failed attempts lock account. Reset:
`faillock --user mayurifag --reset`.

**Windows:** Scripts use `#Requires -RunAsAdministrator`.

## Project Layout

~~~
config_base.json                  sing-box base template (TUN, DNS, routing) — outbound stubs filled in at build time
Makefile                          platform-detecting wrapper for setup/test/cycle/etc.
secrets.ejson                     encrypted: { sudo_password, macos_sudo_password, proxy_*.sub_url }

shared/sub_parse.py               fetch sub URL → base64-decode → parse first proxy URI → sing-box outbound dict
shared/geo_convert.py             v2ray geosite.dat / geoip.dat → sing-box JSON rule-sets (per category)
shared/build_config.py            assemble final sing-box config: base + 2 parsed outbounds
shared/test_core.sh               cross-platform integration test (teardown→down→setup→distinct→QUIC→DNS)
shared/update_geodata_core.sh     cross-platform geodata download + .dat→json conversion
shared/common.sh                  cross-platform bash helpers (ensure_jq, format_domain, generate_singbox_config, git, ejson)
shared/{add,remove}_domain.sh     cross-platform domain editor for config_base.json route.rules
shared/constants.{sh,ps1}         versions, geodata URLs, test URLs — single source of truth

linux/setup.sh                    download sing-box-extended → geo + rule-sets → build config → systemd unit
linux/teardown.sh                 stop/disable/remove unit + legacy xray cleanup
linux/test.sh                     thin wrapper that exec's shared/test_core.sh
linux/ci.sh                       shell + python + json lint
linux/{add,remove}_domain.sh      thin wrappers around shared/{add,remove}_domain.sh
linux/update_geodata.sh           thin wrapper that exec's shared/update_geodata_core.sh
linux/common.sh                   linux helpers: paths, restart_proxy

macos/setup.sh                    download → geo + rule-sets → build config → install LaunchDaemon → wait for utun
macos/teardown.sh                 bootout + remove plists (incl. legacy xray + logrotate)
macos/test.sh                     thin wrapper that exec's shared/test_core.sh (HTTP/3 via brew curl)
macos/ci.sh                       shell + plist + python + json lint
macos/{add,remove}_domain.sh      thin wrappers
macos/update_geodata.sh           thin wrapper that exec's shared/update_geodata_core.sh
macos/common.sh                   macOS helpers: assert_root, ensure_jq, ensure_curl_http3, restart_proxy
macos/plists/*.plist              LaunchDaemon templates with __REPO_ROOT__ placeholder
macos/runtime/                    gitignored: binary, generated config, rule-sets, geodata, logs

windows/setup.ps1                 download → geo + rule-sets → build config (sets interface_name) → register Scheduled Task → wait TUN
windows/teardown.ps1              stop processes, remove tasks (incl. legacy xray-proxy/xray-geodata/xray-logrotate)
windows/test.ps1                  integration tests: -Mode all/proxy_ru/proxy_it/direct
windows/cycle.ps1                 setup → test all → teardown → test direct
windows/{add,remove}_domain.ps1   domain editor for config_base.json
windows/update_geodata.ps1        daily geodata refresh + JSON conversion
windows/ci.ps1                    PowerShell parser + JSON lint
windows/common.ps1                helpers: Assert-Admin, Build-SingboxConfig, Restart-Proxy, Format-Domain
windows/runtime/                  gitignored: binary, generated config, rule-sets, geodata, logs
~~~

## Outbounds

| Outbound   | Protocol  | Purpose             | Test domain           |
| ---------- | --------- | ------------------- | --------------------- |
| `direct`   | direct    | Default (unmatched) | checkip.amazonaws.com |
| `proxy_ru` | hysteria2 | Russian-only sites  | ident.me              |
| `proxy_it` | vless+xhttp+reality | Blocked sites | eth0.me            |

Outbound *types* and credentials are extracted from each `sub_url` — the table
above reflects what the current servers offer; rotate the subscription and the
parsed outbound shape changes accordingly.

## Cross-platform constants

| Constant     | Value             | Where defined                            | Notes                                         |
| ------------ | ----------------- | ---------------------------------------- | --------------------------------------------- |
| TUN address  | `172.19.0.1/30`   | `config_base.json` `inbounds[0].address` | Same on all OSes; sing-box auto-assigns       |
| TUN MTU      | `1500`            | `config_base.json`                       | Default; lower if proxy server has smaller MTU|
| Stack        | `mixed`           | `config_base.json` `inbounds[0].stack`   | gvisor userspace TCP for reliable sniff       |
| geodata URLs | runetfreedom/*    | `shared/geodata_urls.{sh,ps1}`           | Single source of truth                        |
| test URLs    | ident.me, eth0.me, checkip.amazonaws.com | `shared/test_urls.{sh,ps1}` | Single source of truth |

## Subscription parsing

`shared/sub_parse.py` understands `hysteria2://` and `vless://`. URI fields with
no sing-box-extended schema match are dropped silently:

| Dropped field   | Why                                                                      |
| --------------- | ------------------------------------------------------------------------ |
| `fp` (hy2)      | sing-box errors `unsupported usage for uTLS` (uTLS can't wrap QUIC)      |
| `fm` (hy2)      | Duplicate of `obfs` UDP block                                            |
| `spx` (vless)   | sing-box-extended Reality has no `spider_x` field                        |

`fp` for VLESS is kept (uTLS over TCP works); ECH config (when present in URI)
is wrapped as PEM and passed to `tls.ech.config`. **xhttp transport requires
`alpn: ["h2"]`** (HTTP/2 mandatory).

For VLESS+xhttp+REALITY URIs, the `parser` outbound built into sing-box-extended
is **incomplete** (drops `type=xhttp` silently). `sub_parse.py` builds the full
outbound dict ourselves to compensate.

## Geodata flow

`update_geodata.sh|.ps1` downloads runetfreedom `geoip.dat` + `geosite.dat`
(v2ray protobuf). `geo_convert.py` parses them with a minimal protobuf reader
and emits one `*.json` per category referenced in `config_base.json`. sing-box
loads each as a `local`/`source`-format rule-set.

Categories are extracted automatically from the rule-set paths in
`config_base.json` (no separate list to maintain).

## Known gotchas

**Subscription rate limit.** Both 3xui panels return 403 after rapid repeated
fetches. Production usage is one fetch per `setup` so it's a non-issue; in
development, wait ~30s between calls.

**Sub fetch User-Agent.** `urllib.request` default `Python-urllib/X.Y` is
blocked by 3xui. `sub_parse.py` sends `User-Agent: sing-box/1.13` which works.

**`shtorm-7/sing-box-extended` requires `x_padding_bytes` in xhttp.** Empty or
missing → config rejected at startup with `"x_padding_bytes cannot be
disabled"`. Set to `"100-1000"` (xray's xhttp default).

**xhttp client mode = `auto`.** Lets server pick. `packet-up`/`stream-up`/
`stream-one` may fail handshake depending on server config.

**Chromium Secure DNS.** Chrome/Edge use built-in DoH, bypassing system DNS,
so routing breaks for proxy_* domains. Disable in browser, launch with
`--disable-features=DnsOverHttps`, or set managed policy
`/etc/chromium/policies/managed/disable-doh.json` →
`{"DnsOverHttpsMode":"off"}` (Linux).

**`.NET connection pool bypasses TUN (Windows).** `ServicePointManager` reuses
TCP connections across PowerShell requests. After proxy restart, pooled
connections bypass the new TUN routing. Fix: `CloseConnectionGroup('')`
before post-restart checks (already in `windows/test.ps1` direct mode).

**`$pid` in PowerShell.** Reserved read-only variable. Use `$procId`.

**`schtasks /query` with `$ErrorActionPreference = 'Stop'`.** Throws on
nonzero exit. Use `Get-ScheduledTask -ErrorAction SilentlyContinue` instead.

## Migration from xray-based stack

Teardown scripts on every OS bootout/remove the legacy xray daemons + the
extra logrotate task before the new sing-box-extended task is registered.
Running `make teardown` on the old install once is enough; subsequent
`make setup` works directly.
