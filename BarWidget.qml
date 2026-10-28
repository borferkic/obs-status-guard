import QtQuick
import Quickshell
import Quickshell.Io
import qs.Commons
import qs.Commons as Commons
import qs.Ui as Ui

// ON AIR pill with the stream time while OBS is live (green), and an
// OBS CLOSED pill (red) after an abrupt close. Hidden otherwise. It only
// reads the state file the daemon writes; the Service owns the daemon.
Ui.BarWidget {
  id: root
  moduleName: "io.github.borferkic.obs-status-guard"

  property string guardState: "idle"
  property int seconds: 0

  readonly property string helper: Qt.resolvedUrl("bin/obs-status-guard").toString().replace("file://", "")
  readonly property string stateFile: (Quickshell.env("XDG_RUNTIME_DIR") || "/tmp") + "/obs-status-guard/state.json"
  readonly property color liveColor: "#66c98b"
  readonly property color closedColor: Commons.Color.urgent

  Commons.Translations { id: strings; directory: Qt.resolvedUrl("i18n") }

  function clock(total) {
    var h = Math.floor(total / 3600)
    var m = Math.floor((total % 3600) / 60)
    var s = total % 60
    return h + ":" + (m < 10 ? "0" : "") + m + ":" + (s < 10 ? "0" : "") + s
  }

  FileView {
    id: file
    path: root.stateFile
    printErrors: false
    onLoaded: {
      try {
        var s = JSON.parse(text())
        root.guardState = String(s.state || "idle")
        root.seconds = Number(s.seconds || 0)
      } catch (e) { root.guardState = "idle" }
    }
    onLoadFailed: root.guardState = "idle"
  }
  Timer { interval: 1000; running: true; repeat: true; triggeredOnStart: true; onTriggered: file.reload() }

  function injectPanel() {
    var target = panelLoader.item
    if (!target) return
    if ("bar" in target) target.bar = root.bar
    if ("settings" in target) target.settings = root.settings
    if ("anchorItem" in target) target.anchorItem = pill
    if ("hostWidget" in target) target.hostWidget = root
    if ("guardState" in target) target.guardState = root.guardState
  }
  onBarChanged: injectPanel()
  onSettingsChanged: injectPanel()
  onGuardStateChanged: injectPanel()

  // Shape contract for the bar's popout routing.
  readonly property bool opened: panelLoader.item ? panelLoader.item.opened === true : false
  readonly property bool popoutSwitchClosing: panelLoader.item ? panelLoader.item.popoutSwitchClosing === true : false
  function open() { if (panelLoader.item) panelLoader.item.open() }
  function close() { if (panelLoader.item) panelLoader.item.close() }
  function toggle() { if (panelLoader.item) panelLoader.item.toggle() }
  function closeForPopoutSwitch() { if (panelLoader.item) panelLoader.item.closeForPopoutSwitch() }

  Loader {
    id: panelLoader
    active: true
    source: Qt.resolvedUrl("Panel.qml")
    visible: false
    onLoaded: { root.injectPanel(); Qt.callLater(root.injectPanel) }
  }

  // Idle stays visible as a dim marker, so it is clear the plugin is running.
  implicitWidth: pill.width + Style.space(8)
  implicitHeight: barSize

  Rectangle {
    id: pill
    anchors.verticalCenter: parent.verticalCenter
    anchors.horizontalCenter: parent.horizontalCenter
    height: Math.max(Style.space(22), parent.height - Style.space(10))
    width: label.implicitWidth + Style.space(24)
    // The same corners as the rest of the UI (Hyprland's rounding), not a capsule.
    radius: Style.cornerRadius
    color: root.guardState === "live" ? root.liveColor : (root.guardState === "crashed" ? root.closedColor : "transparent")

    Text {
      id: label
      textFormat: Text.PlainText
      anchors.centerIn: parent
      color: (root.guardState === "idle" || root.guardState === "off") ? Commons.Color.foreground : "#101418"
      opacity: root.guardState === "off" ? 0.3 : (root.guardState === "idle" ? 0.5 : 1)
      font.family: Style.font.family
      font.bold: true
      font.pixelSize: Style.font.bodySmall
      text: root.guardState === "live"
        ? "●  " + strings.t("widget.onair") + "  " + root.clock(root.seconds)
        : (root.guardState === "crashed" ? "●  " + strings.t("widget.closed")
          : (root.guardState === "off" ? "○  " + strings.t("widget.off") : "●  " + strings.t("widget.idle")))
    }

    MouseArea {
      anchors.fill: parent
      cursorShape: Qt.PointingHandCursor
      onClicked: root.toggle()
    }
  }
}
