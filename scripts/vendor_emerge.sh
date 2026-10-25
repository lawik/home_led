#!/usr/bin/env bash
# home_base depends on emerge as a path dependency: hex emerge 0.5.0 plus the Elixir-only
# scene-forwarding patch kept in ../home_base/docs. This fetches that into $EMERGE_PATH
# (set in .envrc) so `mix deps.get` for the firmware works on this machine.
set -euo pipefail

here="$(cd "$(dirname "$0")/.." && pwd)"
dest="${EMERGE_PATH:-$here/../_vendor/emerge-home}"
version="${EMERGE_VERSION:-0.5.0}"
patch_file="$here/../home_base/docs/emerge-scene-forwarding.patch"

if [ -e "$dest/mix.exs" ]; then
  echo "emerge already vendored at $dest"
  exit 0
fi

tmp="$(mktemp -d)"
trap 'rm -rf "$tmp"' EXIT
(cd "$tmp" && mix hex.package fetch emerge "$version" --unpack >/dev/null)
mkdir -p "$(dirname "$dest")"
mv "$tmp/emerge-$version" "$dest"
(cd "$dest" && patch -p1 --forward < "$patch_file")
echo "emerge $version + scene-forwarding patch vendored at $dest"
