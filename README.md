# dsh-turn-notify

macOS notification when a [DeepSeek Harness](https://www.deepseek.com/en/harness/) agent finishes a turn.

## Why another notifier

On macOS 26, `osascript -e 'display notification ...'` and `terminal-notifier`
still show up in the notification settings and get permission, but no banner is
ever drawn — you only hear the sound. This project ships a tiny Swift helper
that posts through `UNUserNotificationCenter` and runs as a real `.app`, which
does render the banner. The JavaScript side is a host-side Cordis plugin that
listens to `agent/status` and calls the helper.

- Banner with the session title, optional system sound
- Optional window activation when the turn ends
- Ignores subagents and turns shorter than `minDurationMs`
- Serialized delivery, so parallel turns never fight over the request file

## Requirements

- macOS 13 or newer (built and tested on macOS 26)
- Xcode command line tools for `swiftc`
- DeepSeek Harness with a profile directory at `~/.dsh/profiles/<name>`
  (`desktop` is the usual one)

## Install

```sh
git clone https://github.com/senigius/dsh-turn-notify.git
cd dsh-turn-notify
./install.sh
```

The script builds `~/Applications/DSHNotify.app`, copies the plugin to
`~/.dsh/profiles/desktop/plugins/turn-notify.mjs`, and prints the YAML entry to
add to `~/.dsh/profiles/desktop/cordis.patch.yml`:

```yaml
- insert:
    - id: turn-notify
      name: "./plugins/turn-notify.mjs"
      config:
        notify: true
        activate: false
        sound: Glass
        minDurationMs: 3000
        onlyMainAgent: true
```

Save the file while Harness is running (the profile is watched) or restart the
app. The first notification may ask for permission.

Other profiles and locations:

```sh
./install.sh --profile web
./install.sh --dsh-home /path/to/dsh-home --app /Applications/DSHNotify.app
```

## Configuration

All keys are optional and merge over the defaults in `plugin/turn-notify.js`.

| Key | Default | Meaning |
|---|---|---|
| `notify` | `true` | Show the banner. |
| `activate` | `false` | Bring the Harness window to the front on turn end. |
| `sound` | `Glass` | System sound name: `Glass`, `Hero`, `Ping`, `default`, `none`. |
| `minDurationMs` | `3000` | Skip turns shorter than this. |
| `onlyMainAgent` | `true` | Do not notify for subagents. |
| `seedRunningTurns` | `true` | Also notify for turns already running when the plugin loads. |
| `title` | `DeepSeek Harness` | Notification title. |
| `fallbackBody` | `Turn finished — you can come back` | Body used when the session has no title yet. |
| `appPath` | `~/Applications/DSHNotify.app` | Helper app location. |
| `appBundleId` | `com.deepseek.dsh` | Harness bundle id used by `activate`. |

## Verify

```sh
tail -f ~/Library/Caches/dsh-turn-notify/plugin.log
```

A finished turn appends `turn end after …ms` and `notified: …`. To test the
banner directly:

```sh
mkdir -p ~/Library/Caches/dsh-turn-notify
printf '{"title":"DSH Notify","body":"Test","sound":"Glass"}' \
  > ~/Library/Caches/dsh-turn-notify/request.json
open -n -W ~/Applications/DSHNotify.app
```

Helper diagnostics go to `~/Library/Caches/dsh-turn-notify/helper.log`.

## Troubleshooting

- No banner, but the log says `notified`: open System Settings → Notifications →
  DSH Notify, allow notifications and pick "Banners".
- Nothing in either log: the entry is missing from `cordis.patch.yml`, or the
  plugin file was not copied into the profile.
- `open` fails or macOS refuses to launch the helper: the app was downloaded or
  copied from another machine. Rebuild it locally with `./helper/build.sh`.
- Permission prompt never appears: the helper must run as a bundle from
  `~/Applications`. `swift helper/main.swift` on its own will not work.

## Uninstall

```sh
./uninstall.sh
```

Then remove the `turn-notify` entry from `cordis.patch.yml` and restart Harness.

## How it works

1. The Cordis plugin listens for `agent/status` transitions and measures the
   turn duration.
2. On `running → idle` it writes `{"title","body","sound"}` to
   `~/Library/Caches/dsh-turn-notify/request.json`.
3. It launches the helper with `open -n -W`; LaunchServices cannot pass argv or
   environment, so the file is the only channel.
4. The helper asks `UNUserNotificationCenter` for permission and posts the
   notification, then exits.

The helper is ad-hoc signed. It is not notarized and does not need to be: it is
built on the machine that uses it.

## License

MIT
