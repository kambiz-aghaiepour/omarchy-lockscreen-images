# Lockscreen Images (omarchy)

Photo-drift screensaver and lock screen for Omarchy (Quattro shell), packaged as a plugin with a control panel.

Point it at a folder of images; the plugin bakes them into slow Ken Burns clips (ffmpeg `zoompan`, 1920x1080, 20 s per photo) and drives two surfaces:

- **Screensaver** — fullscreen `mpv` shuffle-loop of the baked clips on a per-monitor special workspace (`org.omarchy.screensaver`), launched by Omarchy's stock idle flow.
- **Lock screen** — while locked, a feeder re-encodes the clips to a single JPEG (`/dev/shm/omarchy-drift.jpg`, atomic rename, rotating every N seconds) that the lock surface paints: live drift *under* the lock, no player window.

This is the behavior already running on the author's machine, generalized: the stock `omarchy-launch-screensaver` and `omarchy-system-lock` automatically adopt `~/.local/bin/omarchy-aerial-drift` / `omarchy-drift-feed` when present — the plugin's panel installs them there.

## Install

```sh
omarchy plugin add <this-repo-url> --enable
```

Then: add **Lockscreen Images** to the bar (`omarchy bar put io.github.kambiz.lockscreen-images rightEnd` or via settings), click the padlock, **Install helpers**, **Bake now**.

Local checkout:

```sh
omarchy plugin add "$PWD" --enable
```

## Control panel (click the padlock widget)

| Control | Effect |
|---|---|
| Image folder | Folder of `.jpg/.jpeg/.png` fed to the baker (`~` allowed). Saved to the widget's entry in `~/.config/omarchy/shell.json` and materialized to `~/.config/lockscreen-drift.json`. |
| Lock-frame rotation | Seconds per clip while locked (5–600, default 60). |
| Live drift under the lock screen | Enables/disables the lock-time feeder. |
| Drift screensaver | Off = Omarchy's built-in terminal-effects screensaver (writes/removes `~/.local/share/omarchy/screensaver-ascii`). |
| Bake now | (Re)build missing clips into `<folder>/.baked/`. Existing clips are kept; delete `.baked/` to rebuild all. |
| Install helpers | Copies `omarchy-aerial-drift`, `omarchy-drift-feed`, `omarchy-lock-if-unlocked` to `~/.local/bin` (existing copies backed up `.bak.<ts>`). |
| Open folder | xdg-open the image folder. |

Status line shows helper state and baked-clip count. Remote control: `omarchy-shell io.github.kambiz.lockscreen-images bake|installHelpers|open|close|toggle`.

## Idle → screensaver → lock wiring (recommended, matches the author's setup)

The plugin owns the drift pipeline; the schedule lives in stock config. Reference `~/.config/hypr/hypridle.conf` single-listener form:

```ini
listener {
  timeout = 300
  on-timeout = bash -c 'date +%s > /tmp/.omarchy-ss-start; systemctl --user stop omarchy-delayed-lock 2>/dev/null; systemd-run --user --unit=omarchy-delayed-lock --on-active=590 $HOME/.local/bin/omarchy-lock-if-unlocked; [[ $(omarchy-shell lock isLocked 2>/dev/null) == "true" ]] || omarchy-launch-screensaver'
  on-resume = bash -c 'systemctl --user stop omarchy-delayed-lock 2>/dev; now=$(date +%s); t=$(cat /tmp/.omarchy-ss-start 2>/dev/null || echo 0); if [[ $((now - t)) -ge 4 ]]; then pkill -f org.omarchy.screensaver || true; fi'
}
```

Input dismissal while the screensaver plays: `~/.config/omarchy/mpv-screensaver.conf` (ESC/SPACE/ENTER/PGUP/PGDN/BS quit). The helper merges this file into a runtime input config and appends the dismissal keys last, so a missing or partial file cannot leave Esc toggling fullscreen. `install-helpers` creates the default file when absent and never overwrites an existing one.

Run only one idle driver. This listener and Omarchy's built-in Idle service both
launch the screensaver at the same timeout. If both are enabled they race, start
two mpv windows, and Esc closes only the focused one. Disable the built-in
service:

```bash
omarchy plugin disable omarchy.idle
```

## Files

```
LockImages.qml            bar widget: padlock button, settings materializer, actions, IPC
Panel.qml                 popout control panel
scripts/omarchy-aerial-drift   engine: bake | serve | feed (config- and arg-driven)
scripts/omarchy-drift-feed     lock-frame feeder (python, ffmpeg pipe → /dev/shm)
scripts/omarchy-lock-if-unlocked  delayed-lock guard for the hypridle timer
scripts/mpv-screensaver.conf   default dismissal bindings, installed if absent
scripts/install-helpers   installer with backups
tests/smoke.sh            end-to-end smoke: bake 1 image, feed frames, assert JPEG
```

Engine config (`~/.config/lockscreen-drift.json`, written by the widget, overridable via `OMARCHY_LOCK_DRIFT_CONFIG`):

```json
{ "imagesDir": "~/Downloads/Backgrounds", "rotateSeconds": 60, "lockDrift": true }
```

## Uninstall

```sh
omarchy plugin remove io.github.kambiz.lockscreen-images
```

Helpers remain in `~/.local/bin` (stock flows keep using them); remove them plus `~/.config/lockscreen-drift.json` to fully revert. Restoring the stock bar/lock behavior needs no further steps — the helpers are plain files the stock flows optionally exec.

## License

MIT.
