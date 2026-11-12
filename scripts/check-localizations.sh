#!/usr/bin/env bash
# Fails if a String Catalog entry is not translated into every language present in that catalog.
# Russian is always required; any other language becomes required as soon as one string is translated into it.
set -euo pipefail
cd "$(dirname "$0")/.."

status=0
while IFS= read -r catalog; do
    languages=$(jq -r '
        .sourceLanguage as $source
        | ([.strings[].localizations // {} | keys[]] + ["ru"])
        | unique | map(select(. != $source)) | .[]' "$catalog")
    for language in $languages; do
        missing=$(jq -r --arg l "$language" '
            .strings | to_entries[]
            | select(.value.shouldTranslate != false)
            | select(.value.localizations[$l]
                | (.stringUnit.state == "translated" or .variations != null) | not)
            | .key' "$catalog")
        if [[ -n "$missing" ]]; then
            echo "error: $catalog has strings without '$language' translation:" >&2
            echo "$missing" | sed 's/^/  - /' >&2
            status=1
        fi
    done
done < <(find Vermail Packages -name '*.xcstrings' -not -path '*/.build/*')

exit $status
