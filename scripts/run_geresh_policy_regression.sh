#!/bin/bash
# Run the real decision engine with in-memory dependencies; no app launch,
# user preferences, installed layout changes or NSSpellChecker dependency.
set -euo pipefail
project_dir="$(cd "$(dirname "$0")/.." && pwd)"
test_dir="$(mktemp -d /private/tmp/autoswitch-geresh-policy.XXXXXX)"
printf 'Artifacts: %s\n' "$test_dir"
xcrun swiftc -module-cache-path "$test_dir/module-cache" \
    "$project_dir/Sources/Core/Models.swift" \
    "$project_dir/Sources/Engine/LanguageDecisionEngine.swift" \
    "$project_dir/Tests/AutoSwitchTests/Fixtures/GereshPolicy/main.swift" \
    -o "$test_dir/geresh-policy"
"$test_dir/geresh-policy"
