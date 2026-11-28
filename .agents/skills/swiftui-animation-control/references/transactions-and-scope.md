# Transactions and animation scope

## A compact mental model

```text
state mutation -> transaction -> view identity/layout update
-> animatable values receive timing -> presentation interpolates
```

The stored state normally reaches its new value immediately. Reading it a moment later gives the destination, not a sample halfway through a spring. That distinction matters for interruption, gesture re-grabs, and completion observers.

## Four scopes, four uses

| API | Use | Important consequence |
| --- | --- | --- |
| `withAnimation` | One semantic action changing related state | Eligible changes caused by the action can animate across affected views |
| `.animation(_:value:)` | A subtree reacts when an equatable trigger changes | Other changes in that subtree/update can share the animation |
| `.animation(_:body:)` | Animate only modifiers in the closure | More precise than a broad subtree modifier |
| `.transaction` / `withTransaction` | Inspect/replace/suppress transaction metadata | Scope and modifier order determine what receives the change |

### Explicit action

```swift
// Fragment: expanded is view state; reduceMotion is an environment value.
withAnimation(reduceMotion ? nil : .smooth(duration: 0.25)) {
    expanded.toggle()
}
```

Good for an intentional disclosure where both the insertion and surrounding layout should react. Avoid bundling unrelated status text or a large batch of data updates into the same action merely because they happen in the same callback.

### Value-triggered animation

```swift
// Fragment: the effect subtree animates when isSelected changes.
BadgeView()
    .scaleEffect(isSelected ? 1.08 : 1)
    .animation(.snappy(duration: 0.22), value: isSelected)
```

The watched value decides **when** the modifier installs animation metadata. It is not a property dependency whitelist. If unrelated padding or opacity below that modifier changes in the same update, it may animate too. If a changing label lies in the subtree, inspect its content/layout behavior rather than assuming it is excluded.

### Scoped modifier animation, macOS 14/iOS 17+

```swift
// Fragment: only the rotation modifier receives this local animation.
Image(systemName: "chevron.right")
    .animation(.smooth(duration: 0.18)) { content in
        content.rotationEffect(.degrees(expanded ? 90 : 0))
    }
```

Use the provided `content`. A scoped animation confines the specified modifiers, but it is not a universal layout sandbox: animated size changes can still cause ancestors/siblings to respond to layout. Keep separate effects in separate scopes and inspect the containing layout when precision matters.

## Suppression has two parts

To make a state update immediate and prevent standard descendant animation modifiers from injecting their own animations:

```swift
// Fragment: restoreState() performs synchronous model changes.
var transaction = Transaction(animation: nil)
transaction.disablesAnimations = true
withTransaction(transaction) {
    restoreState()
}
```

- `animation = nil` clears this transaction's animation.
- `disablesAnimations = true` tells animation-participating views/modifiers not to insert animations.

This is useful for restoration, first presentation, or a reduced-motion update. It is not a generic cancellation handle for independently running keyframe effects, timers, AppKit animators, or arbitrary custom components that ignore transaction policy.

`withAnimation(nil)` alone does not forbid a descendant `.animation` from installing its own timing. `.transaction { $0.animation = nil }` at a leaf can stop inherited animation there, but a later/nested modifier can replace the metadata. Inspect the exact modifier chain before claiming suppression is global.

Use scoped `transaction(_:body:)` when only an effect's transaction needs adjustment. Avoid broad root transaction overrides that accidentally affect navigation, lists, text editing, and system presentation together.

## Async work and transaction boundaries

Do expensive work outside the mutation closure, then animate the final synchronous UI commit:

```text
await load/compute -> validate request/cancellation -> MainActor
-> withAnimation { assign prepared result }
```

An animation closure is synchronous. Starting a `Task` inside it does not keep the transaction attached to future asynchronous assignments. Apply the transaction at the actual UI update site.

Keep frequent streaming text/progress updates outside a container's broad animation scope unless animating every update is intentional. Animate the appearance of a result card or an explicit completion event, not every token's reflow by accident.

## Debug a scope leak

1. Name every state change in the triggering update.
2. Locate all `withAnimation`, `.animation`, binding animation, and transaction modifiers along the affected subtree.
3. Check both identity changes and animatable modifiers.
4. Replace the broad scope with a scoped modifier or a smaller component.
5. Change an unrelated value at the same time; verify it no longer animates unintentionally.

Sources: [withAnimation](https://developer.apple.com/documentation/swiftui/withanimation(_:_:)), [scoped animation](https://developer.apple.com/documentation/swiftui/view/animation(_:body:)), [Transaction](https://developer.apple.com/documentation/swiftui/transaction), [disablesAnimations](https://developer.apple.com/documentation/swiftui/transaction/disablesanimations).
