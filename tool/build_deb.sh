#!/usr/bin/env bash
# Builds the Linux release and packs it into a .deb with dpkg-deb.
# Usage: tool/build_deb.sh            -> build/dist/dhakaflix-player_<version>_amd64.deb
#        DEB_SUFFIX=_ubuntu22.04 tool/build_deb.sh   (name for the libmpv1 build)
#        SKIP_FLUTTER_BUILD=1 tool/build_deb.sh   (reuse an existing release bundle)
set -euo pipefail
cd "$(dirname "$0")/.."
[ -f tool/env.sh ] && . tool/env.sh
version=$(grep -E '^version:' pubspec.yaml | sed -E 's/version: *([0-9.]+).*/\1/')
pkg=dhakaflix-player
arch=amd64
[ "${SKIP_FLUTTER_BUILD:-0}" = 1 ] || flutter build linux --release
bundle=build/linux/x64/release/bundle
root=build/deb/${pkg}_${version}_${arch}
rm -rf "$root"; mkdir -p "$root/DEBIAN" "$root/opt/$pkg" "$root/usr/bin" \
  "$root/usr/share/applications" "$root/usr/share/icons/hicolor/256x256/apps" "$root/usr/share/doc/$pkg"

cp -r "$bundle"/. "$root/opt/$pkg/"
ln -s "/opt/$pkg/dhakaflix_player" "$root/usr/bin/$pkg"
install -m644 packaging/linux/$pkg.desktop "$root/usr/share/applications/"
install -m644 packaging/linux/$pkg.png "$root/usr/share/icons/hicolor/256x256/apps/"
install -m644 LICENSE NOTICE.md "$root/usr/share/doc/$pkg/"
install -m644 CHANGELOG.md "$root/usr/share/doc/$pkg/changelog"

# media_kit_video links against the build machine's libmpv soname, so the
# package must require exactly that one (libmpv.so.2 -> libmpv2, .so.1 -> libmpv1).
soname=$(readelf -d "$bundle/lib/libmedia_kit_video_plugin.so" | grep -oE 'libmpv\.so\.[0-9]+' | head -1)
case "$soname" in
  libmpv.so.2) mpv_dep="libmpv2" ;;
  libmpv.so.1) mpv_dep="libmpv1" ;;
  *) echo "Unexpected libmpv soname: '$soname'" >&2; exit 1 ;;
esac
size=$(du -sk --exclude=DEBIAN "$root" | cut -f1)
cat > "$root/DEBIAN/control" <<CTRL
Package: $pkg
Version: $version
Section: video
Priority: optional
Architecture: $arch
Installed-Size: $size
Depends: $mpv_dep, libgtk-3-0t64 | libgtk-3-0, libglib2.0-0t64 | libglib2.0-0, libegl1, libgles2, libstdc++6, libc6 (>= 2.34)
Recommends: mesa-va-drivers | intel-media-va-driver | va-driver-all
Maintainer: reza107-hub <reza107-hub@users.noreply.github.com>
Description: Lightweight player for DhakaFlix servers
 Search, browse and stream movies and series from a DhakaFlix (h5ai)
 server on the ISP network. Plays HEVC 10-bit, AC3/DTS, multiple audio
 tracks and ASS subtitles via libmpv. No account, no tracking.
CTRL
# Refresh desktop caches on install/remove when the tools exist.
for s in postinst postrm; do
  printf '#!/bin/sh\nset -e\ncommand -v update-desktop-database >/dev/null && update-desktop-database -q /usr/share/applications || true\ncommand -v gtk-update-icon-cache >/dev/null && gtk-update-icon-cache -q -t /usr/share/icons/hicolor || true\n' > "$root/DEBIAN/$s"
  chmod 755 "$root/DEBIAN/$s"
done
find "$root" -type d -exec chmod 755 {} +
chmod 755 "$root/opt/$pkg/dhakaflix_player"
mkdir -p build/dist
out=build/dist/${pkg}_${version}${DEB_SUFFIX:-}_${arch}.deb
dpkg-deb --root-owner-group -Zxz --build "$root" "$out" >/dev/null
echo "$out"
