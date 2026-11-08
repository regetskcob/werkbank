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
printf '<de-DE>\nNur Deutsch.\n</de-DE>\n' >"$repo/store/android/play-notes-45.txt"
expect_fail "notes: a store language without Play notes" notes
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
mkdir -p "$repo/ios" "$repo/macos"
add integration_test/a_test.dart
add integration_test/b_test.dart
check "devicetest: every device but the web, every test, report with the failure" \
  'export FAKE_LOG="$tmp/flutter.log"; ! PATH="$tmp/bin:$PATH" "$wb" devicetest >/dev/null 2>&1;
   [ "$(grep -c "flutter drive --keep-app-running" "$FAKE_LOG")" = 4 ] && ! grep -q chrome "$FAKE_LOG" &&
   grep -q "| BoPhone | integration_test/b_test.dart | FAILED |" build/devicetest/*/report.md &&
   grep -q "| macOS | integration_test/a_test.dart | ok |" build/devicetest/*/report.md'
check "devicetest leaves out platforms the project does not have" \
  'rmdir ios; rm -rf build/devicetest; export FAKE_LOG="$tmp/flutter3.log"; PATH="$tmp/bin:$PATH" "$wb" devicetest >/dev/null 2>&1;
   ! grep -q phone1 "$FAKE_LOG" && grep -q "\-d macos" "$FAKE_LOG"; s=$?; mkdir ios; exit $s'
