# OBS Status & Guard

An [Omarchy](https://omarchy.org) bar widget that watches OBS Studio.

- **While you stream:** a green `● ON AIR 1:27:02` label in the bar with the stream time.
- **If OBS closes abruptly while you are live:** a red `● OBS CLOSED` label, a large on-screen alert above the volume OSD on your main monitor, and (optionally) a sound.
- **Optionally** it reopens OBS in normal mode and resumes the stream by itself.
- **When idle** it shows a dim `● OBS` so you can see the plugin is running, and `○ OBS off` while monitoring is paused.

A normal close, or stopping the stream yourself, never raises the alert: it only fires when OBS disappears while live without announcing that it is exiting.

Click the label for a menu with the options below.

## Requirements

- Omarchy with the shell plugin system (Hyprland, Quickshell).
- OBS Studio with the built-in **WebSocket server (5.x) enabled** (developed and used against OBS 33) (*Tools → WebSocket Server Settings → Enable*). Authentication may stay on: the plugin reads the port and password from OBS's own config.
- `python3` (standard library only), `hyprctl`.
- `pw-play` (PipeWire) for the built-in alert sound.
- Optional: `ffplay` (FFmpeg) for a custom sound file, `uwsm-app` to launch OBS the way Omarchy launches apps, `omarchy-file-select` for the sound file picker.

## Install

```bash
omarchy plugin add https://github.com/borferkic/obs-status-guard.git --enable
```

Then enable OBS's WebSocket server as described above, and start OBS.

## Remove

```bash
omarchy plugin remove io.github.borferkic.obs-status-guard
```

This removes the plugin and its bar entry. The options you chose live in that bar entry in `~/.config/omarchy/shell.json`, so they go with it. The plugin leaves nothing else behind except a small state folder under `$XDG_RUNTIME_DIR/obs-status-guard/`, which is cleared at logout.

## Options (menu on click)

| Option | Default | What it does |
|---|---|---|
| Monitoring | on | Turn off to pause everything: no connection to OBS, no label, no alerts, no relaunch. |
| Reopen OBS automatically | off | After an abrupt close, wait 5 seconds, reopen OBS and start streaming again. **This puts you live without asking.** At most 3 relaunches per 10 minutes. |
| Sound alert | on | Plays a sound once when OBS closes abruptly. |
| Sound file | built-in alarm | Pick your own file (wav, mp3, ogg, opus, flac, m4a, aac). Custom sounds are cut at 10 seconds. |
| Reopen OBS on | default screen | Click to cycle through your monitors. After a relaunch the OBS main window is moved there. |
| Alert size | 300% | 100–500%, in steps of 50. |
| Preview alert | – | Shows the alert for 6 seconds and plays its sound once, whatever the sound option says. |

They are stored as keys of the widget's entry in `shell.json` (`monitoring`, `autoRestart`, `soundAlert`, `soundFile`, `obsMonitor`, `alertScale`, and `monitor` to pin the alert to a monitor; blank uses the largest one), so you can also edit them there.

## What it does on your machine

Please read this before enabling it, as it is more than a display widget.

- **Reads OBS's WebSocket config**, `~/.config/obs-studio/plugin_config/obs-websocket/config.json`, including the password, and connects to **`127.0.0.1` only**. It asks for the stream status once a second and listens for OBS's exit announcement.
- **Runs a small daemon** (`bin/obs-status-guard`, started and stopped by the shell) and writes its state to `$XDG_RUNTIME_DIR/obs-status-guard/`.
- **Only when "Reopen OBS automatically" is on**, after an abrupt close it:
  - deletes the `run_*` files in `~/.config/obs-studio/.sentinel/`. OBS 33 leaves one for each instance that did not exit cleanly and asks "normal or safe mode?" at the next start; with no OBS running they are all stale. This means OBS will not offer safe mode after a crash (`obs --safe-mode` still works);
  - starts OBS with the `Exec=` line of your `com.obsproject.Studio.desktop` (so launcher tweaks such as `LIBVA_DRIVER_NAME` carry over) plus `--startstreaming`, through `uwsm-app` when present;
  - if you chose a monitor, moves OBS's main window there with `hyprctl dispatch` (it never takes focus; dialogs are left alone).
- **Plays the sound** with `pw-play`, or `ffplay` for a custom file. The path is passed as a plain argument and only absolute paths to files under 20 MB are accepted.
- It makes **no network connections** other than that loopback WebSocket, downloads nothing and runs no downloaded code.

## Tests

`tests/test_guard.py` runs the daemon against a mock OBS WebSocket server and a fake `hyprctl` in a temporary home, covering authentication, live and abrupt-close detection, clean exit without a false alarm, the pause switch, the 5-second relaunch delay, launching through the desktop entry, sentinel cleanup and moving only OBS's main window:

```bash
python3 tests/test_guard.py
```

It never touches your real OBS or configuration.

## Languages

Texts are in `i18n/` (English and Spanish) and follow the language chosen in Omarchy. Add `i18n/<code>.json` to translate.

## License

MIT, see [LICENSE](LICENSE).
