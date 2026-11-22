#!/usr/bin/env bash
# Builds the .deb inside an older distro so it runs there and on newer ones
# (a build only works on systems with the same or newer glibc/GLib).
# Usage: tool/build_deb_in_container.sh debian12|ubuntu22
# Needs podman (or docker via ENGINE=docker). Uses a throwaway copy of the
# source; the finished .deb is copied to build/dist/.
set -euo pipefail
cd "$(dirname "$0")/.."
target="${1:?debian12 or ubuntu22}"
case "$target" in
  debian12) image=docker.io/library/debian:12;    suffix="" ;;
  ubuntu22) image=docker.io/library/ubuntu:22.04; suffix="_ubuntu22.04" ;;
  *) echo "unknown target $target" >&2; exit 1 ;;
esac
engine="${ENGINE:-podman}"
flutter_dir="${FLUTTER_ROOT:-$(dirname "$(dirname "$(readlink -f "$(command -v flutter)")")")}"
work="${WORK_DIR:-$(mktemp -d)}"
echo "source copy: $work/src"
mkdir -p "$work/src"
git ls-files -z --cached --others --exclude-standard | xargs -0 -I{} cp --parents {} "$work/src/"
mkdir -p build/dist
$engine run --rm \
  -v "$work/src:/src" -v "$flutter_dir:/flutter:ro" -v "$PWD/build/dist:/out" \
  -e DEB_SUFFIX="$suffix" -e PUB_CACHE=/tmp/pub-cache -e HOME=/tmp/home \
  "$image" bash -euc '
    export DEBIAN_FRONTEND=noninteractive
    apt-get update -qq
    apt-get install -y -qq --no-install-recommends ca-certificates git curl unzip xz-utils \
      clang cmake ninja-build pkg-config libgtk-3-dev libmpv-dev dpkg-dev >/dev/null
    mkdir -p "$HOME" && git config --global --add safe.directory "*"
    # Writable copy of the SDK (Flutter writes its cache on first run).
    cp -a /flutter /tmp/flutter && export PATH=/tmp/flutter/bin:$PATH
    flutter config --no-analytics >/dev/null
    cd /src && flutter pub get >/dev/null
    out=$(tool/build_deb.sh | tail -1)
    cp "$out" /out/ && echo "built: /out/$(basename "$out")"
  '
