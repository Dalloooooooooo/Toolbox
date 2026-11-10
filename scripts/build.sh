#!/bin/zsh
# Builds Toolbox.app (with Power.app and File Explorer.app inside), signs it and installs it in ~/Applications.
#
#   scripts/build.sh                 build for this Mac, install and launch
#   NO_INSTALL=1 scripts/build.sh    build only (build/Toolbox.app)
#   UNIVERSAL=1 scripts/build.sh     Apple Silicon + Intel (needs an SDK that still supports Intel)
#   SIGN_IDENTITY="Name" ...         code signing certificate (default: "SwitchTab Local Signing")
#
# Needs only Xcode or the Command Line Tools: no Xcode project, no dependencies.
set -euo pipefail
ROOT="${0:A:h:h}"
cd "$ROOT"

BUILD=build
APP="$BUILD/Toolbox.app"
MIN_MACOS=14.0
ARCHS=(arm64)
[[ -n "${UNIVERSAL:-}" ]] && ARCHS=(arm64 x86_64)
SIGN_IDENTITY="${SIGN_IDENTITY:-SwitchTab Local Signing}"

# MARK: - Helpers

# compile <executable> <framework,...> <source folders or files...>
# Compiles every .swift file found for each architecture and merges the slices into one executable.
compile() {
  local out="$1" frameworks="$2"; shift 2
  local sources=($(find "$@" -name '*.swift' | sort))
  local flags=(-O -swift-version 5 -F /System/Library/PrivateFrameworks)
  for f in ${(s:,:)frameworks}; do flags+=(-framework "$f"); done
  local slices=()
  for arch in $ARCHS; do
    swiftc $flags -target "$arch-apple-macos$MIN_MACOS" $sources -o "$out.$arch"
    slices+=("$out.$arch")
  done
  lipo -create $slices -output "$out"
  rm -f $slices
}

# make_icns <1024×1024 png> <file.icns>
make_icns() {
  local png="$1" icns="$2"
  local set="$BUILD/${icns:t:r}.iconset"
  mkdir -p "$set"
  for s in 16 32 128 256 512; do
    sips -z $s $s "$png" --out "$set/icon_${s}x${s}.png" >/dev/null
    sips -z $((s * 2)) $((s * 2)) "$png" --out "$set/icon_${s}x${s}@2x.png" >/dev/null
  done
  iconutil -c icns "$set" -o "$icns"
}

# bundle <path.app> <Resources folder of the sources>: bundle layout + Info.plist + resources + localizations
bundle() {
  mkdir -p "$1/Contents/MacOS" "$1/Contents/Resources"
  cp "$2/Info.plist" "$1/Contents/"
  find "$2" -maxdepth 1 -type f ! -name Info.plist -exec cp {} "$1/Contents/Resources/" \;
  find "$2" -maxdepth 1 -type d -name '*.lproj' -exec cp -R {} "$1/Contents/Resources/" \;
}

sign() {
  if security find-identity -p codesigning | grep -q "$SIGN_IDENTITY"; then
    codesign --force --sign "$SIGN_IDENTITY" "$1"
  else
    codesign --force --sign - "$1" # ad-hoc: works, but permissions must be granted again for every build
  fi
}

# MARK: - Icons (generated once from the drawings in Artwork/, then kept in Resources/)

mkdir -p "$BUILD"
if [[ ! -f Toolbox/Resources/AppIcon.icns ]]; then
  # cut the rounded shape out of the drawing's white background
  swift scripts/icons/IconFromImage.swift Artwork/icon-source.png 93 82 1066 1084 "$BUILD/icon.png"
  make_icns "$BUILD/icon.png" Toolbox/Resources/AppIcon.icns
fi
if [[ ! -f Power/Resources/PowerIcon.icns || ! -f Power/Resources/PowerBase.png ]]; then
  swift scripts/icons/IconFromImage.swift Artwork/power-source.png 154 147 939 943 "$BUILD/power.png"
  sips -z 512 512 "$BUILD/power.png" --out Power/Resources/PowerBase.png >/dev/null # base for the color variants
  make_icns "$BUILD/power.png" Power/Resources/PowerIcon.icns
fi
if [[ ! -f Explorer/Resources/ExplorerIcon.icns ]]; then
  if [[ -f Artwork/explorer-source.png ]]; then cp Artwork/explorer-source.png "$BUILD/explorer.png"
  else swift scripts/icons/MakeFolderIcon.swift "$BUILD/explorer.png"; fi
  make_icns "$BUILD/explorer.png" Explorer/Resources/ExplorerIcon.icns
fi

# MARK: - Apps

rm -rf "$APP"
POWER="$APP/Contents/Helpers/Power.app"
EXPLORER="$APP/Contents/Helpers/File Explorer.app"

bundle "$APP" Toolbox/Resources
compile "$APP/Contents/MacOS/Toolbox" Cocoa,ScreenCaptureKit,ServiceManagement,SwiftUI,Carbon,SkyLight Toolbox Shared

bundle "$POWER" Power/Resources
compile "$POWER/Contents/MacOS/Power" Cocoa Power Shared

bundle "$EXPLORER" Explorer/Resources
compile "$EXPLORER/Contents/MacOS/Explorer" Cocoa,SwiftUI,QuickLookThumbnailing,Quartz Explorer

# nested bundles first, then the one that contains them
sign "$POWER"; sign "$EXPLORER"; sign "$APP"
echo "Built: $APP ($ARCHS)"

[[ -n "${NO_INSTALL:-}" ]] && exit 0

# MARK: - Install

pkill -x Toolbox || true; pkill -x Power || true; pkill -x Explorer || true
rm -rf ~/Applications/Toolbox.app
mkdir -p ~/Applications
cp -R "$APP" ~/Applications/
echo "Installed in ~/Applications/Toolbox.app"
open ~/Applications/Toolbox.app
