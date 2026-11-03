#!/usr/bin/env bash
# Copies the werkbank into an app repository (tool/werkbank/), or updates the
# copy there. The copy is what the project and its CI run, so a werkbank
# change reaches a project only through this script and a pull request there.
#
#   ./install.sh <path to the repository>
set -euo pipefail
here="$(cd "$(dirname "$0")" && pwd)"
repo="$(cd "${1:?usage: install.sh <repository>}" && git rev-parse --show-toplevel)"
target="$repo/tool/werkbank"
version="$(git -C "$here" describe --tags --always --dirty 2>/dev/null || echo unknown)"
rm -rf "$target"
mkdir -p "$target"
cp -R "$here/bin" "$here/lib" "$here/STANDARD.md" "$here/LICENSE" "$target/"
echo "$version" >"$target/VERSION"
cat >"$target/README.md" <<TXT
# werkbank (copy)

Copy of github.com/regetskcob/werkbank, version $version. Do not edit here:
change the werkbank repository, then run its install.sh for this repository.
Rules: STANDARD.md. Project settings: tool/werkbank.conf. License: MIT (LICENSE),
also when the project itself uses another license.
TXT
if [ ! -f "$repo/tool/werkbank.conf" ]; then
  cp "$here/werkbank.conf.example" "$repo/tool/werkbank.conf"
  echo "created tool/werkbank.conf – adjust it"
fi
echo "werkbank $version → $target"
