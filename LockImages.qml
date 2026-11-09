import QtQuick
import Quickshell
import Quickshell.Io
import qs.Commons
import qs.Commons as Commons
import qs.Ui

// Lockscreen Images: photo-drift screensaver/lockscreen configurator.
//
// The bar widget is a padlock button; clicking it opens the control panel
// (image folder, lock-frame rotation, drift toggles, bake, helper install).
// Settings live on this widget's entry in shell.json and are materialized by
// the widget into:
//   ~/.config/lockscreen-drift.json                  (engine config)
//   ~/.local/share/omarchy/screensaver-ascii         (driff-off flag)
// The helpers (~/.local/bin/omarchy-aerial-drift, omarchy-drift-feed,
// omarchy-lock-if-unlocked) read the JSON; the stock idle/lock flows adopt
// them automatically once installed via the panel.
BarWidget {
  id: root
  moduleName: "io.github.kambiz.lockscreen-images"

  // ---- Settings (defaults mirror the manifest).

  readonly property string imagesDirRaw: {
    var v = settings && settings.imagesDir
    return typeof v === "string" && v.trim() !== "" ? v : "~/Downloads/Backgrounds"
  }
  readonly property int rotateSeconds: {
    var v = parseInt(settings && settings.rotateSeconds, 10)
    return v >= 5 && v <= 600 ? v : 60
  }
  readonly property bool lockDrift: !settings || settings.lockDrift !== false
  readonly property bool screensaverDrift: !settings || settings.screensaverDrift !== false

  property string statusLine: "checking…"
  property string actionNote: ""
  readonly property bool busy: materializer.running || baker.running || installer.running

  // ---- Settings persistence (same wiring as Omarchy's clock).

  function saveSettings(values) {
    var entry = { id: root.moduleName }
    for (var existing in root.settings) if (existing !== "id") entry[existing] = root.settings[existing]
    for (var key in values) entry[key] = values[key]
    root.settings = entry
    if (panelLoader.item && "settings" in panelLoader.item) panelLoader.item.settings = entry
    if (root.bar && root.bar.shell && typeof root.bar.shell.updateEntryInline === "function")
      root.bar.shell.updateEntryInline(root.moduleName, entry)
    materialize()
  }

  // Materialize entry settings to the files the helpers and stock flows read.
  function materialize() {
    var script = [
      'd=$1; r=$2; l=$3; s=$4',
      'cfg=$HOME/.config/lockscreen-drift.json',
      'mkdir -p "$(dirname "$cfg")"',
      'jq -n --arg d "$d" --argjson r "$r" --argjson l "$l" --argjson s "$s" \'',
      '  {imagesDir:$d, rotateSeconds:(if $r>0 then $r else 60 end), lockDrift:$l, screensaverDrift:$s}\' > "$cfg"',
      'flag=$HOME/.local/share/omarchy/screensaver-ascii',
      'mkdir -p "$(dirname "$flag")"',
      'if [[ $s == true ]]; then rm -f "$flag"; else touch "$flag"; fi'
    ].join("\n")
    materializer.command = ["bash", "-c", script, "bash",
                            imagesDirRaw, String(rotateSeconds),
                            lockDrift ? "true" : "false",
                            screensaverDrift ? "true" : "false"]
    materializer.running = true
  }

  Process {
    id: materializer
    onExited: root.probe()
  }

  // ---- Status probe: one line for the panel and IPC.

  function probe() {
    var script = [
      'cfg=$HOME/.config/lockscreen-drift.json',
      'out=""',
      'if [[ -x $HOME/.local/bin/omarchy-aerial-drift && -x $HOME/.local/bin/omarchy-drift-feed ]]; then',
      '  out="helpers installed"',
      'else',
      '  out="helpers not installed"',
      'fi',
      'd=$(jq -r ".imagesDir // \\"\\"" "$cfg" 2>/dev/null); d=${d/#\\~/$HOME}',
      '[[ -n $d ]] || d=$HOME/Downloads/Backgrounds',
      'c=0; [[ -d $d/.baked ]] && c=$(ls "$d/.baked"/*.mp4 2>/dev/null | wc -l)',
      'out+="; $c baked clip(s) in $d"',
      '[[ -f $cfg ]] || out+="; no config yet"',
      'echo "$out"'
    ].join("\n")
    prober.command = ["bash", "-c", script]
    prober.running = true
  }

  Process {
    id: prober
    stdout: SplitParser {
      onRead: function(line) { root.statusLine = String(line).trim() }
    }
  }

  // ---- Actions.

  function pluginScript(name) {
    var url = Qt.resolvedUrl("scripts/" + name).toString()
    return url.indexOf("file://") === 0 ? decodeURIComponent(url.slice(7)) : url
  }

  // Bake with the plugin's own engine and an explicit dir override, so it
  // works before the helpers are installed.
  function bake() {
    if (root.busy) return
    baker.command = ["bash", "-c", 'exec "$1" bake "${2/#\\~/$HOME}"', "bash",
                     pluginScript("omarchy-aerial-drift"), imagesDirRaw]
    baker.running = true
  }

  Process {
    id: baker
    onExited: function(exitCode) {
      root.actionNote = exitCode === 0 ? "bake finished" : "bake failed (exit " + exitCode + ")"
      root.probe()
    }
  }

  function installHelpers() {
    if (root.busy) return
    installer.command = ["bash", "-c", 'exec "$1"', "bash", pluginScript("install-helpers")]
    installer.running = true
  }

  Process {
    id: installer
    onExited: function(exitCode) {
      root.actionNote = exitCode === 0 ? "helpers installed" : "helper install failed (exit " + exitCode + ")"
      root.probe()
    }
    stdout: SplitParser {
      onRead: function(line) { root.statusLine = String(line).trim() }
    }
  }

  function openFolder() {
    opener.command = ["bash", "-c", 'xdg-open "${1/#\\~/$HOME}" >/dev/null 2>&1', "bash", imagesDirRaw]
    opener.running = true
  }

  Process { id: opener }

  // ---- Control panel (Panel.qml).

  readonly property bool opened: panelLoader.item
    ? panelLoader.item.opened === true : false

  function openPanel() { if (panelLoader.item) panelLoader.item.open() }
  function closePanel() { if (panelLoader.item) panelLoader.item.close() }
  function togglePanel() { if (panelLoader.item) panelLoader.item.toggle() }

  // Popout contract: route dismissal through the owner widget so the panel's
  // open binding stays alive.
  function open() { openPanel() }
  function close() { closePanel() }

  function injectPanel() {
    var target = panelLoader.item
    if (!target) return
    target.bar = root.bar
    target.settings = root.settings
    target.anchorItem = root
    target.hostWidget = root
  }

  Loader {
    id: panelLoader
    active: true
    source: Qt.resolvedUrl("Panel.qml")
    visible: false
    onLoaded: { root.injectPanel(); Qt.callLater(root.injectPanel) }
  }

  onBarChanged: injectPanel()
  onSettingsChanged: {
    injectPanel()
    materialize()
  }

  Component.onCompleted: {
    materialize()
    probe()
  }

  // ---- The widget: standard icon button, sized by the bar like every other
  // icon (Style.bar.iconSize). Closed lock = a drift surface enabled, open =
  // both off.

  implicitWidth: button.implicitWidth
  implicitHeight: button.implicitHeight

  BarIconButton {
    id: button
    anchors.fill: parent
    bar: root.bar
    text: root.screensaverDrift || root.lockDrift ? "\uF033E" : "\uF033C"
    active: root.opened
    tooltipText: "Lockscreen Images — photo drift for the screensaver and lock screen; click for the control panel"
    onPressed: function(mouseButton) { root.togglePanel() }
  }

  // ---- Remote control: omarchy-shell io.github.kambiz.lockscreen-images <method>

  ShellIpc {
    target: "io.github.kambiz.lockscreen-images"
    function open(): void { root.openPanel() }
    function close(): void { root.closePanel() }
    function toggle(): void { root.togglePanel() }
    function bake(): void { root.bake() }
    function installHelpers(): void { root.installHelpers() }
    function status(): string { return root.statusLine }
  }
}
