# Raw dividers, hit areas, and persistence

The positioning and delegate recipes below are for an **app-owned raw `NSSplitView`**, not the split view inside `NSSplitViewController`.

## Coordinate and index discipline

- `isVertical = true`: panes are side by side; use x coordinates and widths.
- `isVertical = false`: panes stack top to bottom; use the split's own coordinates and heights. Do not import a window/screen y coordinate without conversion.
- Divider `i` separates arranged pane `i` from `i + 1`; require at least `i + 2` arranged panes.
- Use `arrangedSubviews` for panes. If `arrangesAllSubviews` is false, an ordinary subview may be decoration.
- `dividerThickness` is layout space. Drawn thickness and draggable hit width are different concerns.

For two expanded side-by-side panes with split bounds starting at zero, leading minimum `L`, trailing minimum `R`, total width `W`, divider thickness `D`, the simple feasible divider interval is `[L, W - D - R]`. With a nonzero bounds origin, offset into that coordinate system. More panes, hidden dividers, collapse, or custom policies need their own calculation.

Do not silently clamp into an inverted interval. `L > W - D - R` means the layout is infeasible; resolve the window/minimum/collapse policy first.

## Supported position request

```swift
import AppKit

@MainActor
func requestRawDividerPosition(
    _ requested: CGFloat,
    divider index: Int,
    in splitView: NSSplitView
) {
    guard requested.isFinite,
          index >= 0,
          index + 1 < splitView.arrangedSubviews.count else { return }

    let lower = splitView.minPossiblePositionOfDivider(at: index)
    let upper = splitView.maxPossiblePositionOfDivider(at: index)
    guard lower <= upper else { return } // Caller must resolve infeasible sizing.
    splitView.setPosition(min(max(requested, lower), upper), ofDividerAt: index)
}
```

Call after useful bounds and constraints exist. `setPosition` behaves as if the divider were dragged; it may collapse an adjacent pane when constraints require it. It is not guaranteed to preserve the requested width exactly.

Apple documents that `NSSplitView` does not invoke `setPosition` itself. Overriding that setter will **not** intercept every user drag. Observe resizing or use delegate constraints for actual interaction policy.

Use `constrainMinCoordinate` and `constrainMaxCoordinate` to establish legal edges, and `constrainSplitPosition` for a special snapping rule. Use a small snap tolerance if snapping is desired; snapping every drag coordinate to a coarse grid produces visible stepping. Avoid reentering `setPosition` from a constraint delegate callback.

## Raw collapse semantics

`splitView(_:canCollapseSubview:)` allows user collapse. Its documented drag threshold is halfway between the view's minimum size and its edge. Apple requires the minimum-coordinate delegate method for a subview to collapse; pair min/max constraints with this policy deliberately.

A collapsed raw subview is retained and may retain its prior size. Do not infer collapse only from `frame.width == 0`; query `isSubviewCollapsed(_:)`. Do not infer user visibility intent solely from `isHidden`.

In a controller-managed implementation, use item `isCollapsed`, `canCollapse`, and controller overrides that call `super`, rather than installing this raw delegate.

## Thin appearance with a usable hit area

Start with the system `.thin` divider, which already proposes a hit area larger than its drawn rectangle. If widening it further, modify the proposed rectangle instead of throwing the default away:

```swift
import AppKit

@MainActor
final class RawDividerHitAreaDelegate: NSObject, NSSplitViewDelegate {
    func splitView(
        _ splitView: NSSplitView,
        effectiveRect proposedEffectiveRect: NSRect,
        forDrawnRect drawnRect: NSRect,
        ofDividerAt dividerIndex: Int
    ) -> NSRect {
        let expanded = splitView.isVertical
            ? proposedEffectiveRect.insetBy(dx: -2, dy: 0)
            : proposedEffectiveRect.insetBy(dx: 0, dy: -2)
        return expanded.intersection(splitView.bounds)
    }
}
```

The raw split owner must retain the delegate because `delegate` is weak. The 2-point expansion is an example, not an accessibility standard. Inspect neighboring selection/scroll controls so a generous hit target does not steal their mouse events.

`additionalEffectiveRectOfDividerAt` can add a separate drag handle. Convert the handle's rectangle into split coordinates with view conversion APIs. Return zero when unavailable; do not use a stale frame after layout changes.

If subclassing for drawing, override `drawDivider(in:)` and use the supplied rectangle. Custom `dividerThickness` changes the layout budget. Use semantic separator colors. For a one-device-pixel treatment, align using backing-coordinate conversions rather than assuming every screen is 2x; reevaluate after moving windows between displays.

## Restoration: choose one owner

### Native autosave

Set a stable, nonempty `autosaveName` to let AppKit save divider configuration. A nil or empty value disables it. Keep the name stable for the same layout meaning; version it if pane order or constraints change materially.

For multiple documents/windows, decide whether widths are shared preferences or independent per-window state. Do not accidentally make every window overwrite a single global geometry preference if independent widths are expected.

### App-owned restoration

Use app-owned state when widths are document-specific or need custom migration. Store semantic pane IDs and finite dimensions, not only divider indexes that may shift after a feature adds a pane.

Suggested state:

```text
layoutVersion
sidebarPreferredExpandedWidth
inspectorPreferredExpandedWidth
userRequestedSidebarVisible
userRequestedInspectorVisible
```

Restore after valid bounds exist, clamp to the current feasible range, and apply once per restoration lifecycle. A saved width is a preference from a different window/screen context, not a permanent required constraint.

Persist the last meaningful **expanded** width; avoid replacing it with a collapsed zero or an in-flight sample. Distinguish automatic temporary collapse from an explicit user visibility choice. Do not continuously enforce a restored width from `layout()`, `viewDidLayout()`, or `updateNSViewController`.

`splitViewDidResizeSubviews` may occur for initial layout, live resize, collapse animation, and programmatic changes. It has no “user finished dragging” guarantee. For custom persistence, coalesce observation and save when stable or at a known lifecycle boundary. A debounce can reduce disk writes; it is not an animation-completion API. `inLiveResize` concerns live resize and is not a universal divider-drag detector.

## Insets and live resize details

During interactive dragging, let geometry track the pointer directly. Adding a spring to every divider sample creates lag. If a snap-to-rest effect is required, animate the release/snap separately using an ownership model that supports it.

Keep expensive content work out of resize delegates. Update lightweight layout; coalesce expensive rendering independently. If a raw `resizeSubviews(withOldSize:)` override takes over the algorithm, it must maintain all pane frames and divider budget consistently—do not mix it with an unrelated Auto Layout policy.

Sources: [position](https://developer.apple.com/documentation/appkit/nssplitview/setposition(_:ofdividerat:)), [delegate](https://developer.apple.com/documentation/appkit/nssplitviewdelegate), [effective rectangle](https://developer.apple.com/documentation/appkit/nssplitviewdelegate/splitview(_:effectiverect:fordrawnrect:ofdividerat:)), [autosave](https://developer.apple.com/documentation/appkit/nssplitview/autosavename-swift.property).
