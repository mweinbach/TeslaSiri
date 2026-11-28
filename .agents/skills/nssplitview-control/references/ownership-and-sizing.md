# Ownership, sizing, and collapse

## Choose the abstraction by the control you need

| Owner | Good fit | Control boundary |
| --- | --- | --- |
| `NavigationSplitView` | SwiftUI navigation, column visibility, preferred column widths | No public arbitrary divider-position or AppKit collapse-policy binding |
| `NSSplitViewController` | Native sidebar/content/inspector with explicit constraints and collapse policy | Controller owns delegate, arrangement, and Auto Layout integration |
| Raw `NSSplitView` | Custom divider algorithms, snapping, specialized split layout | App owns delegate, sizing policy, persistence, and collapse integration |

Do not introspect a SwiftUI-generated view hierarchy and depend on its private structure as the default implementation strategy. If exact AppKit policy is a product requirement, explicitly host an app-owned controller.

Apple's `NSSplitViewController.splitView` documentation permits attribute customization but explicitly warns against changing the delegate or calling split-view methods through it. Keep low-level arrangement/positioning recipes in the raw-split path. Use controller item APIs for managed panes. This avoids relying on a method that happens to work in one OS build.

## What each sizing input actually means

| Input | Meaning | Common mistake |
| --- | --- | --- |
| `minimumThickness` | Pane minimum on the split axis | Assuming unspecified means content has no minimum |
| `maximumThickness` | Pane maximum on the split axis | Forgetting descendants can impose additional limits |
| `holdingPriority` | Relative resistance to changing thickness | Setting every pane to required or treating it as a width |
| `preferredThicknessFraction` | Preferred fraction used for operations including double-click and entering full screen | Reapplying it each layout to force an initial width |
| `automaticMaximumThickness` | Cap for automatic sizing | Assuming it also caps user dragging; `maximumThickness` does that |
| Child constraints | Content's actual fitting behavior | Looking only at item properties and overlooking text/hosting minima |

For sidebar + document + inspector, a useful starting policy is higher holding priorities on ancillary panes and lower on the document. For example, sidebar 260, document 250, inspector 270. These are engineering starting values, not Apple-prescribed constants. Distinct priorities make resize intent explicit; required content constraints still win.

Use `NSSplitViewItem(sidebarWithViewController:)` for a semantic sidebar and `NSSplitViewItem(inspectorWithViewController:)` for an inspector. On macOS 14+, the inspector initializer defaults to a collapsible, fixed 270-point inspector. Set minimum and maximum explicitly if it should be resizable.

## Calculate the geometry budget

For a vertical split with all panes visible:

```text
required split width >= sum(effective pane minima) + sum(visible divider thicknesses)
```

“Effective” includes descendant constraints, compression resistance, hosted SwiftUI fitting sizes, and any minimum imposed by enclosing views. Use the split view's available bounds, not the window's outer frame, in this equation. Account for other content chrome separately.

Example: sidebar 240 + document 480 + inspector 270 + two 1-point dividers requires at least 992 points of split width. A 900-point split cannot satisfy these three minima while leaving its size fixed. Choose a policy explicitly:

- collapse or overlay an ancillary pane where supported;
- reduce a content minimum if that content truly works narrower;
- enforce an appropriate window content minimum;
- permit the window to grow when expansion requires it.

Changing easing curves cannot make an infeasible layout fit. A `.frame(maxWidth: .infinity)` in SwiftUI expresses flexibility; it does not erase another required minimum.

## Collapse behavior is a policy

| `NSSplitViewItem.CollapseBehavior` | Intended behavior | Documented qualification |
| --- | --- | --- |
| `.default` | System default | Do not infer a universal window-resize guarantee |
| `.preferResizingSiblingsWithFixedSplitView` | Other panes resize while split size stays fixed | Preference can break when siblings would fall below minima |
| `.preferResizingSplitViewWithFixedSiblings` | Preserve sibling sizes/onscreen positions, potentially resize window | Preference breaks in full screen and to keep window onscreen |
| `.useConstraints` | Constraint animation at the item's holding priority | May partly resize content and window; does not itself keep window onscreen |

`isCollapsed` is the requested/logical collapse state; reading it is not measuring the currently visible animated width. `canCollapse` controls user-interaction collapse, not a blanket ban on setting `isCollapsed` programmatically.

`canCollapseFromWindowResize` is distinct. Sidebars default to allowing resize collapse; inspectors default to disallowing it. Setting `canCollapse` on a sidebar resets `canCollapseFromWindowResize`, so configure in that order.

`isSpringLoaded` relates to temporary expansion during dragging. Do not automatically persist that temporary appearance as the user's durable preference.

For full screen, review `minimumThicknessForInlineSidebars`: the controller can autocollapse sidebars and show them over content when inline minima cannot fit. Newer SDKs also expose overlay/safe-area-related item behavior. Check current documentation and actual runtime behavior before imposing manual insets over the system's adjustments.

## Initial size versus retained user size

An item does not expose an “always use this initial width” property. In a managed layout, use coherent child fitting constraints and a low-priority initial width preference if needed; let restoration and user resizing take ownership afterward. Do not add a required equality to a pane intended to resize.

If you introduce a temporary initial-width constraint:

1. Give it an explicit owner and lower priority than required bounds.
2. Apply it only for a fresh layout, not after a saved layout has restored.
3. Deactivate it once initial sizing is established or when the user takes control.
4. Verify the same layout at the minimum window size.

For exact raw divider positions, see [dividers and persistence](dividers-and-persistence.md). For controller code, see [the example](../examples/ControlledSplitViewController.swift).

## Focus and chrome

If the first responder is inside a pane about to hide, decide whether focus should move to the document, a surviving control, or the sidebar toggle. Use the relevant `NSWindow.makeFirstResponder(_:)`; avoid globally guessing the key window.

Keep toggle commands reachable when the pane is collapsed. Use native responder-chain actions where they fit; for an explicit controller call, target that window's controller. Toolbar item placement and collapse animation are separate concerns—do not rebuild the entire toolbar or controller to change a Boolean.

Sources: [controller](https://developer.apple.com/documentation/appkit/nssplitviewcontroller), [splitView ownership](https://developer.apple.com/documentation/appkit/nssplitviewcontroller/splitview), [holding priority](https://developer.apple.com/documentation/appkit/nssplitviewitem/holdingpriority), [collapse behavior](https://developer.apple.com/documentation/appkit/nssplitviewitem/collapsebehavior-swift.enum), [preferred fraction](https://developer.apple.com/documentation/appkit/nssplitviewitem/preferredthicknessfraction).
