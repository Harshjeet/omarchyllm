import QtQuick
import QtQuick.Layouts
import Quickshell
import qs.Commons
import qs.Ui
import "js/ToolManager.js" as ToolManager

// Card requiring explicit user confirmation before executing shell commands or file operations
Item {
  id: root

  property string toolName: "run_command"
  property string toolCallId: ""
  property var toolArgs: ({})
  property bool isProcessing: false

  signal approved(string name, var args, string callId)
  signal denied(string name, string callId)

  readonly property var parsedArgs: ToolManager.parseToolArguments(toolArgs)
  readonly property string displayName: ToolManager.getToolDisplayName(toolName)
  readonly property string toolIcon: ToolManager.getToolIcon(toolName)
  readonly property string justification: parsedArgs.justification || ""

  implicitWidth: parent ? parent.width : Style.space(480)
  implicitHeight: card.implicitHeight + Style.space(4)

  Rectangle {
    id: card
    width: parent.width
    implicitHeight: column.implicitHeight + Style.space(16)
    radius: Style.cornerRadius > 0 ? Style.cornerRadius : Style.space(8)
    color: Style.normalFill
    border.width: 1
    border.color: Util.alpha(Color.accent, 0.5)

    Column {
      id: column
      anchors {
        left: parent.left
        right: parent.right
        top: parent.top
        margins: Style.space(10)
      }
      spacing: Style.space(8)

      // Header Row
      Row {
        width: parent.width
        spacing: Style.space(8)

        Rectangle {
          width: Style.space(22)
          height: Style.space(22)
          radius: width / 2
          color: Util.alpha(Color.accent, 0.2)
          border.width: 1
          border.color: Color.accent
          anchors.verticalCenter: parent.verticalCenter

          Text {
            anchors.centerIn: parent
            text: root.toolIcon
            font.family: Style.font.family
            font.pixelSize: Style.font.caption
            color: Color.accent
          }
        }

        Text {
          text: "Tool Permission Request: " + root.displayName
          font.family: Style.font.family
          font.pixelSize: Style.font.bodySmall
          font.weight: Font.DemiBold
          color: Color.popups.text
          anchors.verticalCenter: parent.verticalCenter
        }
      }

      // Justification Text
      Text {
        visible: root.justification !== ""
        width: parent.width
        text: "Justification: " + root.justification
        font.family: Style.font.family
        font.pixelSize: Style.font.caption
        color: Color.muted
        wrapMode: Text.Wrap
      }

      // Command or Parameter Preview Box
      Rectangle {
        width: parent.width
        implicitHeight: paramText.implicitHeight + Style.space(12)
        radius: Style.space(4)
        color: Util.alpha(Color.background, 0.6)
        border.width: 1
        border.color: Style.normalBorderColor

        TextEdit {
          id: paramText
          anchors {
            left: parent.left
            right: parent.right
            top: parent.top
            margins: Style.space(6)
          }
          text: {
            if (root.toolName === "run_command") {
              return "$ " + (root.parsedArgs.command || "");
            } else if (root.toolName === "read_file" || root.toolName === "list_dir") {
              return root.toolName + " " + (root.parsedArgs.path || "");
            } else if (root.toolName === "write_file") {
              return "write_file " + (root.parsedArgs.path || "") + "\n---\n" + (root.parsedArgs.content || "");
            } else if (root.toolName === "web_search") {
              return "🔍 Search: " + (root.parsedArgs.query || "") + " (max: " + (root.parsedArgs.max_results || 5) + ")";
            } else if (root.toolName === "edit_memory") {
              return "󰘚 Memory [" + (root.parsedArgs.action || "list") + "]: " + (root.parsedArgs.phrase || "");
            } else if (root.toolName === "load_skill") {
              return "󰦨 Load Skill: " + (root.parsedArgs.name || "");
            }
            return JSON.stringify(root.parsedArgs, null, 2);
          }
          font.family: "monospace"
          font.pixelSize: Style.font.caption
          color: Color.popups.text
          wrapMode: TextEdit.Wrap
          readOnly: true
          selectByMouse: true
        }
      }

      // Decision Buttons
      Row {
        anchors.right: parent.right
        spacing: Style.space(8)

        Button {
          text: "✕ Deny"
          enabled: !root.isProcessing
          onClicked: {
            root.denied(root.toolName, root.toolCallId);
          }
        }

        Button {
          text: root.isProcessing ? "Running..." : "✔ Approve & Run"
          active: true
          enabled: !root.isProcessing
          onClicked: {
            root.approved(root.toolName, root.parsedArgs, root.toolCallId);
          }
        }
      }
    }
  }
}
