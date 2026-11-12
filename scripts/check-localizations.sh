#!/usr/bin/env bash
# Fails if any String Catalog entry lacks a translated Russian value.
set -euo pipefail
cd "$(dirname "$0")/.."

status=0
while IFS= read -r catalog; do
    missing=$(jq -r '
        .strings | to_entries[]
        | select(.value.shouldTranslate != false)
        | select((.value.localizations.ru.stringUnit.state // "") != "translated")
        | .key' "$catalog")
    if [[ -n "$missing" ]]; then
        echo "error: $catalog has strings without Russian translation:" >&2
        echo "$missing" | sed 's/^/  - /' >&2
        status=1
    fi
done < <(find Vermail Packages -name '*.xcstrings' -not -path '*/.build/*')

exit $status
