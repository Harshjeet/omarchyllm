import QtQuick
import QtQuick.Controls as QQC
import Quickshell
import Quickshell.Io
import qs.Commons
import qs.Ui

// Interactive prompt input for OmarchyLLM supporting multiline text,
// Enter-to-send, Shift+Enter for newlines, voice recording (STT), and Send/Stop toggle.
Item {
  id: root

  property bool isGenerating: false
  property string placeholderText: "Ask Omarchy LLM... (Enter to send, Shift+Enter for newline)"
  property string apiKey: ""
  property string endpoint: ""
  property string sttBackend: "whisper"

  property bool isRecording: false
  property bool isTranscribing: false
  property string voiceError: ""

  signal sendRequested(string message)
  signal stopRequested()
  signal clearRequested()
  signal openSettingsRequested()

  function focusInput() {
    inputArea.forceActiveFocus()
  }

  function clearText() {
    inputArea.text = ""
  }

  function submit() {
    if (root.isGenerating) {
      root.stopRequested()
      return
    }
    var prompt = inputArea.text.trim()
    if (prompt === "") return
    root.sendRequested(prompt)
    inputArea.text = ""
  }

  // -------------------------------------------------------------
  // Speech-to-Text Audio Recording & Transcription
  // -------------------------------------------------------------
  Process {
    id: recordProc
    command: ["pw-record", "/tmp/omarchy_llm_mic.wav"]
    onExited: function(exitCode, exitStatus) {
      if (root.isRecording) {
        root.isRecording = false
      }
      transcribeAudio()
    }
  }

  Process {
    id: transcribeProc
    property string accumulatedText: ""
    property string accumulatedError: ""

    stdout: StdioCollector {
      waitForEnd: true
      onStreamFinished: {
        transcribeProc.accumulatedText = text
      }
    }
    stderr: StdioCollector {
      waitForEnd: true
      onStreamFinished: {
        transcribeProc.accumulatedError = text
      }
    }
    onExited: function(exitCode, exitStatus) {
      root.isTranscribing = false
      var transcript = transcribeProc.accumulatedText.trim()
      if (transcript !== "") {
        root.voiceError = ""
        if (inputArea.text.trim() === "") {
          inputArea.text = transcript
        } else {
          inputArea.text = inputArea.text + " " + transcript
        }
      } else {
        var err = transcribeProc.accumulatedError.trim()
        if (err !== "") {
          root.voiceError = err
        } else if (exitCode !== 0) {
          root.voiceError = "Speech transcription failed (code " + exitCode + ")"
        }
      }
    }
  }

  function toggleRecording() {
    if (root.isRecording) {
      root.isRecording = false
      recordProc.running = false
    } else {
      root.voiceError = ""
      root.isRecording = true
      recordProc.running = true
    }
  }

  function transcribeAudio() {
    root.isTranscribing = true
    root.voiceError = ""
    transcribeProc.accumulatedText = ""
    transcribeProc.accumulatedError = ""
    var scriptPath = Qt.resolvedUrl("stt.py").toString().replace(/^file:\/\//, "")
    var args = ["python3", scriptPath, "--file", "/tmp/omarchy_llm_mic.wav"]
    if (root.sttBackend) {
      args.push("--backend", root.sttBackend)
    }
    if (root.apiKey) {
      args.push("--key", root.apiKey)
    }
    if (root.endpoint) {
      args.push("--endpoint", root.endpoint)
    }
    transcribeProc.command = args
    transcribeProc.running = true
  }

  implicitWidth: parent ? parent.width : Style.space(480)
  implicitHeight: mainColumn.implicitHeight
  height: implicitHeight

  Column {
    id: mainColumn
    width: parent.width
    spacing: Style.space(6)

    // Voice Error / Guidance Banner
    Rectangle {
      id: voiceErrorBanner
      visible: root.voiceError !== ""
      width: parent.width
      implicitHeight: voiceErrorRow.implicitHeight + Style.space(12)
      radius: Style.cornerRadius > 0 ? Style.cornerRadius / 2 : Style.space(6)
      color: Util.alpha(Color.urgent, 0.12)
      border.width: 1
      border.color: Util.alpha(Color.urgent, 0.4)

      Row {
        id: voiceErrorRow
        anchors {
          left: parent.left
          right: parent.right
          verticalCenter: parent.verticalCenter
          margins: Style.space(8)
        }
        spacing: Style.space(8)

        Text {
          text: "󰍮"
          font.family: Style.font.family
          font.pixelSize: Style.font.title
          color: Color.urgent
          anchors.verticalCenter: parent.verticalCenter
        }

        Text {
          width: parent.width - Style.space(140)
          text: root.voiceError
          font.family: Style.font.family
          font.pixelSize: Style.font.bodySmall
          color: Color.popups.text
          wrapMode: Text.Wrap
          anchors.verticalCenter: parent.verticalCenter
        }

        Rectangle {
          width: Style.space(64)
          height: Style.space(24)
          radius: Style.cornerRadius > 0 ? Style.cornerRadius / 3 : Style.space(4)
          color: Util.alpha(Color.accent, 0.2)
          border.width: 1
          border.color: Color.accent
          anchors.verticalCenter: parent.verticalCenter

          Text {
            anchors.centerIn: parent
            text: "Settings"
            font.family: Style.font.family
            font.pixelSize: Style.font.caption
            font.weight: Font.DemiBold
            color: Color.accent
          }

          MouseArea {
            anchors.fill: parent
            cursorShape: Qt.PointingHandCursor
            onClicked: root.openSettingsRequested()
          }
        }

        Rectangle {
          width: Style.space(24)
          height: Style.space(24)
          radius: Style.cornerRadius > 0 ? Style.cornerRadius / 3 : Style.space(4)
          color: "transparent"
          anchors.verticalCenter: parent.verticalCenter

          Text {
            anchors.centerIn: parent
            text: "✕"
            font.family: Style.font.family
            font.pixelSize: Style.font.caption
            color: Color.muted
          }

          MouseArea {
            anchors.fill: parent
            cursorShape: Qt.PointingHandCursor
            onClicked: root.voiceError = ""
          }
        }
      }
    }

    Rectangle {
      id: backgroundBox
      width: parent.width
      height: Math.max(Style.space(48), Math.min(Style.space(120), contentRow.implicitHeight + Style.space(12)))
      radius: Style.cornerRadius > 0 ? Style.cornerRadius : Style.space(8)
      color: inputArea.activeFocus ? Style.controlFill(true, false, Color.foreground, Color.accent) : Style.normalFill
      border.width: inputArea.activeFocus ? Style.focusBorderWidth : Style.normalBorderWidth
      border.color: inputArea.activeFocus ? Style.focusBorderColor : Style.normalBorderColor

      Row {
        id: contentRow
        anchors {
          left: parent.left
          right: parent.right
          verticalCenter: parent.verticalCenter
          margins: Style.space(8)
        }
        spacing: Style.space(8)

      // Multiline scrollable text area
      QQC.ScrollView {
        id: scroll
        width: parent.width - actionsRow.width - Style.space(12)
        height: Math.max(Style.space(28), Math.min(Style.space(100), inputArea.implicitHeight))
        clip: true

        QQC.TextArea {
          id: inputArea
          width: scroll.width
          placeholderText: root.isRecording ? "Listening... (Click mic to finish)" : (root.isTranscribing ? "Transcribing speech..." : root.placeholderText)
          placeholderTextColor: root.isRecording ? Color.urgent : Qt.darker(Color.foreground, 1.6)
          font.family: Style.font.family
          font.pixelSize: Style.font.body
          color: Color.popups.text
          selectionColor: Style.selectionFill
          selectedTextColor: Color.popups.text
          wrapMode: TextEdit.Wrap
          background: null
          leftPadding: Style.space(4)
          rightPadding: Style.space(4)
          topPadding: Style.space(4)
          bottomPadding: Style.space(4)

          Keys.onPressed: function(event) {
            if (event.key === Qt.Key_Return || event.key === Qt.Key_Enter) {
              if (event.modifiers & Qt.ShiftModifier) {
                // Allow Shift+Enter to create a new line
                event.accepted = false
              } else {
                event.accepted = true
                root.submit()
              }
            }
          }
        }
      }

      // Action Buttons Row (Voice + Clear + Send/Stop)
      Row {
        id: actionsRow
        anchors.verticalCenter: parent.verticalCenter
        spacing: Style.space(6)

        // Microphone / Voice Input Button
        Rectangle {
          width: Style.space(30)
          height: Style.space(30)
          radius: Style.cornerRadius > 0 ? Style.cornerRadius / 2 : Style.space(6)
          color: root.isRecording
            ? Util.alpha(Color.urgent, 0.25)
            : (root.isTranscribing ? Util.alpha(Color.accent, 0.2) : (micMouse.containsMouse ? Style.hoverFill : "transparent"))
          border.width: 1
          border.color: root.isRecording ? Color.urgent : (micMouse.containsMouse ? Style.hoverBorderColor : "transparent")

          Text {
            anchors.centerIn: parent
            text: root.isRecording ? "󰍭" : (root.isTranscribing ? "…" : "󰍬")
            font.family: Style.font.family
            font.pixelSize: Style.font.body
            color: root.isRecording ? Color.urgent : (micMouse.containsMouse ? Color.accent : Color.muted)
          }

          SequentialAnimation on opacity {
            running: root.isRecording
            loops: Animation.Infinite
            NumberAnimation { from: 1.0; to: 0.3; duration: 450; easing.type: Easing.InOutQuad }
            NumberAnimation { from: 0.3; to: 1.0; duration: 450; easing.type: Easing.InOutQuad }
          }

          MouseArea {
            id: micMouse
            anchors.fill: parent
            hoverEnabled: true
            cursorShape: Qt.PointingHandCursor
            onClicked: root.toggleRecording()
          }
        }

        // Clear Conversation Button
        Rectangle {
          width: Style.space(30)
          height: Style.space(30)
          radius: Style.cornerRadius > 0 ? Style.cornerRadius / 2 : Style.space(6)
          color: clearMouse.containsMouse ? Style.hoverFill : "transparent"
          border.width: 1
          border.color: clearMouse.containsMouse ? Style.hoverBorderColor : "transparent"

          Text {
            anchors.centerIn: parent
            text: "🧹"
            font.family: Style.font.family
            font.pixelSize: Style.font.body
            color: clearMouse.containsMouse ? Color.accent : Color.muted
          }

          MouseArea {
            id: clearMouse
            anchors.fill: parent
            hoverEnabled: true
            cursorShape: Qt.PointingHandCursor
            onClicked: root.clearRequested()
          }
        }

        // Send / Stop Generation Button
        Rectangle {
          width: Style.space(32)
          height: Style.space(32)
          radius: Style.cornerRadius > 0 ? Style.cornerRadius / 2 : Style.space(6)
          color: root.isGenerating
            ? Util.alpha(Color.urgent, 0.25)
            : (sendMouse.containsMouse ? Util.alpha(Color.accent, 0.25) : Color.accent)
          border.width: 1
          border.color: root.isGenerating ? Color.urgent : Color.accent

          Text {
            anchors.centerIn: parent
            text: root.isGenerating ? "󰙦" : "󰒭"
            font.family: Style.font.family
            font.pixelSize: Style.font.title
            color: root.isGenerating ? Color.urgent : Color.background
          }

          MouseArea {
            id: sendMouse
            anchors.fill: parent
            hoverEnabled: true
            cursorShape: Qt.PointingHandCursor
            onClicked: root.submit()
          }
        }
      }
    }
  }
}
}

