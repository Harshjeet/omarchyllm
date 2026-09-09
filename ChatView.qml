import QtQuick
import QtQuick.Controls as QQC
import Quickshell
import Quickshell.Io
import qs.Commons
import qs.Ui
import "js/Api.js" as Api
import "js/ToolManager.js" as ToolManager
import "js/ContextCompactor.js" as ContextCompactor

// ChatView manages the live conversation stream, multi-turn tool calling,
// user approval cards, interactive terminal blocks, and auto-scrolling message list.
Item {
  id: root

  property var appConfig: ({})
  property var appKeys: ({})
  property string activeProviderId: "ollama"
  property var activeProviderObj: null
  property string activeModelName: "llama3.2"
  property string activeEndpoint: ""
  property string currentApiKey: ""
  property string formattedSystemPrompt: ""

  property bool isGenerating: false
  property bool hasError: false
  property string errorMessage: ""

  // Context Compaction State
  property int compactedUpToMsgId: -1
  property string compactedSummary: ""
  property bool isCompacting: false
  property string compactionStatus: ""
  property bool showCompactedSummary: false

  // Active streaming handle returned by Api.streamChatCompletion
  property var currentStreamHandle: null

  signal openSettingsRequested()

  // -------------------------------------------------------------
  // Data Model for Messages
  // -------------------------------------------------------------
  ListModel {
    id: chatModel
  }

  function formatCurrentTime() {
    var d = new Date()
    var h = d.getHours()
    var m = d.getMinutes()
    var ampm = h >= 12 ? "PM" : "AM"
    h = h % 12
    if (h === 0) h = 12
    var mStr = m < 10 ? ("0" + m) : m
    return h + ":" + mStr + " " + ampm
  }

  function clearHistory() {
    if (root.currentStreamHandle && root.currentStreamHandle.abort) {
      root.currentStreamHandle.abort()
      root.currentStreamHandle = null
    }
    if (toolRunner.running) {
      toolRunner.running = false
    }
    root.isGenerating = false
    chatModel.clear()
    root.hasError = false
    root.errorMessage = ""
    root.compactedUpToMsgId = -1
    root.compactedSummary = ""
    root.compactionStatus = ""
    root.showCompactedSummary = false
  }

  function stopGeneration() {
    if (root.currentStreamHandle && root.currentStreamHandle.abort) {
      root.currentStreamHandle.abort()
      root.currentStreamHandle = null
    }
    if (toolRunner.running) {
      toolRunner.running = false
    }
    root.isGenerating = false
    if (chatModel.count > 0) {
      var lastIdx = chatModel.count - 1
      var lastItem = chatModel.get(lastIdx)
      if (lastItem && lastItem.isStreaming) {
        chatModel.setProperty(lastIdx, "isStreaming", false)
      }
    }
  }

  // -------------------------------------------------------------
  // Tool Execution Engine (Quickshell Process)
  // -------------------------------------------------------------
  Process {
    id: toolRunner
    property int currentItemIndex: -1
    property string currentCallId: ""
    property string currentToolName: ""
    property var currentArgs: ({})
    property string accumulatedStdout: ""
    property string accumulatedStderr: ""

    stdout: StdioCollector {
      waitForEnd: true
      onStreamFinished: {
        toolRunner.accumulatedStdout = text
      }
    }

    stderr: StdioCollector {
      waitForEnd: true
      onStreamFinished: {
        toolRunner.accumulatedStderr = text
      }
    }

    onExited: function(exitCode, exitStatus) {
      var idx = toolRunner.currentItemIndex
      var stdout = toolRunner.accumulatedStdout
      var stderr = toolRunner.accumulatedStderr

      if (idx >= 0 && idx < chatModel.count) {
        chatModel.setProperty(idx, "isRunning", false)
        chatModel.setProperty(idx, "exitCode", exitCode)
        chatModel.setProperty(idx, "stdoutText", stdout)
        chatModel.setProperty(idx, "stderrText", stderr)
      }

      var output = stdout ? stdout : (stderr ? stderr : "(command completed with no output)")
      root.continueConversationWithToolResult(
        toolRunner.currentCallId,
        toolRunner.currentToolName,
        toolRunner.currentArgs,
        output
      )
    }
  }

  function approveToolCall(index, name, args, callId) {
    if (toolRunner.running) return
    if (index < 0 || index >= chatModel.count) return

    chatModel.setProperty(index, "role", "tool_result")
    chatModel.setProperty(index, "isRunning", true)
    chatModel.setProperty(index, "stdoutText", "")
    chatModel.setProperty(index, "stderrText", "")
    chatModel.setProperty(index, "exitCode", 0)

    toolRunner.currentItemIndex = index
    toolRunner.currentCallId = callId
    toolRunner.currentToolName = name
    toolRunner.currentArgs = args
    toolRunner.accumulatedStdout = ""
    toolRunner.accumulatedStderr = ""

    var cmd = ToolManager.buildExecutionCommand(name, args)
    toolRunner.command = ["bash", "-c", cmd]
    toolRunner.running = true
  }

  function denyToolCall(index, name, callId) {
    if (index < 0 || index >= chatModel.count) return

    chatModel.setProperty(index, "role", "tool_result")
    chatModel.setProperty(index, "isRunning", false)
    chatModel.setProperty(index, "exitCode", 1)
    chatModel.setProperty(index, "stdoutText", "")
    chatModel.setProperty(index, "stderrText", "Tool execution was denied by the user.")

    root.continueConversationWithToolResult(
      callId,
      name,
      {},
      "Error: Tool execution was denied by the user."
    )
  }

  // -------------------------------------------------------------
  // Conversation History Payload Builder (Supports Context Compaction)
  // -------------------------------------------------------------
  function buildConversationPayload() {
    var historyPayload = []

    if (root.formattedSystemPrompt && root.formattedSystemPrompt.trim() !== "") {
      historyPayload.push({
        role: "system",
        content: root.formattedSystemPrompt.trim()
      })
    }

    // Inject compacted context summary from earlier turns
    if (root.compactedSummary && root.compactedSummary.trim() !== "") {
      historyPayload.push({
        role: "system",
        content: "## Compacted Prior Context:\n" + root.compactedSummary.trim()
      })
    }

    // Include uncompacted recent messages
    var startIdx = root.compactedUpToMsgId >= 0 ? (root.compactedUpToMsgId + 1) : 0
    for (var i = startIdx; i < chatModel.count; i++) {
      var msg = chatModel.get(i)
      if (!msg || !msg.role) continue

      if (msg.role === "user") {
        historyPayload.push({
          role: "user",
          content: msg.content || ""
        })
      } else if (msg.role === "assistant") {
        // Skip empty placeholder messages that are actively streaming
        if (msg.isStreaming && !msg.content && !msg.thinking) continue

        var asstObj = {
          role: "assistant",
          content: msg.content || ""
        }
        if (msg.toolCallsJson && msg.toolCallsJson !== "") {
          try {
            asstObj.tool_calls = JSON.parse(msg.toolCallsJson)
          } catch(e) {}
        }
        historyPayload.push(asstObj)
      } else if (msg.role === "tool_result") {
        var outText = msg.stdoutText ? msg.stdoutText : (msg.stderrText ? msg.stderrText : "(no output)")
        historyPayload.push({
          role: "tool",
          tool_call_id: msg.toolCallId || "",
          content: outText
        })
      }
    }
    return historyPayload
  }

  // -------------------------------------------------------------
  // Context Compaction Trigger & Logic
  // -------------------------------------------------------------
  function triggerCompaction(keepTurns, callback) {
    if (root.isCompacting || root.isGenerating) {
      if (callback) callback("Assistant is currently generating or already compacting", null)
      return
    }
    var keep = keepTurns || (root.appConfig && root.appConfig.compactionKeepRecentTurns) || 4
    var range = ContextCompactor.findCompactionRange(chatModel, root.compactedUpToMsgId, keep)
    if (!range) {
      var msg = "Not enough conversation history to compact (needs at least " + (keep + 1) + " user turns)."
      root.compactionStatus = msg
      if (callback) callback(msg, null)
      return
    }

    root.isCompacting = true
    root.compactionStatus = "Compacting turns " + (range.startIndex + 1) + " to " + (range.endIndex + 1) + "..."

    var transcript = ContextCompactor.formatTranscript(chatModel, range.startIndex, range.endIndex)
    var providerOpts = {
      endpoint: root.activeEndpoint,
      apiKey: root.currentApiKey,
      model: root.activeModelName
    }

    ContextCompactor.compactHistory(
      root.activeProviderId,
      providerOpts,
      transcript,
      root.compactedSummary,
      function(err, summary) {
        root.isCompacting = false
        if (err) {
          root.compactionStatus = "Compaction failed: " + (err.message || String(err))
          if (callback) callback(err, null)
        } else {
          root.compactedSummary = summary
          root.compactedUpToMsgId = range.endIndex
          root.compactionStatus = "Compacted " + range.candidateTurns + " turns (" + range.totalChars + " chars)"
          if (callback) callback(null, summary)
        }
      }
    )
  }

  // -------------------------------------------------------------
  // Stream Handlers (Shared between user prompts & tool returns)
  // -------------------------------------------------------------
  function handleCompletionDone(assistantIndex, finalText, finalThinking, toolCalls) {
    var hasTools = toolCalls && toolCalls.length > 0
    var contentToSet = finalText

    if ((!finalText || finalText.trim() === "") && hasTools) {
      var firstToolName = toolCalls[0]["function"] ? toolCalls[0]["function"].name : "tool"
      contentToSet = "Calling " + ToolManager.getToolDisplayName(firstToolName) + "..."
    } else if ((!finalText || finalText.trim() === "") && !hasTools) {
      if (finalThinking && finalThinking.trim() !== "") {
        contentToSet = finalThinking.trim()
      } else {
        contentToSet = "[No response received from model. The provider returned an empty response or timed out. Try switching to a verified model like nvidia/nemotron-3.5-lightning:free.]"
      }
    }

    if (assistantIndex < chatModel.count) {
      chatModel.setProperty(assistantIndex, "content", contentToSet)
      chatModel.setProperty(assistantIndex, "thinking", finalThinking)
      chatModel.setProperty(assistantIndex, "isStreaming", false)
      if (hasTools) {
        chatModel.setProperty(assistantIndex, "toolCallsJson", JSON.stringify(toolCalls))
      }
    }

    root.currentStreamHandle = null

    if (hasTools) {
      root.isGenerating = false
      for (var t = 0; t < toolCalls.length; t++) {
        var call = toolCalls[t]
        var callName = call["function"] ? call["function"].name : ""
        var callArgs = call["function"] ? call["function"].arguments : "{}"
        var callId = call.id || ("call_" + Math.random().toString(36).substring(2, 9))

        var autoApprove = (root.appConfig && root.appConfig.autoApproveTerminal === true)

        var cardIdx = chatModel.count
        chatModel.append({
          role: autoApprove ? "tool_result" : "tool_approval",
          content: "",
          thinking: "",
          timestamp: formatCurrentTime(),
          modelName: "",
          isStreaming: false,
          toolCallsJson: "",
          toolName: callName,
          toolCallId: callId,
          toolArgs: callArgs,
          isProcessing: false,
          stdoutText: "",
          stderrText: "",
          exitCode: 0,
          isRunning: autoApprove
        })

        if (autoApprove) {
          approveToolCall(cardIdx, callName, callArgs, callId)
        }
      }
    } else {
      root.isGenerating = false

      // Check Automatic Context Compaction Triggers
      if (root.appConfig && root.appConfig.compactionEnabled !== false && !root.isCompacting) {
        var keepTurns = root.appConfig.compactionKeepRecentTurns || 4
        var range = ContextCompactor.findCompactionRange(chatModel, root.compactedUpToMsgId, keepTurns)
        if (range) {
          var triggerMode = root.appConfig.compactionTriggerMode || "chars"
          var charThreshold = root.appConfig.compactionThresholdChars || 20000
          var turnThreshold = root.appConfig.compactionThresholdTurns || 4
          var shouldTrigger = false
          if (triggerMode === "chars" && range.totalChars >= charThreshold) {
            shouldTrigger = true
          } else if (triggerMode === "turns" && range.candidateTurns >= turnThreshold) {
            shouldTrigger = true
          } else if (triggerMode === "both" && (range.totalChars >= charThreshold || range.candidateTurns >= turnThreshold)) {
            shouldTrigger = true
          }
          if (shouldTrigger) {
            console.log("OmarchyLLM: Triggering automatic context compaction...")
            root.triggerCompaction(keepTurns, null)
          }
        }
      }
    }

    messageListView.positionViewAtEnd()
  }

  function handleCompletionError(assistantIndex, err, canRetryWithoutTools) {
    console.error("OmarchyLLM: Stream error:", err)
    var errMsg = (err && err.message) ? err.message : String(err || "Unknown error")

    // Automatic fallback: if error is due to tools/function calling schema, retry once without tools
    if (canRetryWithoutTools && (errMsg.indexOf("tool") !== -1 || errMsg.indexOf("function") !== -1 || errMsg.indexOf("400") !== -1 || errMsg.indexOf("schema") !== -1)) {
      console.log("OmarchyLLM: Model does not support tool schemas, retrying without tools...")
      if (assistantIndex < chatModel.count) {
        chatModel.setProperty(assistantIndex, "content", "*(Retrying without tools...)*")
      }
      var retryOpts = {
        endpoint: root.activeEndpoint,
        model: root.activeModelName,
        apiKey: root.currentApiKey,
        temperature: root.appConfig.temperature !== undefined ? root.appConfig.temperature : 0.7,
        maxTokens: root.appConfig.maxTokens !== undefined ? root.appConfig.maxTokens : 4096,
        tools: []
      }
      var historyPayload = buildConversationPayload()
      root.currentStreamHandle = Api.streamChatCompletion(
        root.activeProviderId,
        retryOpts,
        historyPayload,
        {
          onToken: function(token) {
            if (assistantIndex < chatModel.count) {
              var curr = chatModel.get(assistantIndex).content || ""
              if (curr.indexOf("*(Retrying") === 0) curr = ""
              chatModel.setProperty(assistantIndex, "content", curr + token)
              messageListView.positionViewAtEnd()
            }
          },
          onThinking: function(thinkDelta) {
            if (assistantIndex < chatModel.count) {
              var currThink = chatModel.get(assistantIndex).thinking || ""
              chatModel.setProperty(assistantIndex, "thinking", currThink + thinkDelta)
              messageListView.positionViewAtEnd()
            }
          },
          onDone: function(finalText, finalThinking, toolCalls) {
            handleCompletionDone(assistantIndex, finalText, finalThinking, toolCalls)
          },
          onError: function(retryErr) {
            handleCompletionError(assistantIndex, retryErr, false)
          }
        }
      )
      return
    }

    root.hasError = true
    root.errorMessage = errMsg
    if (assistantIndex < chatModel.count) {
      var existing = chatModel.get(assistantIndex).content || ""
      if (existing.indexOf("*(Retrying") === 0) existing = ""
      var errDisplay = existing ? (existing + "\n\n[Error: " + root.errorMessage + "]") : ("[Error: " + root.errorMessage + "]")
      chatModel.setProperty(assistantIndex, "content", errDisplay)
      chatModel.setProperty(assistantIndex, "isStreaming", false)
    }
    root.isGenerating = false
    root.currentStreamHandle = null
    messageListView.positionViewAtEnd()
  }

  // -------------------------------------------------------------
  // Send User Prompt
  // -------------------------------------------------------------
  function sendUserPrompt(promptText) {
    console.log("OmarchyLLM: ChatView.sendUserPrompt starting with prompt:", promptText)
    if (!promptText || promptText.trim() === "") return
    if (root.isGenerating) {
      console.warn("OmarchyLLM: ChatView is already generating, ignoring prompt")
      return
    }

    root.hasError = false
    root.errorMessage = ""

    var timeStr = formatCurrentTime()

    // 1. Add User Message
    chatModel.append({
      role: "user",
      content: promptText.trim(),
      thinking: "",
      timestamp: timeStr,
      modelName: "",
      isStreaming: false,
      toolCallsJson: "",
      toolName: "",
      toolCallId: "",
      toolArgs: "",
      isProcessing: false,
      stdoutText: "",
      stderrText: "",
      exitCode: 0,
      isRunning: false
    })

    // 2. Prepare Assistant Placeholder
    var assistantIndex = chatModel.count
    chatModel.append({
      role: "assistant",
      content: "",
      thinking: "",
      timestamp: timeStr,
      modelName: root.activeModelName,
      isStreaming: true,
      toolCallsJson: "",
      toolName: "",
      toolCallId: "",
      toolArgs: "",
      isProcessing: false,
      stdoutText: "",
      stderrText: "",
      exitCode: 0,
      isRunning: false
    })

    root.isGenerating = true
    messageListView.positionViewAtEnd()

    // 3. Build Conversation History for LLM Payload
    var historyPayload = buildConversationPayload()

    var toolsList = []
    if (root.appConfig && root.appConfig.toolsMasterEnabled !== false) {
      toolsList = ToolManager.getToolDefinitions(root.appConfig)
    }

    var providerOptions = {
      endpoint: root.activeEndpoint,
      model: root.activeModelName,
      apiKey: root.currentApiKey,
      temperature: root.appConfig.temperature !== undefined ? root.appConfig.temperature : 0.7,
      maxTokens: root.appConfig.maxTokens !== undefined ? root.appConfig.maxTokens : 4096,
      tools: toolsList
    }

    console.log("OmarchyLLM: Dispatching to provider:", root.activeProviderId,
                "endpoint:", root.activeEndpoint,
                "model:", root.activeModelName,
                "hasKey:", (root.currentApiKey && root.currentApiKey.length > 0))

    // 4. Dispatch Streaming Completion via Api.js
    root.currentStreamHandle = Api.streamChatCompletion(
      root.activeProviderId,
      providerOptions,
      historyPayload,
      {
        onToken: function(token) {
          if (assistantIndex < chatModel.count) {
            var curr = chatModel.get(assistantIndex).content || ""
            chatModel.setProperty(assistantIndex, "content", curr + token)
            messageListView.positionViewAtEnd()
          }
        },
        onThinking: function(thinkDelta) {
          if (assistantIndex < chatModel.count) {
            var currThink = chatModel.get(assistantIndex).thinking || ""
            chatModel.setProperty(assistantIndex, "thinking", currThink + thinkDelta)
            messageListView.positionViewAtEnd()
          }
        },
        onDone: function(finalText, finalThinking, toolCalls) {
          handleCompletionDone(assistantIndex, finalText, finalThinking, toolCalls)
        },
        onError: function(err) {
          handleCompletionError(assistantIndex, err, true)
        }
      }
    )
  }

  // -------------------------------------------------------------
  // Multi-Turn Continuation with Tool Result
  // -------------------------------------------------------------
  function continueConversationWithToolResult(callId, name, args, toolOutput) {
    if (root.isGenerating) return

    root.hasError = false
    root.errorMessage = ""
    root.isGenerating = true

    var historyPayload = buildConversationPayload()

    var timeStr = formatCurrentTime()
    var assistantIndex = chatModel.count
    chatModel.append({
      role: "assistant",
      content: "",
      thinking: "",
      timestamp: timeStr,
      modelName: root.activeModelName,
      isStreaming: true,
      toolCallsJson: "",
      toolName: "",
      toolCallId: "",
      toolArgs: "",
      isProcessing: false,
      stdoutText: "",
      stderrText: "",
      exitCode: 0,
      isRunning: false
    })

    messageListView.positionViewAtEnd()

    var contTools = []
    if (root.appConfig && root.appConfig.toolsMasterEnabled !== false) {
      contTools = ToolManager.getToolDefinitions(root.appConfig)
    }

    var providerOptions = {
      endpoint: root.activeEndpoint,
      model: root.activeModelName,
      apiKey: root.currentApiKey,
      stream: true,
      temperature: root.appConfig.temperature !== undefined ? root.appConfig.temperature : 0.7,
      maxTokens: root.appConfig.maxTokens !== undefined ? root.appConfig.maxTokens : 4096,
      tools: contTools
    }

    root.currentStreamHandle = Api.streamChatCompletion(
      root.activeProviderId,
      providerOptions,
      historyPayload,
      {
        onToken: function(token) {
          if (assistantIndex < chatModel.count) {
            var curr = chatModel.get(assistantIndex).content || ""
            chatModel.setProperty(assistantIndex, "content", curr + token)
            messageListView.positionViewAtEnd()
          }
        },
        onThinking: function(thinkDelta) {
          if (assistantIndex < chatModel.count) {
            var currThink = chatModel.get(assistantIndex).thinking || ""
            chatModel.setProperty(assistantIndex, "thinking", currThink + thinkDelta)
            messageListView.positionViewAtEnd()
          }
        },
        onDone: function(finalText, finalThinking, toolCalls) {
          handleCompletionDone(assistantIndex, finalText, finalThinking, toolCalls)
        },
        onError: function(err) {
          handleCompletionError(assistantIndex, err)
        }
      }
    )
  }

  // -------------------------------------------------------------
  // LAYOUT: Message Stream + Input Bar
  // -------------------------------------------------------------
  Column {
    anchors.fill: parent
    spacing: Style.space(8)

    // Message List Area
    Column {
      width: parent.width
      height: parent.height - chatInput.height - Style.space(8)
      spacing: Style.space(6)

      // Context Compaction Notification & Summary Banner
      Rectangle {
        id: compactionBannerBox
        width: parent.width
        visible: (root.compactedSummary !== "" || root.isCompacting) && chatModel.count > 0
        height: visible ? (compactionBannerCol.implicitHeight + Style.space(12)) : 0
        radius: Style.cornerRadius > 0 ? Style.cornerRadius / 2 : Style.space(6)
        color: Util.alpha(Color.accent, 0.12)
        border.width: 1
        border.color: Util.alpha(Color.accent, 0.3)

        Column {
          id: compactionBannerCol
          anchors.left: parent.left
          anchors.right: parent.right
          anchors.verticalCenter: parent.verticalCenter
          anchors.margins: Style.space(8)
          spacing: Style.space(6)

          Row {
            width: parent.width
            spacing: Style.space(8)

            Text {
              text: "󰈚"
              font.family: Style.font.family
              font.pixelSize: Style.font.body
              color: Color.accent
              anchors.verticalCenter: parent.verticalCenter
            }

            Text {
              width: parent.width - Style.space(130)
              text: root.isCompacting ? root.compactionStatus : ("Context Compacted: Earlier " + (root.compactedUpToMsgId + 1) + " messages summarized into background memory")
              font.family: Style.font.family
              font.pixelSize: Style.font.caption
              font.weight: Font.DemiBold
              color: Color.popups.text
              elide: Text.ElideRight
              anchors.verticalCenter: parent.verticalCenter
            }

            Button {
              anchors.right: parent.right
              anchors.verticalCenter: parent.verticalCenter
              visible: root.compactedSummary !== "" && !root.isCompacting
              text: root.showCompactedSummary ? "Hide" : "View"
              onClicked: root.showCompactedSummary = !root.showCompactedSummary
            }
          }

          Rectangle {
            width: parent.width
            height: Style.space(90)
            visible: root.showCompactedSummary && root.compactedSummary !== ""
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
                text: root.compactedSummary
                font.family: Style.font.family
                font.pixelSize: Style.font.caption
                color: Color.popups.text
                wrapMode: Text.Wrap
              }
            }
          }
        }
      }

      // Container for Empty State or ListView
      Item {
        width: parent.width
        height: parent.height - (compactionBannerBox.visible ? compactionBannerBox.height + Style.space(6) : 0)

        // Empty State View
        Rectangle {
          anchors.fill: parent
          visible: chatModel.count === 0
          radius: Style.cornerRadius > 0 ? Style.cornerRadius : Style.space(8)
          color: Style.normalFill
          border.width: 1
          border.color: Style.normalBorderColor

          Column {
            anchors.centerIn: parent
            spacing: Style.space(14)
            width: parent.width - Style.space(40)

            Text {
              anchors.horizontalCenter: parent.horizontalCenter
              text: "󰚩"
              font.family: Style.font.family
              font.pixelSize: Style.space(44)
              color: Util.alpha(Color.accent, 0.7)
            }

            Column {
              anchors.horizontalCenter: parent.horizontalCenter
              spacing: Style.space(4)

              Text {
                anchors.horizontalCenter: parent.horizontalCenter
                text: "Ready to assist"
                font.family: Style.font.family
                font.pixelSize: Style.font.title
                font.weight: Font.DemiBold
                color: Color.popups.text
              }

              Text {
                anchors.horizontalCenter: parent.horizontalCenter
              text: "Connected to " + (root.activeProviderObj ? root.activeProviderObj.displayName : root.activeProviderId) + " (" + root.activeModelName + ")"
              font.family: Style.font.family
              font.pixelSize: Style.font.caption
              color: Color.muted
            }
          }

          // Sample Starter Prompts with Tool Exploration
          Column {
            anchors.horizontalCenter: parent.horizontalCenter
            spacing: Style.space(6)
            width: parent.width

            Repeater {
              model: [
                "List files in my home directory",
                "What is my system kernel and disk usage?",
                "Explain how Hyprland window tiling works"
              ]

              Rectangle {
                width: parent.width
                height: Style.space(32)
                radius: Style.cornerRadius > 0 ? Style.cornerRadius / 2 : Style.space(6)
                color: promptMouse.containsMouse ? Style.hoverFill : "transparent"
                border.width: 1
                border.color: promptMouse.containsMouse ? Style.hoverBorderColor : Style.normalBorderColor

                Row {
                  anchors.fill: parent
                  anchors.leftMargin: Style.space(10)
                  anchors.rightMargin: Style.space(10)
                  spacing: Style.space(8)

                  Text {
                    text: "💬"
                    font.family: Style.font.family
                    font.pixelSize: Style.font.caption
                    anchors.verticalCenter: parent.verticalCenter
                  }

                  Text {
                    text: modelData
                    font.family: Style.font.family
                    font.pixelSize: Style.font.bodySmall
                    color: promptMouse.containsMouse ? Color.accent : Color.popups.text
                    elide: Text.ElideRight
                    anchors.verticalCenter: parent.verticalCenter
                  }
                }

                MouseArea {
                  id: promptMouse
                  anchors.fill: parent
                  hoverEnabled: true
                  cursorShape: Qt.PointingHandCursor
                  onClicked: root.sendUserPrompt(modelData)
                }
              }
            }
          }
        }
      }

      // Live Message Stream
      ListView {
        id: messageListView
        anchors.fill: parent
        visible: chatModel.count > 0
        model: chatModel
        clip: true
        spacing: Style.space(10)
        boundsBehavior: Flickable.StopAtBounds

        QQC.ScrollBar.vertical: QQC.ScrollBar {
          policy: QQC.ScrollBar.AsNeeded
        }

        delegate: Item {
          id: delegateItem
          required property var model
          required property int index
          width: messageListView.width
          implicitHeight: {
            if (delegateItem.model.role === "tool_approval") return toolApprovalItem.implicitHeight
            if (delegateItem.model.role === "tool_result") return toolResultItem.implicitHeight
            return chatMsgItem.implicitHeight
          }

          ChatMessage {
            id: chatMsgItem
            anchors.left: parent.left
            anchors.right: parent.right
            visible: delegateItem.model.role !== "tool_approval" && delegateItem.model.role !== "tool_result"
            role: delegateItem.model.role || ""
            content: delegateItem.model.content || ""
            thinking: delegateItem.model.thinking || ""
            timestamp: delegateItem.model.timestamp || ""
            modelName: delegateItem.model.modelName || ""
            isStreaming: delegateItem.model.isStreaming === true
          }

          ToolApprovalCard {
            id: toolApprovalItem
            anchors.left: parent.left
            anchors.right: parent.right
            visible: delegateItem.model.role === "tool_approval"
            toolName: delegateItem.model.toolName || ""
            toolCallId: delegateItem.model.toolCallId || ""
            toolArgs: delegateItem.model.toolArgs || ""
            isProcessing: delegateItem.model.isProcessing === true
            onApproved: function(name, args, callId) {
              root.approveToolCall(delegateItem.index, name, args, callId)
            }
            onDenied: function(name, callId) {
              root.denyToolCall(delegateItem.index, name, callId)
            }
          }

          ToolResultBlock {
            id: toolResultItem
            anchors.left: parent.left
            anchors.right: parent.right
            visible: delegateItem.model.role === "tool_result"
            toolName: delegateItem.model.toolName || ""
            toolArgs: delegateItem.model.toolArgs || ""
            stdoutText: delegateItem.model.stdoutText || ""
            stderrText: delegateItem.model.stderrText || ""
            exitCode: delegateItem.model.exitCode !== undefined ? delegateItem.model.exitCode : 0
            isRunning: delegateItem.model.isRunning === true
          }
        }
      }
    }
  }

  // Input Bar Component
    ChatInput {
      id: chatInput
      width: parent.width
      isGenerating: root.isGenerating
      apiKey: root.currentApiKey
      endpoint: root.activeEndpoint
      sttBackend: root.appConfig && root.appConfig.sttBackend ? root.appConfig.sttBackend : "whisper"
      onSendRequested: function(prompt) {
        root.sendUserPrompt(prompt)
      }
      onStopRequested: {
        root.stopGeneration()
      }
      onClearRequested: {
        root.clearHistory()
      }
      onOpenSettingsRequested: {
        root.openSettingsRequested()
      }
    }
  }
}
