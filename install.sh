#!/usr/bin/env bash
set -euo pipefail

here="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
profile="${DSH_PROFILE:-desktop}"
dsh_home="${DSH_HOME:-$HOME/.dsh}"
app="$HOME/Applications/DSHNotify.app"
build_helper=1

usage() {
  cat <<'EOF'
usage: ./install.sh [options]

  --profile NAME   DSH profile to install into (default: desktop)
  --dsh-home PATH  DSH home directory (default: ~/.dsh)
  --app PATH       where to build the helper app (default: ~/Applications/DSHNotify.app)
  --skip-build     reuse an existing helper app
  -h, --help       show this help

Builds the macOS notification helper, copies the Cordis plugin into the
profile, and prints the YAML entry to add to cordis.patch.yml.
EOF
}

while [[ $# -gt 0 ]]; do
  case "$1" in
    --profile) profile="${2:?--profile needs a value}"; shift 2 ;;
    --dsh-home) dsh_home="${2:?--dsh-home needs a value}"; shift 2 ;;
    --app) app="${2:?--app needs a value}"; shift 2 ;;
    --skip-build) build_helper=0; shift ;;
    -h|--help) usage; exit 0 ;;
    *) echo "unknown option: $1" >&2; usage >&2; exit 1 ;;
  esac
done

if [[ "$(uname -s)" != "Darwin" ]]; then
  echo "error: dsh-turn-notify targets macOS" >&2
  exit 1
fi

if [[ ! -d "$dsh_home/profiles/$profile" ]]; then
  echo "error: no DSH profile at $dsh_home/profiles/$profile" >&2
  if [[ -d "$dsh_home/profiles" ]]; then
    echo "available profiles: $(ls "$dsh_home/profiles" | tr '\n' ' ')" >&2
  else
    echo "hint: pass --dsh-home if DSH keeps profiles elsewhere" >&2
  fi
  exit 1
fi

if [[ "$build_helper" == 1 ]]; then
  "$here/helper/build.sh" "$app"
elif [[ ! -d "$app" ]]; then
  echo "error: $app not found; run without --skip-build first" >&2
  exit 1
fi

mkdir -p "$dsh_home/profiles/$profile/plugins"
install -m 644 "$here/plugin/turn-notify.js" "$dsh_home/profiles/$profile/plugins/turn-notify.mjs"

cat <<EOF

Installed:
  helper  $app
  plugin  $dsh_home/profiles/$profile/plugins/turn-notify.mjs

Add this entry to $dsh_home/profiles/$profile/cordis.patch.yml:

- insert:
    - id: turn-notify
      name: "./plugins/turn-notify.mjs"
      config:
        notify: true
        activate: false
        sound: Glass
        minDurationMs: 3000
        onlyMainAgent: true

Save the file while DSH is running (the profile is watched) or restart DSH.
Check delivery: tail -f "$HOME/Library/Caches/dsh-turn-notify/plugin.log"
EOF
