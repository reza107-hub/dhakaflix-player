# Third-party notices

DhakaFlix Player is licensed under the GNU General Public License v3.0
(see `LICENSE`). It includes or uses the components below. Their licences
are compatible with GPL-3.0.

## Playback engine (bundled in the Android and Windows builds)

The Android APK and the Windows build ship a prebuilt **libmpv** shared library
(`libmpv.so` / `libmpv-2.dll`) that contains **mpv** and **FFmpeg**. Both were
built in their LGPL configurations; checked from the build flags embedded in
the binaries:

| Platform | Source build | mpv | FFmpeg |
|---|---|---|---|
| Android (all ABIs) | [media-kit/libmpv-android-video-build v1.1.7](https://github.com/media-kit/libmpv-android-video-build/releases/tag/v1.1.7) | v0.36.0, `-Dgpl=false` → **LGPL-2.1-or-later** | n6.0, `--disable-gpl --disable-nonfree --enable-version3` → **LGPL-3.0-or-later** |
| Windows x64 | [media-kit/libmpv-win32-video-build 2023-09-24](https://github.com/media-kit/libmpv-win32-video-build/releases/tag/2023-09-24) | v0.36.0, `-Dgpl=false` → **LGPL-2.1-or-later** | n6.0, `--disable-gpl --disable-nonfree --enable-version3` → **LGPL-3.0-or-later** |
| Linux | Not bundled. The `.deb` uses the distribution's `libmpv2`/`libmpv1` package. | distro package | distro package |

LGPL notes:

- libmpv is a separate shared library. You can replace it with your own
  build: on Windows swap `libmpv-2.dll` next to the program; on Android
  rebuild the APK from this repository with a different libmpv.
- Complete corresponding source for these libraries is available from the
  build repositories linked above (their build scripts pin the exact upstream
  sources), and from upstream: <https://github.com/mpv-player/mpv>,
  <https://ffmpeg.org/download.html>.

Libraries linked into those libmpv builds (all GPL-3.0 compatible):

| Library | Licence | Android | Windows |
|---|---|---|---|
| libass | ISC | ✓ | ✓ |
| FreeType | FreeType License (FTL) | ✓ | ✓ |
| HarfBuzz | MIT | ✓ | ✓ |
| FriBidi | LGPL-2.1-or-later | ✓ | ✓ |
| dav1d | BSD-2-Clause | ✓ | ✓ |
| libxml2 | MIT | ✓ | ✓ |
| Mbed TLS | Apache-2.0 | ✓ | |
| libwebp, libjxl, Speex, libmysofa | BSD | | ✓ |
| oneVPL / libvpl, libmfx | MIT | | ✓ |
| zimg | WTFPL | | ✓ |
| libsoxr | LGPL-2.1-or-later | | ✓ |
| libbs2b | MIT | | ✓ |
| shaderc | Apache-2.0 | | ✓ |
| Little CMS (lcms2) | MIT | | ✓ |
| uchardet | MPL-1.1 / GPL-2.0+ / LGPL-2.1+ (used under LGPL) | | ✓ |
| MuJS | ISC | | ✓ |
| ANGLE (OpenGL ES on Windows) | BSD-3-Clause | | ✓ |

The list of Windows libraries comes from the FFmpeg/mpv build flags of the
binary. Its exact contents are set by the build repository above.

## Dart / Flutter packages

| Package | Licence |
|---|---|
| Flutter SDK and engine | BSD-3-Clause |
| media_kit, media_kit_video, media_kit_libs_* | MIT |
| sqflite_common_ffi | BSD-2-Clause |
| sqlite3 (Dart), with bundled SQLite | MIT; SQLite is public domain |
| http, path, path_provider | BSD-3-Clause |

The app's **Settings → About → View licences** page lists every Dart package
with its full licence text.

## Font

**Noto Sans** (`assets/fonts/NotoSans-Regular.ttf`) is used to render
subtitles on Android. Copyright 2022 The Noto Project Authors. Licensed under
the SIL Open Font License 1.1 (`assets/fonts/OFL.txt`).

## Trademarks and content

"DhakaFlix" is the name of a third-party media server. This project is not
affiliated with or endorsed by its operators. The app contains no media
content. It only plays files that the user's own DhakaFlix server provides.
