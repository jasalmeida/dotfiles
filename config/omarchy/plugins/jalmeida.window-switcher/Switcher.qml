import QtQuick
import Quickshell
import Quickshell.Hyprland
import Quickshell.Wayland
import qs.Commons
import qs.Commons as Commons
import qs.Ui

// Alt+Tab overlay: a row of window icons, most recently used first, with the
// selected one highlighted. window-cycle summons it on every Tab press with
// {"windows": [{address, class, title}, ...], "index": n} and hides it when
// Alt is released. It only appears once Alt has been held for showDelay, so a
// quick Alt+Tab toggle doesn't flash it.
Item {
  id: root

  property bool opened: false
  property bool wanted: false
  property var windows: []
  property int index: 0

  readonly property int iconSize: Style.space(56)
  readonly property int cell: iconSize + Style.space(28)
  readonly property int pad: Style.space(16)
  readonly property int titleGap: Style.space(12)
  readonly property var selected: windows.length > 0 ? windows[Math.min(index, windows.length - 1)] : null

  // Window classes with no desktop entry of their own, mapped to one that fits
  readonly property var classAliases: ({ "org.omarchy.terminal": "foot" })

  function iconFor(windowClass) {
    var cls = String(windowClass || "")
    cls = classAliases[cls] || cls
    var entry = cls ? DesktopEntries.heuristicLookup(cls) : null
    var name = entry && entry.icon ? entry.icon : cls.toLowerCase()
    var path = name ? Quickshell.iconPath(name, true) : ""
    return path || Quickshell.iconPath("application-x-executable", true)
  }

  function open(payloadJson) {
    try {
      var p = JSON.parse(payloadJson || "{}")
      windows = Array.isArray(p.windows) ? p.windows : []
      index = p.index || 0
    } catch (e) {
      return
    }
    wanted = true
    if (!opened && !showDelay.running) showDelay.restart()
  }

  function close() {
    wanted = false
    showDelay.stop()
    opened = false
  }

  Timer {
    id: showDelay
    interval: 120
    onTriggered: if (root.wanted) root.opened = true
  }

  PanelWindow {
    id: panel
    visible: root.opened
    screen: {
      var name = Hyprland.focusedMonitor ? Hyprland.focusedMonitor.name : ""
      var screens = Quickshell.screens
      for (var i = 0; i < screens.length; i++) if (screens[i].name === name) return screens[i]
      return screens.length ? screens[0] : null
    }
    anchors { top: true; bottom: true; left: true; right: true }
    color: "transparent"
    WlrLayershell.namespace: "jalmeida-window-switcher"
    WlrLayershell.layer: WlrLayer.Overlay
    WlrLayershell.keyboardFocus: WlrKeyboardFocus.None
    exclusionMode: ExclusionMode.Ignore
    // Visual only: never take clicks from the windows underneath
    mask: Region {}

    BorderSurface {
      id: card
      readonly property int listWidth: Math.min(root.windows.length * root.cell, panel.width * 0.9 - 2 * root.pad)
      width: card.borderLeft + root.pad + listWidth + root.pad + card.borderRight
      height: card.borderTop + root.pad + root.cell + root.titleGap + titleText.height + root.pad + card.borderBottom
      anchors.centerIn: parent
      color: Util.alpha(Commons.Color.background, 0.95)
      borderSpec: Border.surfaceSpec("popups", "border", Commons.Color.popups.border, Math.max(1, Style.space(2)))
      radius: Style.cornerRadius

      ListView {
        id: list
        x: card.borderLeft + root.pad
        y: card.borderTop + root.pad
        width: card.listWidth
        height: root.cell
        orientation: ListView.Horizontal
        interactive: false
        model: root.windows
        currentIndex: root.index
        highlightMoveDuration: 0
        // Keep the selection in view when there are more windows than fit
        highlightRangeMode: ListView.ApplyRange
        preferredHighlightBegin: root.cell
        preferredHighlightEnd: width - root.cell

        highlight: Rectangle {
          width: root.cell
          height: root.cell
          radius: Style.cornerRadius
          color: Util.alpha(Commons.Color.accent, 0.25)
          border.color: Commons.Color.accent
          border.width: Math.max(1, Style.space(2))
        }

        delegate: Item {
          required property var modelData
          width: root.cell
          height: root.cell

          Image {
            anchors.centerIn: parent
            width: root.iconSize
            height: root.iconSize
            sourceSize.width: root.iconSize
            sourceSize.height: root.iconSize
            source: root.iconFor(modelData.class)
            fillMode: Image.PreserveAspectFit
            smooth: true
            asynchronous: true
          }
        }
      }

      Text {
        id: titleText
        x: card.borderLeft + root.pad
        y: list.y + list.height + root.titleGap
        width: card.listWidth
        horizontalAlignment: Text.AlignHCenter
        textFormat: Text.PlainText
        text: root.selected ? root.selected.title || root.selected.class || "" : ""
        font.family: Style.font.family
        font.bold: true
        font.pixelSize: Style.font.title
        color: Commons.Color.popups.text
        elide: Text.ElideRight
        maximumLineCount: 1
      }
    }
  }
}