check "devicetest skips a device whose devicetest_before fails" \
  'cp tool/werkbank.conf "$tmp/conf.bak"; printf "devicetest_before() { [ \"\$2\" != ios ]; }\n" >>tool/werkbank.conf;
   rm -rf build/devicetest; export FAKE_LOG="$tmp/flutter4.log"; ! PATH="$tmp/bin:$PATH" "$wb" devicetest >/dev/null 2>&1;
   s=1; ! grep -q phone1 "$FAKE_LOG" && grep -q "| BoPhone | – | skipped" build/devicetest/*/report.md && s=0;
   cp "$tmp/conf.bak" tool/werkbank.conf; exit $s'
check "devicetest --device runs one device only" \
  'rm -rf build/devicetest; export FAKE_LOG="$tmp/flutter2.log"; PATH="$tmp/bin:$PATH" "$wb" devicetest --device macos integration_test/a_test.dart >/dev/null 2>&1;
   [ "$(grep -c . "$FAKE_LOG")" = 1 ] && grep -q "\-d macos" "$FAKE_LOG"'

# Release: a fresh project with an origin, one product built by a hook.
rel="$tmp/rel"
git init -q --bare -b main "$tmp/rel-origin.git"
git init -q -b main "$rel"
git -C "$rel" config user.name t
git -C "$rel" config user.email t@example.com
printf 'name: rel\nversion: 2.0.0+7\n' >"$rel/pubspec.yaml"
printf '# Changelog\n\n## 1.0.0\n\n- old\n' >"$rel/CHANGELOG.md"
mkdir -p "$rel/tool"
cat >"$rel/tool/werkbank.conf" <<'CONF'
WB_PLATFORMS_app=''
verify_release() { echo verified >>build/calls; }
release_app() { mkdir -p build/release; echo "built upload=$1" >>build/calls; echo x >build/release/rel-2.0.0+7.zip; [ -z "${FAKE_RESOLVE:-}" ] || echo resolved-anew >"$FAKE_RESOLVE"; }
CONF
printf 'build/\n' >"$rel/.gitignore"
resolved=ios/Runner.xcworkspace/xcshareddata/swiftpm/Package.resolved
mkdir -p "$rel/$(dirname "$resolved")" && echo pinned >"$rel/$resolved"
git -C "$rel" add -A
git -C "$rel" commit -q -m init
git -C "$rel" remote add origin "$tmp/rel-origin.git"
git -C "$rel" push -q -u origin main
rr() { (cd "$rel" && "$wb" "$@"); }
check "release: a build_ios hook replaces the werkbank iOS build" \
  '[ "$(cd "$rel" && . "$(dirname "$wb")/../lib/common.sh" && wb_load_conf && unset -f release_app && WB_PLATFORMS_app=ios &&
     build_ios() { echo "hook upload=$1"; } && wb_ios() { echo werkbank-ios; } && wb_release_build app true)" = "hook upload=true" ]'
if rr release --dry-run >/dev/null 2>"$tmp/err"; then bad "release: dry run refuses a version without changelog section"; else
  if grep -q 'no finished section "## 2.0.0' "$tmp/err"; then ok "release: dry run refuses a version without changelog section"; else bad "release: dry run names the missing section"; fi
fi
printf '# Changelog\n\n## 2.0.0 – 2026-11-05\n\n- new\n\n## 1.0.0\n\n- old\n' >"$rel/CHANGELOG.md"
printf '# Änderungen\n\n## 2.0.0 – 2026-11-05\n\n- neu\n' >"$rel/CHANGELOG.de.md"
git -C "$rel" add -A
git -C "$rel" commit -q -m changelog
git -C "$rel" push -q
check "release: changelog section without the heading" '[ "$(cd "$rel" && . "$(dirname "$wb")/../lib/common.sh" && wb_load_conf && wb_changelog_section 2.0.0)" = "- new" ]'
check "release: dry run is ready and changes nothing" 'rr release --dry-run 2>&1 | grep "would release app 2.0.0+7" >/dev/null && [ -z "$(git -C "$rel" tag)" ] && [ ! -e "$rel/build/calls" ]'
echo dirty >"$rel/dirty.txt"
check "release: refuses uncommitted changes" '! rr release >/dev/null 2>&1 && [ -z "$(git -C "$rel" tag)" ]'
rm "$rel/dirty.txt"
check "resolved: a check outside a hook promises no upload happened" \
  'echo resolved-anew >"$rel/$resolved"; ! (cd "$rel" && . "$(dirname "$wb")/../lib/common.sh" && wb_resolved_guard) 2>"$tmp/err"; git -C "$rel" checkout -q -- "$resolved"; grep -q "nothing was uploaded or tagged" "$tmp/err"'
check "resolved: unchanged Package.resolved passes" 'rr resolved >/dev/null 2>&1'
echo resolved-anew >"$rel/$resolved"
check "resolved: a rewritten Package.resolved fails and is named" '! rr resolved 2>"$tmp/err" >/dev/null && grep -q "$resolved" "$tmp/err"'
check "release: dry run names a rewritten Package.resolved" '! rr release --dry-run 2>"$tmp/err" >/dev/null && grep -q "Package.resolved changed.*$resolved" "$tmp/err" && ! grep -q "uncommitted changes" "$tmp/err"'
git -C "$rel" checkout -q -- "$resolved"
mkdir -p "$rel/macos/Runner.xcworkspace"
echo new >"$rel/macos/Runner.xcworkspace/Package.resolved"
check "resolved: a new untracked Package.resolved counts" '! rr resolved >/dev/null 2>&1'
rm -r "$rel/macos"
check "release: a build that rewrites Package.resolved stops before the tag" \
  '! FAKE_RESOLVE="$resolved" rr release 2>"$tmp/err" >/dev/null && grep -q "commit them via PR" "$tmp/err" && grep -q "already in the store" "$tmp/err" && [ -z "$(git -C "$rel" tag)" ] &&
   ! git --git-dir="$tmp/rel-origin.git" rev-parse -q --verify refs/tags/v2.0.0+7 >/dev/null'
git -C "$rel" checkout -q -- "$resolved"
rm -f "$rel/build/calls"
check "release: verify, build, tag pushed, report" 'rr release >/dev/null 2>&1 && grep -q verified "$rel/build/calls" && grep -q "built upload=false" "$rel/build/calls" &&
   git --git-dir="$tmp/rel-origin.git" rev-parse -q --verify refs/tags/v2.0.0+7 >/dev/null && grep -q "tag v2.0.0+7" "$rel"/build/release/report-*.md'
check "release: a released version is skipped" 'rr release 2>&1 | grep "already released" >/dev/null'
check "release: products and tag prefixes from the conf" \
  'printf "WB_PRODUCTS=\"app addon\"\nWB_VERSION_FILE_addon=addon.yaml\nWB_TAG_PREFIX_app=app-v\n" >>"$rel/tool/werkbank.conf"; printf "version: \"1.4.0\"\n" >"$rel/addon.yaml";
   out=$(cd "$rel" && . "$(dirname "$wb")/../lib/common.sh" && wb_load_conf && echo "$(wb_product_version addon) $(wb_tag_prefix addon) $(wb_tag_prefix app)"); [ "$out" = "1.4.0 addon-v app-v" ]'

# Changelog: "Unreleased" becomes the version, otherwise a marked draft; heading format checked.
cl="$tmp/cl"
git init -q -b main "$cl"
printf 'name: cl\nversion: 3.1.0+9\n' >"$cl/pubspec.yaml"
printf '# Changelog\n\nIntro.\n\n## Unreleased\n\n### New\n\n- A view\n\n## 3.0.0 – 2026-10-01\n\n- old\n' >"$cl/CHANGELOG.md"
cc() { (cd "$cl" && "$wb" "$@"); }
check "changelog: missing German file and section" '! cc changelog >/dev/null 2>&1'
check "changelog --draft: Unreleased becomes the version with today, German drafted" \
  'cc changelog --draft >/dev/null 2>&1; grep -q "^## 3.1.0 – $(date +%F)$" "$cl/CHANGELOG.md" && ! grep -q Unreleased "$cl/CHANGELOG.md" &&
   grep -q "^## 3.1.0 – " "$cl/CHANGELOG.de.md" && grep -q ENTWURF "$cl/CHANGELOG.de.md"'
check "changelog: a draft is not finished" '! cc changelog >/dev/null 2>&1'
sed -i.bak '/ENTWURF/d' "$cl/CHANGELOG.de.md" && rm "$cl/CHANGELOG.de.md.bak"
check "changelog: complete in both languages" 'cc changelog >/dev/null 2>&1'
sed -i.bak 's/^## 3.1.0 – .*/## 3.1.0/' "$cl/CHANGELOG.md" && rm "$cl/CHANGELOG.md.bak"
check "changelog: heading needs the date" '! cc changelog >/dev/null 2>&1'

