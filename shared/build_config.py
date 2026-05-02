#!/usr/bin/env python3
"""Assemble a sing-box-extended config from proxies.conf + subscription URLs.

Usage:
    python3 build_config.py <proxies_conf> <secrets_json> <rule_set_dir> \
        [--interface-name NAME]

Reads proxies.conf for routing source-of-truth, expands rule_set + route.rules,
fetches each `<tag>.sub_url` from the decrypted secrets dict, parses the URI
via sub_parse, and appends the resulting outbounds. Sub fetch failure is fatal.

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


def _base_config() -> dict:
    return {
        'log': {'level': 'warn', 'timestamp': True},
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
          interface_name: str | None = None) -> dict:
    cfg = _base_config()
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
    p = argparse.ArgumentParser()
    p.add_argument('proxies_conf')
    p.add_argument('secrets_json')
    p.add_argument('rule_set_dir')
    p.add_argument('--interface-name', default=None)
    args = p.parse_args()
    cfg = build(args.proxies_conf, json.loads(args.secrets_json),
                args.rule_set_dir, args.interface_name)
    json.dump(cfg, sys.stdout, indent=2)
    return 0


if __name__ == '__main__':
    sys.exit(main())
