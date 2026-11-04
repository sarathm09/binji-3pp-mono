#!/usr/bin/env bash
set -euo pipefail

usage() {
  echo "usage: libass/build.sh [ios|iossim|macos|tvos|tvossim|xros|xrossim ...]   (default: all)" >&2
  exit 64
}

here="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
root="$(cd "$here/.." && pwd)"
out="$root/.build/libass"
min_os="26.0"
bundle_prefix="app.s10n.apple.Binji.vendor"
all_slices="ios iossim macos tvos tvossim xros xrossim"
slices="${*:-$all_slices}"
for s in $slices; do
  case " $all_slices " in *" $s "*) ;; *) usage ;; esac
done

for tool in meson ninja pkg-config xcrun xcodebuild lipo ditto shasum curl; do
  command -v "$tool" >/dev/null || { echo "missing tool: $tool" >&2; exit 69; }
done

lock_field() { awk -v n="$1" -v f="$2" '$1 == n { print $f }' "$here/sources.lock"; }
version_of() { lock_field "$1" 2; }

fetch() {
  local name="$1" version sha url file
  version="$(lock_field "$name" 2)"
  sha="$(lock_field "$name" 3)"
  url="$(lock_field "$name" 4)"
  [[ -n "$sha" && "$url" == https://* ]] || { echo "bad lock entry: $name" >&2; exit 65; }
  file="$out/downloads/$(basename "$url")"
  mkdir -p "$out/downloads" "$out/src"
  if [[ ! -f "$file" ]] || ! echo "$sha  $file" | shasum -a 256 -c --status; then
    curl -fsSL --proto '=https' --tlsv1.2 -o "$file.part" "$url"
    echo "$sha  $file.part" | shasum -a 256 -c --status || { echo "checksum mismatch: $url" >&2; rm -f "$file.part"; exit 65; }
    mv "$file.part" "$file"
  fi
  if [[ ! -d "$out/src/$name-$version" ]]; then
    tar -xJf "$file" -C "$out/src"
  fi
}

slice_config() {
  case "$1" in
    ios)     sdk=iphoneos;         archs="arm64";        suffix="apple-ios$min_os";             subsystem=ios;                platform=iPhoneOS ;;
    iossim)  sdk=iphonesimulator;  archs="arm64";        suffix="apple-ios$min_os-simulator";   subsystem=ios-simulator;      platform=iPhoneSimulator ;;
    macos)   sdk=macosx;           archs="arm64 x86_64"; suffix="apple-macos$min_os";           subsystem=macos;              platform=MacOSX ;;
    tvos)    sdk=appletvos;        archs="arm64";        suffix="apple-tvos$min_os";            subsystem=tvos;               platform=AppleTVOS ;;
    tvossim) sdk=appletvsimulator; archs="arm64";        suffix="apple-tvos$min_os-simulator";  subsystem=tvos-simulator;     platform=AppleTVSimulator ;;
    xros)    sdk=xros;             archs="arm64";        suffix="apple-xros$min_os";            subsystem=visionos;           platform=XROS ;;
    xrossim) sdk=xrsimulator;      archs="arm64";        suffix="apple-xros$min_os-simulator";  subsystem=visionos-simulator; platform=XRSimulator ;;
  esac
  sdk_path="$(xcrun --sdk "$sdk" --show-sdk-path)"
}

write_cross_file() {
  local file="$1" arch="$2" triple="$3" prefix="$4" family
  [[ "$arch" == arm64 ]] && family=aarch64 || family=x86_64
  local flags="['-target', '$triple', '-isysroot', '$sdk_path']"
  cat > "$file" <<CROSS
[binaries]
c = '$(xcrun --sdk "$sdk" --find clang)'
cpp = '$(xcrun --sdk "$sdk" --find clang++)'
objc = '$(xcrun --sdk "$sdk" --find clang)'
ar = '$(xcrun --sdk "$sdk" --find ar)'
strip = '$(xcrun --sdk "$sdk" --find strip)'
pkg-config = '$(command -v pkg-config)'

[built-in options]
c_args = $flags
cpp_args = $flags
objc_args = $flags
c_link_args = $flags
cpp_link_args = $flags
objc_link_args = $flags

[properties]
needs_exe_wrapper = true
pkg_config_libdir = ['$prefix/lib/pkgconfig']

[host_machine]
system = 'darwin'
subsystem = '$subsystem'
kernel = 'xnu'
cpu_family = '$family'
cpu = '$arch'
endian = 'little'
CROSS
}

