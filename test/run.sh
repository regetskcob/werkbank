#!/usr/bin/env bash
# Tests of the werkbank CLI in throwaway repositories (no Flutter needed).
# shellcheck disable=SC2016 # check() evaluates its command in the test repo
set -euo pipefail
wb="$(cd "$(dirname "$0")/.." && pwd)/bin/werkbank"
tmp=$(mktemp -d)
trap 'rm -rf "$tmp"' EXIT
fails=0
# Tests must not touch the clipboard of whoever runs them.
export WB_NO_CLIPBOARD=1
ok() { printf 'ok   %s\n' "$1"; }
bad() { printf 'FAIL %s\n' "$1"; fails=$((fails + 1)); }
# check <name> <command…>: passes if the command succeeds.
check() { if (cd "$repo" && eval "${*:2}") >/dev/null 2>&1; then ok "$1"; else bad "$1"; fi; }
expect_ok() { if (cd "$repo" && "$wb" "${@:2}" >/dev/null 2>"$tmp/err"); then ok "$1"; else bad "$1"; cat "$tmp/err"; fi; }
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

echo x >"$repo/untracked.txt"
expect_fail "layout: new file not yet added" layout
rm "$repo/untracked.txt"
printf 'ignored/\n' >"$repo/.gitignore"
mkdir -p "$repo/ignored" && echo x >"$repo/ignored/a.png"
git -C "$repo" add .gitignore
expect_ok "layout: ignored files do not count" layout

add notes.txt
expect_fail "layout: unknown top-level file" layout
git -C "$repo" rm -q -f notes.txt

add docs/shot.png
expect_fail "layout: image loose in docs/" layout
git -C "$repo" rm -q -f docs/shot.png

add notes.txt
add docs/shot.png
check "layout: reports top-level and media problems together" '! "$wb" layout 2>"$tmp/err"; grep -q notes.txt "$tmp/err" && grep -q docs/shot.png "$tmp/err"'
git -C "$repo" rm -q -f notes.txt docs/shot.png

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

web="$tmp/blog"
git init -q "$web"
mkdir -p "$tmp/built/a" "$web/static/demo/keep"
echo new >"$tmp/built/a/index.html"
echo old >"$web/static/demo/stale.html"
echo kept >"$web/static/demo/keep/x.html"
check "site blog copies, deletes stale files, keeps --keep" \
  '. "$(dirname "$wb")/../lib/common.sh"; wb_load_conf; WEBSITE_REPO="$web" wb_site_blog "$tmp/built" demo --keep /keep/ &&
   [ -f "$web/static/demo/a/index.html" ] && [ ! -e "$web/static/demo/stale.html" ] && [ -f "$web/static/demo/keep/x.html" ]'
git -C "$web" add -A
git -C "$web" -c user.name=test -c user.email=test@example.com commit -q -m site
check "site blog --push with nothing changed succeeds" \
  '. "$(dirname "$wb")/../lib/common.sh"; wb_load_conf; WEBSITE_REPO="$web" wb_site_blog "$tmp/built" demo --keep /keep/ --push | grep -q "nothing to push"'

expect_fail "collect: missing file" collect ipa nothing.ipa
echo ipa >"$tmp/x.ipa"
check "collect ipa copies to build/release" '"$wb" collect ipa "$tmp/x.ipa" && [ -f build/release/demo-1.2.3+45.ipa ]'

check "collect with variant" '"$wb" collect ipa "$tmp/x.ipa" wear && [ -f build/release/demo-wear-1.2.3+45.ipa ]'
mkdir -p "$repo/tool/werkbank"
cp -R "$(dirname "$wb")/../bin" "$(dirname "$wb")/../lib" "$repo/tool/werkbank/"
check "a copy in tool/werkbank acts on its project from anywhere" 'cd / && "$repo/tool/werkbank/bin/werkbank" version | grep -q 1.2.3+45'
rm -rf "$repo/tool/werkbank"

# Release texts: drafts from merged pull requests, refused while marked, then complete.
git -C "$repo" -c user.name=t -c user.email=t@example.com commit -q -m init
git -C "$repo" tag v1.2.3+44
git -C "$repo" checkout -q -b feature
git -C "$repo" -c user.name=t -c user.email=t@example.com commit -q --allow-empty -m work
git -C "$repo" checkout -q -
git -C "$repo" -c user.name=t -c user.email=t@example.com merge -q --no-ff feature -m 'Merge pull request #7 from o/feature

