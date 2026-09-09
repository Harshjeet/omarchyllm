import QtQuick
import Quickshell
import Quickshell.Io
import qs.Commons
import qs.Ui

// Omarchy LLM Bar Widget with left-click toggle, right-click context menu, and IPC handler
BarWidget {
  id: root
  moduleName: "harsh.llm"

  readonly property var panelItem: panelLoader.item
  readonly property bool opened: panelItem ? panelItem.opened === true : false
  readonly property bool isGenerating: panelItem ? panelItem.isGenerating === true : false
  readonly property string activeModelName: panelItem ? panelItem.activeModelName : "AI Assistant"

  function injectPanel() {
    var target = panelLoader.item
    if (!target) return
    if ("bar" in target) target.bar = root.bar
    if ("settings" in target) target.settings = root.settings
    if ("anchorItem" in target) target.anchorItem = button
    if ("hostWidget" in target) target.hostWidget = root
  }

  function openChat() {
    contextMenu.open = false
    if (panelLoader.item && panelLoader.item.openChat) {
      panelLoader.item.openChat()
    } else {
      root.open()
    }
  }

  function openSettings() {
    contextMenu.open = false
    if (panelLoader.item && panelLoader.item.openSettings) {
      panelLoader.item.openSettings()
    } else {
      root.open()
    }
  }

  function clearChat() {
    contextMenu.open = false
    if (panelLoader.item && panelLoader.item.clearChat) {
      panelLoader.item.clearChat()
    }
  }

  function togglePanel() {
    contextMenu.open = false
    if (panelLoader.item && panelLoader.item.toggle) {
      panelLoader.item.toggle()
    }
  }

  function open() {
    contextMenu.open = false
    if (panelLoader.item && panelLoader.item.open) panelLoader.item.open()
  }

  function close() {
    contextMenu.open = false
    if (panelLoader.item && panelLoader.item.close) panelLoader.item.close()
  }

  readonly property real openPanelIndicatorWidth: button.labelWidth > 0 ? button.labelWidth : Style.bar.iconSlot
  readonly property real openPanelIndicatorHeight: Math.max(Style.space(10), Math.round(Style.bar.iconSlot * 0.55))

  implicitWidth: button.implicitWidth
  implicitHeight: button.implicitHeight

  onBarChanged: injectPanel()
  onSettingsChanged: injectPanel()

  Loader {
    id: panelLoader
    active: true
    source: Qt.resolvedUrl("Panel.qml")
    visible: false
    onLoaded: {
      root.injectPanel()
      Qt.callLater(root.injectPanel)
    }
    onStatusChanged: {
      if (status === Loader.Error) {
        console.error("OmarchyLLM: Failed to load Panel.qml:", sourceComponent ? sourceComponent.errorString() : "unknown error")
      }
    }
  }

  function sendPrompt(text) {
    console.log("OmarchyLLM: BarWidget.sendPrompt called with:", text)
    contextMenu.open = false
    root.openChat()
    if (panelLoader.item && panelLoader.item.sendPrompt) {
      panelLoader.item.sendPrompt(text)
    } else {
      console.warn("OmarchyLLM: panelLoader.item or sendPrompt not available")
    }
  }

  // --- IPC Interface for Terminal & Hyprland Shortcuts ---
  IpcHandler {
    target: "harsh.llm"

    function open(): void { root.openChat() }
    function openChat(): void { root.openChat() }
    function close(): void { root.close() }
    function show(): void { root.openChat() }
    function hide(): void { root.close() }
    function toggle(): void { root.togglePanel() }
    function settings(): void { root.openSettings() }
    function openSettings(): void { root.openSettings() }
    function clear(): void { root.clearChat() }
    function clearChat(): void { root.clearChat() }
    function prompt(text: string): void { root.sendPrompt(text) }
  }

  IpcHandler {
    target: "omarchy.llm"

    function open(): void { root.openChat() }
    function openChat(): void { root.openChat() }
    function close(): void { root.close() }
    function show(): void { root.openChat() }
    function hide(): void { root.close() }
    function toggle(): void { root.togglePanel() }
    function settings(): void { root.openSettings() }
    function openSettings(): void { root.openSettings() }
    function clear(): void { root.clearChat() }
    function clearChat(): void { root.clearChat() }
    function prompt(text: string): void { root.sendPrompt(text) }
  }

  // --- Bar Icon Button ---
  BarIconButton {
    id: button
    anchors.fill: parent
    bar: root.bar
    text: root.setting("icon", "󰚩")
    slotSize: Style.bar.iconSlot
    active: root.opened || root.isGenerating
    useActiveColor: true
    activeColor: root.isGenerating ? Color.accent : (root.opened ? Color.accent : Color.foreground)
    tooltipText: root.isGenerating
      ? "Omarchy LLM (Generating response...)"
      : ("Omarchy LLM • " + root.activeModelName)

    onPressed: function(b) {
      if (b === Qt.RightButton) {
        // Toggle the quick context menu on right click
        contextMenu.open = !contextMenu.open
      } else {
        // Left click toggles the main chat panel
        root.togglePanel()
      }
    }
  }

  // --- Right-Click Context Menu Popup ---
  PopupCard {
    id: contextMenu
    anchorItem: button
    bar: root.bar
    owner: root
    open: false
    contentWidth: Style.space(200)
    contentHeight: Style.space(136)

    Column {
      anchors.fill: parent
      anchors.margins: Style.space(6)
      spacing: Style.space(4)

      // Option 1: Open Settings
      Rectangle {
        width: parent.width
        height: Style.space(36)
        radius: Style.cornerRadius > 0 ? Style.cornerRadius / 2 : 0
        color: settingsMouse.containsMouse ? Style.hoverFill : "transparent"

        Row {
          anchors.fill: parent
          anchors.leftMargin: Style.space(10)
          spacing: Style.space(10)

          Text {
            text: "⚙"
            font.family: Style.font.family
            font.pixelSize: Style.font.body
            color: Color.popups.text
            anchors.verticalCenter: parent.verticalCenter
          }

          Text {
            text: "Settings & Models"
            font.family: Style.font.family
            font.pixelSize: Style.font.body
            font.weight: Font.Medium
            color: Color.popups.text
            anchors.verticalCenter: parent.verticalCenter
          }
        }

        MouseArea {
          id: settingsMouse
          anchors.fill: parent
          hoverEnabled: true
          cursorShape: Qt.PointingHandCursor
          onClicked: root.openSettings()
        }
      }

      // Option 2: Open Chat
      Rectangle {
        width: parent.width
        height: Style.space(36)
        radius: Style.cornerRadius > 0 ? Style.cornerRadius / 2 : 0
        color: chatMouse.containsMouse ? Style.hoverFill : "transparent"

        Row {
          anchors.fill: parent
          anchors.leftMargin: Style.space(10)
          spacing: Style.space(10)

          Text {
            text: "󰚩"
            font.family: Style.font.family
            font.pixelSize: Style.font.body
            color: Color.popups.text
            anchors.verticalCenter: parent.verticalCenter
          }

          Text {
            text: "Open Assistant"
            font.family: Style.font.family
            font.pixelSize: Style.font.body
            color: Color.popups.text
            anchors.verticalCenter: parent.verticalCenter
          }
        }

        MouseArea {
          id: chatMouse
          anchors.fill: parent
          hoverEnabled: true
          cursorShape: Qt.PointingHandCursor
          onClicked: root.openChat()
        }
      }

      // Option 3: Clear Chat
      Rectangle {
        width: parent.width
        height: Style.space(36)
        radius: Style.cornerRadius > 0 ? Style.cornerRadius / 2 : 0
        color: clearMouse.containsMouse ? Style.hoverFill : "transparent"

        Row {
          anchors.fill: parent
          anchors.leftMargin: Style.space(10)
          spacing: Style.space(10)

          Text {
            text: "🧹"
            font.family: Style.font.family
            font.pixelSize: Style.font.body
            color: Color.popups.text
            anchors.verticalCenter: parent.verticalCenter
          }

          Text {
            text: "Clear Conversation"
            font.family: Style.font.family
            font.pixelSize: Style.font.body
            color: Color.popups.text
            anchors.verticalCenter: parent.verticalCenter
          }
        }

        MouseArea {
          id: clearMouse
          anchors.fill: parent
          hoverEnabled: true
          cursorShape: Qt.PointingHandCursor
          onClicked: root.clearChat()
        }
      }
    }
  }
}