meson_options() {
  case "$1" in
    freetype) echo "-Dbrotli=disabled -Dbzip2=disabled -Dharfbuzz=disabled -Dpng=disabled -Dzlib=disabled -Dtests=disabled" ;;
    fribidi)  echo "-Ddeprecated=false -Ddocs=false -Dbin=false -Dtests=false" ;;
    harfbuzz) echo "-Dglib=disabled -Dgobject=disabled -Dcairo=disabled -Dchafa=disabled -Dpng=disabled -Dzlib=disabled -Dicu=disabled -Dfreetype=disabled -Dcoretext=disabled -Draster=disabled -Dvector=disabled -Dgpu=disabled -Dgpu_demo=disabled -Dsubset=disabled -Dtests=disabled -Dintrospection=disabled -Ddocs=disabled -Dutilities=disabled -Dbenchmark=disabled" ;;
    libass)   echo "-Dfontconfig=disabled -Dcoretext=enabled -Ddirectwrite=disabled -Dlibunibreak=disabled -Dasm=disabled -Dtest=disabled -Dcompare=disabled -Dprofile=disabled -Dfuzz=disabled -Dcheckasm=disabled -Drequire-system-font-provider=true" ;;
  esac
}

framework_name() {
  case "$1" in
    freetype) echo Libfreetype ;; fribidi) echo Libfribidi ;; harfbuzz) echo Libharfbuzz ;; libass) echo Libass ;;
  esac
}

install_name() {
  local fw="$1"
  if [[ "$platform" == MacOSX ]]; then echo "@rpath/$fw.framework/Versions/A/$fw"; else echo "@rpath/$fw.framework/$fw"; fi
}

link_dylib() {
  local name="$1" arch="$2" triple="$3" work="$4" fw version extra=()
  fw="$(framework_name "$name")"
  version="$(version_of "$name")"
  case "$name" in
    harfbuzz) extra=(-lc++) ;;
    libass) extra=(-F "$work/link" -framework Libfreetype -framework Libfribidi -framework Libharfbuzz
                   -framework CoreText -framework CoreGraphics -framework CoreFoundation -liconv) ;;
  esac
  mkdir -p "$work/link/$fw.framework"
  "$(xcrun --sdk "$sdk" --find clang)" -dynamiclib -target "$triple" -isysroot "$sdk_path" \
    -install_name "$(install_name "$fw")" \
    -compatibility_version 1 -current_version "$version" \
    -Wl,-all_load "$work/prefix/lib/lib$name.a" ${extra[@]+"${extra[@]}"} \
    -Wl,-dead_strip_dylibs -Wl,-headerpad_max_install_names \
    -o "$work/link/$fw.framework/$fw"
  "$(xcrun --sdk "$sdk" --find strip)" -x "$work/link/$fw.framework/$fw"
}

build_arch() {
  local slice="$1" arch="$2" triple="$2-$suffix" work="$out/work/$1-$2" name opts
  rm -rf "$work"
  mkdir -p "$work"
  write_cross_file "$work/cross.ini" "$arch" "$triple" "$work/prefix"
  for name in freetype fribidi harfbuzz libass; do
    read -r -a opts <<< "$(meson_options "$name")"
    PKG_CONFIG_LIBDIR="$work/prefix/lib/pkgconfig" PKG_CONFIG_PATH="" \
      meson setup "$work/build-$name" "$out/src/$name-$(version_of "$name")" \
        --cross-file "$work/cross.ini" --prefix "$work/prefix" --libdir lib \
        --default-library=static --buildtype=release --wrap-mode=nodownload -Db_ndebug=true \
        "${opts[@]}" >"$work/$name-setup.log"
    meson compile -C "$work/build-$name" >"$work/$name-compile.log"
    meson install -C "$work/build-$name" --quiet >"$work/$name-install.log"
    link_dylib "$name" "$arch" "$triple" "$work"
  done
}

