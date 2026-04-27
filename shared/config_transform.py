#!/usr/bin/env python3
"""Transform xray config.json template by substituting secrets and applying
platform-specific transforms.

Usage:
    python3 config_transform.py <mode> <template_path> <secrets_json>

Modes:
    linux  — placeholder substitution only.
    macos  — placeholder substitution + 4 transforms (replace inbounds with SOCKS,
             strip mark, drop port-53 routing rule, add log.error path).

Reads template from <template_path>, secrets as JSON string from <secrets_json>.
Writes resulting config JSON to stdout.

For macos mode, the log.error path is read from env var XRAY_ERROR_LOG_PATH.
"""
import json
import os
import sys


def substitute_placeholders(template: str, secrets: dict) -> str:
    mapping = [
        ('PLACEHOLDER_PROXY_RU_HOST',       secrets['proxy_ru']['host']),
        ('PLACEHOLDER_PROXY_RU_UUID',       secrets['proxy_ru']['uuid']),
        ('PLACEHOLDER_PROXY_RU_SHORT_ID',   secrets['proxy_ru']['short_id']),
        ('PLACEHOLDER_PROXY_RU_PUBLIC_KEY', secrets['proxy_ru']['public_key']),
        ('PLACEHOLDER_PROXY_IT_HOST',       secrets['proxy_it']['host']),
        ('PLACEHOLDER_PROXY_IT_UUID',       secrets['proxy_it']['uuid']),
        ('PLACEHOLDER_PROXY_IT_SHORT_ID',   secrets['proxy_it']['short_id']),
        ('PLACEHOLDER_PROXY_IT_PUBLIC_KEY', secrets['proxy_it']['public_key']),
    ]
    for key, value in mapping:
        template = template.replace(key, value)
    return template


def apply_macos_transforms(cfg: dict) -> dict:
    # Transform 1: replace inbounds with single SOCKS at 127.0.0.1:10808
    cfg['inbounds'] = [{
        'tag': 'socks-in',
        'port': 10808,
        'listen': '127.0.0.1',
        'protocol': 'socks',
        'settings': {'auth': 'noauth', 'udp': True},
        'sniffing': {
            'enabled': True,
            'routeOnly': True,
            'destOverride': ['http', 'tls', 'quic'],
        },
    }]

    # Transform 2: strip 'mark' from every outbound's streamSettings.sockopt
    for ob in cfg.get('outbounds', []):
        ss = ob.get('streamSettings')
        if not ss:
            continue
        sock = ss.get('sockopt')
        if sock and 'mark' in sock:
            del sock['mark']
            if not sock:
                del ss['sockopt']
        if not ss:
            del ob['streamSettings']

    # Transform 3: drop the port-53 routing rule (has inboundTag tun-in)
    cfg['routing']['rules'] = [
        r for r in cfg['routing']['rules']
        if 'inboundTag' not in r
    ]

    # Transform 4: add log.error path
    error_log = os.environ.get('XRAY_ERROR_LOG_PATH')
    if not error_log:
        raise RuntimeError('XRAY_ERROR_LOG_PATH env var required for macos mode')
    cfg.setdefault('log', {})['error'] = error_log

    return cfg


def main() -> int:
    if len(sys.argv) != 4:
        print(__doc__, file=sys.stderr)
        return 2
    mode, template_path, secrets_json = sys.argv[1], sys.argv[2], sys.argv[3]

    with open(template_path) as f:
        template = f.read()
    secrets = json.loads(secrets_json)

    substituted = substitute_placeholders(template, secrets)

    if mode == 'linux':
        sys.stdout.write(substituted)
        return 0

    if mode == 'macos':
        cfg = json.loads(substituted)
        cfg = apply_macos_transforms(cfg)
        sys.stdout.write(json.dumps(cfg, indent=2))
        return 0

    print(f'Unknown mode: {mode}', file=sys.stderr)
    return 2


if __name__ == '__main__':
    sys.exit(main())
