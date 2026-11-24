#!/bin/zsh
# Snapshots of every page in light and dark, with seed data, on a fresh test store.
# Usage: tools/snap.sh            all pages
#        APP_SNAPSHOT_PAGES=all,settings tools/snap.sh
set -u
app=~/Applications/Hangar.app/Contents/MacOS/Hangar
store=/tmp/Hangar-test.json
shots=/tmp/Hangar-shots
# A crashed run leaves saved window state, and the next launch would wait on a "reopen windows?" alert.
rm -rf ~/Library/Saved\ Application\ State/com.mathieuares.hangar.savedState
# Start every run at the window's default size: APP_SNAPSHOT_MIN shrinks it, and the size is remembered.
defaults delete com.mathieuares.hangar "NSWindow Frame main" 2>/dev/null
# Seed data only fills an empty store, so start from nothing.
rm -f $store ${store:r}.log
rm -rf $shots
rm -rf ${store:r}-fixtures
# APP_LANGUAGE=fr tools/snap.sh shoots the French pages.
lang=()
lang=(-AppleLanguages "(${APP_LANGUAGE:-en})")
APP_STORE=$store APP_SEED=1 APP_FIXTURES=${0:A:h:h}/Tests/Fixtures APP_SNAPSHOT=$shots $app $lang