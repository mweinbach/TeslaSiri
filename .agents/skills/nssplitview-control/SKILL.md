---
name: nssplitview-control
description: Design, implement, and debug precise macOS split-pane behavior with NSSplitView, NSSplitViewController, and NSSplitViewItem. Use for divider constraints and hit areas, sidebar or inspector collapse, holding priorities, unexpected window resizing, saved widths, live resize, and SwiftUI hosting or NavigationSplitView limitations.
---

# NSSplitView control

Make pane geometry predictable before tuning its motion. State which object owns the layout and which object owns collapse.

## Workflow

1. Identify whether the app uses SwiftUI `NavigationSplitView`, an app-owned `NSSplitViewController`, or a raw `NSSplitView`.
2. Read [ownership and sizing](references/ownership-and-sizing.md) before changing constraints, collapse behavior, or a window frame.
3. Describe the intended behavior: which pane absorbs resize, whether the window may grow, what happens when minima cannot fit, whether a user may drag-collapse, and how reopening restores width.
4. For raw divider positioning, custom hit areas, or restoration, read [dividers and persistence](references/dividers-and-persistence.md).
5. For hosted SwiftUI and two-way visibility, read [SwiftUI bridging](references/swiftui-bridging.md).
6. For jumps or inconsistent behavior, use [diagnostics](references/diagnostics.md) and inspect the constraint budget before trying a timing workaround.
7. Verify unfamiliar APIs with [Xcode research](references/xcode-research.md); use [sources](references/sources.md) as the query and citation index.

## Non-negotiable engineering rules

- `isVertical = true` means vertical dividers and side-by-side panes. Thickness is width in this configuration.
- A split view controller owns its split view delegate and child arrangement. Add/remove controller panes through split view items. Do not replace its delegate or treat its split view as an independently frame-managed splitter.
- Overrides of the controller's split-view delegate methods must call `super`.
- A holding priority is a relative preference to retain size, not a width or a required minimum. The lowest-priority item absorbs resize first.
- `.preferResizingSiblingsWithFixedSplitView` can be overridden when sibling minima cannot fit. Never describe it as a window-frame lock.
- Do not use `preferredThicknessFraction` as an exact initial-width setter. Its documented uses include divider double-click and entering full screen.
- Assign `canCollapse` before a distinct `canCollapseFromWindowResize` policy; changing the former on a sidebar resets the latter.
- Choose one source of truth for saved divider geometry. Do not restore a width on every layout or representable update.
- Make desired visibility, observed collapse, and animation progress separate concepts. A resize notification is not proof of a user action or animation completion.
- Prefer supported collapse policy and constraints over saving a window frame and restoring it on the next run-loop turn.
- Use only the current view/controller's window; account for independent windows and document lifetimes.

## Implementation assets

- [ControlledSplitViewController.swift](examples/ControlledSplitViewController.swift): app-owned controller, sizing policy, reduced-motion collapse, and SwiftUI spring option. Baseline macOS 14; modern spring path macOS 15.
- Raw divider snippets in the reference explicitly assume a raw split view. Do not paste them into a controller-managed layout.

## Finishing a task

Explain the chosen geometry owner, minimum-width budget, collapse/restoration policy, and any availability branch. Verify narrow/wide windows, repeated reversal, drag to bounds, restored widths, and Reduce Motion when they affect the change. Report observed behavior separately from compiled or documented behavior.

For animation implementation, load `appkit-animation-control`. For SwiftUI transactions or insertion/removal, load `swiftui-animation-control`. Do not bulk-load both unless the change crosses that boundary.
