#!/usr/bin/env bash
# Tests of the werkbank CLI in throwaway repositories (no Flutter needed).
# shellcheck disable=SC2016 # check() evaluates its command in the test repo
set -euo pipefail
wb="$(cd "$(dirname "$0")/.." && pwd)/bin/werkbank"
tmp=$(mktemp -d)
trap 'rm -rf "$tmp"' EXIT
fails=0
ok() { printf 'ok   %s\n' "$1"; }
bad() { printf 'FAIL %s\n' "$1"; fails=$((fails + 1)); }
# check <name> <command…>: passes if the command succeeds.
check() { if (cd "$repo" && eval "${*:2}") >/dev/null 2>&1; then ok "$1"; else bad "$1"; fi; }
expect_ok() { if (cd "$repo" && "$wb" "${@:2}" >/dev/null 2>&1); then ok "$1"; else bad "$1"; fi; }
expect_fail() { if (cd "$repo" && "$wb" "${@:2}" >/dev/null 2>&1); then bad "$1"; else ok "$1"; fi; }
add() { mkdir -p "$repo/$(dirname "$1")" && echo x >"$repo/$1" && git -C "$repo" add "$1"; }

repo="$tmp/app"
mkdir -p "$repo"
git -C "$repo" init -q
printf 'name: demo_app\nversion: 1.2.3+45\n' >"$repo/pubspec.yaml"
git -C "$repo" add pubspec.yaml
add lib/main.dart
add assets/icon.png
add docs/images/start/a.png
add test/goldens/x.png
add test/ui/goldens/y.png
add store/ios/screenshots/de-DE/iphone69_01_start.png

expect_ok "layout: standard repository" layout
check "version" '[ "$("$wb" version)" = "1.2.3+45" ]'
check "version name" '[ "$("$wb" version name)" = "1.2.3" ]'
check "version build" '[ "$("$wb" version build)" = "45" ]'
check "runs from a subfolder" 'cd lib && "$wb" layout'

add notes.txt
expect_fail "layout: unknown top-level file" layout
git -C "$repo" rm -q --cached notes.txt

add docs/shot.png
expect_fail "layout: image loose in docs/" layout
git -C "$repo" rm -q --cached docs/shot.png

add notes.txt
add docs/shot.png
check "layout: reports top-level and media problems together" '! "$wb" layout 2>err; grep -q notes.txt err && grep -q docs/shot.png err'
git -C "$repo" rm -q --cached notes.txt docs/shot.png

add tool/case.stl
expect_fail "layout: model in tool/" layout
mkdir -p "$repo/tool"
printf "WB_MEDIA_EXTRA='tool/'\n" >"$repo/tool/werkbank.conf"
expect_ok "layout: WB_MEDIA_EXTRA allows it" layout

add box/setup.sh
expect_fail "layout: product folder without WB_TOP_EXTRA" layout
printf "WB_MEDIA_EXTRA='tool/'\nWB_TOP_EXTRA='box'\n" >"$repo/tool/werkbank.conf"
expect_ok "layout: WB_TOP_EXTRA allows it" layout

printf 'WB_APP=demo\n' >>"$repo/tool/werkbank.conf"
check "doctor reads the conf" '"$wb" doctor 2>/dev/null | grep -q "app demo, version 1.2.3+45"'

printf 'verify_quick_extra() { echo quick-hook; }\nverify_extra() { echo slow-hook; }\n' >>"$repo/tool/werkbank.conf"
check "hooks are loaded from the conf" '. "$(dirname "$wb")/../lib/common.sh"; wb_load_conf; wb_has_hook verify_quick_extra && wb_has_hook verify_extra'

expect_fail "android without key.properties" android
expect_fail "unknown command" frobnicate

if [ "$fails" != 0 ]; then
  echo "$fails failed"
  exit 1
fi
echo "all tests passed"
