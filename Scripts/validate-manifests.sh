#!/usr/bin/env bash
# Validate tool manifest YAML files against the ios-mcp schema contract.
# Requires: python3 with pyyaml (pre-installed on GitHub Actions runners).
#
# Usage: bash Scripts/validate-manifests.sh

set -euo pipefail

MANIFEST_DIR="$(cd "$(dirname "$0")/../Manifests/tools" && pwd)"

ALLOWED_CATEGORIES="project_discovery simulator build logging ui_automation debugging inspection quality extras"

ERRORS=0

validate_file() {
    local file="$1"
    local name
    name="$(basename "$file")"

    python3 -c "
import sys, yaml

with open('$file') as f:
    doc = yaml.safe_load(f)

errors = []

for key in ['name', 'description', 'category', 'input', 'output', 'idempotent', 'destructive', 'timeout']:
    if key not in doc:
        errors.append(f'Missing required key: {key}')

if 'timeout' in doc:
    t = doc['timeout']
    if not isinstance(t, dict):
        errors.append('timeout must be a mapping')
    else:
        if 'default' not in t:
            errors.append('timeout missing \"default\" key')
        if 'max' not in t:
            errors.append('timeout missing \"max\" key')

allowed = set('${ALLOWED_CATEGORIES}'.split())
if 'category' in doc and doc['category'] not in allowed:
    errors.append(f'Invalid category \"{doc[\"category\"]}\" — must be one of: ${ALLOWED_CATEGORIES}')

if errors:
    for e in errors:
        print(f'  ERROR: {e}', file=sys.stderr)
    sys.exit(1)
" 2>&1
}

echo "Validating manifests in $MANIFEST_DIR ..."

for file in "$MANIFEST_DIR"/*.yaml; do
    name="$(basename "$file")"

    # Skip the schema definition file
    if [ "$name" = "_schema.yaml" ]; then
        continue
    fi

    if output=$(validate_file "$file" 2>&1); then
        echo "  OK  $name"
    else
        echo "  FAIL $name"
        echo "$output"
        ERRORS=$((ERRORS + 1))
    fi
done

if [ "$ERRORS" -gt 0 ]; then
    echo ""
    echo "FAILED: $ERRORS manifest(s) invalid."
    exit 1
fi

echo ""
echo "All manifests valid."
