import QtQuick
import QtQuick.Layouts
import QtQuick.Controls as QQC
import Quickshell
import qs.Commons
import qs.Ui
import "js/Api.js" as Api

// Model selector component supporting dynamic online fetching (OpenRouter, Ollama, OpenAI, Gemini),
// live search/filtering, free-tier highlighting, and custom manual model overrides.
Item {
  id: root

  property string providerId: "openrouter"
  property string endpoint: ""
  property string apiKey: ""
  property string selectedModel: ""
  property var defaultModels: []

  // Dynamic model list fetched online or fallback defaults
  property var fetchedModels: []
  property bool isFetching: false
  property string fetchError: ""
  property string filterText: ""
  property bool freeOnlyFilter: false

  signal modelSelected(string modelName)

  implicitWidth: parent ? parent.width : Style.space(480)
  implicitHeight: mainCol.implicitHeight

  // Active list of all available models (fetched online if present, else defaults)
  readonly property var activeModelList: {
    if (root.fetchedModels && root.fetchedModels.length > 0) {
      return root.fetchedModels
    }
    return root.defaultModels && root.defaultModels.length > 0 ? root.defaultModels : []
  }

  // Filtered model list based on search and free filter
  readonly property var filteredModels: {
    var all = root.activeModelList
    if (!all || all.length === 0) return []
    var query = root.filterText.trim().toLowerCase()
    var result = []
    for (var i = 0; i < all.length; i++) {
      var m = all[i]
      if (typeof m !== "string") continue
      if (root.freeOnlyFilter && m.indexOf(":free") === -1) continue
      if (query !== "" && m.toLowerCase().indexOf(query) === -1) continue
      result.push(m)
    }
    return result
  }

  // Count of free models
  readonly property int freeModelsCount: {
    var all = root.activeModelList
    if (!all) return 0
    var count = 0
    for (var i = 0; i < all.length; i++) {
      if (typeof all[i] === "string" && all[i].indexOf(":free") !== -1) {
        count++
      }
    }
    return count
  }

  Component.onCompleted: {
    if (root.providerId === "ollama" || (root.apiKey && root.apiKey.trim().length > 0)) {
      root.fetchOnlineModels()
    }
  }

  onApiKeyChanged: {
    if (root.apiKey && root.apiKey.trim().length > 0 && root.fetchedModels.length === 0) {
      root.fetchOnlineModels()
    }
  }

  onProviderIdChanged: {
    root.fetchedModels = []
    root.fetchError = ""
    root.filterText = ""
    if (root.providerId === "ollama" || (root.apiKey && root.apiKey.trim().length > 0)) {
      root.fetchOnlineModels()
    }
  }

  function fetchOnlineModels() {
    if (root.isFetching) return
    root.isFetching = true
    root.fetchError = ""

    Api.fetchModels(root.providerId, root.endpoint, root.apiKey, function(err, list) {
      root.isFetching = false
      if (err) {
        root.fetchError = err
      } else if (list && list.length > 0) {
        root.fetchedModels = list
        root.fetchError = ""
      } else {
        root.fetchError = "No models found from " + root.providerId
      }
    })
  }

  function selectModel(modelName) {
    if (!modelName) return
    root.selectedModel = modelName
    root.modelSelected(modelName)
  }

  Column {
    id: mainCol
    width: parent.width
    spacing: Style.space(8)

    // 1. Header row: Title + Fetch Button
    Row {
      width: parent.width
      spacing: Style.space(8)

      Text {
        anchors.verticalCenter: parent.verticalCenter
        text: "Model Selection:"
        font.family: Style.font.family
        font.pixelSize: Style.font.bodySmall
        font.weight: Font.DemiBold
        color: Color.muted
      }

      Item {
        // Spacer
        width: parent.width - (parent.children[0].implicitWidth + fetchBtn.implicitWidth + Style.space(16))
        height: 1
      }

      Button {
        id: fetchBtn
        anchors.verticalCenter: parent.verticalCenter
        text: root.isFetching ? "󰑐 Fetching..." : "󰑐 Fetch Online Models"
        tooltipText: "Fetch available models live from " + root.providerId
        onClicked: root.fetchOnlineModels()
      }
    }

    // 2. Active Model Status Card
    Rectangle {
      width: parent.width
      height: Style.space(34)
      radius: Style.cornerRadius > 0 ? Style.cornerRadius : Style.space(6)
      color: Util.alpha(Color.accent, 0.08)
      border.width: 1
      border.color: Util.alpha(Color.accent, 0.3)

      Row {
        anchors.fill: parent
        anchors.leftMargin: Style.space(10)
        anchors.rightMargin: Style.space(10)
        spacing: Style.space(8)

        Text {
          anchors.verticalCenter: parent.verticalCenter
          text: "Active Model:"
          font.family: Style.font.family
          font.pixelSize: Style.font.caption
          font.weight: Font.DemiBold
          color: Color.muted
        }

        Text {
          anchors.verticalCenter: parent.verticalCenter
          text: root.selectedModel || "(None selected)"
          font.family: Style.font.family
          font.pixelSize: Style.font.bodySmall
          font.weight: Font.Bold
          color: Color.accent
          elide: Text.ElideMiddle
          width: Math.min(implicitWidth, parent.width - Style.space(160))
        }

        Item {
          width: 1
          height: 1
          Layout.fillWidth: true
        }

        // Free badge if active model is free
        Rectangle {
          anchors.verticalCenter: parent.verticalCenter
          visible: root.selectedModel.indexOf(":free") !== -1
          width: freeText.implicitWidth + Style.space(8)
          height: Style.space(18)
          radius: Style.space(4)
          color: Util.alpha("#a6e3a1", 0.2)
          border.width: 1
          border.color: "#a6e3a1"

          Text {
            id: freeText
            anchors.centerIn: parent
            text: "FREE"
            font.family: Style.font.family
            font.pixelSize: Style.font.caption
            font.weight: Font.Bold
            color: "#a6e3a1"
          }
        }
      }
    }

    // 3. Status or Error Banner
    Item {
      width: parent.width
      height: statusText.implicitHeight
      visible: root.fetchError !== "" || root.fetchedModels.length > 0

      Text {
        id: statusText
        width: parent.width
        text: root.fetchError !== ""
          ? ("⚠ " + root.fetchError)
          : ("✔ Loaded " + root.fetchedModels.length + " online models" + (root.freeModelsCount > 0 ? " (" + root.freeModelsCount + " free tier)" : ""))
        font.family: Style.font.family
        font.pixelSize: Style.font.caption
        color: root.fetchError !== "" ? Color.urgent : "#a6e3a1"
        wrapMode: Text.Wrap
      }
    }

    // 4. Search Filter & Free Filter Bar
    Row {
      width: parent.width
      spacing: Style.space(6)

      TextField {
        id: searchField
        width: parent.width - (root.freeModelsCount > 0 ? Style.space(110) : 0)
        placeholderText: "󰍉 Search models (" + root.activeModelList.length + " available)..."
        text: root.filterText
        onTextChanged: root.filterText = text
      }

      Button {
        visible: root.freeModelsCount > 0
        width: Style.space(104)
        text: root.freeOnlyFilter ? "★ Free Only" : "☆ All Models"
        active: root.freeOnlyFilter
        onClicked: root.freeOnlyFilter = !root.freeOnlyFilter
      }
    }

    // 5. Scrollable Model Selection List
    Rectangle {
      width: parent.width
      height: Style.space(180)
      radius: Style.cornerRadius > 0 ? Style.cornerRadius : Style.space(6)
      color: Style.normalFill
      border.width: 1
      border.color: Style.normalBorderColor
      clip: true

      QQC.ScrollView {
        anchors.fill: parent
        clip: true

        ListView {
          id: modelsListView
          width: parent.width
          model: root.filteredModels
          boundsBehavior: Flickable.StopAtBounds

          delegate: Rectangle {
            id: rowDelegate
            required property var modelData
            required property int index

            readonly property string itemModelName: String(rowDelegate.modelData || "")
            readonly property bool isCurrent: root.selectedModel === itemModelName
            readonly property bool isFree: itemModelName.indexOf(":free") !== -1
            readonly property bool isRecommended: itemModelName === "nvidia/nemotron-3.5-lightning:free" || itemModelName === "liquid/lfm-2.5-2.6b:free" || itemModelName === "nex-agi/nex-n2.5-mini:free" || itemModelName === "inclusionai/ling-3.0-flash-fin:free"

            width: modelsListView.width
            height: Style.space(28)
            color: rowMouse.containsMouse
              ? Util.alpha(Color.accent, 0.15)
              : (rowDelegate.isCurrent ? Util.alpha(Color.accent, 0.08) : "transparent")

            MouseArea {
              id: rowMouse
              anchors.fill: parent
              hoverEnabled: true
              cursorShape: Qt.PointingHandCursor
              onClicked: root.selectModel(rowDelegate.itemModelName)
            }

            Row {
              anchors.fill: parent
              anchors.leftMargin: Style.space(8)
              anchors.rightMargin: Style.space(8)
              spacing: Style.space(6)

              Text {
                anchors.verticalCenter: parent.verticalCenter
                text: rowDelegate.isCurrent ? "󰄲" : "  "
                font.family: Style.font.family
                font.pixelSize: Style.font.bodySmall
                color: Color.accent
              }

              Text {
                anchors.verticalCenter: parent.verticalCenter
                text: rowDelegate.itemModelName
                font.family: Style.font.family
                font.pixelSize: Style.font.bodySmall
                font.weight: rowDelegate.isCurrent ? Font.Bold : Font.Normal
                color: rowDelegate.isCurrent ? Color.accent : Color.popups.text
                elide: Text.ElideMiddle
                width: parent.width - (rowDelegate.isRecommended ? Style.space(150) : (rowDelegate.isFree ? Style.space(80) : Style.space(30)))
              }

              Rectangle {
                anchors.verticalCenter: parent.verticalCenter
                visible: rowDelegate.isRecommended
                width: recText.implicitWidth + Style.space(6)
                height: Style.space(16)
                radius: Style.space(3)
                color: Util.alpha(Color.accent, 0.2)
                border.width: 1
                border.color: Color.accent

                Text {
                  id: recText
                  anchors.centerIn: parent
                  text: "★ VERIFIED"
                  font.family: Style.font.family
                  font.pixelSize: Style.font.caption
                  font.weight: Font.DemiBold
                  color: Color.accent
                }
              }

              Rectangle {
                anchors.verticalCenter: parent.verticalCenter
                visible: rowDelegate.isFree && !rowDelegate.isRecommended
                width: badgeText.implicitWidth + Style.space(6)
                height: Style.space(16)
                radius: Style.space(3)
                color: Util.alpha("#a6e3a1", 0.15)
                border.width: 1
                border.color: Util.alpha("#a6e3a1", 0.5)

                Text {
                  id: badgeText
                  anchors.centerIn: parent
                  text: "FREE"
                  font.family: Style.font.family
                  font.pixelSize: Style.font.caption
                  font.weight: Font.DemiBold
                  color: "#a6e3a1"
                }
              }
            }
          }

          // Empty filtered view
          Item {
            anchors.centerIn: parent
            visible: root.filteredModels.length === 0
            width: parent.width
            height: Style.space(60)

            Column {
              anchors.centerIn: parent
              spacing: Style.space(4)

              Text {
                anchors.horizontalCenter: parent.horizontalCenter
                text: "No models match filter"
                font.family: Style.font.family
                font.pixelSize: Style.font.caption
                color: Color.muted
              }

              Button {
                anchors.horizontalCenter: parent.horizontalCenter
                text: "Clear Filter"
                onClicked: {
                  root.filterText = ""
                  root.freeOnlyFilter = false
                }
              }
            }
          }
        }
      }
    }

    // 6. Manual Custom Model Override Entry
    Row {
      width: parent.width
      spacing: Style.space(6)

      TextField {
        id: manualField
        width: parent.width - Style.space(80)
        placeholderText: "Or type custom model name..."
        text: root.selectedModel
      }

      Button {
        width: Style.space(74)
        text: "Apply"
        onClicked: {
          var val = manualField.text.trim()
          if (val !== "") {
            root.selectModel(val)
          }
        }
      }
    }
  }
}