Neue Ansicht'
expect_fail "notes: missing texts" notes
check "notes --draft creates drafts from merged pull requests" \
  '"$wb" notes --draft >/dev/null 2>&1; grep -q "^- Neue Ansicht" store/ios/testflight/whats_new_45_de-DE.txt && grep -q "<en-US>" store/android/play-notes-45.txt'
expect_fail "notes: drafts are not finished texts" notes
printf 'Neu: eine Ansicht.\n' >"$repo/store/ios/testflight/whats_new_45_de-DE.txt"
printf 'New: a view.\n' >"$repo/store/ios/testflight/whats_new_45_en-US.txt"
printf '<de-DE>\nNeu: eine Ansicht.\n</de-DE>\n<en-US>\nNew: a view.\n</en-US>\n' >"$repo/store/android/play-notes-45.txt"
check "notes: complete texts, Play block printed" '"$wb" notes 2>/dev/null | grep "<de-DE>" >/dev/null'
python3 -c 'print("<de-DE>" + "x" * 501 + "</de-DE>")' >"$repo/store/android/play-notes-45.txt"
expect_fail "notes: Play notes over 500 characters" notes
printf '<de-DE>\nNeu.\n</de-DE>\n' >"$repo/store/android/play-notes-45.txt"
echo aab >"$tmp/a.aab"
check "play upload (dry run) reads package, track and notes" \
  'python3 "$(dirname "$wb")/../lib/play_upload.py" --key none --package de.demo.app --aab "$tmp/a.aab" --track alpha --status draft --notes store/android/play-notes-45.txt --dry-run | grep -q "de.demo.app, track alpha (draft), notes: de-DE"'
check "play upload refuses an odd package name" \
  '! python3 "$(dirname "$wb")/../lib/play_upload.py" --key none --package "x;rm" --aab "$tmp/a.aab" --dry-run'
expect_fail "upload-play without WB_PLAY_PACKAGE" upload-play "$tmp/a.aab"
expect_fail "upload-apple without archive" upload-apple "$tmp/none.xcarchive"

# Device tests with a stand-in flutter: two devices plus the web, one test fails on one device.
mkdir -p "$tmp/bin" "$repo/integration_test"
cat >"$tmp/bin/flutter" <<'FAKE'
#!/usr/bin/env bash
if [ "$1" = devices ]; then
  echo '[{"id":"phone1","name":"BoPhone","targetPlatform":"ios"},{"id":"macos","name":"macOS","targetPlatform":"darwin"},{"id":"chrome","name":"Chrome","targetPlatform":"web-javascript"}]'
  exit 0
fi
echo "flutter $*" >>"$FAKE_LOG"
case "$*" in *--keep-app-running*) ;; *) exit 3 ;; esac
case "$*" in *--target=integration_test/b_test.dart*"-d phone1"*) exit 1 ;; esac
exit 0
FAKE
chmod +x "$tmp/bin/flutter"
add integration_test/a_test.dart
add integration_test/b_test.dart
check "devicetest: every device but the web, every test, report with the failure" \
  'export FAKE_LOG="$tmp/flutter.log"; ! PATH="$tmp/bin:$PATH" "$wb" devicetest >/dev/null 2>&1;
   [ "$(grep -c "flutter drive --keep-app-running" "$FAKE_LOG")" = 4 ] && ! grep -q chrome "$FAKE_LOG" &&
   grep -q "| BoPhone | integration_test/b_test.dart | FAILED |" build/devicetest/*/report.md &&
   grep -q "| macOS | integration_test/a_test.dart | ok |" build/devicetest/*/report.md'
check "devicetest --device runs one device only" \
  'rm -rf build/devicetest; export FAKE_LOG="$tmp/flutter2.log"; PATH="$tmp/bin:$PATH" "$wb" devicetest --device macos integration_test/a_test.dart >/dev/null 2>&1;
   [ "$(grep -c . "$FAKE_LOG")" = 1 ] && grep -q "\-d macos" "$FAKE_LOG"'

expect_fail "android without key.properties" android
expect_fail "unknown command" frobnicate

if [ "$fails" != 0 ]; then
  echo "$fails failed"
  exit 1
fi
echo "all tests passed"
