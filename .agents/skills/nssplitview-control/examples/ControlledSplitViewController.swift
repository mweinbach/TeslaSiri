import AppKit
import SwiftUI

/// App-owned controller; child controllers provide Auto Layout-compatible views.
/// Example policies assume at least 240 + 480 + dividerThickness points to
/// show both panes without violating their explicit minima.
@available(macOS 14.0, *)
@MainActor
final class ControlledSplitViewController: NSSplitViewController {
    let sidebarItem: NSSplitViewItem
    let documentItem: NSSplitViewItem

    init(sidebar: NSViewController, document: NSViewController) {
        sidebarItem = NSSplitViewItem(sidebarWithViewController: sidebar)
        documentItem = NSSplitViewItem(viewController: document)
        super.init(nibName: nil, bundle: nil)
    }

    required init?(coder: NSCoder) {
        fatalError("Create this example with child controllers.")
    }

    override func viewDidLoad() {
        super.viewDidLoad()
        splitView.isVertical = true
        splitView.dividerStyle = .thin

        sidebarItem.minimumThickness = 240
        sidebarItem.maximumThickness = 400
        sidebarItem.holdingPriority = NSLayoutConstraint.Priority(260)
        sidebarItem.canCollapse = true
        // Set after canCollapse, which resets this value for sidebars.
        sidebarItem.canCollapseFromWindowResize = false
        sidebarItem.collapseBehavior = .preferResizingSiblingsWithFixedSplitView

        documentItem.minimumThickness = 480
        documentItem.holdingPriority = .defaultLow

        addSplitViewItem(sidebarItem)
        addSplitViewItem(documentItem)
    }

    /// Classic AppKit animation owns the item collapse.
    func setSidebarCollapsed(_ collapsed: Bool, animated: Bool) {
        _ = view // Establish item configuration before accepting commands.
        guard sidebarItem.isCollapsed != collapsed else { return }

        let reduceMotion = NSWorkspace.shared.accessibilityDisplayShouldReduceMotion
        guard animated && !reduceMotion else {
            sidebarItem.isCollapsed = collapsed
            return
        }

        NSAnimationContext.runAnimationGroup { context in
            context.duration = 0.22 // Product tuning value, not a system constant.
            sidebarItem.animator().isCollapsed = collapsed
        }
    }

    /// Alternative animation engine. Choose this OR the classic method per action.
    @available(macOS 15.0, *)
    func setSidebarCollapsed(_ collapsed: Bool, animation: Animation) {
        _ = view
        guard sidebarItem.isCollapsed != collapsed else { return }
        guard !NSWorkspace.shared.accessibilityDisplayShouldReduceMotion else {
            sidebarItem.isCollapsed = collapsed
            return
        }
        NSAnimationContext.animate(animation) {
            sidebarItem.isCollapsed = collapsed
            view.layoutSubtreeIfNeeded()
        }
    }
}
