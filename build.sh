#!/bin/zsh
# Builds Hangar and installs it to ~/Applications/Hangar.app.
# Build products live in ~/Library/Developer/Hangar, outside the repo
# (and outside Dropbox or iCloud, which would try to sync them).
#
# Usage: ./build.sh            release build, install
#        ./build.sh --debug    debug build, install
#        ./build.sh --open     install, then quit the running copy and open the new one
set -euo pipefail
here=${0:A:h}
name="Hangar"
scratch="$HOME/Library/Developer/$name/build"
config=release
[[ " $* " == *" --debug "* ]] && config=debug

# Sign with your Apple Development certificate when you have one (Xcode >
# Settings > Accounts). Otherwise sign ad hoc, which is fine for your own Mac.
identity="${SIGN_IDENTITY:-}"
if [[ -z "$identity" ]]; then
  # The certificate's hash, not its name: two certificates can share a name.
  identity=$(security find-identity -v -p codesigning 2>/dev/null | grep -m1 '"Apple Development: ' | awk '{print $2}' || true)
fi
[[ -n "$identity" ]] || identity=-

# The compiler also writes the constant values App Intents need (Shortcuts actions, S-027).
intents=(-Xswiftc -emit-const-values -Xswiftc -Xfrontend -Xswiftc -const-gather-protocols-file
         -Xswiftc -Xfrontend -Xswiftc "$here/tools/appintents-protocols.json")
swift build -c $config --package-path "$here" --scratch-path "$scratch" $intents 2>&1 | grep -E "error|warning|Build complete" | grep -v "^\[" || true
bin="$scratch/$config/$name"
[[ -x "$bin" ]] || { echo "build failed"; exit 1; }
# swift build can report success while an edited file failed to compile. Catch that.
stale=$(find "$here/Sources" -name '*.swift' -newer "$bin" | head -1)
if [[ -n "$stale" ]]; then
  echo "build failed: binary is older than $stale"
  swift build -c $config --package-path "$here" --scratch-path "$scratch" $intents 2>&1 | grep -E "error" | head -20
  exit 1
fi

app="$HOME/Applications/$name.app"
mkdir -p "$HOME/Applications"
rm -rf "$app"
mkdir -p "$app/Contents/MacOS" "$app/Contents/Resources"
cp "$bin" "$app/Contents/MacOS/$name"
sed -e "s/__BUILD__/$(date +%Y%m%d%H%M)/" "$here/Info.plist.in" > "$app/Contents/Info.plist"
# Shortcuts actions: Metadata.appintents, which a plain swift build doesn't make (Xcode does).
Config=${(C)config}
print -l "$here"/Sources/$name/**/*.swift > "$scratch/appintents-sources.txt"
find "$scratch/out/Intermediates.noindex/$name.build/$Config" -name '*.swiftconstvalues' -path "*/$name-*" > "$scratch/appintents-constvalues.txt" 2>/dev/null || true
if [[ -s "$scratch/appintents-constvalues.txt" ]]; then
  xcrun appintentsmetadataprocessor --output "$app/Contents/Resources" \
    --toolchain-dir "$(xcode-select -p)/Toolchains/XcodeDefault.xctoolchain" --module-name $name \
    --sdk-root "$(xcrun --show-sdk-path)" --xcode-version "$(xcodebuild -version | awk '/Build version/ {print $3}')" \
    --platform-family macOS --deployment-target 26.0 --target-triple arm64-apple-macos26.0 \
    --source-file-list "$scratch/appintents-sources.txt" --swift-const-vals-list "$scratch/appintents-constvalues.txt" \
    --binary-file "$bin" --force 2>&1 | grep -iE "error|warning" || true
  [[ -d "$app/Contents/Resources/Metadata.appintents" ]] || echo "warning: no Metadata.appintents, Shortcuts won't list Hangar's actions"
fi
# Package resources (LogKit's viewer strings): Bundle.module finds them in Contents/Resources.
for bundle in "$scratch/$config"/*.bundle(N); do cp -R "$bundle" "$app/Contents/Resources/"; done
# The icon: Icon/AppIcon.icon -> Resources/Assets.car + AppIcon.icns, rebuilt when it changed.
if [[ -d "$here/Icon/AppIcon.icon" ]]; then
  car="$here/Resources/Assets.car"
  if [[ ! -f "$car" || -n "$(find "$here/Icon/AppIcon.icon" -newer "$car" | head -1)" ]]; then
    "$here/tools/make_icon.sh"
  fi
  cp -X "$car" "$here/Resources/AppIcon.icns" "$app/Contents/Resources/"
fi
# Translations: Localization/*.xcstrings -> <lang>.lproj/*.strings
for catalog in "$here"/Localization/*.xcstrings(N); do
  xcrun xcstringstool compile "$catalog" --output-directory "$app/Contents/Resources"
done
mkdir -p "$app/Contents/Resources/en.lproj"
# Release notes: What's New shows release-notes/<version>.md the first time a new version opens.
[[ -d "$here/release-notes" ]] && cp -R "$here/release-notes" "$app/Contents/Resources/"
# The recipe manifest.
cp "$here/Recipes/recipes.json" "$app/Contents/Resources/"
# Sparkle, for automatic updates.
framework="$scratch/$config/Sparkle.framework"
if [[ -d "$framework" ]]; then
  mkdir -p "$app/Contents/Frameworks"
  ditto "$framework" "$app/Contents/Frameworks/Sparkle.framework"
fi
xattr -cr "$app"
[[ -d "$app/Contents/Frameworks/Sparkle.framework" ]] && codesign --force --deep --sign "$identity" "$app/Contents/Frameworks/Sparkle.framework" 2>&1 | grep -v "replacing existing signature" || true
codesign --force --sign "$identity" "$app" 2>&1 | grep -v "replacing existing signature" || true
echo "installed $app (signed: ${identity})"

if [[ " $* " == *" --open "* ]]; then
  osascript -e "quit app \"$name\"" 2>/dev/null || true
  sleep 0.5
  open "$app"
fi