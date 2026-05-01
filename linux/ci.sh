#!/bin/bash
set -euo pipefail
cd "$(dirname "$0")/.."

for f in linux/*.sh shared/*.sh; do
    bash -n "$f"
done

python3 -c "import ast,sys
for p in sys.argv[1:]: ast.parse(open(p).read(), p)" \
    shared/sub_parse.py shared/build_config.py shared/geo_convert.py

python3 -c "import json,sys
for p in sys.argv[1:]: json.load(open(p))" config_base.json

echo "linux ci: shell + python + json lint pass"
