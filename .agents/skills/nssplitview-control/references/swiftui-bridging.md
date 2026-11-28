# SwiftUI and AppKit split ownership

## Start with the public SwiftUI surface

`NavigationSplitView(columnVisibility:)` expresses visibility intent. Column content can apply `navigationSplitViewColumnWidth(min:ideal:max:)`; the documentation calls these preferred widths and says the presentation environment can use another width.

`.balanced` reduces detail space to show leading columns. `.prominentDetail` attempts to preserve detail size. Neither name specifies every macOS window-frame consequence under unsatisfiable constraints.

Use an app-owned `NSSplitViewController` bridge when the requirement is specifically an AppKit collapse policy, explicit pane holding priorities, or native controller behavior unavailable through SwiftUI. For truly arbitrary divider control, evaluate a raw split implementation and its additional responsibilities.

## Stable controller lifetime

An `NSViewControllerRepresentable` has three jobs:

1. `makeNSViewController`: create the split controller and child `NSHostingController`s once.
2. `updateNSViewController`: reconcile changed inputs; update existing hosting controllers' `rootView` values while preserving appropriate view identity.
3. `dismantleNSViewController`: invalidate observations and queued callbacks owned by the bridge.

Do not recreate split items to toggle visibility. Replacing the controller to refresh content also resets pane width, focus, observations, restoration, and animation history.

A SwiftUI value-type representable can be recreated frequently while its AppKit controller persists. A coordinator must use the **current** bindings/callbacks, not permanently retain the first representable struct supplied at creation.

## Two-way visibility is reconciliation

Separate these values:

| Value | Owner | Purpose |
| --- | --- | --- |
| Requested visibility | SwiftUI/document model, per window | User intent or a programmatic command |
| Actual `isCollapsed` | AppKit item | Result of interaction, layout policy, or the command |
| In-flight presentation | Animation engine | What is currently drawn; not persistent preference |

Recommended flow:

```text
SwiftUI request -> compare with item -> apply only a change
AppKit observation -> distinguish echo/temporary policy -> coalesce
-> compare with current request -> publish an actual change
```

Do not synchronously mutate a SwiftUI binding while SwiftUI is executing the representable update. AppKit can notify synchronously as a consequence of your write. Track an `isApplyingSwiftUIUpdate` scope and suppress echoes, then publish later from the coordinator when necessary.

For asynchronous publication, use a generation/revision token and weak lifetime capture. Check the token **when the deferred work runs**; dispatching to the next turn alone does not prevent stale values from overwriting a newer toggle. Invalidate pending work on teardown.

Observe the documented item state through a suitable mechanism for the SDK (for example, verified KVO support), controller callbacks, and/or resize notifications followed by reconciliation. A resize callback is a reason to reread state, not proof that the user requested a new preference. If subclassing controller delegate methods, call `super`.

Decide how automatic and spring-loaded collapse affect the binding. If the model stores durable intent, a temporary full-screen overlay should not necessarily turn that preference off. If the binding stores current presentation, name it accordingly and keep durable preference elsewhere.

## Pick one animation route

### AppKit-owned system collapse

The SwiftUI button changes requested visibility without adding an unrelated root spring. The bridge invokes the controller's collapse method once, optionally using `item.animator().isCollapsed` inside an `NSAnimationContext` group.

This is useful when the native split controller should own the complete geometry transition. SwiftUI content may still animate its own unrelated feedback, but not the same pane width.

### Shared SwiftUI transaction, macOS 15+

For an explicitly hosted controller, `NSViewControllerRepresentableContext.animate(changes:completion:)` forwards the transaction's `Animation` into AppKit. The analogous method exists for `NSViewRepresentableContext`.

```swift
// Fragment inside updateNSViewController(_:context:).
// controller and context belong to this representable.
if controller.sidebarItem.isCollapsed != collapsed {
    controller.view.layoutSubtreeIfNeeded()
    context.animate {
        controller.sidebarItem.isCollapsed = collapsed
        controller.view.layoutSubtreeIfNeeded()
    }
}
```

In this route, the outer SwiftUI action supplies the animation, and the bridge applies it once. Do not call the example controller's separately animating method **inside** `context.animate`.

Installed Xcode 27 SDK evidence: these context methods are available from **macOS 15.0**, with `@backDeployed(before: macOS 15.4)`. The 15.4 annotation is not a 15.4 deployment minimum. Compile against the SDK you actually use; an older SDK might not contain the method even when the runtime minimum is older.

The published back-deployed implementation checks both `transaction.animation` and `!transaction.disablesAnimations`; without an active permitted animation it executes changes and completion immediately. Preserve that behavior rather than substituting an arbitrary fallback spring.

Below macOS 15, use the AppKit-owned route or apply changes immediately according to an explicit bridge policy. Matching a SwiftUI spring with an unrelated cubic Bézier by guessing its duration is not exact synchronization.

## Hosting measurement and window access

`NSHostingController` fitting behavior can contribute minimum widths. Inspect the actual constraints and the hosted content's use of fixed frames, `.fixedSize`, unbreakable text, and scroll views. Where using `sizingOptions`, check that its intrinsic/minimum/maximum propagation matches the container's intended role; do not blindly switch every sizing flag on or off.

For a window callback, prefer a small AppKit view with `viewDidMoveToWindow()` or an owned controller lifecycle hook. `nsView.window` can be nil while making or updating the representable; a callback tied to moving windows gives the right lifecycle signal. Coalesce any binding publication and clear stale ownership after detachment.

Do not infer the correct window from `NSApp.windows.first`, a global singleton, or a cached key window. Multiple windows can have different sidebar state and minima.

## Integration verification

- Open two windows; toggle one and verify the other retains its state.
- Change hosted content without recreating the split controller; widths and focus should survive.
- Toggle twice during collapse; the newest requested state should win.
- Trigger automatic collapse/full-screen overlay and verify the chosen intent-versus-presentation policy.
- Verify no “modifying state during view update” diagnostics.
- With Reduce Motion, both the SwiftUI transaction and the AppKit-owned path should follow the chosen reduced-motion policy.

Sources: [preferred widths](https://developer.apple.com/documentation/swiftui/view/navigationsplitviewcolumnwidth(min:ideal:max:)), [balanced style](https://developer.apple.com/documentation/swiftui/balancednavigationsplitviewstyle), [controller context animation](https://developer.apple.com/documentation/swiftui/nsviewcontrollerrepresentablecontext/animate(changes:completion:)), [unified animation](https://developer.apple.com/documentation/swiftui/unifying-your-app-s-animations).
