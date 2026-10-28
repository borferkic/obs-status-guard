import QtQuick
import Quickshell
import Quickshell.Io
import qs.Commons
import qs.Commons as Commons
import qs.Ui

// The menu that opens from the bar pill: the two checks (reopen, sound), the
// alert size, a preview button and, while an alert is up, a dismiss button.
// Options are written to this widget's inline entry in shell.json, which the
// daemon reads back, so the shell and the daemon never disagree.
Panel {
  id: root
  moduleName: "io.github.borferkic.obs-status-guard"
  manageIpc: false

  property var anchorItem: null
  property var hostWidget: null
  readonly property var barIdentity: hostWidget || root
  property string guardState: "idle"

  readonly property string helper: Qt.resolvedUrl("bin/obs-status-guard").toString().replace("file://", "")
  readonly property bool monitoring: setting("monitoring", true) !== false
  readonly property bool autoRestart: setting("autoRestart", false) === true
  readonly property bool soundAlert: setting("soundAlert", true) !== false
  readonly property string obsMonitor: String(setting("obsMonitor", ""))
  readonly property string soundFile: String(setting("soundFile", ""))
  readonly property int alertScale: Math.max(100, Math.min(500, Number(setting("alertScale", 300))))

  Commons.Translations { id: strings; directory: Qt.resolvedUrl("i18n") }

  function open() { root.controller.show() }
  function close() { root.controller.hide() }
  function toggle() { if (root.opened) root.close(); else root.open() }

  // value === defaultValue removes the key, so shell.json only holds real choices.
  function setOption(key, value, defaultValue) {
    if (!root.bar || !root.bar.shell || typeof root.bar.shell.updateEntryInline !== "function") return
    var next = Object.assign({}, root.settings || {})
    next.id = root.moduleName
    if (value === defaultValue) delete next[key]
    else next[key] = value
    // Applied locally first so the control answers the click; the shell.json
    // write comes back through the bar as the same value.
    root.settings = next
    root.bar.shell.updateEntryInline(root.moduleName, next)
  }

  Process { id: previewProc; command: [root.helper, "preview"] }
  // The desktop file chooser (a portal dialog) prints the chosen path, or
  // nothing when the dialog is cancelled.
  Process {
    id: picker
    command: ["omarchy-file-select", "--title", strings.t("panel.soundFile.title"),
              "--extensions", "wav mp3 ogg oga opus flac m4a aac"]
    stdout: SplitParser {
      onRead: function(line) {
        var path = String(line).trim()
        if (path !== "") root.setOption("soundFile", path, "")
      }
    }
  }
  Process { id: dismissProc; command: [root.helper, "dismiss"] }

  KeyboardPanel {
    id: panel
    anchorItem: root.anchorItem
    owner: root.barIdentity
    bar: root.bar
    open: root.opened
    centerOnBar: false
    focusTarget: panel.loadedContent
    contentWidth: Style.space(360)
    contentHeight: panel.fittedContentHeight(panel.loadedContentHeight)

    content: PanelKeyCatcher {
      implicitHeight: column.implicitHeight
      anchors.fill: parent
      onCloseRequested: root.close()

      Column {
        id: column
        width: parent.width
        spacing: Style.space(10)

        Text {
          textFormat: Text.PlainText
          text: strings.t("panel.title")
          color: Commons.Color.popups.text
          font.family: Style.font.family
          font.bold: true
          font.pixelSize: Style.font.title
        }

        Toggle {
          width: parent.width
          label: strings.t("panel.monitoring.label")
          description: strings.t("panel.monitoring.desc")
          checked: root.monitoring
          onClicked: root.setOption("monitoring", !root.monitoring, true)
        }

        Toggle {
          width: parent.width
          label: strings.t("panel.autoRestart.label")
          description: strings.t("panel.autoRestart.desc")
          checked: root.autoRestart
          onClicked: root.setOption("autoRestart", !root.autoRestart, false)
        }

        Toggle {
          width: parent.width
          label: strings.t("panel.sound.label")
          description: strings.t("panel.sound.desc")
          checked: root.soundAlert
          onClicked: root.setOption("soundAlert", !root.soundAlert, true)
        }

        Column {
          width: parent.width
          spacing: Style.space(6)
          Text {
            textFormat: Text.PlainText
            width: parent.width
            elide: Text.ElideMiddle
            text: root.soundFile === "" ? strings.t("panel.soundFile.default") : root.soundFile.split("/").pop()
            color: Commons.Color.popups.text
            font.family: Style.font.family
            font.pixelSize: Style.font.body
          }
          Row {
            width: parent.width
            spacing: Style.space(8)
            Button {
              width: root.soundFile === "" ? parent.width : (parent.width - Style.space(8)) / 2
              text: strings.t("panel.soundFile.choose")
              bordered: true
              onClicked: picker.running = true
            }
            Button {
              visible: root.soundFile !== ""
              width: (parent.width - Style.space(8)) / 2
              text: strings.t("panel.soundFile.reset")
              bordered: true
              onClicked: root.setOption("soundFile", "", "")
            }
          }
        }

        Button {
          width: parent.width
          bordered: true
          text: strings.t("panel.obsMonitor").arg(root.obsMonitor === "" ? strings.t("panel.obsMonitor.auto") : root.obsMonitor)
          tooltipText: strings.t("panel.obsMonitor.tip")
          onClicked: {
            // default -> each connected monitor in turn -> default
            var names = [""]
            for (var i = 0; i < Quickshell.screens.length; i++) names.push(Quickshell.screens[i].name)
            var at = names.indexOf(root.obsMonitor)
            root.setOption("obsMonitor", names[(at + 1) % names.length], "")
          }
        }

        Row {
          width: parent.width
          spacing: Style.space(8)
          Button {
            text: "−"
            tooltipText: strings.t("panel.scale.less")
            enabled: root.alertScale > 100
            onClicked: root.setOption("alertScale", Math.max(100, root.alertScale - 50), 300)
          }
          Text {
            textFormat: Text.PlainText
            anchors.verticalCenter: parent.verticalCenter
            width: parent.width - Style.space(16) - Style.space(96)
            horizontalAlignment: Text.AlignHCenter
            text: strings.t("panel.scale").arg(Commons.I18n.formatNumber(root.alertScale))
            color: Commons.Color.popups.text
            font.family: Style.font.family
            font.pixelSize: Style.font.body
          }
          Button {
            text: "+"
            tooltipText: strings.t("panel.scale.more")
            enabled: root.alertScale < 500
            onClicked: root.setOption("alertScale", Math.min(500, root.alertScale + 50), 300)
          }
        }

        Button {
          width: parent.width
          text: strings.t("panel.preview")
          bordered: true
          onClicked: previewProc.running = true
        }

        Button {
          width: parent.width
          visible: root.guardState === "crashed"
          text: strings.t("panel.dismiss")
          bordered: true
          onClicked: { dismissProc.running = true; root.close() }
        }
      }
    }
  }
}
