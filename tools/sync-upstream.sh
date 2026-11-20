#!/usr/bin/env bash
set -euo pipefail

usage() { echo "usage: tools/sync-upstream.sh <aetherengine|ffmpegbuild|smbclient> <tag>" >&2; exit 64; }
[[ $# -eq 2 ]] || usage

skip=()
case "$1" in
  aetherengine) repo="superuser404notfound/AetherEngine" ;;
  ffmpegbuild)  repo="superuser404notfound/FFmpegBuild" ;;
  smbclient)    repo="kishikawakatsumi/SMBClient"; skip=(--exclude 'Tests/SMBClientTests/Fixtures') ;;
  *) usage ;;
esac
dir="$1"
tag="$2"
[[ "$tag" =~ ^[0-9A-Za-z._-]+$ ]] || { echo "bad tag: $tag" >&2; exit 64; }

root="$(cd "$(dirname "$0")/.." && pwd)"
work="$(mktemp -d)"
trap 'rm -rf "$work"' EXIT

commit="$(gh api "repos/$repo/commits/$tag" --jq .sha)"
gh api "repos/$repo/tarball/$commit" > "$work/src.tar.gz"
mkdir "$work/src"
tar -xzf "$work/src.tar.gz" -C "$work/src" --strip-components 1 \
  --exclude '*.xcframework' --exclude '*.zip' --exclude '*.a' --exclude '*.dylib' ${skip[@]+"${skip[@]}"}

mkdir -p "$root/$dir"
rsync -a --delete --exclude UPSTREAM "$work/src/" "$root/$dir/"
cat > "$root/$dir/UPSTREAM" <<META
repository: https://github.com/$repo
tag: $tag
commit: $commit
synced: $(date -u +%Y-%m-%dT%H:%M:%SZ)
binaries: not mirrored; prebuilt frameworks ship from the upstream tag above
META
echo "$dir -> $repo@$tag ($commit)"
