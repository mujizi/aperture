#!/bin/zsh
set -euo pipefail

script_dir=${0:A:h}
project_dir=${script_dir:h}
build_dir="$project_dir/.build/macos"
app_dir="$build_dir/Aperture.app"
contents_dir="$app_dir/Contents"
resources_dir="$contents_dir/Resources"
icon_work_dir="$build_dir/AppIcon.iconset"
deployment_target=${MACOSX_DEPLOYMENT_TARGET:-13.0}
build_arch=${APERTURE_ARCH:-$(uname -m)}

cd "$project_dir"
npm run build

rm -rf "$app_dir" "$icon_work_dir"
mkdir -p "$contents_dir/MacOS" "$resources_dir/runtime" "$icon_work_dir"

swiftc \
  -target "${build_arch}-apple-macos${deployment_target}" \
  -O \
  -framework AppKit \
  -framework WebKit \
  -framework QuartzCore \
  native/ApertureCompanion/main.swift \
  -o "$contents_dir/MacOS/Aperture"

cp native/ApertureCompanion/Info.plist "$contents_dir/Info.plist"
cp native/ApertureCompanion/ApertureCatSprite.png \
  "$resources_dir/ApertureCatSprite.png"
cp plugins/aperture-attention/runtime/server.mjs "$resources_dir/runtime/server.mjs"
ditto dist/web "$resources_dir/runtime/web"

icon_preview_dir="$build_dir/icon-preview"
rm -rf "$icon_preview_dir"
mkdir -p "$icon_preview_dir"
qlmanage -t -s 1024 -o "$icon_preview_dir" native/ApertureCompanion/AppIcon.svg >/dev/null 2>&1
icon_source="$icon_preview_dir/AppIcon.svg.png"

if [[ -f "$icon_source" ]]; then
  sips -z 16 16 "$icon_source" --out "$icon_work_dir/icon_16x16.png" >/dev/null
  sips -z 32 32 "$icon_source" --out "$icon_work_dir/icon_16x16@2x.png" >/dev/null
  sips -z 32 32 "$icon_source" --out "$icon_work_dir/icon_32x32.png" >/dev/null
  sips -z 64 64 "$icon_source" --out "$icon_work_dir/icon_32x32@2x.png" >/dev/null
  sips -z 128 128 "$icon_source" --out "$icon_work_dir/icon_128x128.png" >/dev/null
  sips -z 256 256 "$icon_source" --out "$icon_work_dir/icon_128x128@2x.png" >/dev/null
  sips -z 256 256 "$icon_source" --out "$icon_work_dir/icon_256x256.png" >/dev/null
  sips -z 512 512 "$icon_source" --out "$icon_work_dir/icon_256x256@2x.png" >/dev/null
  sips -z 512 512 "$icon_source" --out "$icon_work_dir/icon_512x512.png" >/dev/null
  cp "$icon_source" "$icon_work_dir/icon_512x512@2x.png"
  iconutil -c icns "$icon_work_dir" -o "$resources_dir/AppIcon.icns"
fi

codesign --force --deep --sign - "$app_dir" >/dev/null
echo "$app_dir"
