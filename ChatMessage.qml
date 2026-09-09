import QtQuick
import QtQuick.Layouts
import Quickshell
import qs.Commons
import qs.Ui

// Chat message bubble rendering user prompts, assistant responses,
// collapsible thinking blocks, and one-click clipboard copying.
Item {
  id: root

  property string role: "user" // "user" | "assistant" | "system" | "tool"
  property string content: ""
  property string thinking: ""
  property string timestamp: ""
  property string modelName: ""
  property bool isStreaming: false

  // UI state
  property bool userToggledThinking: false
  readonly property bool isThinkingActive: root.isStreaming && (!root.content || root.content.trim() === "") && (root.thinking && root.thinking.trim() !== "")
  property bool thinkingExpanded: false
  property bool copied: false

  onIsThinkingActiveChanged: {
    if (isThinkingActive && !userToggledThinking) {
      thinkingExpanded = true
    }
  }

  implicitWidth: parent ? parent.width : Style.space(480)
  implicitHeight: card.implicitHeight + Style.space(4)

  // Copy content to Wayland clipboard using wl-copy
  function copyToClipboard(textToCopy) {
    var text = textToCopy || root.content
    if (!text) return
    Quickshell.execDetached(["bash", "-c", "printf %s " + Util.shellQuote(text) + " | wl-copy"])
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
    implicitHeight: column.implicitHeight + Style.space(16)
    radius: Style.cornerRadius > 0 ? Style.cornerRadius : Style.space(8)

    // User messages use a tinted accent background; Assistant messages use neutral card fill
    color: root.role === "user"
      ? Util.alpha(Color.accent, 0.12)
      : Style.normalFill

    border.width: 1
    border.color: root.role === "user"
      ? Util.alpha(Color.accent, 0.35)
      : Style.normalBorderColor

    Column {
      id: column
      anchors {
        left: parent.left
        right: parent.right
        top: parent.top
        margins: Style.space(10)
      }
      spacing: Style.space(8)

      // -------------------------------------------------------------
      // HEADER: Role avatar / name + Timestamp + Actions
      // -------------------------------------------------------------
      Item {
        width: parent.width
        height: Style.space(22)

        Row {
          anchors.left: parent.left
          anchors.verticalCenter: parent.verticalCenter
          spacing: Style.space(6)

          // Avatar Icon badge
          Rectangle {
            width: Style.space(20)
            height: Style.space(20)
            radius: width / 2
            color: root.role === "user"
              ? Color.accent
              : (root.isStreaming ? Util.alpha(Color.accent, 0.25) : Style.hoverFill)
            border.width: 1
            border.color: root.role === "user" ? Color.accent : Style.normalBorderColor
            anchors.verticalCenter: parent.verticalCenter

            Text {
              anchors.centerIn: parent
              text: root.role === "user" ? "" : "󰚩"
              font.family: Style.font.family
              font.pixelSize: Style.font.caption
              color: root.role === "user" ? Color.background : Color.popups.text
            }
          }

          // Author Label
          Text {
            text: root.role === "user" ? "You" : (root.modelName ? root.modelName : "Omarchy LLM")
            font.family: Style.font.family
            font.pixelSize: Style.font.bodySmall
            font.weight: Font.DemiBold
            color: root.role === "user" ? Color.accent : Color.popups.text
            anchors.verticalCenter: parent.verticalCenter
          }

          // Timestamp
          Text {
            visible: root.timestamp !== ""
            text: root.timestamp
            font.family: Style.font.family
            font.pixelSize: Style.font.caption
            color: Color.muted
            anchors.verticalCenter: parent.verticalCenter
          }

          // Streaming pill indicator
          Rectangle {
            visible: root.isStreaming
            width: Style.space(6)
            height: Style.space(6)
            radius: width / 2
            color: Color.accent
            anchors.verticalCenter: parent.verticalCenter

            SequentialAnimation on opacity {
              running: root.isStreaming
              loops: Animation.Infinite
              NumberAnimation { from: 1.0; to: 0.2; duration: 600; easing.type: Easing.InOutQuad }
              NumberAnimation { from: 0.2; to: 1.0; duration: 600; easing.type: Easing.InOutQuad }
            }
          }
        }

        // Action Toolbar (Right)
        Row {
          anchors.right: parent.right
          anchors.verticalCenter: parent.verticalCenter
          spacing: Style.space(4)

          // Copy Message Button
          Rectangle {
            width: Style.space(24)
            height: Style.space(20)
            radius: Style.cornerRadius > 0 ? Style.cornerRadius / 2 : Style.space(4)
            color: copyMouse.containsMouse ? Style.hoverFill : "transparent"
            border.width: 1
            border.color: copyMouse.containsMouse ? Style.hoverBorderColor : "transparent"

            Text {
              anchors.centerIn: parent
              text: root.copied ? "✔" : "󰆏"
              font.family: Style.font.family
              font.pixelSize: Style.font.caption
              color: root.copied ? "#a6e3a1" : (copyMouse.containsMouse ? Color.accent : Color.muted)
            }

            MouseArea {
              id: copyMouse
              anchors.fill: parent
              hoverEnabled: true
              cursorShape: Qt.PointingHandCursor
              onClicked: root.copyToClipboard(root.content)
            }
          }
        }
      }

      // -------------------------------------------------------------
      // COLLAPSIBLE THINKING ACCORDION (DeepSeek-R1 / Qwen-QwQ / Claude)
      // -------------------------------------------------------------
      Column {
        width: parent.width
        visible: root.thinking && root.thinking.trim() !== ""
        spacing: Style.space(4)

        // Accordion Toggle Header Bar
        Rectangle {
          width: parent.width
          height: Style.space(26)
          radius: Style.space(4)
          color: thinkingMouse.containsMouse ? Style.hoverFill : Util.alpha(Color.foreground, 0.04)
          border.width: 1
          border.color: Style.normalBorderColor

          Item {
            anchors.fill: parent
            anchors.leftMargin: Style.space(8)
            anchors.rightMargin: Style.space(8)

            Row {
              anchors.left: parent.left
              anchors.verticalCenter: parent.verticalCenter
              spacing: Style.space(6)

              Text {
                text: root.thinkingExpanded ? "▾" : "▸"
                font.family: Style.font.family
                font.pixelSize: Style.font.caption
                color: Color.muted
                anchors.verticalCenter: parent.verticalCenter
              }

              Text {
                text: "󱚣 Thinking Process"
                font.family: Style.font.family
                font.pixelSize: Style.font.caption
                font.weight: Font.Medium
                color: root.isStreaming && !root.content ? Color.accent : Color.muted
                anchors.verticalCenter: parent.verticalCenter
              }
            }

            Text {
              anchors.right: parent.right
              anchors.verticalCenter: parent.verticalCenter
              text: root.thinkingExpanded ? "Click to collapse" : "Click to view"
              font.family: Style.font.family
              font.pixelSize: Style.font.caption
              color: Color.muted
            }
          }

          MouseArea {
            id: thinkingMouse
            anchors.fill: parent
            hoverEnabled: true
            cursorShape: Qt.PointingHandCursor
            onClicked: {
              root.userToggledThinking = true
              root.thinkingExpanded = !root.thinkingExpanded
            }
          }
        }

        // Expanded Thinking Content Box
        Rectangle {
          visible: root.thinkingExpanded
          width: parent.width
          implicitHeight: Math.min(Style.space(200), thinkingText.implicitHeight + Style.space(16))
          radius: Style.space(4)
          color: Util.alpha(Color.background, 0.5)
          border.width: 1
          border.color: Style.normalBorderColor
          clip: true

          Flickable {
            anchors.fill: parent
            anchors.margins: Style.space(8)
            contentWidth: width
            contentHeight: thinkingText.implicitHeight
            clip: true
            boundsBehavior: Flickable.StopAtBounds

            TextEdit {
              id: thinkingText
              width: parent.width
              text: root.thinking
              font.family: "monospace"
              font.pixelSize: Style.font.caption
              color: Color.muted
              wrapMode: TextEdit.Wrap
              readOnly: true
              selectByMouse: true
              selectionColor: Style.selectionFill
            }
          }
        }
      }

      // -------------------------------------------------------------
      // MAIN MESSAGE CONTENT BODY
      // -------------------------------------------------------------
      TextEdit {
        id: bodyText
        width: parent.width
        text: {
          if (root.content !== "") return root.content
          if (root.isStreaming) {
            if (root.thinking && root.thinking.trim() !== "") return "*(Thinking...)*"
            return "Thinking..."
          }
          if (root.thinking && root.thinking.trim() !== "") return ""
          return "[Empty response]"
        }
        textFormat: TextEdit.MarkdownText
        font.family: Style.font.family
        font.pixelSize: Style.font.body
        color: Color.popups.text
        wrapMode: TextEdit.Wrap
        readOnly: true
        selectByMouse: true
        selectionColor: Style.selectionFill
      }
    }
  }
}
