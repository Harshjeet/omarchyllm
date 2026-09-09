import QtQuick
import QtQuick.Layouts
import Quickshell
import qs.Commons
import qs.Ui
import "js/ToolManager.js" as ToolManager

// Collapsible terminal console block displaying stdout, stderr, and exit codes of executed tools
Item {
  id: root

  property string toolName: "run_command"
  property var toolArgs: ({})
  property string stdoutText: ""
  property string stderrText: ""
  property int exitCode: 0
  property bool isRunning: false

  // UI state
  property bool isExpanded: true
  property bool copied: false

  readonly property var parsedArgs: ToolManager.parseToolArguments(toolArgs)
  readonly property string displayName: ToolManager.getToolDisplayName(toolName)
  readonly property string toolIcon: ToolManager.getToolIcon(toolName)

  implicitWidth: parent ? parent.width : Style.space(480)
  implicitHeight: card.implicitHeight + Style.space(4)

  function copyOutput() {
    var full = (stdoutText ? stdoutText : "") + (stderrText ? ("\n" + stderrText) : "")
    if (!full) return
    Quickshell.execDetached(["bash", "-c", "printf %s " + Util.shellQuote(full) + " | wl-copy"])
    root.copied = true
    copiedTimer.restart()
  }

  Timer {
    id: copiedTimer
    interval: 2000
    onTriggered: root.copied = false
  }

  Rectangle {
    id: card
    width: parent.width
    implicitHeight: column.implicitHeight + Style.space(12)
    radius: Style.cornerRadius > 0 ? Style.cornerRadius : Style.space(6)
    color: Style.normalFill
    border.width: 1
    border.color: root.exitCode === 0 ? Style.normalBorderColor : Color.urgent

    Column {
      id: column
      anchors {
        left: parent.left
        right: parent.right
        top: parent.top
        margins: Style.space(8)
      }
      spacing: Style.space(6)

      // Header Bar (Clickable to collapse/expand)
      Item {
        id: headerBar
        width: parent.width
        height: Style.space(24)

        Row {
          anchors.left: parent.left
          anchors.verticalCenter: parent.verticalCenter
          spacing: Style.space(6)

          Text {
            text: root.isExpanded ? "▾" : "▸"
            font.family: Style.font.family
            font.pixelSize: Style.font.caption
            color: Color.muted
            anchors.verticalCenter: parent.verticalCenter
          }

          Text {
            text: root.toolIcon
            font.family: Style.font.family
            font.pixelSize: Style.font.caption
            color: Color.accent
            anchors.verticalCenter: parent.verticalCenter
          }

          Text {
            text: root.displayName + (root.parsedArgs.command ? (": " + root.parsedArgs.command) : (root.parsedArgs.query ? (": " + root.parsedArgs.query) : (root.parsedArgs.name ? (": " + root.parsedArgs.name) : (root.parsedArgs.path ? (": " + root.parsedArgs.path) : ""))))
            font.family: Style.font.family
            font.pixelSize: Style.font.caption
            font.weight: Font.Medium
            color: Color.popups.text
            elide: Text.ElideRight
            width: Math.min(Math.max(headerBar.width - Style.space(120), 0), implicitWidth)
            anchors.verticalCenter: parent.verticalCenter
          }

          // Status Badge: Running or Exit Code
          Rectangle {
            height: Style.space(16)
            width: statusBadgeText.implicitWidth + Style.space(8)
            radius: height / 2
            color: root.isRunning
              ? Util.alpha(Color.accent, 0.2)
              : (root.exitCode === 0 ? Util.alpha("#a6e3a1", 0.2) : Util.alpha(Color.urgent, 0.2))
            border.width: 1
            border.color: root.isRunning ? Color.accent : (root.exitCode === 0 ? "#a6e3a1" : Color.urgent)
            anchors.verticalCenter: parent.verticalCenter

            Text {
              id: statusBadgeText
              anchors.centerIn: parent
              text: root.isRunning ? "Running..." : ("exit: " + root.exitCode)
              font.family: Style.font.family
              font.pixelSize: Style.font.caption
              font.weight: Font.Medium
              color: root.isRunning ? Color.accent : (root.exitCode === 0 ? "#a6e3a1" : Color.urgent)
            }
          }
        }

        // Action Toolbar (Right)
        Row {
          anchors.right: parent.right
          anchors.verticalCenter: parent.verticalCenter
          spacing: Style.space(4)

          Rectangle {
            width: Style.space(22)
            height: Style.space(20)
            radius: Style.space(3)
            color: copyMouse.containsMouse ? Style.hoverFill : "transparent"

            Text {
              anchors.centerIn: parent
              text: root.copied ? "✔" : "󰆏"
              font.family: Style.font.family
              font.pixelSize: Style.font.caption
              color: root.copied ? "#a6e3a1" : Color.muted
            }

            MouseArea {
              id: copyMouse
              anchors.fill: parent
              hoverEnabled: true
              cursorShape: Qt.PointingHandCursor
              onClicked: root.copyOutput()
            }
          }
        }

        MouseArea {
          anchors.left: parent.left
          anchors.right: parent.right
          anchors.rightMargin: Style.space(30)
          anchors.top: parent.top
          anchors.bottom: parent.bottom
          cursorShape: Qt.PointingHandCursor
          onClicked: root.isExpanded = !root.isExpanded
        }
      }

      // Collapsible Console Output Area
      Rectangle {
        visible: root.isExpanded
        width: parent.width
        implicitHeight: Math.min(Style.space(220), outputText.implicitHeight + Style.space(12))
        radius: Style.space(4)
        color: Util.alpha(Color.background, 0.7)
        border.width: 1
        border.color: Style.normalBorderColor
        clip: true

        Flickable {
          anchors.fill: parent
          anchors.margins: Style.space(6)
          contentWidth: width
          contentHeight: outputText.implicitHeight
          clip: true
          boundsBehavior: Flickable.StopAtBounds

          TextEdit {
            id: outputText
            width: parent.width
            text: {
              var out = root.stdoutText || "";
              if (root.stderrText) {
                out += (out ? "\n[stderr]\n" : "[stderr]\n") + root.stderrText;
              }
              return out.trim() !== "" ? out : (root.isRunning ? "Executing..." : "(No output)");
            }
            font.family: "monospace"
            font.pixelSize: Style.font.caption
            color: root.exitCode === 0 ? Color.popups.text : Color.urgent
            wrapMode: TextEdit.Wrap
            readOnly: true
            selectByMouse: true
            selectionColor: Style.selectionFill
          }
        }
      }
    }
  }
}
