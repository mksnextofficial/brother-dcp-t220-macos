#!/bin/bash
# SPDX-License-Identifier: GPL-2.0-only
# Build on macOS, without administrator privileges or third-party dependencies.
set -euo pipefail
export COPYFILE_DISABLE=1
cd "$(dirname "$0")/.."
VERSION=1.0.0
NAME="Brother-DCP-T220-macOS-$VERSION"
WORK="$(mktemp -d)"
trap 'rm -rf "$WORK"' EXIT
ROOT="$WORK/root"
DEST="$ROOT/Library/Printers/BrotherPWG"
RES="$ROOT/Library/Printers/PPDs/Contents/Resources"
mkdir -p "$DEST" "$RES" "$WORK/resources" "$WORK/dmg" dist
install -m 755 filter/rastertobrotherpjl "$DEST/rastertobrotherpjl"
./ppd/generate-ppd.sh DCP-T220 /Library/Printers/BrotherPWG/rastertobrotherpjl > "$DEST/brother-pwg.ppd"
chmod 644 "$DEST/brother-pwg.ppd"
cp "$DEST/brother-pwg.ppd" "$RES/Brother-DCP-T220-PWG.ppd"
cp LICENSE "$DEST/LICENSE"
cp README.md "$DEST/README.md"
cp packaging/resources/*.html "$WORK/resources/"
cp LICENSE "$WORK/resources/LICENSE.txt"
# Do not ship local Finder/resource-fork metadata in the generated payload.
xattr -cr "$ROOT" "$WORK/resources"
pkgbuild --filter '/\._' --root "$ROOT" --ownership recommended --scripts packaging/scripts \
  --identifier io.github.mksnextofficial.brother-dcp-t220 --version "$VERSION" \
  --install-location / "$WORK/component.pkg"
productbuild --distribution packaging/Distribution.xml --resources "$WORK/resources" \
  --package-path "$WORK" "dist/$NAME.pkg"
cp "dist/$NAME.pkg" "$WORK/dmg/"
cp packaging/START-HERE.txt "$WORK/dmg/START-HERE.txt"
cp LICENSE "$WORK/dmg/LICENSE.txt"
hdiutil create -quiet -volname "Brother DCP-T220 $VERSION" -srcfolder "$WORK/dmg" \
  -format UDZO -ov "dist/$NAME.dmg"
(cd dist && shasum -a 256 "$NAME.pkg" "$NAME.dmg" > SHA256SUMS.txt)
echo "Built dist/$NAME.pkg and .dmg (unsigned, not notarized)."
