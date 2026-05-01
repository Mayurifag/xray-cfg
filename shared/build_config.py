#!/usr/bin/env python3
"""Assemble a sing-box-extended config from config_base.json + subscription URLs.

Usage:
    python3 build_config.py <base_path> <secrets_json> <rule_set_dir>

Reads config_base.json, substitutes ${RULE_SET_DIR}, fetches each
proxy_*.sub_url from the decrypted secrets, parses the URI via sub_parse, and
appends the resulting outbounds. Sub fetch failure is fatal.
"""
from __future__ import annotations

import json
import os
import sys

sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
import sub_parse  # noqa: E402


def build(base_path: str, secrets: dict, rule_set_dir: str) -> dict:
    text = open(base_path).read().replace('${RULE_SET_DIR}', rule_set_dir)
    cfg = json.loads(text)
    for tag in ('proxy_ru', 'proxy_it'):
        cfg['outbounds'].append(
            sub_parse.parse_uri(sub_parse.fetch_first_uri(secrets[tag]['sub_url']), tag)
        )
    return cfg


def main() -> int:
    if len(sys.argv) != 4:
        print(__doc__, file=sys.stderr)
        return 2
    base_path, secrets_json, rule_set_dir = sys.argv[1:]
    cfg = build(base_path, json.loads(secrets_json), rule_set_dir)
    json.dump(cfg, sys.stdout, indent=2)
    return 0


if __name__ == '__main__':
    sys.exit(main())
