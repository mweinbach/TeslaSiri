# Split-view source ledger

Research date: 2026-09-13. Primary retrieval: Xcode MCP `DocumentationSearch`; declaration checks: Xcode 27.0 (27A266a), macOS SDK. Recommendations in this skill are project-authored.

| Source | What it establishes |
| --- | --- |
| [NSSplitViewController](https://developer.apple.com/documentation/appkit/nssplitviewcontroller) | Controller is delegate; overrides call super; Auto Layout and lazy loading |
| [Controller splitView](https://developer.apple.com/documentation/appkit/nssplitviewcontroller/splitview) | Ownership restrictions; custom split supplied before superclass view loading |
| [NSSplitViewItem](https://developer.apple.com/documentation/appkit/nssplitviewitem) | Pane model and property families |
| [holdingPriority](https://developer.apple.com/documentation/appkit/nssplitviewitem/holdingpriority) | Lowest priority absorbs size changes first; default low |
| [minimumThickness](https://developer.apple.com/documentation/appkit/nssplitviewitem/minimumthickness) | Descendant constraints can still impose minima |
| [maximumThickness](https://developer.apple.com/documentation/appkit/nssplitviewitem/maximumthickness) | Explicit and descendant maxima |
| [preferredThicknessFraction](https://developer.apple.com/documentation/appkit/nssplitviewitem/preferredthicknessfraction) | Double-click/full-screen sizing rather than an exact initial width |
| [automaticMaximumThickness](https://developer.apple.com/documentation/appkit/nssplitviewitem/automaticmaximumthickness) | Automatic cap differs from user drag cap |
| [fixed split preference](https://developer.apple.com/documentation/appkit/nssplitviewitem/collapsebehavior-swift.enum/preferresizingsiblingswithfixedsplitview) | Can break when sibling minima cannot fit |
| [fixed siblings preference](https://developer.apple.com/documentation/appkit/nssplitviewitem/collapsebehavior-swift.enum/preferresizingsplitviewwithfixedsiblings) | Window resize preference and full-screen/onscreen exceptions |
| [constraint collapse](https://developer.apple.com/documentation/appkit/nssplitviewitem/collapsebehavior-swift.enum/useconstraints) | Holding-priority animation; potential mixed window/content resizing |
| [canCollapseFromWindowResize](https://developer.apple.com/documentation/appkit/nssplitviewitem/cancollapsefromwindowresize) | Distinct policy; setting sidebar canCollapse resets it |
| [inspector initializer](https://developer.apple.com/documentation/appkit/nssplitviewitem/init(inspectorwithviewcontroller:)) | macOS 14+ inspector defaults |
| [minimumThicknessForInlineSidebars](https://developer.apple.com/documentation/appkit/nssplitviewcontroller/minimumthicknessforinlinesidebars) | Autocollapse, constraints, full-screen overlay |
| [setPosition](https://developer.apple.com/documentation/appkit/nssplitview/setposition(_:ofdividerat:)) | Drag-like behavior; AppKit does not call the method itself |
| [NSSplitViewDelegate](https://developer.apple.com/documentation/appkit/nssplitviewdelegate) | Min/max/snapping, collapse, effective hit areas, resize observation |
| [autosaveName](https://developer.apple.com/documentation/appkit/nssplitview/autosavename-swift.property) | Named automatic divider saving |
| [NavigationSplitView](https://developer.apple.com/documentation/swiftui/navigationsplitview) | Public SwiftUI navigation surface |
| [controller context animation](https://developer.apple.com/documentation/swiftui/nsviewcontrollerrepresentablecontext/animate(changes:completion:)) | Shared transaction animation; SDK minimum macOS 15.0 |

## Availability discipline

The controller example uses a macOS 14 baseline, with its direct SwiftUI spring method marked macOS 15+. It does not imply every listed API was introduced in 14. Newer overlay or appearance behavior must be rechecked before adoption.

## Relationship to existing skills

`swiftui-specialist` remains the source for Apple's SwiftUI identity/dataflow/custom-`Animatable` guidance. This split-view skill supplies AppKit-specific ownership and geometry details absent from that reference set.

For motion, read [AppKit animation control](../../appkit-animation-control/SKILL.md) or [SwiftUI animation control](../../swiftui-animation-control/SKILL.md) only when the task needs that layer.
