import QtQuick
import Quickshell
import Quickshell.Io
import Quickshell.Wayland
import qs.Commons
import qs.Commons as Commons

// Owns the obs-status-guard daemon, the on-screen warning and its sound. The
// bar has a widget per monitor, so the one daemon and the one warning live
// here and the widgets only read the state file.
Item {
  id: root

  property string guardState: "idle"
  property bool restarting: false
  property bool previewing: false
  property bool soundAlert: true
  property int alertScale: 300
  property string soundFile: ""
  property string monitorName: ""

  readonly property bool alertShown: guardState === "crashed" || previewing
  readonly property string helper: Qt.resolvedUrl("bin/obs-status-guard").toString().replace("file://", "")
  readonly property string defaultSound: "/usr/share/sounds/freedesktop/stereo/alarm-clock-elapsed.oga"

  Commons.Translations { id: strings; directory: Qt.resolvedUrl("i18n") }

  Process {
    id: daemon
    command: [root.helper, "daemon"]
    running: true
    stdout: SplitParser {
      onRead: function(line) {
        try {
          var s = JSON.parse(line)
          root.guardState = String(s.state || "idle")
          root.restarting = s.restarting === true
          root.previewing = s.preview === true
          root.soundAlert = s.soundAlert !== false
          root.alertScale = Math.max(100, Math.min(500, Number(s.alertScale || 300)))
          root.soundFile = String(s.soundFile || "")
          root.monitorName = String(s.monitor || "")
        } catch (e) { /* partial line while the daemon restarts */ }
      }
    }
    onExited: restart.start()
  }
  Timer { id: restart; interval: 3000; onTriggered: daemon.running = true }

  // The sound plays once when the alert starts. A preview always plays it once,
  // so the volume can be checked before the sound alert is turned on.
  // A chosen file goes through ffplay (it reads mp3, aac and the rest, and
  // -t cuts a long file at 10 s); the built-in alarm goes through pw-play.
  // The daemon only passes absolute paths, so a name can never read as an option.
  Process {
    id: player
    command: root.soundFile !== ""
      ? ["ffplay", "-nodisp", "-autoexit", "-loglevel", "error", "-t", "10", root.soundFile]
      : ["pw-play", root.defaultSound]
  }
  function playAlert() { if (!player.running) player.running = true }

  readonly property bool crashed: guardState === "crashed"
  onCrashedChanged: if (crashed && soundAlert) playAlert()
  onPreviewingChanged: if (previewing) playAlert()
  function screenByName(name) {
    for (var i = 0; i < Quickshell.screens.length; i++)
      if (Quickshell.screens[i].name === name) return Quickshell.screens[i]
    return Quickshell.screens.length > 0 ? Quickshell.screens[0] : null
  }

  // Sits just above the volume OSD (a bottom-centered card 67 units from the
  // edge) on one fixed monitor, whichever one has focus.
  PanelWindow {
    id: alert
    readonly property real k: root.alertScale / 100
    // Same footprint as the OSD card, plus a gap, so the two never overlap.
    readonly property int osdTop: Style.space(67) + Style.font.displayLarge + Style.space(32) + Style.space(14)

    readonly property var targetScreen: root.screenByName(root.monitorName)
    visible: root.alertShown && targetScreen !== null
    screen: targetScreen
    anchors { bottom: true; left: true; right: true }
    implicitHeight: osdTop + card.height + Style.space(8)
    color: "transparent"
    exclusionMode: ExclusionMode.Ignore
    WlrLayershell.layer: WlrLayer.Overlay
    WlrLayershell.namespace: "omarchy-obs-status-guard"
    WlrLayershell.keyboardFocus: WlrKeyboardFocus.None
    // Visual only: never swallow clicks meant for the desktop below.
    mask: Region {}

    Rectangle {
      id: card
      anchors.horizontalCenter: parent.horizontalCenter
      anchors.bottom: parent.bottom
      anchors.bottomMargin: alert.osdTop
      width: Math.min(row.implicitWidth + Style.space(32) * alert.k, parent.width - Style.space(16))
      height: row.implicitHeight + Style.space(32) * alert.k
      color: Qt.rgba(Commons.Color.background.r, Commons.Color.background.g, Commons.Color.background.b, 0.97)
      border.color: Commons.Color.urgent
      border.width: Math.max(1, Style.space(2) * Math.sqrt(alert.k))
      radius: Style.cornerRadius * alert.k
      opacity: root.alertShown ? 1 : 0
      Behavior on opacity { NumberAnimation { duration: Style.duration(180); easing.type: Easing.OutCubic } }

      Row {
        id: row
        anchors.centerIn: parent
        spacing: Style.space(14) * alert.k

        Text {
          textFormat: Text.PlainText
          anchors.verticalCenter: parent.verticalCenter
          text: "●"
          color: Commons.Color.urgent
          font.family: Style.font.family
          font.pixelSize: Style.font.displayLarge * alert.k
        }
        Column {
          anchors.verticalCenter: parent.verticalCenter
          spacing: Style.space(2) * alert.k
          Text {
            textFormat: Text.PlainText
            text: strings.t("alert.title")
            color: Commons.Color.popups.text
            font.family: Style.font.family
            font.bold: true
            font.pixelSize: Style.font.title * alert.k
          }
          Text {
            textFormat: Text.PlainText
            text: root.restarting ? strings.t("alert.restarting") : strings.t("alert.body")
            color: Commons.Color.popups.text
            font.family: Style.font.family
            font.pixelSize: Style.font.body * alert.k
          }
        }
      }
    }
  }
}
