#!/bin/zsh
set -euo pipefail

script_dir=${0:A:h}
project_dir=${script_dir:h}
build_dir="$project_dir/.build/macos"
release_dir="$project_dir/.build/release"
app_dir="$build_dir/Aperture.app"
dmg_root=$(mktemp -d "${TMPDIR:-/tmp}/aperture-dmg.XXXXXX")
trap 'rm -rf "$dmg_root"' EXIT
version=$(plutil -extract CFBundleShortVersionString raw \
  "$project_dir/native/ApertureCompanion/Info.plist")
build_arch=${APERTURE_ARCH:-$(uname -m)}
artifact_base="Aperture-v${version}-macos-${build_arch}"
zip_path="$release_dir/${artifact_base}.zip"
dmg_path="$release_dir/${artifact_base}.dmg"

cd "$project_dir"
APERTURE_ARCH="$build_arch" npm run build:mac

mkdir -p "$release_dir"
ditto "$app_dir" "$dmg_root/Aperture.app"
ln -s /Applications "$dmg_root/Applications"

ditto -c -k --sequesterRsrc --keepParent "$app_dir" "$zip_path"
hdiutil create \
  -volname "Aperture" \
  -srcfolder "$dmg_root" \
  -ov \
  -format UDZO \
  "$dmg_path" >/dev/null

(
  cd "$release_dir"
  shasum -a 256 \
    "${artifact_base}.zip" \
    "${artifact_base}.dmg" > SHA256SUMS.txt
)

echo "$dmg_path"
echo "$zip_path"
echo "$release_dir/SHA256SUMS.txt"
