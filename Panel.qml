import QtQuick
import QtQuick.Layouts
import QtQuick.Controls as QQC
import Quickshell
import Quickshell.Io
import qs.Commons
import qs.Ui
import "js/Config.js" as Config
import "js/SystemInfo.js" as SystemInfo
import "js/Api.js" as Api
import "js/ContextCompactor.js" as ContextCompactor

// Main popup panel for Omarchy LLM with settings management, system telemetry, and live file watching
Panel {
  id: root
  moduleName: "harsh.llm"
  ipcTarget: "harsh.llm"
  manageIpc: false

  property var anchorItem: null
  property var hostWidget: null
  readonly property var barIdentity: hostWidget || root

  // Navigation tab state: "chat" or "settings"
  property string currentTab: "chat"
  property string settingsSubTab: "providers"

  // Status flags
  property bool isGenerating: false
  property bool hasError: false
  property string statusText: isGenerating ? "Thinking..." : "Ready"

  // Live System Telemetry
  property var currentTelemetry: ({})
  property bool showTelemetryPreview: false
  readonly property string formattedSystemPrompt: SystemInfo.interpolatePrompt(
    appConfig.systemPrompt || Config.DEFAULT_SYSTEM_PROMPT,
    currentTelemetry,
    currentTelemetry.memories || ""
  )

  // Memory & Compaction State
  property var memoryList: []
  property string newMemoryTextInput: ""
  property bool isTestingCompaction: false
  property string compactionTestResponse: ""
  property string compactionTestStatus: ""

  // -------------------------------------------------------------
  // Persistent Configuration, Key & Memory Watching
  // -------------------------------------------------------------
  FileView {
    id: configFile
    path: Quickshell.env("HOME") + "/.local/state/omarchy/plugins/harsh.llm/config.json"
    watchChanges: true
    printErrors: false
    onFileChanged: reload()
  }

  FileView {
    id: keysFile
    path: Quickshell.env("HOME") + "/.local/state/omarchy/plugins/harsh.llm/keys.json"
    watchChanges: true
    printErrors: false
    onFileChanged: reload()
  }

  FileView {
    id: memoryFile
    path: Quickshell.env("HOME") + "/.local/state/omarchy/plugins/harsh.llm/memory.json"
    watchChanges: true
    printErrors: false
    onFileChanged: {
      refreshMemories()
      refreshTelemetry()
    }
  }

  property var appConfig: Config.parseConfigFile(configFile.text())
  property var appKeys: Config.parseKeysFile(keysFile.text())

  readonly property string activeProviderId: appConfig.activeProvider || "ollama"
  readonly property var activeProviderObj: Config.getProvider(activeProviderId)
  readonly property string activeModelName: appConfig.activeModel || (activeProviderObj ? activeProviderObj.defaultModels[0] : "llama3.2")
  readonly property string activeEndpoint: (appConfig.endpoints && appConfig.endpoints[activeProviderId])
    ? appConfig.endpoints[activeProviderId]
    : (activeProviderObj ? activeProviderObj.defaultEndpoint : "")
  readonly property string currentApiKey: appKeys[activeProviderId] || ""

  // Ephemeral editing state in settings
  property string editingProviderId: activeProviderId
  readonly property var editingProviderObj: Config.getProvider(editingProviderId)
  property string editingKeyInput: ""
  property bool showKeyPlaintext: false
  property string saveFeedbackMsg: ""

  onActiveProviderIdChanged: {
    editingProviderId = activeProviderId
    editingKeyInput = appKeys[activeProviderId] || ""
  }

  function open() {
    refreshTelemetry()
    root.controller.show()
    Qt.callLater(function() {
      if (root.opened) setCenterHoverRevealSuppressed(true)
    })
  }

  function close() {
    setCenterHoverRevealSuppressed(false)
    root.controller.hide()
  }

  function toggle() {
    if (root.opened) root.close()
    else root.open()
  }

  function setCenterHoverRevealSuppressed(value) {
    if (root.bar && "centerHoverRevealSuppressed" in root.bar)
      root.bar.centerHoverRevealSuppressed = value
  }

  function openChat() {
    currentTab = "chat"
    open()
  }

  function openSettings() {
    currentTab = "settings"
    editingProviderId = activeProviderId
    editingKeyInput = appKeys[activeProviderId] || ""
    saveFeedbackMsg = ""
    open()
  }

  function clearChat() {
    if (chatView) chatView.clearHistory()
  }

  function sendPrompt(promptText) {
    console.log("OmarchyLLM: Panel.sendPrompt called:", promptText)
    openChat()
    if (chatView) chatView.sendUserPrompt(promptText)
    else console.warn("OmarchyLLM: chatView is null in Panel")
  }

  // -------------------------------------------------------------
  // Configuration Mutation Helpers
  // -------------------------------------------------------------
  function saveCurrentConfig(mutated) {
    var payload = JSON.stringify(mutated)
    saveConfigProcess.command = [
      "python3",
      Qt.resolvedUrl("save-config.py").toString().replace(/^file:\/\//, ""),
      "--save-config",
      payload
    ]
    saveConfigProcess.running = true
  }

  function updateConfigKey(key, value) {
    var updated = JSON.parse(JSON.stringify(appConfig))
    updated[key] = value
    saveCurrentConfig(updated)
  }

  function updateNestedConfig(parentKey, childKey, value) {
    var updated = JSON.parse(JSON.stringify(appConfig))
    if (!updated[parentKey]) updated[parentKey] = {}
    updated[parentKey][childKey] = value
    saveCurrentConfig(updated)
  }

  function selectProvider(pId) {
    var p = Config.getProvider(pId)
    var updated = JSON.parse(JSON.stringify(appConfig))
    updated.activeProvider = pId
    if (!updated.endpoints) updated.endpoints = {}
    if (!updated.endpoints[pId]) updated.endpoints[pId] = p.defaultEndpoint
    if (updated.providerModels && updated.providerModels[pId]) {
      updated.activeModel = updated.providerModels[pId]
    } else {
      updated.activeModel = p.defaultModels[0]
    }
    saveCurrentConfig(updated)
  }

  function selectModel(mName) {
    var updated = JSON.parse(JSON.stringify(appConfig))
    updated.activeProvider = editingProviderId
    updated.activeModel = mName
    if (!updated.providerModels) updated.providerModels = {}
    updated.providerModels[editingProviderId] = mName
    saveCurrentConfig(updated)
  }

  function setEndpoint(ep) {
    var updated = JSON.parse(JSON.stringify(appConfig))
    if (!updated.endpoints) updated.endpoints = {}
    updated.endpoints[editingProviderId] = ep
    saveCurrentConfig(updated)
  }

  function saveApiKey(pId, key) {
    saveKeyProcess.command = [
      "python3",
      Qt.resolvedUrl("save-config.py").toString().replace(/^file:\/\//, ""),
      "--save-key",
      pId,
      key
    ]
    saveKeyProcess.running = true
  }

  // --- Background Save Processes ---
  Process {
    id: saveConfigProcess
    onExited: {
      configFile.reload()
      root.saveFeedbackMsg = "Configuration saved!"
    }
  }

  Process {
    id: saveKeyProcess
    onExited: {
      keysFile.reload()
      root.editingKeyInput = ""
      root.saveFeedbackMsg = "API key saved securely (0600)!"
    }
  }

  // --- Telemetry Gathering Process ---
  Process {
    id: telemetryProc
    command: [
      "python3",
      Qt.resolvedUrl("telemetry.py").toString().replace(/^file:\/\//, "")
    ]
    stdout: StdioCollector {
      waitForEnd: true
      onStreamFinished: {
        try {
          if (text.trim() !== "") {
            root.currentTelemetry = JSON.parse(text)
          }
        } catch(e) {
          console.warn("OmarchyLLM: Failed to parse telemetry output:", e)
        }
      }
    }
  }

  // --- Persistent Memory Management Processes ---
  Process {
    id: memoryListProc
    command: [
      "python3",
      Qt.resolvedUrl("memory.py").toString().replace(/^file:\/\//, ""),
      "list",
      "--json"
    ]
    stdout: StdioCollector {
      waitForEnd: true
      onStreamFinished: {
        try {
          if (text.trim() !== "") {
            root.memoryList = JSON.parse(text)
          } else {
            root.memoryList = []
          }
        } catch(e) {
          root.memoryList = []
        }
      }
    }
  }

  Process {
    id: memoryActionProc
    onExited: {
      refreshMemories()
      refreshTelemetry()
    }
  }

  function refreshMemories() {
    if (!memoryListProc.running) memoryListProc.running = true
  }

  function addMemoryPhrase(phrase) {
    if (!phrase || phrase.trim() === "") return
    memoryActionProc.command = [
      "python3",
      Qt.resolvedUrl("memory.py").toString().replace(/^file:\/\//, ""),
      "add",
      phrase.trim()
    ]
    memoryActionProc.running = true
  }

  function removeMemoryPhrase(indexOrPhrase) {
    memoryActionProc.command = [
      "python3",
      Qt.resolvedUrl("memory.py").toString().replace(/^file:\/\//, ""),
      "remove",
      String(indexOrPhrase)
    ]
    memoryActionProc.running = true
  }

  function clearAllMemories() {
    memoryActionProc.command = [
      "python3",
      Qt.resolvedUrl("memory.py").toString().replace(/^file:\/\//, ""),
      "clear"
    ]
    memoryActionProc.running = true
  }

  // --- Offline Whisper Diagnostics & Testing Processes ---
  property var whisperDiagnostics: null
  property string whisperTestResult: ""
  property bool isTestingWhisper: false
  property bool isDownloadingWhisperModel: false

  Process {
    id: whisperCheckProc
    command: [
      "python3",
      Qt.resolvedUrl("stt.py").toString().replace(/^file:\/\//, ""),
      "--check"
    ]
    stdout: StdioCollector {
      waitForEnd: true
      onStreamFinished: {
        try {
          root.whisperDiagnostics = JSON.parse(text)
        } catch(e) {
          console.warn("OmarchyLLM: Failed to parse whisper diagnostics:", e)
        }
      }
    }
  }

  Process {
    id: testWhisperProc
    command: [
      "python3",
      Qt.resolvedUrl("stt.py").toString().replace(/^file:\/\//, ""),
      "--file",
      "/tmp/test_silence.wav",
      "--backend",
      "whisper"
    ]
    onExited: function(exitCode, exitStatus) {
      root.isTestingWhisper = false
      if (exitCode === 0) {
        root.whisperTestResult = "✔ Test Passed: Offline Whisper (whisper-cpp) is working perfectly!"
      } else {
        root.whisperTestResult = "✖ Test Failed (exit code " + exitCode + "). Check stderr output."
      }
      refreshWhisperStatus()
    }
  }

  Process {
    id: downloadWhisperModelProc
    command: [
      "python3",
      Qt.resolvedUrl("stt.py").toString().replace(/^file:\/\//, ""),
      "--download-model",
      "ggml-base.en.bin"
    ]
    onExited: function(exitCode, exitStatus) {
      root.isDownloadingWhisperModel = false
      refreshWhisperStatus()
    }
  }

  function refreshWhisperStatus() {
    whisperCheckProc.running = true
  }

  function runWhisperTest() {
    root.isTestingWhisper = true
    root.whisperTestResult = "Running test transcription..."
    testWhisperProc.running = true
  }

  function triggerDownloadWhisperModel() {
    root.isDownloadingWhisperModel = true
    root.whisperTestResult = "Downloading model ggml-base.en.bin (~142MB)..."
    downloadWhisperModelProc.running = true
  }

  function refreshTelemetry() {
    if (!telemetryProc.running) telemetryProc.running = true
  }

  onOpenedChanged: {
    if (opened) {
      refreshTelemetry()
      refreshMemories()
      refreshWhisperStatus()
    }
  }

  onSettingsSubTabChanged: {
    if (settingsSubTab === "voice") {
      refreshWhisperStatus()
    }
  }

  Component.onCompleted: {
    refreshTelemetry()
    refreshMemories()
    refreshWhisperStatus()
  }

  Timer {
    interval: 30000
    running: root.opened
    repeat: true
    onTriggered: {
      root.refreshTelemetry()
      root.refreshMemories()
    }
  }

  KeyboardPanel {
    id: panel
    anchorItem: root.anchorItem
    owner: root.barIdentity
    bar: root.bar
    open: root.opened
    centerOnBar: false
    focusTarget: keyCatcher

    contentWidth: panel.fittedContentWidth(Style.space(540))
    contentHeight: panel.fittedContentHeight(Style.space(660))

    PanelKeyCatcher {
      id: keyCatcher
      anchors.fill: parent
      onCloseRequested: root.close()
      onTabRequested: function(direction) {
        root.currentTab = (root.currentTab === "chat") ? "settings" : "chat"
      }

      Column {
        anchors.fill: parent
        anchors.margins: Style.spacing.popupPadding
        spacing: Style.space(10)

        // =========================================================
        // TOP HEADER BAR
        // =========================================================
        Item {
          width: parent.width
          height: Style.space(36)

          Row {
            anchors.left: parent.left
            anchors.verticalCenter: parent.verticalCenter
            spacing: Style.space(8)

            Rectangle {
              width: Style.space(28)
              height: Style.space(28)
              radius: Style.cornerRadius > 0 ? Math.min(Style.cornerRadius, width / 2) : Style.space(6)
              color: root.isGenerating ? Util.alpha(Color.accent, 0.2) : Style.normalFill
              border.width: 1
              border.color: root.isGenerating ? Color.accent : Style.normalBorderColor
              anchors.verticalCenter: parent.verticalCenter

              Text {
                anchors.centerIn: parent
                text: "󰚩"
                font.family: Style.font.family
                font.pixelSize: Style.font.heading
                color: root.isGenerating ? Color.accent : Color.popups.text
              }
            }

            Column {
              anchors.verticalCenter: parent.verticalCenter
              spacing: Style.space(1)

              Row {
                spacing: Style.space(6)

                Text {
                  text: "Omarchy LLM"
                  font.family: Style.font.family
                  font.pixelSize: Style.font.title
                  font.weight: Font.Bold
                  color: Color.popups.text
                }

                Rectangle {
                  anchors.verticalCenter: parent.verticalCenter
                  height: Style.space(16)
                  width: statusRow.width + Style.space(10)
                  radius: height / 2
                  color: root.isGenerating ? Util.alpha(Color.accent, 0.2) : Style.normalFill
                  border.width: 1
                  border.color: root.isGenerating ? Color.accent : Style.normalBorderColor

                  Row {
                    id: statusRow
                    anchors.centerIn: parent
                    spacing: Style.space(4)

                    Rectangle {
                      width: Style.space(6)
                      height: Style.space(6)
                      radius: width / 2
                      color: root.hasError ? Color.urgent : (root.isGenerating ? Color.accent : "#a6e3a1")
                      anchors.verticalCenter: parent.verticalCenter
                    }

                    Text {
                      text: root.statusText
                      font.family: Style.font.family
                      font.pixelSize: Style.font.caption
                      font.weight: Font.Medium
                      color: Color.popups.text
                      anchors.verticalCenter: parent.verticalCenter
                    }
                  }
                }
              }

              Rectangle {
                id: quickModelPill
                width: quickModelRow.implicitWidth + Style.space(12)
                height: Style.space(20)
                radius: Style.space(4)
                color: quickModelMouse.containsMouse ? Style.hoverFill : "transparent"
                border.width: 1
                border.color: quickModelMouse.containsMouse ? Style.hoverBorderColor : "transparent"

                Row {
                  id: quickModelRow
                  anchors.centerIn: parent
                  spacing: Style.space(4)

                  Text {
                    text: root.activeProviderObj.displayName + " • " + root.activeModelName
                    font.family: Style.font.family
                    font.pixelSize: Style.font.caption
                    color: quickModelMouse.containsMouse ? Color.accent : Color.muted
                  }

                  Text {
                    text: "▾"
                    font.family: Style.font.family
                    font.pixelSize: Style.font.caption
                    color: Color.muted
                  }
                }

                MouseArea {
                  id: quickModelMouse
                  anchors.fill: parent
                  hoverEnabled: true
                  cursorShape: Qt.PointingHandCursor
                  onClicked: quickModelMenu.open()
                }

                QQC.Menu {
                  id: quickModelMenu
                  y: quickModelPill.height + Style.space(4)

                  QQC.MenuItem {
                    text: "★ nvidia/nemotron-3.5-lightning:free (Verified Fast)"
                    onTriggered: root.selectModel("nvidia/nemotron-3.5-lightning:free")
                  }
                  QQC.MenuItem {
                    text: "★ liquid/lfm-2.5-2.6b:free (Verified Fast)"
                    onTriggered: root.selectModel("liquid/lfm-2.5-2.6b:free")
                  }
                  QQC.MenuItem {
                    text: "★ nex-agi/nex-n2.5-mini:free (Verified Fast)"
                    onTriggered: root.selectModel("nex-agi/nex-n2.5-mini:free")
                  }
                  QQC.MenuItem {
                    text: "★ inclusionai/ling-3.0-flash-fin:free (Verified)"
                    onTriggered: root.selectModel("inclusionai/ling-3.0-flash-fin:free")
                  }
                  QQC.MenuSeparator {}
                  QQC.MenuItem {
                    text: "⚙ More Models in Settings..."
                    onTriggered: root.openSettings()
                  }
                }
              }
            }
          }

          // Navigation Tab Pills
          Row {
            anchors.right: parent.right
            anchors.verticalCenter: parent.verticalCenter
            spacing: Style.space(6)

            Button {
              text: "󰭻 Chat"
              active: root.currentTab === "chat"
              onClicked: root.currentTab = "chat"
            }

            Button {
              text: "⚙ Settings"
              active: root.currentTab === "settings"
              onClicked: root.openSettings()
            }

            Button {
              text: "󰅖"
              onClicked: root.close()
            }
          }
        }

        Rectangle {
          width: parent.width
          height: 1
          color: Color.popups.border
        }

        // =========================================================
        // MAIN VIEW CONTAINER
        // =========================================================
        Item {
          id: mainContentArea
          width: parent.width
          height: parent.height - Style.space(56)

          // -------------------------------------------------------
          // TAB 1: CHAT VIEW
          // -------------------------------------------------------
          ChatView {
            id: chatView
            anchors.fill: parent
            visible: root.currentTab === "chat"
            appConfig: root.appConfig
            appKeys: root.appKeys
            activeProviderId: root.activeProviderId
            activeProviderObj: root.activeProviderObj
            activeModelName: root.activeModelName
            activeEndpoint: root.activeEndpoint
            currentApiKey: root.currentApiKey
            formattedSystemPrompt: root.formattedSystemPrompt
            onIsGeneratingChanged: {
              root.isGenerating = chatView.isGenerating
            }
            onOpenSettingsRequested: {
              root.currentTab = "settings"
              root.settingsSubTab = "voice"
            }
          }

          // -------------------------------------------------------
          // TAB 2: SETTINGS & PROFILES VIEW
          // -------------------------------------------------------
          Column {
            anchors.fill: parent
            visible: root.currentTab === "settings"
            spacing: Style.space(10)

            Rectangle {
              width: parent.width
              height: parent.height
              radius: Style.cornerRadius
              color: Style.normalFill
              border.width: 1
              border.color: Style.normalBorderColor

              QQC.ScrollView {
                anchors.fill: parent
                anchors.margins: Style.space(14)
                clip: true

                Column {
                  width: mainContentArea.width - Style.space(40)
                  spacing: Style.space(14)

                  // Title & feedback
                  Item {
                    width: parent.width
                    height: titleText.implicitHeight

                    Text {
                      id: titleText
                      anchors.left: parent.left
                      anchors.verticalCenter: parent.verticalCenter
                      text: {
                        if (root.settingsSubTab === "generation") return "Inference & Generation Controls"
                        if (root.settingsSubTab === "tools") return "Tool Calling & System Permissions"
                        if (root.settingsSubTab === "web") return "Web Search Configuration"
                        if (root.settingsSubTab === "compaction") return "Context Compaction & Token Optimization"
                        if (root.settingsSubTab === "voice") return "Voice & Speech-to-Text (STT)"
                        if (root.settingsSubTab === "system") return "System Prompt, Telemetry & Memory"
                        return "Model Providers & API Keys"
                      }
                      font.family: Style.font.family
                      font.pixelSize: Style.font.heading
                      font.weight: Font.Bold
                      color: Color.popups.text
                    }

                    Text {
                      anchors.right: parent.right
                      anchors.verticalCenter: parent.verticalCenter
                      text: root.saveFeedbackMsg
                      font.family: Style.font.family
                      font.pixelSize: Style.font.bodySmall
                      color: Color.accent
                      visible: root.saveFeedbackMsg !== ""
                    }
                  }

                  // Sub-category Navigation Pills
                  Flow {
                    width: parent.width
                    spacing: Style.space(6)

                    Button {
                      text: "󰒓 Providers"
                      active: root.settingsSubTab === "providers"
                      onClicked: root.settingsSubTab = "providers"
                    }

                    Button {
                      text: "󰅒 Generation"
                      active: root.settingsSubTab === "generation"
                      onClicked: root.settingsSubTab = "generation"
                    }

                    Button {
                      text: "󰞋 Tools"
                      active: root.settingsSubTab === "tools"
                      onClicked: root.settingsSubTab = "tools"
                    }

                    Button {
                      text: "󰖟 Web"
                      active: root.settingsSubTab === "web"
                      onClicked: root.settingsSubTab = "web"
                    }

                    Button {
                      text: "󰈚 Compaction"
                      active: root.settingsSubTab === "compaction"
                      onClicked: root.settingsSubTab = "compaction"
                    }

                    Button {
                      text: "󰍬 Voice / STT"
                      active: root.settingsSubTab === "voice"
                      onClicked: root.settingsSubTab = "voice"
                    }

                    Button {
                      text: "󰚩 System & Memory"
                      active: root.settingsSubTab === "system"
                      onClicked: root.settingsSubTab = "system"
                    }
                  }

                  Rectangle {
                    width: parent.width
                    height: 1
                    color: Style.normalBorderColor
                  }

                  // =========================================================
                  // SUB-TAB 1: PROVIDERS & MODELS
                  // =========================================================
                  Column {
                    width: parent.width
                    visible: root.settingsSubTab === "providers"
                    spacing: Style.space(12)

                    // Provider Selection Chips
                    Column {
                      width: parent.width
                      spacing: Style.space(6)

                      Text {
                        text: "Select Provider:"
                        font.family: Style.font.family
                        font.pixelSize: Style.font.bodySmall
                        font.weight: Font.DemiBold
                        color: Color.muted
                      }

                      Flow {
                        width: parent.width
                        spacing: Style.space(6)

                        Repeater {
                          model: Config.getProviders()

                          Button {
                            text: modelData.displayName + (root.activeProviderId === modelData.id ? " ★" : "")
                            active: root.editingProviderId === modelData.id
                            onClicked: {
                              root.editingProviderId = modelData.id
                              root.editingKeyInput = root.appKeys[modelData.id] || ""
                              root.saveFeedbackMsg = ""
                            }
                          }
                        }
                      }

                      Row {
                        visible: root.editingProviderId !== root.activeProviderId
                        spacing: Style.space(8)

                        Button {
                          text: "✔ Set " + root.editingProviderObj.displayName + " as Active Provider"
                          onClicked: {
                            root.selectProvider(root.editingProviderId)
                            root.saveFeedbackMsg = "Switched to " + root.editingProviderObj.displayName
                          }
                        }
                      }
                    }

                    Rectangle {
                      width: parent.width
                      height: 1
                      color: Style.normalBorderColor
                    }

                    // Endpoint Configuration
                    Column {
                      width: parent.width
                      spacing: Style.space(6)

                      Text {
                        text: "API Endpoint URL:"
                        font.family: Style.font.family
                        font.pixelSize: Style.font.bodySmall
                        font.weight: Font.DemiBold
                        color: Color.muted
                      }

                      TextField {
                        id: endpointInput
                        width: parent.width
                        text: (root.appConfig.endpoints && root.appConfig.endpoints[root.editingProviderId])
                          ? root.appConfig.endpoints[root.editingProviderId]
                          : root.editingProviderObj.defaultEndpoint
                        onEditingFinished: root.setEndpoint(text.trim())
                      }
                    }

                    // Dynamic Model Selector & Online Fetcher
                    ModelPicker {
                      id: modelPicker
                      width: parent.width
                      providerId: root.editingProviderId
                      endpoint: (root.appConfig.endpoints && root.appConfig.endpoints[root.editingProviderId])
                        ? root.appConfig.endpoints[root.editingProviderId]
                        : root.editingProviderObj.defaultEndpoint
                      apiKey: root.appKeys[root.editingProviderId] || ""
                      selectedModel: (root.editingProviderId === root.activeProviderId)
                        ? root.activeModelName
                        : ((root.appConfig.providerModels && root.appConfig.providerModels[root.editingProviderId])
                            ? root.appConfig.providerModels[root.editingProviderId]
                            : (root.editingProviderObj.defaultModels[0] || ""))
                      defaultModels: root.editingProviderObj.defaultModels || []
                      onModelSelected: function(modelName) {
                        root.selectModel(modelName)
                      }
                    }

                    Rectangle {
                      width: parent.width
                      height: 1
                      color: Style.normalBorderColor
                    }

                    // Secure API Key
                    Column {
                      width: parent.width
                      spacing: Style.space(6)

                      Row {
                        spacing: Style.space(6)
                        Text {
                          text: "API Key (" + root.editingProviderObj.displayName + "):"
                          font.family: Style.font.family
                          font.pixelSize: Style.font.bodySmall
                          font.weight: Font.DemiBold
                          color: Color.muted
                        }

                        Text {
                          text: !root.editingProviderObj.requiresKey
                            ? "• (Local: No key required)"
                            : (root.appKeys[root.editingProviderId] ? "✔ Key Saved" : "⚠ Key Required")
                          font.family: Style.font.family
                          font.pixelSize: Style.font.bodySmall
                          color: !root.editingProviderObj.requiresKey
                            ? "#a6e3a1"
                            : (root.appKeys[root.editingProviderId] ? "#a6e3a1" : Color.urgent)
                        }
                      }

                      Row {
                        width: parent.width
                        spacing: Style.space(6)

                        TextField {
                          id: apiKeyField
                          width: parent.width - Style.space(140)
                          placeholderText: root.editingProviderObj.requiresKey
                            ? (root.appKeys[root.editingProviderId] ? Config.maskApiKey(root.appKeys[root.editingProviderId]) : root.editingProviderObj.keyPlaceholder)
                            : "No API key needed for local service"
                          password: !root.showKeyPlaintext
                          text: root.editingKeyInput
                          onTextChanged: root.editingKeyInput = text
                        }

                        Button {
                          text: root.showKeyPlaintext ? "Hide" : "Show"
                          onClicked: root.showKeyPlaintext = !root.showKeyPlaintext
                        }

                        Button {
                          text: "Save Key"
                          active: true
                          enabled: root.editingKeyInput.trim() !== ""
                          onClicked: {
                            root.saveApiKey(root.editingProviderId, root.editingKeyInput.trim())
                          }
                        }
                      }

                      Text {
                        text: "Keys are stored in ~/.local/state/omarchy/plugins/harsh.llm/keys.json with 0600 permissions."
                        font.family: Style.font.family
                        font.pixelSize: Style.font.caption
                        color: Color.muted
                      }
                    }
                  }

                  // =========================================================
                  // SUB-TAB 2: INFERENCE & GENERATION
                  // =========================================================
                  Column {
                    width: parent.width
                    visible: root.settingsSubTab === "generation"
                    spacing: Style.space(14)

                    // Temperature Section
                    Column {
                      width: parent.width
                      spacing: Style.space(6)

                      Row {
                        width: parent.width
                        spacing: Style.space(8)

                        Text {
                          anchors.verticalCenter: parent.verticalCenter
                          text: "Sampling Temperature:"
                          font.family: Style.font.family
                          font.pixelSize: Style.font.bodySmall
                          font.weight: Font.DemiBold
                          color: Color.muted
                        }

                        Text {
                          anchors.verticalCenter: parent.verticalCenter
                          text: (root.appConfig.temperature !== undefined ? root.appConfig.temperature.toFixed(2) : "0.70")
                          font.family: Style.font.family
                          font.pixelSize: Style.font.bodySmall
                          font.weight: Font.Bold
                          color: Color.accent
                        }
                      }

                      Flow {
                        width: parent.width
                        spacing: Style.space(6)

                        Button {
                          text: "0.2 (Precise / Code)"
                          active: Math.abs((root.appConfig.temperature || 0.7) - 0.2) < 0.05
                          onClicked: root.updateConfigKey("temperature", 0.2)
                        }
                        Button {
                          text: "0.7 (Balanced / Default)"
                          active: Math.abs((root.appConfig.temperature || 0.7) - 0.7) < 0.05
                          onClicked: root.updateConfigKey("temperature", 0.7)
                        }
                        Button {
                          text: "1.0 (Creative)"
                          active: Math.abs((root.appConfig.temperature || 0.7) - 1.0) < 0.05
                          onClicked: root.updateConfigKey("temperature", 1.0)
                        }
                      }
                    }

                    Rectangle {
                      width: parent.width
                      height: 1
                      color: Style.normalBorderColor
                    }

                    // Max Tokens Section
                    Column {
                      width: parent.width
                      spacing: Style.space(6)

                      Row {
                        width: parent.width
                        spacing: Style.space(8)

                        Text {
                          anchors.verticalCenter: parent.verticalCenter
                          text: "Max Tokens per Response:"
                          font.family: Style.font.family
                          font.pixelSize: Style.font.bodySmall
                          font.weight: Font.DemiBold
                          color: Color.muted
                        }

                        Text {
                          anchors.verticalCenter: parent.verticalCenter
                          text: String(root.appConfig.maxTokens || 4096)
                          font.family: Style.font.family
                          font.pixelSize: Style.font.bodySmall
                          font.weight: Font.Bold
                          color: Color.accent
                        }
                      }

                      Flow {
                        width: parent.width
                        spacing: Style.space(6)

                        Button {
                          text: "1024"
                          active: root.appConfig.maxTokens === 1024
                          onClicked: root.updateConfigKey("maxTokens", 1024)
                        }
                        Button {
                          text: "2048"
                          active: root.appConfig.maxTokens === 2048
                          onClicked: root.updateConfigKey("maxTokens", 2048)
                        }
                        Button {
                          text: "4096 (Default)"
                          active: root.appConfig.maxTokens === 4096 || !root.appConfig.maxTokens
                          onClicked: root.updateConfigKey("maxTokens", 4096)
                        }
                        Button {
                          text: "8192"
                          active: root.appConfig.maxTokens === 8192
                          onClicked: root.updateConfigKey("maxTokens", 8192)
                        }
                        Button {
                          text: "16384"
                          active: root.appConfig.maxTokens === 16384
                          onClicked: root.updateConfigKey("maxTokens", 16384)
                        }
                      }
                    }

                    Rectangle {
                      width: parent.width
                      height: 1
                      color: Style.normalBorderColor
                    }

                    // Reasoning / Thoughts Toggle
                    Toggle {
                      width: parent.width
                      label: "Show Model Reasoning / Thinking"
                      description: "Renders collapsible thoughts block from reasoning models (DeepSeek-R1, Claude 3.7)"
                      checked: root.appConfig.showThoughts !== false
                      onClicked: root.updateConfigKey("showThoughts", root.appConfig.showThoughts === false ? true : false)
                    }
                  }

                  // =========================================================
                  // SUB-TAB 3: TOOLS & SECURITY
                  // =========================================================
                  Column {
                    width: parent.width
                    visible: root.settingsSubTab === "tools"
                    spacing: Style.space(12)

                    Toggle {
                      width: parent.width
                      label: "Enable Tool Calling (Agent Capabilities)"
                      description: "Allow models to run commands, inspect local files, and search the web"
                      checked: root.appConfig.toolsMasterEnabled !== false
                      onClicked: root.updateConfigKey("toolsMasterEnabled", root.appConfig.toolsMasterEnabled === false ? true : false)
                    }

                    Toggle {
                      width: parent.width
                      label: "Auto-Approve Shell Commands"
                      description: "Run bash commands immediately without user confirmation card (CAUTION: Use only with trusted models)"
                      checked: root.appConfig.autoApproveTerminal === true
                      onClicked: root.updateConfigKey("autoApproveTerminal", !root.appConfig.autoApproveTerminal)
                    }

                    Rectangle {
                      width: parent.width
                      height: 1
                      color: Style.normalBorderColor
                    }

                    Text {
                      text: "Allowed System Tools:"
                      font.family: Style.font.family
                      font.pixelSize: Style.font.bodySmall
                      font.weight: Font.DemiBold
                      color: Color.muted
                    }

                    Column {
                      width: parent.width
                      spacing: Style.space(6)

                      Toggle {
                        width: parent.width
                        label: "Terminal Command Execution (`run_command`)"
                        description: "Execute bash commands in background and return output"
                        checked: (!root.appConfig.enabledTools || root.appConfig.enabledTools.run_command !== false)
                        onClicked: root.updateNestedConfig("enabledTools", "run_command", root.appConfig.enabledTools && root.appConfig.enabledTools.run_command === false ? true : false)
                      }

                      Toggle {
                        width: parent.width
                        label: "Read Local Files (`read_file`)"
                        description: "Inspect file contents on system"
                        checked: (!root.appConfig.enabledTools || root.appConfig.enabledTools.read_file !== false)
                        onClicked: root.updateNestedConfig("enabledTools", "read_file", root.appConfig.enabledTools && root.appConfig.enabledTools.read_file === false ? true : false)
                      }

                      Toggle {
                        width: parent.width
                        label: "Write & Create Files (`write_file`)"
                        description: "Create or overwrite local files atomically"
                        checked: (!root.appConfig.enabledTools || root.appConfig.enabledTools.write_file !== false)
                        onClicked: root.updateNestedConfig("enabledTools", "write_file", root.appConfig.enabledTools && root.appConfig.enabledTools.write_file === false ? true : false)
                      }

                      Toggle {
                        width: parent.width
                        label: "Directory Listing (`list_dir`)"
                        description: "List directory contents and directory structures"
                        checked: (!root.appConfig.enabledTools || root.appConfig.enabledTools.list_directory !== false)
                        onClicked: root.updateNestedConfig("enabledTools", "list_directory", root.appConfig.enabledTools && root.appConfig.enabledTools.list_directory === false ? true : false)
                      }

                      Toggle {
                        width: parent.width
                        label: "Web Search Tool (`web_search`)"
                        description: "Real-time web queries via DuckDuckGo"
                        checked: (!root.appConfig.enabledTools || root.appConfig.enabledTools.web_search !== false)
                        onClicked: root.updateNestedConfig("enabledTools", "web_search", root.appConfig.enabledTools && root.appConfig.enabledTools.web_search === false ? true : false)
                      }

                      Toggle {
                        width: parent.width
                        label: "Persistent Memory (`edit_memory`)"
                        description: "Store and recall personal preferences and habits across sessions"
                        checked: (!root.appConfig.enabledTools || root.appConfig.enabledTools.save_memory !== false)
                        onClicked: root.updateNestedConfig("enabledTools", "save_memory", root.appConfig.enabledTools && root.appConfig.enabledTools.save_memory === false ? true : false)
                      }
                    }

                    Rectangle {
                      width: parent.width
                      height: 1
                      color: Style.normalBorderColor
                    }

                    // Workspace Directory
                    Column {
                      width: parent.width
                      spacing: Style.space(6)

                      Text {
                        text: "Default Working Directory:"
                        font.family: Style.font.family
                        font.pixelSize: Style.font.bodySmall
                        font.weight: Font.DemiBold
                        color: Color.muted
                      }

                      TextField {
                        width: parent.width
                        text: root.appConfig.workspaceDir || "~"
                        onEditingFinished: root.updateConfigKey("workspaceDir", text.trim() || "~")
                      }
                    }
                  }

                  // =========================================================
                  // SUB-TAB 4: WEB SEARCH
                  // =========================================================
                  Column {
                    width: parent.width
                    visible: root.settingsSubTab === "web"
                    spacing: Style.space(12)

                    Toggle {
                      width: parent.width
                      label: "Enable Web Search Grounding"
                      description: "Fetch live web results to answer queries about current events, documentation, or releases"
                      checked: root.appConfig.enableWebSearch !== false
                      onClicked: root.updateConfigKey("enableWebSearch", root.appConfig.enableWebSearch === false ? true : false)
                    }

                    Rectangle {
                      width: parent.width
                      height: 1
                      color: Style.normalBorderColor
                    }

                    Column {
                      width: parent.width
                      spacing: Style.space(6)

                      Text {
                        text: "Maximum Results Count:"
                        font.family: Style.font.family
                        font.pixelSize: Style.font.bodySmall
                        font.weight: Font.DemiBold
                        color: Color.muted
                      }

                      Flow {
                        width: parent.width
                        spacing: Style.space(6)

                        Button {
                          text: "3 Results"
                          active: root.appConfig.maxSearchResults === 3
                          onClicked: root.updateConfigKey("maxSearchResults", 3)
                        }
                        Button {
                          text: "5 Results (Recommended)"
                          active: root.appConfig.maxSearchResults === 5 || !root.appConfig.maxSearchResults
                          onClicked: root.updateConfigKey("maxSearchResults", 5)
                        }
                        Button {
                          text: "8 Results"
                          active: root.appConfig.maxSearchResults === 8
                          onClicked: root.updateConfigKey("maxSearchResults", 8)
                        }
                        Button {
                          text: "10 Results"
                          active: root.appConfig.maxSearchResults === 10
                          onClicked: root.updateConfigKey("maxSearchResults", 10)
                        }
                      }
                    }

                    Rectangle {
                      width: parent.width
                      height: 1
                      color: Style.normalBorderColor
                    }

                    Column {
                      width: parent.width
                      spacing: Style.space(6)

                      Text {
                        text: "Search Engine Backend:"
                        font.family: Style.font.family
                        font.pixelSize: Style.font.bodySmall
                        font.weight: Font.DemiBold
                        color: Color.muted
                      }

                      Row {
                        spacing: Style.space(6)

                        Button {
                          text: "DuckDuckGo (Instant / Free)"
                          active: true
                        }
                      }
                    }
                  }

                  // =========================================================
                  // SUB-TAB 5: CONTEXT COMPACTION
                  // =========================================================
                  Column {
                    width: parent.width
                    visible: root.settingsSubTab === "compaction"
                    spacing: Style.space(12)

                    Toggle {
                      width: parent.width
                      label: "Enable Context Compaction"
                      description: "Compresses earlier turns into a dense background summary with message IDs, dramatically saving token usage in long chats"
                      checked: root.appConfig.compactionEnabled !== false
                      onClicked: root.updateConfigKey("compactionEnabled", root.appConfig.compactionEnabled === false ? true : false)
                    }

                    Rectangle {
                      width: parent.width
                      height: 1
                      color: Style.normalBorderColor
                    }

                    // Trigger Mode
                    Column {
                      width: parent.width
                      spacing: Style.space(6)

                      Text {
                        text: "Trigger Strategy:"
                        font.family: Style.font.family
                        font.pixelSize: Style.font.bodySmall
                        font.weight: Font.DemiBold
                        color: Color.muted
                      }

                      Flow {
                        width: parent.width
                        spacing: Style.space(6)

                        Button {
                          text: "By Character Count"
                          active: (root.appConfig.compactionTriggerMode || "chars") === "chars"
                          onClicked: root.updateConfigKey("compactionTriggerMode", "chars")
                        }
                        Button {
                          text: "By Turn Count"
                          active: root.appConfig.compactionTriggerMode === "turns"
                          onClicked: root.updateConfigKey("compactionTriggerMode", "turns")
                        }
                        Button {
                          text: "Whichever Comes First (Both)"
                          active: root.appConfig.compactionTriggerMode === "both"
                          onClicked: root.updateConfigKey("compactionTriggerMode", "both")
                        }
                      }
                    }

                    Rectangle {
                      width: parent.width
                      height: 1
                      color: Style.normalBorderColor
                    }

                    // Character Threshold
                    Column {
                      width: parent.width
                      spacing: Style.space(6)

                      Row {
                        width: parent.width
                        spacing: Style.space(8)

                        Text {
                          anchors.verticalCenter: parent.verticalCenter
                          text: "Character Threshold:"
                          font.family: Style.font.family
                          font.pixelSize: Style.font.bodySmall
                          font.weight: Font.DemiBold
                          color: Color.muted
                        }

                        Text {
                          anchors.verticalCenter: parent.verticalCenter
                          text: String(root.appConfig.compactionThresholdChars || 20000) + " chars (~" + Math.round((root.appConfig.compactionThresholdChars || 20000) / 4) + " tokens)"
                          font.family: Style.font.family
                          font.pixelSize: Style.font.bodySmall
                          font.weight: Font.Bold
                          color: Color.accent
                        }
                      }

                      Flow {
                        width: parent.width
                        spacing: Style.space(6)

                        Button {
                          text: "5,000 chars"
                          active: root.appConfig.compactionThresholdChars === 5000
                          onClicked: root.updateConfigKey("compactionThresholdChars", 5000)
                        }
                        Button {
                          text: "10,000 chars"
                          active: root.appConfig.compactionThresholdChars === 10000
                          onClicked: root.updateConfigKey("compactionThresholdChars", 10000)
                        }
                        Button {
                          text: "20,000 chars (Default)"
                          active: root.appConfig.compactionThresholdChars === 20000 || !root.appConfig.compactionThresholdChars
                          onClicked: root.updateConfigKey("compactionThresholdChars", 20000)
                        }
                        Button {
                          text: "40,000 chars"
                          active: root.appConfig.compactionThresholdChars === 40000
                          onClicked: root.updateConfigKey("compactionThresholdChars", 40000)
                        }
                      }
                    }

                    Rectangle {
                      width: parent.width
                      height: 1
                      color: Style.normalBorderColor
                    }

                    // Keep Recent Turns
                    Column {
                      width: parent.width
                      spacing: Style.space(6)

                      Row {
                        width: parent.width
                        spacing: Style.space(8)

                        Text {
                          anchors.verticalCenter: parent.verticalCenter
                          text: "Keep Recent Turns Verbatim:"
                          font.family: Style.font.family
                          font.pixelSize: Style.font.bodySmall
                          font.weight: Font.DemiBold
                          color: Color.muted
                        }

                        Text {
                          anchors.verticalCenter: parent.verticalCenter
                          text: String(root.appConfig.compactionKeepRecentTurns || 4) + " turns uncompacted"
                          font.family: Style.font.family
                          font.pixelSize: Style.font.bodySmall
                          font.weight: Font.Bold
                          color: Color.accent
                        }
                      }

                      Flow {
                        width: parent.width
                        spacing: Style.space(6)

                        Button {
                          text: "2 Turns"
                          active: root.appConfig.compactionKeepRecentTurns === 2
                          onClicked: root.updateConfigKey("compactionKeepRecentTurns", 2)
                        }
                        Button {
                          text: "4 Turns (Recommended)"
                          active: root.appConfig.compactionKeepRecentTurns === 4 || !root.appConfig.compactionKeepRecentTurns
                          onClicked: root.updateConfigKey("compactionKeepRecentTurns", 4)
                        }
                        Button {
                          text: "6 Turns"
                          active: root.appConfig.compactionKeepRecentTurns === 6
                          onClicked: root.updateConfigKey("compactionKeepRecentTurns", 6)
                        }
                      }
                    }

                    Rectangle {
                      width: parent.width
                      height: 1
                      color: Style.normalBorderColor
                    }

                    // Compaction Instructions Template
                    Column {
                      width: parent.width
                      spacing: Style.space(6)

                      Row {
                        width: parent.width
                        spacing: Style.space(8)

                        Text {
                          anchors.verticalCenter: parent.verticalCenter
                          text: "Compaction Instructions Template:"
                          font.family: Style.font.family
                          font.pixelSize: Style.font.bodySmall
                          font.weight: Font.DemiBold
                          color: Color.muted
                        }

                        Item {
                          width: 1
                          height: 1
                          Layout.fillWidth: true
                        }

                        Button {
                          anchors.verticalCenter: parent.verticalCenter
                          text: "↺ Reset Default"
                          onClicked: {
                            compactionInstructionsInput.text = Config.DEFAULT_CONFIG.compactionInstructions
                            root.updateConfigKey("compactionInstructions", Config.DEFAULT_CONFIG.compactionInstructions)
                          }
                        }

                        Button {
                          anchors.verticalCenter: parent.verticalCenter
                          text: "Save Instructions"
                          active: true
                          onClicked: {
                            root.updateConfigKey("compactionInstructions", compactionInstructionsInput.text)
                            root.saveFeedbackMsg = "Saved Compaction Instructions"
                          }
                        }
                      }

                      Rectangle {
                        width: parent.width
                        height: Style.space(110)
                        radius: Style.cornerRadius > 0 ? Style.cornerRadius / 2 : Style.space(6)
                        color: Style.hoverFill
                        border.width: 1
                        border.color: Style.normalBorderColor

                        QQC.ScrollView {
                          anchors.fill: parent
                          anchors.margins: Style.space(6)
                          clip: true

                          QQC.TextArea {
                            id: compactionInstructionsInput
                            width: parent.width
                            text: root.appConfig.compactionInstructions || Config.DEFAULT_CONFIG.compactionInstructions
                            font.family: Style.font.family
                            font.pixelSize: Style.font.caption
                            color: Color.popups.text
                            wrapMode: TextEdit.Wrap
                            background: null
                          }
                        }
                      }
                    }

                    Rectangle {
                      width: parent.width
                      height: 1
                      color: Style.normalBorderColor
                    }

                    // Diagnostics & Manual Action
                    Column {
                      width: parent.width
                      spacing: Style.space(8)

                      Text {
                        text: "Manual Actions & Diagnostics:"
                        font.family: Style.font.family
                        font.pixelSize: Style.font.bodySmall
                        font.weight: Font.DemiBold
                        color: Color.muted
                      }

                      Row {
                        width: parent.width
                        spacing: Style.space(8)

                        Button {
                          text: "󰈚 Compact Active Chat History"
                          onClicked: {
                            if (chatView) {
                              chatView.triggerCompaction(null, function(err, res) {
                                if (err) root.saveFeedbackMsg = "Compaction error: " + err
                                else root.saveFeedbackMsg = "Chat compacted successfully!"
                              })
                            }
                          }
                        }

                        Button {
                          text: root.isTestingCompaction ? "Testing..." : "Test Compaction Prompt"
                          enabled: !root.isTestingCompaction
                          onClicked: {
                            root.isTestingCompaction = true
                            root.compactionTestStatus = "Connecting to " + root.activeModelName + "..."
                            var sample = (
                              "[1] Role: user\nContent: Please review the Arch Linux Hyprland config in ~/.config/hypr/hyprland.conf\n\n" +
                              "[2] Role: assistant\nContent: The config looks good with waybar enabled and dwindle layout active.\n\n" +
                              "[3] Role: user\nContent: Can you add a keybinding for launching the LLM assistant?\n\n" +
                              "[4] Role: assistant\nContent: Added bind = $mainMod, L, exec, quickshell ipc call harsh.llm toggle"
                            )
                            var pOpts = {
                              endpoint: root.activeEndpoint,
                              model: root.activeModelName,
                              apiKey: root.currentApiKey
                            }
                            ContextCompactor.compactHistory(
                              root.activeProviderId,
                              pOpts,
                              sample,
                              "",
                              function(err, res) {
                                root.isTestingCompaction = false
                                if (err) {
                                  root.compactionTestStatus = "Failed: " + err
                                  root.compactionTestResponse = ""
                                } else {
                                  root.compactionTestStatus = "Compaction succeeded!"
                                  root.compactionTestResponse = res
                                }
                              }
                            )
                          }
                        }
                      }

                      Text {
                        visible: root.compactionTestStatus !== ""
                        text: root.compactionTestStatus
                        font.family: Style.font.family
                        font.pixelSize: Style.font.caption
                        color: Color.accent
                      }

                      Rectangle {
                        visible: root.compactionTestResponse !== ""
                        width: parent.width
                        height: Style.space(90)
                        radius: Style.cornerRadius > 0 ? Style.cornerRadius / 2 : Style.space(4)
                        color: Style.normalFill
                        border.width: 1
                        border.color: Style.normalBorderColor

                        QQC.ScrollView {
                          anchors.fill: parent
                          anchors.margins: Style.space(6)
                          clip: true

                          Text {
                            width: parent.width
                            text: root.compactionTestResponse
                            font.family: Style.font.family
                            font.pixelSize: Style.font.caption
                            color: Color.popups.text
                            wrapMode: Text.Wrap
                          }
                        }
                      }
                    }
                  }

                  // =========================================================
                  // SUB-TAB: VOICE & SPEECH-TO-TEXT (STT)
                  // =========================================================
                  Column {
                    width: parent.width
                    visible: root.settingsSubTab === "voice"
                    spacing: Style.space(12)

                    // Card 1: Diagnostic / Status Banner
                    Rectangle {
                      width: parent.width
                      implicitHeight: voiceDiagCol.implicitHeight + Style.space(16)
                      radius: Style.cornerRadius > 0 ? Style.cornerRadius / 2 : Style.space(6)
                      color: Util.alpha(Color.accent, 0.1)
                      border.width: 1
                      border.color: Util.alpha(Color.accent, 0.3)

                      Column {
                        id: voiceDiagCol
                        anchors.left: parent.left
                        anchors.right: parent.right
                        anchors.verticalCenter: parent.verticalCenter
                        anchors.margins: Style.space(10)
                        spacing: Style.space(6)

                        Row {
                          spacing: Style.space(8)
                          Text {
                            text: "󰍬"
                            font.family: Style.font.family
                            font.pixelSize: Style.font.title
                            color: Color.accent
                            anchors.verticalCenter: parent.verticalCenter
                          }
                          Text {
                            text: "How Voice Transcription Works in OmarchyLLM"
                            font.family: Style.font.family
                            font.pixelSize: Style.font.body
                            font.weight: Font.Bold
                            color: Color.popups.text
                            anchors.verticalCenter: parent.verticalCenter
                          }
                        }

                        Text {
                          width: parent.width
                          text: "• Audio Capture: PipeWire (`pw-record`) captures microphone input cleanly into `/tmp/omarchy_llm_mic.wav`.\n" +
                                "• Local Whisper (whisper-cpp): 100% private and offline on your machine with zero API keys or cloud tokens.\n" +
                                "• Free Cloud Solution: Groq provides free Whisper API (`whisper-large-v3-turbo`) with generous rate limits."
                          font.family: Style.font.family
                          font.pixelSize: Style.font.caption
                          color: Color.popups.text
                          wrapMode: Text.Wrap
                        }
                      }
                    }

                    // Card 1b: STT Engine Mode Selector
                    Rectangle {
                      width: parent.width
                      implicitHeight: sttEngineCol.implicitHeight + Style.space(16)
                      radius: Style.cornerRadius > 0 ? Style.cornerRadius / 2 : Style.space(6)
                      color: Style.normalFill
                      border.width: 1
                      border.color: Style.normalBorderColor

                      Column {
                        id: sttEngineCol
                        anchors.left: parent.left
                        anchors.right: parent.right
                        anchors.verticalCenter: parent.verticalCenter
                        anchors.margins: Style.space(10)
                        spacing: Style.space(8)

                        Text {
                          text: "Active Speech-to-Text Engine"
                          font.family: Style.font.family
                          font.pixelSize: Style.font.bodySmall
                          font.weight: Font.DemiBold
                          color: Color.popups.text
                        }

                        Row {
                          spacing: Style.space(8)

                          Button {
                            text: "󰒋 Offline Whisper (Local)"
                            active: (!root.appConfig || !root.appConfig.sttBackend || root.appConfig.sttBackend === "whisper" || root.appConfig.sttBackend === "local")
                            onClicked: root.updateConfigKey("sttBackend", "whisper")
                          }

                          Button {
                            text: "⚡ Groq Whisper (Cloud)"
                            active: (root.appConfig && root.appConfig.sttBackend === "groq")
                            onClicked: root.updateConfigKey("sttBackend", "groq")
                          }

                          Button {
                            text: "󰚩 Auto"
                            active: (root.appConfig && root.appConfig.sttBackend === "auto")
                            onClicked: root.updateConfigKey("sttBackend", "auto")
                          }
                        }
                      }
                    }

                    // Card 2: Groq Free Whisper Key
                    Rectangle {
                      width: parent.width
                      implicitHeight: groqKeyCol.implicitHeight + Style.space(16)
                      radius: Style.cornerRadius > 0 ? Style.cornerRadius / 2 : Style.space(6)
                      color: Style.normalFill
                      border.width: 1
                      border.color: Style.normalBorderColor

                      Column {
                        id: groqKeyCol
                        anchors.left: parent.left
                        anchors.right: parent.right
                        anchors.verticalCenter: parent.verticalCenter
                        anchors.margins: Style.space(10)
                        spacing: Style.space(8)

                        Row {
                          width: parent.width
                          spacing: Style.space(8)

                          Text {
                            text: "⚡ Groq Free Whisper Key (Recommended for Free Voice)"
                            font.family: Style.font.family
                            font.pixelSize: Style.font.bodySmall
                            font.weight: Font.DemiBold
                            color: Color.popups.text
                            anchors.verticalCenter: parent.verticalCenter
                          }

                          Text {
                            visible: !!root.appKeys.groq
                            text: "✓ Configured (" + Config.maskApiKey(root.appKeys.groq || "") + ")"
                            font.family: Style.font.family
                            font.pixelSize: Style.font.caption
                            color: Color.accent
                            anchors.verticalCenter: parent.verticalCenter
                          }
                        }

                        Text {
                          width: parent.width
                          text: "Get a free API key at console.groq.com. When configured, speech recordings will transcribe instantly via Groq Whisper for free, even if you chat with OpenRouter."
                          font.family: Style.font.family
                          font.pixelSize: Style.font.caption
                          color: Color.muted
                          wrapMode: Text.Wrap
                        }

                        Row {
                          width: parent.width
                          spacing: Style.space(8)

                          Rectangle {
                            width: parent.width - Style.space(90)
                            height: Style.space(32)
                            radius: Style.cornerRadius > 0 ? Style.cornerRadius / 2 : Style.space(4)
                            color: Style.normalFill
                            border.width: 1
                            border.color: groqKeyField.activeFocus ? Color.accent : Style.normalBorderColor

                            QQC.TextField {
                              id: groqKeyField
                              anchors.fill: parent
                              anchors.margins: Style.space(4)
                              placeholderText: "Paste Groq API Key (gsk_...)"
                              font.family: Style.font.family
                              font.pixelSize: Style.font.bodySmall
                              color: Color.popups.text
                              echoMode: TextInput.Password
                              background: null
                            }
                          }

                          Button {
                            text: "Save Key"
                            anchors.verticalCenter: parent.verticalCenter
                            onClicked: {
                              if (groqKeyField.text.trim() !== "") {
                                root.saveApiKey("groq", groqKeyField.text.trim())
                                groqKeyField.text = ""
                              }
                            }
                          }
                        }
                      }
                    }

                    // Card 3: OpenAI Key (Alternative)
                    Rectangle {
                      width: parent.width
                      implicitHeight: openaiVoiceCol.implicitHeight + Style.space(16)
                      radius: Style.cornerRadius > 0 ? Style.cornerRadius / 2 : Style.space(6)
                      color: Style.normalFill
                      border.width: 1
                      border.color: Style.normalBorderColor

                      Column {
                        id: openaiVoiceCol
                        anchors.left: parent.left
                        anchors.right: parent.right
                        anchors.verticalCenter: parent.verticalCenter
                        anchors.margins: Style.space(10)
                        spacing: Style.space(8)

                        Row {
                          width: parent.width
                          spacing: Style.space(8)

                          Text {
                            text: "󰚩 OpenAI Whisper Key (Alternative)"
                            font.family: Style.font.family
                            font.pixelSize: Style.font.bodySmall
                            font.weight: Font.DemiBold
                            color: Color.popups.text
                            anchors.verticalCenter: parent.verticalCenter
                          }

                          Text {
                            visible: !!root.appKeys.openai
                            text: "✓ Configured (" + Config.maskApiKey(root.appKeys.openai || "") + ")"
                            font.family: Style.font.family
                            font.pixelSize: Style.font.caption
                            color: Color.accent
                            anchors.verticalCenter: parent.verticalCenter
                          }
                        }

                        Text {
                          width: parent.width
                          text: "Uses official OpenAI Whisper endpoint (/v1/audio/transcriptions) with whisper-1 model."
                          font.family: Style.font.family
                          font.pixelSize: Style.font.caption
                          color: Color.muted
                          wrapMode: Text.Wrap
                        }

                        Row {
                          width: parent.width
                          spacing: Style.space(8)

                          Rectangle {
                            width: parent.width - Style.space(90)
                            height: Style.space(32)
                            radius: Style.cornerRadius > 0 ? Style.cornerRadius / 2 : Style.space(4)
                            color: Style.normalFill
                            border.width: 1
                            border.color: openaiVoiceField.activeFocus ? Color.accent : Style.normalBorderColor

                            QQC.TextField {
                              id: openaiVoiceField
                              anchors.fill: parent
                              anchors.margins: Style.space(4)
                              placeholderText: "Paste OpenAI Key (sk-proj-...)"
                              font.family: Style.font.family
                              font.pixelSize: Style.font.bodySmall
                              color: Color.popups.text
                              echoMode: TextInput.Password
                              background: null
                            }
                          }

                          Button {
                            text: "Save Key"
                            anchors.verticalCenter: parent.verticalCenter
                            onClicked: {
                              if (openaiVoiceField.text.trim() !== "") {
                                root.saveApiKey("openai", openaiVoiceField.text.trim())
                                openaiVoiceField.text = ""
                              }
                            }
                          }
                        }
                      }
                    }

                    // Card 4: Local Whisper (Offline)
                    Rectangle {
                      width: parent.width
                      implicitHeight: localWhisperCol.implicitHeight + Style.space(16)
                      radius: Style.cornerRadius > 0 ? Style.cornerRadius / 2 : Style.space(6)
                      color: (root.appConfig && (!root.appConfig.sttBackend || root.appConfig.sttBackend === "whisper" || root.appConfig.sttBackend === "local"))
                             ? Util.alpha(Color.accent, 0.08)
                             : Style.normalFill
                      border.width: 1
                      border.color: (root.appConfig && (!root.appConfig.sttBackend || root.appConfig.sttBackend === "whisper" || root.appConfig.sttBackend === "local"))
                                    ? Color.accent
                                    : Style.normalBorderColor

                      Column {
                        id: localWhisperCol
                        anchors.left: parent.left
                        anchors.right: parent.right
                        anchors.verticalCenter: parent.verticalCenter
                        anchors.margins: Style.space(10)
                        spacing: Style.space(8)

                        Row {
                          width: parent.width
                          spacing: Style.space(8)

                          Text {
                            text: "󰒋"
                            font.family: Style.font.family
                            font.pixelSize: Style.font.title
                            color: Color.accent
                            anchors.verticalCenter: parent.verticalCenter
                          }

                          Column {
                            spacing: Style.space(2)
                            anchors.verticalCenter: parent.verticalCenter

                            Text {
                              text: "Local Offline Whisper (Private / Zero Cloud)"
                              font.family: Style.font.family
                              font.pixelSize: Style.font.bodySmall
                              font.weight: Font.DemiBold
                              color: Color.popups.text
                            }

                            Text {
                              text: (root.appConfig && (!root.appConfig.sttBackend || root.appConfig.sttBackend === "whisper" || root.appConfig.sttBackend === "local"))
                                    ? "Active STT Engine: Transcription runs 100% locally on your machine"
                                    : "Runs completely offline using your CPU with whisper-cpp"
                              font.family: Style.font.family
                              font.pixelSize: Style.font.caption
                              color: Color.muted
                            }
                          }
                        }

                        // Diagnostics & Status
                        Column {
                          width: parent.width
                          spacing: Style.space(4)

                          Text {
                            text: root.whisperDiagnostics && root.whisperDiagnostics.whisper_cpp_available
                                  ? "✔ Binary: " + root.whisperDiagnostics.whisper_cpp_binary
                                  : "✖ Binary: whisper-cpp not found (install with: sudo pacman -S whisper-cpp)"
                            font.family: Style.font.family
                            font.pixelSize: Style.font.caption
                            color: root.whisperDiagnostics && root.whisperDiagnostics.whisper_cpp_available ? "#4ade80" : "#f87171"
                          }

                          Text {
                            text: root.whisperDiagnostics && root.whisperDiagnostics.whisper_cpp_model
                                  ? "✔ Model: " + root.whisperDiagnostics.whisper_cpp_model_name + " (" + root.whisperDiagnostics.whisper_cpp_model_size_mb + " MB) in ~/.local/share/whisper-cpp/"
                                  : "✖ Model: No model found. Click 'Download Base Model' below."
                            font.family: Style.font.family
                            font.pixelSize: Style.font.caption
                            color: root.whisperDiagnostics && root.whisperDiagnostics.whisper_cpp_model ? "#4ade80" : "#f87171"
                          }

                          Text {
                            visible: root.whisperTestResult !== ""
                            text: root.whisperTestResult
                            font.family: Style.font.family
                            font.pixelSize: Style.font.caption
                            font.weight: Font.DemiBold
                            color: Color.popups.text
                          }
                        }

                        // Action Controls
                        Row {
                          spacing: Style.space(8)

                          Button {
                            text: (root.appConfig && (!root.appConfig.sttBackend || root.appConfig.sttBackend === "whisper" || root.appConfig.sttBackend === "local"))
                                  ? "✔ Active Engine"
                                  : "Set as Active"
                            active: (root.appConfig && (!root.appConfig.sttBackend || root.appConfig.sttBackend === "whisper" || root.appConfig.sttBackend === "local"))
                            onClicked: {
                              root.updateConfigKey("sttBackend", "whisper")
                            }
                          }

                          Button {
                            text: root.isTestingWhisper ? "Testing..." : "Test Local Whisper"
                            onClicked: {
                              root.runWhisperTest()
                            }
                          }

                          Button {
                            visible: !(root.whisperDiagnostics && root.whisperDiagnostics.whisper_cpp_model)
                            text: root.isDownloadingWhisperModel ? "Downloading..." : "Download Base Model (~142MB)"
                            onClicked: {
                              root.triggerDownloadWhisperModel()
                            }
                          }
                        }
                      }
                    }
                  }

                  // =========================================================
                  // SUB-TAB 6: SYSTEM PROMPT, TELEMETRY & MEMORY
                  // =========================================================
                  Column {
                    width: parent.width
                    visible: root.settingsSubTab === "system"
                    spacing: Style.space(12)

                    // System Prompt Editor
                    Column {
                      width: parent.width
                      spacing: Style.space(6)

                      Row {
                        width: parent.width
                        spacing: Style.space(8)

                        Text {
                          anchors.verticalCenter: parent.verticalCenter
                          text: "System Prompt Template:"
                          font.family: Style.font.family
                          font.pixelSize: Style.font.bodySmall
                          font.weight: Font.DemiBold
                          color: Color.muted
                        }

                        Item {
                          width: 1
                          height: 1
                          Layout.fillWidth: true
                        }

                        Button {
                          anchors.verticalCenter: parent.verticalCenter
                          text: "↺ Reset Default"
                          onClicked: {
                            systemPromptInput.text = Config.DEFAULT_SYSTEM_PROMPT
                            root.updateConfigKey("systemPrompt", Config.DEFAULT_SYSTEM_PROMPT)
                          }
                        }

                        Button {
                          anchors.verticalCenter: parent.verticalCenter
                          text: "Save Prompt"
                          active: true
                          onClicked: {
                            root.updateConfigKey("systemPrompt", systemPromptInput.text)
                            root.saveFeedbackMsg = "Saved System Prompt"
                          }
                        }
                      }

                      Rectangle {
                        width: parent.width
                        height: Style.space(120)
                        radius: Style.cornerRadius > 0 ? Style.cornerRadius / 2 : Style.space(6)
                        color: Style.hoverFill
                        border.width: 1
                        border.color: Style.normalBorderColor

                        QQC.ScrollView {
                          anchors.fill: parent
                          anchors.margins: Style.space(6)
                          clip: true

                          QQC.TextArea {
                            id: systemPromptInput
                            width: parent.width
                            text: root.appConfig.systemPrompt || Config.DEFAULT_SYSTEM_PROMPT
                            font.family: Style.font.family
                            font.pixelSize: Style.font.caption
                            color: Color.popups.text
                            wrapMode: TextEdit.Wrap
                            background: null
                          }
                        }
                      }

                      Text {
                        text: "Placeholders: {{system_info}} (hardware & OS specs), {{memories}} (user habits), {{datetime}}."
                        font.family: Style.font.family
                        font.pixelSize: Style.font.caption
                        color: Color.muted
                      }
                    }

                    Rectangle {
                      width: parent.width
                      height: 1
                      color: Style.normalBorderColor
                    }

                    // System Telemetry Section
                    Column {
                      width: parent.width
                      spacing: Style.space(6)

                      Item {
                        width: parent.width
                        height: telemetryLabel.implicitHeight

                        Text {
                          id: telemetryLabel
                          anchors.left: parent.left
                          anchors.verticalCenter: parent.verticalCenter
                          text: "System Telemetry & Desktop Context:"
                          font.family: Style.font.family
                          font.pixelSize: Style.font.bodySmall
                          font.weight: Font.DemiBold
                          color: Color.muted
                        }

                        Button {
                          anchors.right: parent.right
                          anchors.verticalCenter: parent.verticalCenter
                          text: "🔄 Refresh"
                          onClicked: root.refreshTelemetry()
                        }
                      }

                      Rectangle {
                        width: parent.width
                        height: Style.space(110)
                        radius: Style.cornerRadius > 0 ? Style.cornerRadius / 2 : Style.space(6)
                        color: Style.hoverFill
                        border.width: 1
                        border.color: Style.normalBorderColor

                        Column {
                          anchors.fill: parent
                          anchors.margins: Style.space(8)
                          spacing: Style.space(3)

                          Text {
                            text: "• OS: " + (root.currentTelemetry.os || "Omarchy") + " • Kernel: " + (root.currentTelemetry.kernel || "Linux")
                            font.family: Style.font.family
                            font.pixelSize: Style.font.caption
                            color: Color.popups.text
                          }

                          Text {
                            text: "• Compositor: " + (root.currentTelemetry.desktop || "Hyprland") + " • Theme: " + (root.currentTelemetry.theme || "Active")
                            font.family: Style.font.family
                            font.pixelSize: Style.font.caption
                            color: Color.popups.text
                          }

                          Text {
                            text: "• Hardware: " + (root.currentTelemetry.cpu || "CPU") + " • RAM: " + (root.currentTelemetry.memory || "RAM")
                            font.family: Style.font.family
                            font.pixelSize: Style.font.caption
                            color: Color.popups.text
                          }

                          Text {
                            text: "• Active Window: " + (root.currentTelemetry.activeWindow || "Desktop")
                            font.family: Style.font.family
                            font.pixelSize: Style.font.caption
                            color: Color.accent
                            elide: Text.ElideRight
                            width: parent.width
                          }
                        }
                      }

                      // Injected prompt preview toggle
                      Row {
                        spacing: Style.space(8)

                        Button {
                          text: root.showTelemetryPreview ? "Hide Injected Prompt" : "Show Full Injected Prompt"
                          onClicked: root.showTelemetryPreview = !root.showTelemetryPreview
                        }
                      }

                      Rectangle {
                        visible: root.showTelemetryPreview
                        width: parent.width
                        height: Style.space(120)
                        radius: Style.cornerRadius > 0 ? Style.cornerRadius / 2 : Style.space(6)
                        color: Style.normalFill
                        border.width: 1
                        border.color: Style.normalBorderColor

                        QQC.ScrollView {
                          anchors.fill: parent
                          anchors.margins: Style.space(8)
                          clip: true

                          Text {
                            width: parent.width
                            text: root.formattedSystemPrompt
                            font.family: Style.font.family
                            font.pixelSize: Style.font.caption
                            color: Color.popups.text
                            wrapMode: Text.Wrap
                          }
                        }
                      }
                    }

                    Rectangle {
                      width: parent.width
                      height: 1
                      color: Style.normalBorderColor
                    }

                    // Persistent Memory Management Section
                    Column {
                      width: parent.width
                      spacing: Style.space(8)

                      Row {
                        width: parent.width
                        spacing: Style.space(8)

                        Text {
                          anchors.verticalCenter: parent.verticalCenter
                          text: "Persistent Memories (" + root.memoryList.length + "):"
                          font.family: Style.font.family
                          font.pixelSize: Style.font.bodySmall
                          font.weight: Font.DemiBold
                          color: Color.muted
                        }

                        Item {
                          width: 1
                          height: 1
                          Layout.fillWidth: true
                        }

                        Button {
                          anchors.verticalCenter: parent.verticalCenter
                          text: "Clear All"
                          visible: root.memoryList.length > 0
                          onClicked: root.clearAllMemories()
                        }
                      }

                      Text {
                        text: "Personal preferences remembered across sessions and injected automatically into {{memories}}."
                        font.family: Style.font.family
                        font.pixelSize: Style.font.caption
                        color: Color.muted
                      }

                      // Input row to add new memory
                      Row {
                        width: parent.width
                        spacing: Style.space(6)

                        TextField {
                          id: newMemoryField
                          width: parent.width - Style.space(80)
                          placeholderText: "e.g. Always write bash scripts with 'set -e'..."
                          text: root.newMemoryTextInput
                          onTextChanged: root.newMemoryTextInput = text
                          Keys.onReturnPressed: {
                            if (text.trim() !== "") {
                              root.addMemoryPhrase(text.trim())
                              root.newMemoryTextInput = ""
                              newMemoryField.text = ""
                            }
                          }
                        }

                        Button {
                          text: "󰐕 Add"
                          active: root.newMemoryTextInput.trim() !== ""
                          enabled: root.newMemoryTextInput.trim() !== ""
                          onClicked: {
                            root.addMemoryPhrase(root.newMemoryTextInput.trim())
                            root.newMemoryTextInput = ""
                            newMemoryField.text = ""
                          }
                        }
                      }

                      // Memory List Box
                      Rectangle {
                        width: parent.width
                        height: Math.min(Style.space(160), Math.max(Style.space(48), root.memoryList.length * Style.space(34) + Style.space(12)))
                        radius: Style.cornerRadius > 0 ? Style.cornerRadius / 2 : Style.space(6)
                        color: Style.normalFill
                        border.width: 1
                        border.color: Style.normalBorderColor

                        Text {
                          anchors.centerIn: parent
                          visible: root.memoryList.length === 0
                          text: "No memories stored yet. Add preferences above or let the assistant save them via tools."
                          font.family: Style.font.family
                          font.pixelSize: Style.font.caption
                          color: Color.muted
                        }

                        QQC.ScrollView {
                          anchors.fill: parent
                          anchors.margins: Style.space(6)
                          clip: true
                          visible: root.memoryList.length > 0

                          Column {
                            width: parent.width
                            spacing: Style.space(4)

                            Repeater {
                              model: root.memoryList

                              Rectangle {
                                width: parent.width
                                height: Style.space(30)
                                radius: Style.cornerRadius > 0 ? Style.cornerRadius / 2 : Style.space(4)
                                color: Style.hoverFill
                                border.width: 1
                                border.color: Style.normalBorderColor

                                Item {
                                  anchors.fill: parent
                                  anchors.leftMargin: Style.space(8)
                                  anchors.rightMargin: Style.space(6)

                                  Row {
                                    anchors.left: parent.left
                                    anchors.right: delBtn.left
                                    anchors.rightMargin: Style.space(6)
                                    anchors.verticalCenter: parent.verticalCenter
                                    spacing: Style.space(6)

                                    Text {
                                      text: (index + 1) + "."
                                      font.family: Style.font.family
                                      font.pixelSize: Style.font.caption
                                      font.weight: Font.DemiBold
                                      color: Color.accent
                                      anchors.verticalCenter: parent.verticalCenter
                                    }

                                    Text {
                                      width: parent.width - Style.space(24)
                                      text: modelData
                                      font.family: Style.font.family
                                      font.pixelSize: Style.font.caption
                                      color: Color.popups.text
                                      elide: Text.ElideRight
                                      anchors.verticalCenter: parent.verticalCenter
                                    }
                                  }

                                  Button {
                                    id: delBtn
                                    anchors.right: parent.right
                                    anchors.verticalCenter: parent.verticalCenter
                                    text: "󰅖"
                                    onClicked: root.removeMemoryPhrase(index + 1)
                                  }
                                }
                              }
                            }
                          }
                        }
                      }
                    }
                  }
                }
              }
            }
          }
        }
      }
    }
  }
}