# Sites: preview builds only, --live deploys to gh-pages (stand-in hugo, local "GitHub").
cat >"$tmp/bin/hugo" <<'FAKE'
#!/usr/bin/env bash
while [ $# -gt 0 ]; do [ "$1" = --destination ] && dest=$2; shift; done
mkdir -p "$dest" && echo "<h1>site</h1>" >"$dest/index.html"
FAKE
chmod +x "$tmp/bin/hugo"
mkdir -p "$tmp/gh/o" "$rel/site"
git init -q --bare -b main "$tmp/gh/o/pages.git"
echo "WB_SITES='web=site|https://example.org/|ghpages:o/pages:example.org'" >>"$rel/tool/werkbank.conf"
check "site-deploy: preview builds, deploys nothing" 'PATH="$tmp/bin:$PATH" rr site-deploy web 2>&1 | grep Preview >/dev/null && ! git --git-dir="$tmp/gh/o/pages.git" rev-parse -q --verify gh-pages >/dev/null'
check "site-deploy --live: gh-pages with CNAME and .nojekyll" \
  'PATH="$tmp/bin:$PATH" WB_GIT_BASE="$tmp/gh/" rr site-deploy web --live >/dev/null 2>&1 &&
   [ "$(git --git-dir="$tmp/gh/o/pages.git" show gh-pages:CNAME)" = example.org ] && git --git-dir="$tmp/gh/o/pages.git" show gh-pages:.nojekyll >/dev/null &&
   git --git-dir="$tmp/gh/o/pages.git" show gh-pages:index.html | grep -q site'
git clone -q "$tmp/gh/o/pages.git" "$tmp/pages-edit" -b gh-pages
mkdir -p "$tmp/pages-edit/socials" && echo social >"$tmp/pages-edit/socials/index.html"
git -C "$tmp/pages-edit" add -A && git -C "$tmp/pages-edit" -c user.name=t -c user.email=t@e commit -q -m socials && git -C "$tmp/pages-edit" push -q
echo "WB_SITE_KEEP_web='socials'" >>"$rel/tool/werkbank.conf"
check "site-deploy --live keeps folders the build lacks (WB_SITE_KEEP_<name>)" \
  'PATH="$tmp/bin:$PATH" WB_GIT_BASE="$tmp/gh/" rr site-deploy web --live >/dev/null 2>&1 &&
   git --git-dir="$tmp/gh/o/pages.git" show gh-pages:socials/index.html | grep -q social'
expect_fail "site-deploy: unknown site" site-deploy nope

# Verify stamp: a clean tree is stamped, push marks exactly that commit on GitHub.
st="$tmp/stamp"
git init -q --bare -b main "$tmp/stamp-origin.git"
git init -q -b main "$st"
git -C "$st" -c user.name=t -c user.email=t@e commit -q --allow-empty -m one
git -C "$st" remote add origin "$tmp/stamp-origin.git"
mkdir -p "$tmp/ghbin"
cat >"$tmp/ghbin/gh" <<'FAKE'
#!/usr/bin/env bash
case "$1" in
  repo) echo o/stamp ;;
  api) echo "$*" >>"$GH_LOG" ;;
