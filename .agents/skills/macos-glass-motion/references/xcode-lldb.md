# Xcode MCP and LLDB: repeatable runtime investigation

## Tool discovery and documentation

Use the [shared Xcode research workflow](../../nssplitview-control/references/xcode-research.md) for the complete documentation/SDK process. In a Code Mode harness, discover exact names and signatures:

```javascript
return search({ namespace: "Xcode", query: "InvokeDebuggerCommand", limit: 1 });
```

Relevant tools used in this investigation were `XcodeListWorkspaces`, `DocumentationSearch`, `RunProject`, `StopProject`, `InvokeDebuggerCommand`, `GetConsoleOutput`, and `RunSomeTests`. Rediscover them rather than copying a historical signature blindly.

`RunProject` needs `attachDebugger: true` for LLDB work. Record its launch reference and PID only for the current run. Building/relaunching invalidates the previous process, object addresses, and LLDB persistent variables.

For documentation, query exact symbols and follow up with SDK declarations if search is incomplete:

```text
NSGlassEffectView contentView
NSGlassEffectView effectIsInteractive
NSTitlebarAccessoryViewController layoutAttribute
NSSplitViewController toggleSidebar
NSSplitViewItem collapseBehavior preferResizingSiblingsWithFixedSplitView
NavigationSplitView balanced
```

Do not infer availability from a search-result ranking. `effectIsInteractive` was found in the SDK as macOS 27-only even though the surrounding glass class is macOS 26.

## Establish the stopped process

Start with:

```text
process status
```

If it is running, interrupt before evaluating expressions:

```text
process interrupt
```

At the end, resume with `continue` or stop through Xcode as appropriate. Do not leave the user's app paused accidentally.

The following recipes assume a stopped macOS app with `AppKit` available. LLDB Swift expressions are diagnostic code in the live process; declarations can differ across Xcode versions. Run discovery and setup in small steps before an elaborate sample.

## Locate app-owned views first

Import once:

```text
expression -l swift -- import AppKit
```

Find the correct window by its app-owned accessory identifier, rather than assuming `NSApp.windows.first` is always the workspace:

```text
expression -l swift -- let $workspaceWindow = NSApp.windows.first { $0.titlebarAccessoryViewControllers.contains { $0.identifier?.rawValue == "workspace.sidebarToggle" } }!
expression -l swift -- let $accessory = $workspaceWindow.titlebarAccessoryViewControllers.first { $0.identifier?.rawValue == "workspace.sidebarToggle" }!
expression -l swift -- let $trackView = $accessory.view
expression -l swift -- let $hostView = $trackView.subviews.first!
expression -l swift -- func $ownedDescendants(_ view: NSView) -> [NSView] { [view] + view.subviews.flatMap { $ownedDescendants($0) } }
expression -l swift -- let $toggleButton = $ownedDescendants($hostView).compactMap { $0 as? NSButton }.first { $0.accessibilityIdentifier() == "workspace.sidebarToggle" }!
expression -l swift -- ($workspaceWindow.frame, $workspaceWindow.windowNumber, $hostView.frame, $toggleButton.frame, $toggleButton.accessibilityLabel())
```

These force unwraps are debugger conveniences after discovering the current hierarchy; they are not recommended production lookup code. The production owner already holds references directly.

The current track contains one hosting view. Locate the native toggle by its public accessibility identifier. The earlier AppKit-only implementation instead used `NSGlassEffectView.contentView`; do not apply that historical lookup to the SwiftUI glass container or style its private material layers.

## Inspect the native split in diagnostics only

Ordinary child-controller traversal did not find the native split controller during this investigation. Recursive view traversal found the `NSSplitView`, and its delegate could be cast to `NSSplitViewController`:

```text
expression -l swift -- func $descendants(_ view: NSView) -> [NSView] { [view] + view.subviews.flatMap { $descendants($0) } }
expression -l swift -- let $splitView = $descendants($workspaceWindow.contentView!).compactMap { $0 as? NSSplitView }.first!
expression -l swift -- let $splitController = $splitView.delegate as! NSSplitViewController
expression -l swift -- let $sidebarItem = $splitController.splitViewItems.first { $0.behavior == .sidebar }!
expression -l swift -- let $sidebarProbe = $descendants($sidebarItem.viewController.view).first { String(describing: type(of: $0)).contains("SidebarGeometryView") }!
expression -l swift -- ($sidebarItem.isCollapsed, $sidebarProbe.bounds, $sidebarProbe.visibleRect, $sidebarProbe.convert($sidebarProbe.bounds, to: nil))
```

For a multi-split app, select the relevant split instead of the first match. The class-name predicate is a test/debug aid; compiled tests can use the concrete app type via `@testable import Commander`.

Do not copy this private-host discovery into production. The app's code intentionally reads only its own probes and uses the responder chain for the action.

## Deliver an actual click