write_info_plist() {
  local file="$1" fw="$2" version="$3" min_key
  [[ "$platform" == MacOSX ]] && min_key=LSMinimumSystemVersion || min_key=MinimumOSVersion
  cat > "$file" <<PLIST
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
	<key>CFBundleDevelopmentRegion</key>
	<string>en</string>
	<key>CFBundleExecutable</key>
	<string>$fw</string>
	<key>CFBundleIdentifier</key>
	<string>$bundle_prefix.$(echo "$fw" | tr '[:upper:]' '[:lower:]')</string>
	<key>CFBundleInfoDictionaryVersion</key>
	<string>6.0</string>
	<key>CFBundleName</key>
	<string>$fw</string>
	<key>CFBundlePackageType</key>
	<string>FMWK</string>
	<key>CFBundleShortVersionString</key>
	<string>$version</string>
	<key>CFBundleVersion</key>
	<string>$version</string>
	<key>CFBundleSupportedPlatforms</key>
	<array>
		<string>$platform</string>
	</array>
	<key>$min_key</key>
	<string>$min_os</string>
</dict>
</plist>
PLIST
}

assemble_framework() {
  local slice="$1" name="$2" fw version dest content arch inputs=()
  fw="$(framework_name "$name")"
  version="$(version_of "$name")"
  dest="$out/frameworks/$slice/$fw.framework"
  rm -rf "$dest"
  if [[ "$platform" == MacOSX ]]; then
    content="$dest/Versions/A"
    mkdir -p "$content/Resources" "$content/Modules"
    write_info_plist "$content/Resources/Info.plist" "$fw" "$version"
  else
    content="$dest"
    mkdir -p "$content/Modules"
    write_info_plist "$content/Info.plist" "$fw" "$version"
  fi
  for arch in $archs; do inputs+=("$out/work/$slice-$arch/link/$fw.framework/$fw"); done
  lipo -create "${inputs[@]}" -output "$content/$fw"
  if [[ "$name" == libass ]]; then
    mkdir -p "$content/Headers"
    cp "$out/work/$slice-${archs%% *}/prefix/include/ass/"*.h "$content/Headers/"
    printf 'framework module %s [system] {\n    umbrella header "ass.h"\n    export *\n}\n' "$fw" > "$content/Modules/module.modulemap"
  else
    printf 'framework module %s [system] {\n    export *\n}\n' "$fw" > "$content/Modules/module.modulemap"
  fi
  if [[ "$platform" == MacOSX ]]; then
    ln -s A "$dest/Versions/Current"
    for link in "$fw" Resources Modules; do ln -s "Versions/Current/$link" "$dest/$link"; done
    [[ -d "$content/Headers" ]] && ln -s Versions/Current/Headers "$dest/Headers"
  fi
  return 0
}

for name in freetype fribidi harfbuzz libass; do fetch "$name"; done

for slice in $slices; do
  slice_config "$slice"
  for arch in $archs; do
    echo "building $slice $arch"
    build_arch "$slice" "$arch"
  done
  for name in freetype fribidi harfbuzz libass; do assemble_framework "$slice" "$name"; done
done

mkdir -p "$out/dist"
: > "$out/dist/checksums.txt"
for name in freetype fribidi harfbuzz libass; do
  fw="$(framework_name "$name")"
  args=()
  for slice in $slices; do args+=(-framework "$out/frameworks/$slice/$fw.framework"); done
  rm -rf "$out/dist/$fw.xcframework" "$out/dist/$fw.xcframework.zip"
  xcodebuild -create-xcframework "${args[@]}" -output "$out/dist/$fw.xcframework" >/dev/null
  (cd "$out/dist" && ditto -c -k --sequesterRsrc --keepParent "$fw.xcframework" "$fw.xcframework.zip")
  echo "$fw $(shasum -a 256 "$out/dist/$fw.xcframework.zip" | awk '{ print $1 }')" >> "$out/dist/checksums.txt"
done
cat "$out/dist/checksums.txt"
