import QtQuick
import Quickshell
import Quickshell.Io
import Quickshell.Services.SystemTray
import qs.Commons
import qs.Ui
import "Status.js" as Status
import "StatusStrings.js" as Strings

// Bar widget for the kDrive desktop client (Infomaniak).
//
// kDrive 3.x on Linux exposes no safe API: its GUI <-> server channel takes a
// single client and the server quits when that client drops. So the widget only
// reads the tooltip of the official tray icon (StatusNotifierItem
// "kDrive_client") and drives the client from the outside: open its window,
// restart it, open the synced folder. See README.md for the upstream tracking.
Panel {
  id: root
  moduleName: "rle87.kdrive"
  ipcTarget: "rle87.kdrive"

  readonly property string trayId: "kDrive_client"
  readonly property string home: Quickshell.env("HOME") || ""
  readonly property string logDir: home + "/.local/state/kDrive/logs"

  // ---------- Settings (inline in shell.json) ----------
  readonly property string appImage: expandHome(setting("appImage", "~/Applications/kDrive.AppImage"))
  readonly property string webUrl: setting("webUrl", "https://kdrive.infomaniak.com")
  readonly property bool notify: setting("notify", true)
  readonly property bool hideTrayIcon: setting("hideTrayIcon", false)

  function expandHome(path) {
    var p = String(path || "")
    return p.indexOf("~/") === 0 ? home + p.slice(1) : p
  }

  function saveSetting(name, value) {
    if (!root.bar || !root.bar.shell || typeof root.bar.shell.updateEntryInline !== "function") return
    var next = {}
    for (var k in root.settings) next[k] = root.settings[k]
    next[name] = value
    root.bar.shell.updateEntryInline(root.moduleName, next)
  }

  // Moves the official kDrive icon in or out of the tray's hidden list.
  // A third-party widget may only update its own shell.json entry, and
  // `omarchy bar set --json` mangles arrays, so edit the file in one write
  // (tray lists and our own setting together); the shell reloads it on change.
  function setTrayIconHidden(hidden) {
    if (trayProc.running) return
    trayProc.command = ["bash", "-c",
      "f=\"$1\"; tmp=$(mktemp \"$f.XXXXXX\") || exit 1; " +
      "jq --arg id \"$2\" --arg me \"$3\" --argjson hide \"$4\" '" +
      "(.bar.layout[][] | select(.id == \"omarchy.tray\")) |= (" +
      "  .hidden = ((.hidden // [] | if type == \"array\" then . else [.] end) - [$id] + (if $hide then [$id] else [] end))" +
      "  | .pinned = ((.pinned // []) - (if $hide then [$id] else [] end)))" +
      " | (.bar.layout[][] | select(.id == $me)).hideTrayIcon = $hide" +
      "' \"$f\" > \"$tmp\" && mv \"$tmp\" \"$f\" || { rm -f \"$tmp\"; exit 1; }",
      "kdrive-tray", root.home + "/.config/omarchy/shell.json", root.trayId, root.moduleName, hidden ? "true" : "false"]
    trayProc.running = true
  }

  // ---------- kDrive state ----------
  readonly property var trayItem: {
    var values = SystemTray.items.values
    for (var i = 0; i < values.length; i++) {
      if (values[i] && values[i].id === root.trayId) return values[i]
    }
    return null
  }
  readonly property string tooltip: trayItem ? String(trayItem.tooltipTitle || "") + "\n" + String(trayItem.tooltipDescription || "") : ""
  readonly property var parsed: Status.parse(tooltip, home)
  readonly property string syncState: trayItem ? parsed.state : "offline"
  readonly property var folders: trayItem ? parsed.folders : []
  readonly property string folderPath: folders.length > 0 ? folders[0].path : setting("folder", "")
  readonly property bool problem: Status.isProblem(syncState)

  property bool restarting: false
  property var disk: null          // { source, fstype, target, avail, size, used, writable }
  property var recentErrors: []    // last error lines of the kDrive server log
  property string lastState: ""

  onSyncStateChanged: {
    if (root.notify && root.lastState !== "" && root.lastState !== root.syncState && !root.restarting) {
      if (Status.isProblem(root.syncState)) {
        Quickshell.execDetached(["notify-send", "-a", "kDrive", "-i", "dialog-warning",
                                 "kDrive : " + Status.labels[root.syncState],
                                 root.folderPath !== "" ? root.folderPath : "Ouvrez le panneau kDrive pour les détails."])
      } else if (root.syncState === "offline") {
        Quickshell.execDetached(["notify-send", "-a", "kDrive", "-i", "dialog-warning",
                                 "kDrive s'est arrêté", "La synchronisation n'est plus active."])
      }
    }
    root.lastState = root.syncState
    refreshDetails()
  }

  function refreshDetails() {
    if (root.folderPath !== "" && !diskProc.running) {
      diskProc.command = ["bash", "-c",
        "p=\"$1\"; m=$(findmnt -n -o SOURCE,FSTYPE,TARGET -T \"$p\" 2>/dev/null | head -1); " +
        "d=$(df -h --output=avail,size,pcent \"$p\" 2>/dev/null | tail -1); " +
        "w=no; [ -w \"$p\" ] && w=yes; echo \"$m\"; echo \"$d\"; echo \"$w\"",
        "kdrive-disk", root.folderPath]
      diskProc.running = true
    }
    if (!logProc.running) logProc.running = true
  }

  function parseDisk(raw) {
    var lines = String(raw || "").split("\n")
    var mount = (lines[0] || "").trim().split(/\s+/)
    var space = (lines[1] || "").trim().split(/\s+/)
    if (mount.length < 3) { root.disk = null; return }
    root.disk = { source: mount[0], fstype: mount[1], target: mount.slice(2).join(" "),
                  avail: space[0] || "?", size: space[1] || "?", used: space[2] || "?",
                  writable: (lines[2] || "").trim() === "yes" }
  }

  // ---------- Actions ----------
  function openFolder() {
    if (root.folderPath !== "") Quickshell.execDetached(["xdg-open", root.folderPath])
    close()
  }

  function openWeb() {
    Quickshell.execDetached(["xdg-open", root.webUrl])
    close()
  }

  function openLogs() {
    Quickshell.execDetached(["xdg-open", root.logDir])
    close()
  }

  // Shows the official kDrive window (status, activity, preferences).
  function openOfficialWindow() {
    if (root.trayItem) root.trayItem.activate()
    close()
  }

  function start() {
    Quickshell.execDetached(["uwsm-app", "--", root.appImage])
  }

  // Quitting the GUI makes the kDrive server quit too; wait for both before relaunching.
  function restart() {
    if (restartProc.running) return
    root.restarting = true
    restartProc.command = ["bash", "-c",
      "pkill -TERM -x kDrive_client; " +
      "for i in $(seq 1 60); do pgrep -x kDrive_client >/dev/null || pgrep -f '[.]mount_kDrive' >/dev/null || break; sleep 0.5; done; " +
      "exec uwsm-app -- \"$1\"", "kdrive-restart", root.appImage]
    restartProc.running = true
  }

  onOpenedChanged: if (opened) refreshDetails()
  Component.onCompleted: refreshDetails()

  Process {
    id: diskProc
    stdout: StdioCollector { waitForEnd: true; onStreamFinished: root.parseDisk(text) }
  }

  // Last error lines of the newest server log, without the timestamp noise.
  Process {
    id: logProc
    command: ["bash", "-c",
      "f=$(ls -t \"$1\"/*_kDrive.log 2>/dev/null | head -1); [ -n \"$f\" ] || exit 0; " +
      "grep -a ' \\[E\\] ' \"$f\" | grep -av 'versionretriever\\|Failed to set full access rights' | tail -3 | " +
      "sed -E 's/^[0-9-]+ ([0-9]+:[0-9]+):[0-9:]+ \\[E\\] \\([0-9]+\\) [^ ]+ - /\\1 /'",
      "kdrive-log", root.logDir]
    stdout: StdioCollector {
      waitForEnd: true
      onStreamFinished: root.recentErrors = String(text || "").split("\n").filter(function(l) { return l.trim() !== "" })
    }
  }

  Process { id: trayProc }

  Process {
    id: restartProc
    onExited: function() { restartDone.restart() }
  }

  // Leave the new client a moment to register its tray icon before notifying again.
  Timer { id: restartDone; interval: 20000; onTriggered: root.restarting = false }

  // The tray tooltip is reactive; this only keeps disk space and errors fresh.
  Timer { interval: root.opened ? 5000 : 60000; running: true; repeat: true; onTriggered: root.refreshDetails() }

  implicitWidth: button.implicitWidth
  implicitHeight: button.implicitHeight

  BarIconButton {
    id: button
    anchors.fill: parent
    bar: root.bar
    text: Status.icons[root.syncState] || Status.icons.undefined
    active: root.problem
    dimmed: root.syncState === "offline" || root.syncState === "paused"
    tooltipText: "kDrive : " + (Status.labels[root.syncState] || root.syncState)
    onPressed: function(b) { root.toggle() }
  }

  KeyboardPanel {
    id: panel
    anchorItem: button
    owner: root
    bar: root.bar
    open: root.opened
    focusTarget: keyCatcher
    contentWidth: panel.fittedContentWidth(Style.space(400))
    contentHeight: panel.fittedContentHeight(column.implicitHeight)

    PanelKeyCatcher {
      id: keyCatcher
      anchors.fill: parent
      onCloseRequested: root.close()
      onTabRequested: function(direction) { root.switchPanel(direction) }

      Column {
        id: column
        anchors.left: parent.left
        anchors.right: parent.right
        anchors.top: parent.top
        spacing: Style.space(14)

        // ---------- Hero ----------
        Row {
          width: parent.width
          spacing: Style.space(14)

          Text {
            id: heroIcon
            textFormat: Text.PlainText
            text: button.text
            color: root.problem ? Color.urgent : root.bar.foreground
            font.family: root.bar.fontFamily
            font.pixelSize: Style.font.display
            anchors.verticalCenter: parent.verticalCenter
          }

          Column {
            anchors.verticalCenter: parent.verticalCenter
            width: parent.width - heroIcon.width - parent.spacing
            spacing: Style.space(2)

            Text {
              text: "kDrive"
              color: root.bar.foreground
              font.family: root.bar.fontFamily
              font.pixelSize: Style.font.title
              font.bold: true
              elide: Text.ElideRight
              width: parent.width
            }

            Text {
              textFormat: Text.PlainText
              text: (root.restarting ? "Redémarrage…" : Status.labels[root.syncState] || root.syncState).toUpperCase()
              color: root.problem ? Color.urgent : Qt.darker(root.bar.foreground, 1.4)
              font.family: root.bar.fontFamily
              font.pixelSize: Style.font.caption
              font.bold: true
              font.letterSpacing: 1.2
              elide: Text.ElideRight
              width: parent.width
            }
          }
        }

        PanelSeparator { foreground: root.bar.foreground }

        // ---------- Folders ----------
        Text {
          visible: root.syncState === "offline"
          width: parent.width
          wrapMode: Text.Wrap
          text: "Le client kDrive ne tourne pas : rien n'est synchronisé."
          color: root.bar.foreground
          opacity: 0.7
          font.family: root.bar.fontFamily
          font.pixelSize: Style.font.bodySmall
        }

        Repeater {
          model: root.folders

          Column {
            required property var modelData
            width: column.width
            spacing: Style.space(4)

            Row {
              width: parent.width
              spacing: Style.space(8)

              Rectangle {
                width: Style.space(8)
                height: width
                radius: width / 2
                anchors.verticalCenter: parent.verticalCenter
                color: Status.isProblem(modelData.state) ? Color.urgent
                     : modelData.state === "ok" || modelData.state === "running" ? Color.accent
                     : Qt.rgba(root.bar.foreground.r, root.bar.foreground.g, root.bar.foreground.b, 0.3)
              }

              Text {
                textFormat: Text.PlainText
                text: modelData.path
                color: root.bar.foreground
                font.family: root.bar.fontFamily
                font.pixelSize: Style.font.body
                font.bold: true
                elide: Text.ElideMiddle
                width: parent.width - Style.space(16)
                anchors.verticalCenter: parent.verticalCenter
              }
            }

            Text {
              textFormat: Text.PlainText
              text: modelData.state === "undefined" && modelData.message !== "" ? modelData.message : Status.labels[modelData.state]
              leftPadding: Style.space(16)
              width: parent.width
              elide: Text.ElideRight
              color: root.bar.foreground
              opacity: 0.6
              font.family: root.bar.fontFamily
              font.pixelSize: Style.font.bodySmall
            }
          }
        }

        // ---------- Disk ----------
        Text {
          visible: root.disk !== null && root.syncState !== "offline"
          width: parent.width
          wrapMode: Text.Wrap
          textFormat: Text.PlainText
          text: root.disk ? (root.disk.avail + " libres sur " + root.disk.size + " (" + root.disk.used + " utilisés) · "
                             + root.disk.source + " " + root.disk.fstype + " sur " + root.disk.target) : ""
          color: root.bar.foreground
          opacity: 0.6
          font.family: root.bar.fontFamily
          font.pixelSize: Style.font.caption
        }

        Text {
          visible: root.disk !== null && !root.disk.writable
          width: parent.width
          wrapMode: Text.Wrap
          text: "Le dossier n'est pas modifiable par votre utilisateur : kDrive ne pourra pas y écrire."
          color: Color.urgent
          font.family: root.bar.fontFamily
          font.pixelSize: Style.font.bodySmall
        }

        // ---------- Recent errors (only when something is wrong) ----------
        Column {
          visible: (root.problem || root.syncState === "offline") && root.recentErrors.length > 0
          width: parent.width
          spacing: Style.space(4)

          PanelSectionHeader {
            text: "Dernières erreurs du journal"
            foreground: root.bar.foreground
            fontFamily: root.bar.fontFamily
          }

          Repeater {
            model: root.recentErrors

            Text {
              required property string modelData
              width: column.width
              wrapMode: Text.WrapAnywhere
              maximumLineCount: 3
              elide: Text.ElideRight
              textFormat: Text.PlainText
              text: modelData
              color: Color.urgent
              font.family: root.bar.fontFamily
              font.pixelSize: Style.font.caption
            }
          }
        }

        PanelSeparator { foreground: root.bar.foreground }

        // ---------- Actions ----------
        Flow {
          width: parent.width
          spacing: Style.space(6)

          Button {
            visible: root.syncState === "offline" && !root.restarting
            text: "Démarrer kDrive"
            iconText: "󰐊"
            fontSize: Style.font.bodySmall
            foreground: root.bar.foreground
            fontFamily: root.bar.fontFamily
            bordered: true
            onClicked: root.start()
          }

          Button {
            visible: root.folderPath !== ""
            text: "Dossier"
            iconText: "󰉋"
            fontSize: Style.font.bodySmall
            foreground: root.bar.foreground
            fontFamily: root.bar.fontFamily
            bordered: true
            onClicked: root.openFolder()
          }

          Button {
            visible: root.trayItem !== null
            text: "Fenêtre kDrive"
            iconText: "󰍹"
            tooltipText: "Activité, pause et préférences dans l'application officielle"
            fontSize: Style.font.bodySmall
            foreground: root.bar.foreground
            fontFamily: root.bar.fontFamily
            bordered: true
            onClicked: root.openOfficialWindow()
          }

          Button {
            text: "En ligne"
            iconText: "󰖟"
            fontSize: Style.font.bodySmall
            foreground: root.bar.foreground
            fontFamily: root.bar.fontFamily
            bordered: true
            onClicked: root.openWeb()
          }

          Button {
            visible: root.syncState !== "offline" || root.restarting
            text: root.restarting ? "Redémarrage…" : "Redémarrer"
            iconText: "󰑓"
            iconSpinning: root.restarting
            tooltipText: "Quitte puis relance le client kDrive"
            fontSize: Style.font.bodySmall
            foreground: root.bar.foreground
            fontFamily: root.bar.fontFamily
            bordered: true
            onClicked: root.restart()
          }

          Button {
            text: "Journaux"
            iconText: "󰈙"
            fontSize: Style.font.bodySmall
            foreground: root.bar.foreground
            fontFamily: root.bar.fontFamily
            bordered: true
            onClicked: root.openLogs()
          }
        }

        PanelSeparator { foreground: root.bar.foreground }

        // ---------- Settings ----------
        PanelSectionHeader {
          text: "Réglages"
          foreground: root.bar.foreground
          fontFamily: root.bar.fontFamily
        }

        Toggle {
          width: parent.width
          label: "Notifications"
          description: "Prévenir quand la synchronisation s'arrête, échoue ou que kDrive se ferme."
          foreground: root.bar.foreground
          fontFamily: root.bar.fontFamily
          checked: root.notify
          onClicked: root.saveSetting("notify", !root.notify)
        }

        Toggle {
          width: parent.width
          label: "Masquer l'icône officielle"
          description: "Retire l'icône kDrive de la zone de notification : ce widget la remplace."
          foreground: root.bar.foreground
          fontFamily: root.bar.fontFamily
          checked: root.hideTrayIcon
          onClicked: root.setTrayIconHidden(!root.hideTrayIcon)
        }

        Column {
          width: parent.width
          spacing: Style.space(4)

          Text {
            text: "AppImage kDrive"
            color: root.bar.foreground
            font.family: root.bar.fontFamily
            font.pixelSize: Style.font.bodySmall
          }

          TextField {
            id: appImageField
            width: parent.width
            text: root.setting("appImage", "~/Applications/kDrive.AppImage")
            placeholderText: "~/Applications/kDrive.AppImage"
            foreground: root.bar.foreground
            font.family: root.bar.fontFamily
            onEditingFinished: if (text.trim() !== "") root.saveSetting("appImage", text.trim())
          }
        }

        Text {
          width: parent.width
          wrapMode: Text.Wrap
          textFormat: Text.PlainText
          text: "Compatible kDrive " + Strings.upstreamVersion + " · lecture de l'état via l'icône système"
          color: root.bar.foreground
          opacity: 0.4
          font.family: root.bar.fontFamily
          font.pixelSize: Style.font.caption
        }
      }
    }
  }
}
