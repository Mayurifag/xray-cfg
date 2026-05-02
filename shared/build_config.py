#!/usr/bin/env python3
"""Assemble a sing-box-extended config from proxies.conf + subscription URLs.

Usage:
    cat secrets.json | python3 build_config.py <proxies_conf> <rule_set_dir> \
        [--interface-name NAME] [--log-output PATH]

Reads proxies.conf for routing source-of-truth, expands rule_set + route.rules,
fetches each `<tag>.sub_url` from the decrypted secrets dict (read from
stdin), parses the URI via sub_parse, and appends the resulting outbounds.
Sub fetch failure is fatal.

Secrets come via stdin so multi-line JSON survives PowerShell 5.1 native
arg passing (which mangles arg-borne quotes).

Static base config (log/dns/inbounds/sniff+hijack rules/final/etc.) is inlined
below — single source of truth. `--interface-name` pins the TUN adapter name
(Windows uses `singbox_tun` so teardown can find it; other OSes auto-name).
"""
from __future__ import annotations

import argparse
import json
import os
import sys

sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
import sub_parse  # noqa: E402
from proxies_conf import all_of_kind, load  # noqa: E402


def _base_config(log_output: str | None = None) -> dict:
    log = {'level': 'warn', 'timestamp': True}
    if log_output:
        log['output'] = log_output
    return {
        'log': log,
        'dns': {
            'servers': [
                {'type': 'https', 'tag': 'doh-cf', 'server': '1.1.1.1'},
                {'type': 'https', 'tag': 'doh-google', 'server': '8.8.8.8'},
            ],
            'strategy': 'ipv4_only',
        },
        'inbounds': [{
            'type': 'tun',
            'tag': 'tun-in',
            'address': ['172.19.0.1/30'],
            'mtu': 1500,
            'auto_route': True,
            'strict_route': True,
            'stack': 'mixed',
        }],
        'outbounds': [{'type': 'direct', 'tag': 'direct'}],
        'route': {
            'rule_set': [],
            'rules': [
                {'action': 'sniff'},
                {'protocol': 'dns', 'action': 'hijack-dns'},
            ],
            'final': 'direct',
            'auto_detect_interface': True,
            'default_domain_resolver': 'doh-cf',
        },
    }


def _geo_tags(kinds: dict) -> list[str]:
    return [f'geosite-{c}' for c in sorted(set(kinds.get('geosites', [])))] + \
           [f'geoip-{c}' for c in sorted(set(kinds.get('geoips', [])))]


def build(proxies_path: str, secrets: dict, rule_set_dir: str,
          interface_name: str | None = None,
          log_output: str | None = None) -> dict:
    cfg = _base_config(log_output)
    if interface_name:
        cfg['inbounds'][0]['interface_name'] = interface_name

    proxies = load(proxies_path)

    all_tags = (
        [f'geosite-{c}' for c in all_of_kind(proxies, 'geosites')]
        + [f'geoip-{c}' for c in all_of_kind(proxies, 'geoips')]
    )
    cfg['route']['rule_set'] = [
        {'type': 'local', 'tag': t, 'format': 'source',
         'path': f'{rule_set_dir}/{t}.json'}
        for t in sorted(all_tags)
    ]

    for tag, kinds in proxies.items():
        domains = sorted(set(kinds.get('domains', [])))
        if domains:
            cfg['route']['rules'].append({'domain': domains, 'outbound': tag})
        rs = _geo_tags(kinds)
        if rs:
            cfg['route']['rules'].append({'rule_set': rs, 'outbound': tag})

    for tag in proxies:
        cfg['outbounds'].append(sub_parse.fetch_outbound(secrets[tag]['sub_url'], tag))

    return cfg


def main() -> int:
    p = argparse.ArgumentParser(description='Reads secrets JSON from stdin.')
    p.add_argument('proxies_conf')
    p.add_argument('rule_set_dir')
    p.add_argument('--interface-name', default=None)
    p.add_argument('--log-output', default=None)
    args = p.parse_args()
    secrets = json.load(sys.stdin)
    cfg = build(args.proxies_conf, secrets, args.rule_set_dir,
                args.interface_name, args.log_output)
    json.dump(cfg, sys.stdout, indent=2)
    return 0


if __name__ == '__main__':
    sys.exit(main())