The working runtime approach converted the button's center to window coordinates and sent both mouse events to that window. A Swift expression body can use:

```swift
let window = $workspaceWindow
let button = $toggleButton
let point = button.convert(
    NSPoint(x: button.bounds.midX, y: button.bounds.midY),
    to: nil
)
for kind in [NSEvent.EventType.leftMouseDown, .leftMouseUp] {
    let event = NSEvent.mouseEvent(
        with: kind,
        location: point,
        modifierFlags: [],
        timestamp: ProcessInfo.processInfo.systemUptime,
        windowNumber: window.windowNumber,
        context: nil,
        eventNumber: 0,
        clickCount: 1,
        pressure: 1
    )!
    window.sendEvent(event)
}
```

Submit it through `expression -l swift -- ...`, then let the app run and verify `$sidebarItem.isCollapsed`. Synthetic event behavior can vary with control tracking/window activation. If event delivery blocks or does not change state, diagnose that rather than counting it as a successful toggle.

For target/action diagnosis only:

```text
expression -l swift -- NSApp.sendAction($toggleButton.action!, to: $toggleButton.target, from: $toggleButton)
```

For the native controller action only:

```text
expression -l swift -- $splitController.toggleSidebar(nil)
```

These test different layers. Target/action success is not a mouse hit-test result; an explicit controller target is not a test of menu/keyboard routing.

## Sample while the app actually runs

Avoid drawing final conclusions from a stopped-process expression that nests `RunLoop.main.run` repeatedly. It can starve SwiftUI main-actor work and return transient/stale geometry. Use the asynchronous regression test or schedule diagnostic sampling and **continue the process**.

A useful LLDB technique:

1. Create a persistent `NSMutableArray` for records in one expression.
2. In a later expression, bind the persistent window/button/probe references to ordinary local variables.
3. Capture those locals in a finite `Timer` closure installed on the main run loop in `.common` mode.
4. Record geometry/state/identity; optionally dispatch clicks at specific ticks.
5. Invalidate the timer at a fixed final tick.
6. `continue`, let the interaction complete, then interrupt and inspect records.

The captured-local step matters: LLDB failed to resolve persistent Swift globals referenced directly from helper functions in some attempts (`Couldn't look up symbols: $button`). Do not leave an unbounded diagnostic timer running.

Example record fields:

```text
timestamp
sidebar visible width
glass frame converted to window coordinates
button bounds converted to window coordinates
window frame (origin and size)
native isCollapsed
same button / parent / material / accessory identities
```

Sampling every 16 ms is diagnostic cadence, not a production animation clock or a guarantee of every display refresh. Preserve enough intermediate samples to see whether the control stops while the sidebar continues.

A prior Commander geometry trace is preserved in [the dated investigation](../../../../docs/investigations/2026-09-sidebar-glass.md). It is historical evidence rather than a current check or a guaranteed sampling rate.

## Coordinates and bridging traps

- Convert view-local bounds with `view.convert(view.bounds, to: nil)` to compare window coordinates. A nested `frame.origin` is relative to its immediate parent.
- Compare all four window-frame components for movement/resizing, not just endpoint width.
- `visibleRect`, safe-area insets, layer presentation, and native destination properties describe different things. Sample more than one when they disagree.
- The glass content button can have a different local frame from the wrapper. Translation diagnostics should include the wrapper.
- Values stored as `Any` retain their Swift/bridged types. A recorded `CGFloat` did not safely force-cast as `Double` in LLDB; that expression aborted. Prefer `as? CGFloat`, explicit conversion, or inspect the array directly.
- A failed persistent declaration may leave an unusable variable (“used before being initialized”). Use a new name or restart setup rather than building further expressions on it.
- The Swift importer sometimes treated `NSViewController.view` as nonoptional and rejected a copied force unwrap. Follow the current imported type.

One initial `import AppKit` expression reported a linked `libcups.dylib` load error, while a later expression in the same session succeeded. Capture such errors as debugger/importer issues; they do not establish an app linkage failure. Avoid making project-linker changes merely to silence an LLDB-only symptom.

## Screenshots and console checks

Xcode Device Interaction returned “None of the available devices are supported for Device Interaction” for this macOS app. Use available macOS-capable interaction tooling; in this environment, LLDB plus a targeted window screenshot was the working fallback.

Obtain `window.windowNumber` from the actual process and pass it to:

```sh
screencapture -x -l <window-number> '<approved-output-directory>/sidebar-expanded.png'
```

Open the resulting image. Capture expanded and collapsed states, and record whether the window was active. A screenshot file's existence alone is not visual verification.

Use `GetConsoleOutput` with the current launch reference to look for Auto Layout conflicts, `AttributeGraph` cycles, and state-mutation-during-update diagnostics when changing geometry observation. No matches for a chosen filter is scoped evidence, not proof the application has no errors.

Historical PIDs, workspace IDs, window numbers, launch references, and temporary image paths are deliberately not part of this reusable recipe.