esac
FAKE
chmod +x "$tmp/ghbin/gh"
# shellcheck source=/dev/null
sw() { (cd "$st" && . "$(dirname "$wb")/../lib/common.sh" && "$@"); }
check "stamp: a quick verify stamps only where the CI runs quick (WB_CI_VERIFY)" \
  'rm -f "$st/.git/werkbank-verified"; (cd "$st" && . "$(dirname "$wb")/../lib/common.sh" && wb_load_conf && WB_CI_VERIFY=quick &&
     [ "$WB_CI_VERIFY" = quick ] && wb_stamp_verified >/dev/null) && [ -f "$st/.git/werkbank-verified" ]'
check "stamp: a clean tree after verify is stamped with HEAD" \
  'sw wb_stamp_verified >/dev/null && [ "$(cat "$st/.git/werkbank-verified")" = "$(git -C "$st" rev-parse HEAD)" ]'
echo x >"$st/new.txt"
check "stamp: untracked files mean no stamp" '! { sw wb_stamp_verified >/dev/null; [ -f "$st/.git/werkbank-verified" ]; }'
rm "$st/new.txt"
sw wb_stamp_verified >/dev/null
check "push: the stamped HEAD gets status werkbank/verify" \
  'export GH_LOG="$tmp/gh1.log"; PATH="$tmp/ghbin:$PATH" sw wb_push -q -u origin main >/dev/null 2>&1 &&
   grep -q "statuses/$(git -C "$st" rev-parse HEAD) -f state=success -f context=werkbank/verify" "$GH_LOG"'
git -C "$st" -c user.name=t -c user.email=t@e commit -q --allow-empty -m two
check "push: a commit after verify gets no status, the push still happens" \
  'export GH_LOG="$tmp/gh2.log"; PATH="$tmp/ghbin:$PATH" sw wb_push -q >/dev/null 2>"$tmp/err" &&
   [ ! -s "$GH_LOG" ] && grep -q "CI runs in full" "$tmp/err" &&
   [ "$(git --git-dir="$tmp/stamp-origin.git" rev-parse main)" = "$(git -C "$st" rev-parse HEAD)" ]'

sw wb_stamp_verified >/dev/null
git -C "$st" tag -a v1 -m v1
check "push-tag: the tag is pushed and the stamped commit gets werkbank/verify" \
  'export GH_LOG="$tmp/gh3.log"; PATH="$tmp/ghbin:$PATH" sw wb_push_tag v1 >/dev/null 2>&1 &&
   git --git-dir="$tmp/stamp-origin.git" rev-parse -q --verify refs/tags/v1 >/dev/null &&
   grep -q "statuses/$(git -C "$st" rev-parse HEAD) -f state=success -f context=werkbank/verify" "$GH_LOG"'
check "stamp: a named stamp gets its own status werkbank/<name>" \
  'export GH_LOG="$tmp/gh4.log"; sw wb_stamp smoke >/dev/null && PATH="$tmp/ghbin:$PATH" sw wb_push -q >/dev/null 2>&1 &&
   grep -q "context=werkbank/smoke" "$GH_LOG" && grep -q "context=werkbank/verify" "$GH_LOG"'
git -C "$st" -c user.name=t -c user.email=t@e commit -q --allow-empty -m three
git -C "$st" tag -a v2 -m v2
check "push-tag: a tag on a commit verify did not check gets no status" \
  'export GH_LOG="$tmp/gh5.log"; PATH="$tmp/ghbin:$PATH" sw wb_push_tag v2 >/dev/null 2>"$tmp/err" &&
   [ ! -s "$GH_LOG" ] && grep -q "CI runs in full" "$tmp/err"'

expect_fail "android without key.properties" android
expect_fail "unknown command" frobnicate

if [ "$fails" != 0 ]; then
  echo "$fails failed"
  exit 1
fi
echo "all tests passed"
