#!/bin/bash

resolvectl revert xray0 2>/dev/null || true
ip rule del not fwmark 255 lookup 100 pref 9000 2>/dev/null || true
ip route flush table 100 2>/dev/null || true
ip link delete xray0 2>/dev/null || true
