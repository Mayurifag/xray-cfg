#!/usr/bin/env python3
"""Convert v2ray geosite.dat and geoip.dat (protobuf) to sing-box rule-set
JSON files. Only emits categories supplied as arguments.

Usage:
    python3 geo_convert.py <geosite.dat> <geoip.dat> <out_dir> \
        [--geosite cat1 ...] [--geoip code1 ...] [--from-proxies-conf path]

Output:
    <out_dir>/geosite-<cat>.json
    <out_dir>/geoip-<code>.json

The .json format is sing-box rule-set source format (version 3).
"""
from __future__ import annotations

import argparse
import ipaddress
import json
import os
import sys


def _read_varint(buf: memoryview, i: int) -> tuple[int, int]:
    n = 0
    shift = 0
    while True:
        b = buf[i]
        i += 1
        n |= (b & 0x7F) << shift
        if b & 0x80 == 0:
            return n, i
        shift += 7


def _iter_fields(buf: memoryview):
    i = 0
    end = len(buf)
    while i < end:
        tag, i = _read_varint(buf, i)
        field = tag >> 3
        wire = tag & 0x7
        if wire == 0:
            value, i = _read_varint(buf, i)
            yield field, value, None
        elif wire == 2:
            length, i = _read_varint(buf, i)
            yield field, None, buf[i:i+length]
            i += length
        elif wire == 1:
            yield field, int.from_bytes(bytes(buf[i:i+8]), 'little'), None
            i += 8
        elif wire == 5:
            yield field, int.from_bytes(bytes(buf[i:i+4]), 'little'), None
            i += 4
        else:
            raise RuntimeError(f'unsupported wire type {wire}')


def _parse_domain(buf: memoryview) -> tuple[int, str]:
    # message Domain { Type type=1; string value=2; ...attributes=3 }
    dtype, value = 0, ''
    for field, ival, sub in _iter_fields(buf):
        if field == 1:
            dtype = ival
        elif field == 2:
            value = bytes(sub).decode('utf-8')
    return dtype, value


def _parse_geosite_entry(buf: memoryview) -> tuple[str, list]:
    code = ''
    domains = []
    for field, ival, sub in _iter_fields(buf):
        if field == 1:
            code = bytes(sub).decode('utf-8')
        elif field == 2:
            domains.append(_parse_domain(sub))
    return code.lower(), domains


def parse_geosite(path: str) -> dict[str, list]:
    with open(path, 'rb') as f:
        data = memoryview(f.read())
    sites = {}
    for field, _, sub in _iter_fields(data):
        if field == 1:
            code, domains = _parse_geosite_entry(sub)
            sites[code] = domains
    return sites


def _parse_cidr(buf: memoryview) -> tuple[bytes, int]:
    ip, prefix = b'', 0
    for field, ival, sub in _iter_fields(buf):
        if field == 1:
            ip = bytes(sub)
        elif field == 2:
            prefix = ival
    return ip, prefix


def _parse_geoip_entry(buf: memoryview) -> tuple[str, list]:
    code = ''
    cidrs = []
    for field, ival, sub in _iter_fields(buf):
        if field == 1:
            code = bytes(sub).decode('utf-8')
        elif field == 2:
            cidrs.append(_parse_cidr(sub))
    return code.lower(), cidrs


def parse_geoip(path: str) -> dict[str, list]:
    with open(path, 'rb') as f:
        data = memoryview(f.read())
    out = {}
    for field, _, sub in _iter_fields(data):
        if field == 1:
            code, cidrs = _parse_geoip_entry(sub)
            out[code] = cidrs
    return out


def geosite_to_ruleset(domains: list[tuple[int, str]]) -> dict:
    rule = {}
    suffix, keyword, exact, regex = [], [], [], []
    for dtype, value in domains:
        if dtype == 0:        # Plain (substring)
            keyword.append(value)
        elif dtype == 1:      # Regex
            regex.append(value)
        elif dtype == 2:      # Domain suffix
            suffix.append(value)
        elif dtype == 3:      # Full (exact)
            exact.append(value)
    if exact:
        rule['domain'] = sorted(set(exact))
    if suffix:
        rule['domain_suffix'] = sorted(set(suffix))
    if keyword:
        rule['domain_keyword'] = sorted(set(keyword))
    if regex:
        rule['domain_regex'] = sorted(set(regex))
    return {'version': 3, 'rules': [rule]}


def geoip_to_ruleset(cidrs: list[tuple[bytes, int]]) -> dict:
    out_cidrs = []
    for ip, prefix in cidrs:
        if len(ip) == 4:
            net = ipaddress.IPv4Network((ip, prefix), strict=False)
        elif len(ip) == 16:
            net = ipaddress.IPv6Network((ip, prefix), strict=False)
        else:
            continue
        out_cidrs.append(str(net))
    return {'version': 3, 'rules': [{'ip_cidr': sorted(set(out_cidrs))}]}


def categories_from_proxies_conf(path: str) -> tuple[list[str], list[str]]:
    sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
    from proxies_conf import all_of_kind, load
    data = load(path)
    return all_of_kind(data, 'geosites'), all_of_kind(data, 'geoips')


def main() -> int:
    p = argparse.ArgumentParser()
    p.add_argument('geosite_dat')
    p.add_argument('geoip_dat')
    p.add_argument('out_dir')
    p.add_argument('--geosite', nargs='*', default=[])
    p.add_argument('--geoip', nargs='*', default=[])
    p.add_argument('--from-proxies-conf', default=None,
                   help='extract category list from a proxies.conf file')
    args = p.parse_args()

    if args.from_proxies_conf:
        gs, gi = categories_from_proxies_conf(args.from_proxies_conf)
        args.geosite = list(args.geosite) + gs
        args.geoip = list(args.geoip) + gi

    os.makedirs(args.out_dir, exist_ok=True)

    expected = {f'geosite-{c.lower()}.json' for c in args.geosite} | \
               {f'geoip-{c.lower()}.json' for c in args.geoip}
    for fname in os.listdir(args.out_dir):
        if (fname.startswith('geosite-') or fname.startswith('geoip-')) and \
                fname.endswith('.json') and fname not in expected:
            os.remove(os.path.join(args.out_dir, fname))

    if args.geosite:
        sites = parse_geosite(args.geosite_dat)
        for cat in args.geosite:
            cat_lc = cat.lower()
            if cat_lc not in sites:
                print(f'geosite category not found: {cat}', file=sys.stderr)
                return 1
            ruleset = geosite_to_ruleset(sites[cat_lc])
            path = os.path.join(args.out_dir, f'geosite-{cat_lc}.json')
            with open(path, 'w') as f:
                json.dump(ruleset, f, indent=2)
            print(f'wrote {path}')

    if args.geoip:
        ips = parse_geoip(args.geoip_dat)
        for code in args.geoip:
            code_lc = code.lower()
            if code_lc not in ips:
                print(f'geoip code not found: {code}', file=sys.stderr)
                return 1
            ruleset = geoip_to_ruleset(ips[code_lc])
            path = os.path.join(args.out_dir, f'geoip-{code_lc}.json')
            with open(path, 'w') as f:
                json.dump(ruleset, f, indent=2)
            print(f'wrote {path}')

    return 0


if __name__ == '__main__':
    sys.exit(main())
