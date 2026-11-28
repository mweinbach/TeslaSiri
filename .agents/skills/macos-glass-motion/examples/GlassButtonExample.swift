import AppKit

/// Reference construction, not an additional Commander app-target component.
/// The caller owns this view's placement. Move this whole view when following
/// another control; don't independently animate its button and glass.
@available(macOS 26.0, *)
@MainActor
final class GlassButtonExample: NSView {
    let button = NSButton()
    let glass = NSGlassEffectView()
    private let onPress: @MainActor () -> Void

    init(
        symbol: String,
        accessibilityLabel: String,
        accessibilityIdentifier: String,
        onPress: @escaping @MainActor () -> Void
    ) {
        self.onPress = onPress
        super.init(frame: NSRect(x: 0, y: 0, width: 36, height: 36))

        button.image = NSImage(systemSymbolName: symbol, accessibilityDescription: nil)
        button.imagePosition = .imageOnly
        button.symbolConfiguration = NSImage.SymbolConfiguration(pointSize: 16, weight: .regular)
        button.bezelStyle = .circular
        button.isBordered = false
        button.setButtonType(.momentaryPushIn)
        button.setAccessibilityLabel(accessibilityLabel)
        button.setAccessibilityIdentifier(accessibilityIdentifier)
        button.frame = bounds
        button.autoresizingMask = [.width, .height]
        button.target = self
        button.action = #selector(performAction(_:))

        glass.frame = bounds
        glass.style = .regular
        glass.cornerRadius = 18
        if #available(macOS 27.0, *) {
            glass.effectIsInteractive = true
        }
        glass.contentView = button
        addSubview(glass)
    }

    required init?(coder: NSCoder) { nil }

    override func layout() {
        super.layout()
        glass.frame = bounds
        glass.cornerRadius = min(bounds.width, bounds.height) / 2
    }

    @objc private func performAction(_ sender: Any?) {
        onPress()
    }
}
