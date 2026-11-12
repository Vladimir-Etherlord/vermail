#!/usr/bin/env bash
# Full local check: formatting, lint, localizations, package tests, app build and tests.
set -euo pipefail
cd "$(dirname "$0")/.."

step() { printf '\n==> %s\n' "$1"; }

step "Generate Xcode project"
xcodegen generate --quiet

step "SwiftFormat"
swiftformat --lint .

step "SwiftLint"
swiftlint lint --strict --quiet

step "Localizations"
scripts/check-localizations.sh

step "VermailKit tests"
swift test --package-path Packages/VermailKit --quiet

step "App build and tests"
xcodebuild -project Vermail.xcodeproj -scheme Vermail -destination 'platform=macOS,arch=arm64' test | xcbeautify --quiet

printf '\nAll checks passed.\n'
