import AppKit
import MenubarCore

/// Owns the menubar item. macOS mirrors one status item onto every display's menubar, so the label
/// shows all monitors and emphasises the focused one.
@MainActor
final class StatusItemController {
    private let item = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)
    private let fontSize = NSFont.systemFontSize

    init(menu: NSMenu) {
        // A stable, unique name (instead of the default "Item-0") so macOS and menubar managers
        // like Thaw/Ice can remember this item's position and section.
        item.autosaveName = "com.zepocas.komorebi-menubar.workspace"
        item.menu = menu
        showDisconnected()
    }

    func show(_ label: WorkspaceLabel) {
        guard let button = item.button else { return }

        let focused: [NSAttributedString.Key: Any] = [
            .font: NSFont.monospacedDigitSystemFont(ofSize: fontSize, weight: .bold),
            .foregroundColor: NSColor.labelColor,
        ]
        let unfocused: [NSAttributedString.Key: Any] = [
            .font: NSFont.monospacedDigitSystemFont(ofSize: fontSize, weight: .regular),
            .foregroundColor: NSColor.secondaryLabelColor,
        ]
        let separator: [NSAttributedString.Key: Any] = [
            .font: NSFont.systemFont(ofSize: fontSize, weight: .light),
            .foregroundColor: NSColor.tertiaryLabelColor,
        ]

        let title = NSMutableAttributedString()
        for (index, segment) in label.segments.enumerated() {
            if index > 0 {
                title.append(NSAttributedString(string: WorkspaceLabel.separator, attributes: separator))
            }
            title.append(NSAttributedString(string: segment.text, attributes: segment.isFocusedMonitor ? focused : unfocused))
        }

        button.image = nil
        button.appearsDisabled = false
        button.attributedTitle = title
        button.toolTip = "komorebi workspace: \(label.plainText)"
    }

    func showDisconnected() {
        guard let button = item.button else { return }
        button.attributedTitle = NSAttributedString()
        button.image = NSImage(systemSymbolName: "rectangle.split.2x1", accessibilityDescription: "komorebi is not running")
        button.appearsDisabled = true
        button.toolTip = "komorebi is not running"
    }
}
