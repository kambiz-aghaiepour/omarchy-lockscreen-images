import QtQuick
import QtQuick.Controls
import Quickshell
import Quickshell.Io
import qs.Commons
import qs.Commons as Commons
import qs.Ui

// Control panel for Lockscreen Images, opened by clicking the padlock widget.
// Settings changes are written to the widget's entry in shell.json (the widget
// materializes them to the engine config / drift-off flag); the action buttons
// run bake / helper-install / file manager against the configured folder.
Panel {
  id: root

  property var anchorItem: null
  property var hostWidget: null
  readonly property var barIdentity: hostWidget ? hostWidget : root

  readonly property var cfg: hostWidget ? (hostWidget.settings || {}) : ({})
  readonly property string dirValue: {
    var v = cfg.imagesDir
    return typeof v === "string" && v.trim() !== "" ? v : "~/Downloads/Backgrounds"
  }
  readonly property int rotateValue: {
    var v = parseInt(cfg.rotateSeconds, 10)
    return v >= 5 && v <= 600 ? v : 60
  }
  readonly property bool lockDrift: cfg.lockDrift !== false
  readonly property bool screensaverDrift: cfg.screensaverDrift !== false

  readonly property color fg: bar ? bar.barForeground : Commons.Color.foreground

  function save(values) {
    if (root.hostWidget) root.hostWidget.saveSettings(values)
  }

  function open() { root.controller.show() }
  function close() { root.controller.hide() }
  function toggle() {
    if (root.opened) root.close()
    else root.open()
  }

  function status() { return root.opened ? "open" : "closed" }

  function switchPanel(direction) {
    if (root.bar && typeof root.bar.switchPanelFrom === "function")
      return root.bar.switchPanelFrom(root.barIdentity, direction)
    return false
  }

  component PanelButton: Rectangle {
    id: buttonRoot
    property string label: ""
    property var action: null
    property bool working: false

    width: label.implicitWidth + 2 * 12
    height: 26
    radius: 5
    color: mouse.pressed ? Qt.rgba(1, 1, 1, 0.16) : Qt.rgba(1, 1, 1, 0.08)
    border.width: 1
    border.color: Qt.rgba(1, 1, 1, 0.14)
    opacity: enabled ? 1 : 0.45

    Text {
      id: label
      anchors.centerIn: parent
      text: buttonRoot.working ? "…" : buttonRoot.label
      color: root.fg
      font.family: Style.font.family
      font.pixelSize: Style.font.caption
    }

    MouseArea {
      id: mouse
      anchors.fill: parent
      cursorShape: Qt.PointingHandCursor
      onClicked: if (buttonRoot.action && !buttonRoot.working) buttonRoot.action()
    }
  }

  KeyboardPanel {
    id: panel
    anchorItem: root.anchorItem
    owner: root.barIdentity
    bar: root.bar
    open: root.opened
    centerOnBar: false
    focusTarget: panel.loadedContent
    contentWidth: panel.fittedContentWidth(Style.space(360))
    contentHeight: panel.fittedContentHeight(panel.loadedContentHeight)

    content: PanelKeyCatcher {
      id: keyCatcher
      anchors.fill: parent
      implicitHeight: contentColumn.implicitHeight
      onCloseRequested: root.close()
      onTabRequested: function(direction) { root.switchPanel(direction) }

      Column {
        id: contentColumn
        width: parent.width
        spacing: Style.space(10)

        Item { width: 1; height: Style.space(2) }

        Text {
          textFormat: Text.PlainText
          text: "Lockscreen Images"
          color: root.fg
          font.family: Style.font.family
          font.pixelSize: Style.font.subtitle
          font.bold: true
        }

        Text {
          textFormat: Text.PlainText
          width: parent.width
          text: hostWidget ? hostWidget.statusLine : ""
          color: Qt.alpha(root.fg, 0.55)
          font.family: Style.font.family
          font.pixelSize: Style.font.caption
          wrapMode: Text.WordWrap
        }

        Text {
          textFormat: Text.PlainText
          width: parent.width
          text: "Image folder (drift source, ~ allowed)"
          color: root.fg
          font.family: Style.font.family
          font.pixelSize: Style.font.caption
        }

        Row {
          width: parent.width
          spacing: Style.space(6)

          TextField {
            id: dirField
            width: parent.width - applyButton.width - parent.spacing
            placeholderText: "~/Pictures/Lockscreen"
            color: root.fg
            font.family: Style.font.family
            font.pixelSize: Style.font.body
            text: root.dirValue
            onVisibleChanged: if (visible) text = root.dirValue
            onAccepted: root.save({ imagesDir: text.trim() })
          }

          PanelButton {
            id: applyButton
            anchors.verticalCenter: parent.verticalCenter
            label: "Apply"
            action: function() { root.save({ imagesDir: dirField.text.trim() }) }
          }
        }

        NumberField {
          label: "Lock-frame rotation (seconds)"
          width: parent.width
          from: 5
          to: 600
          stepSize: 5
          value: root.rotateValue
          onModified: function(value) { root.save({ rotateSeconds: value }) }
        }

        Toggle {
          width: parent.width
          label: "Live drift under the lock screen"
          description: "Lock surface paints fed frames from the baked clips"
          checked: root.lockDrift
          onClicked: root.save({ lockDrift: !root.lockDrift })
        }

        Toggle {
          width: parent.width
          label: "Drift screensaver"
          description: "Off = Omarchy's terminal-effects screensaver"
          checked: root.screensaverDrift
          onClicked: root.save({ screensaverDrift: !root.screensaverDrift })
        }

        Row {
          width: parent.width
          spacing: Style.space(6)

          PanelButton {
            label: "Bake now"
            working: hostWidget ? hostWidget.busy : false
            action: function() { if (hostWidget) hostWidget.bake() }
          }
          PanelButton {
            label: "Install helpers"
            working: hostWidget ? hostWidget.busy : false
            action: function() { if (hostWidget) hostWidget.installHelpers() }
          }
          PanelButton {
            label: "Open folder"
            action: function() { if (hostWidget) hostWidget.openFolder() }
          }
        }

        Text {
          textFormat: Text.PlainText
          width: parent.width
          text: hostWidget && hostWidget.actionNote !== "" ? hostWidget.actionNote
                : "Install helpers once; stock idle/lock flows adopt them. Auto-lock delay lives in ~/.config/hypr/hypridle.conf."
          color: Qt.alpha(root.fg, 0.55)
          font.family: Style.font.family
          font.pixelSize: Style.font.caption
          wrapMode: Text.WordWrap
        }

        Item { width: 1; height: Style.space(2) }
      }
    }
  }

  onOpenedChanged: if (opened && hostWidget) hostWidget.probe()
}
