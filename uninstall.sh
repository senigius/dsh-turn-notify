#!/usr/bin/env bash
set -euo pipefail

profile="${DSH_PROFILE:-desktop}"
dsh_home="${DSH_HOME:-$HOME/.dsh}"
app="$HOME/Applications/DSHNotify.app"

while [[ $# -gt 0 ]]; do
  case "$1" in
    --profile) profile="${2:?--profile needs a value}"; shift 2 ;;
    --dsh-home) dsh_home="${2:?--dsh-home needs a value}"; shift 2 ;;
    --app) app="${2:?--app needs a value}"; shift 2 ;;
    *) echo "unknown option: $1" >&2; exit 1 ;;
  esac
done

rm -rf "$app"
rm -f "$dsh_home/profiles/$profile/plugins/turn-notify.mjs"

echo "removed:"
echo "  $app"
echo "  $dsh_home/profiles/$profile/plugins/turn-notify.mjs"
echo
echo "Still to do: remove the turn-notify entry from $dsh_home/profiles/$profile/cordis.patch.yml"
