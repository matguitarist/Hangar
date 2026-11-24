#!/bin/zsh
# Runs the in-app self-test against a fresh store in /tmp. Exit code 0 when every check passed.
set -u
rm -rf ~/Library/Saved\ Application\ State/com.mathieuares.hangar.savedState
store=/tmp/Hangar-self.json
rm -f $store ${store:r}.log
rm -rf ${store:r}-fixtures ${store:r}-covers
# The sample library: Steam, CrossOver bottles and Mac apps, copied to /tmp by the app.
# APP_LANGUAGE=fr tools/selftest.sh runs it in French.
lang=()
[[ -n "${APP_LANGUAGE:-}" ]] && lang=(-AppleLanguages "(${APP_LANGUAGE})")
APP_STORE=$store APP_FIXTURES=${0:A:h:h}/Tests/Fixtures ~/Applications/Hangar.app/Contents/MacOS/Hangar $lang --selftest