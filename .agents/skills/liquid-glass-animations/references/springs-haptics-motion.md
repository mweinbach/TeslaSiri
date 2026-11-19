# Springs, Haptics, Custom Glass Typography & Motion Accessibility

## 1. Spring Curves That Match Liquid Glass Optics

Liquid Glass has physical visual mass—abrupt linear easing feels broken, while overly bouncy springs feel cartoonish. Stick to three disciplined SwiftUI spring presets:

| Preset | Feel | Best Used For |
| :--- | :--- | :--- |
| **`.snappy(duration: 0.28, extraBounce: 0.0)`** | Crisp, responsive, zero wobble | Toolbar expansions, segmented pill swaps, detached FAB morphs |
| **`.smooth(duration: 0.35, extraBounce: 0.0)`** | Calm, fluid, editorial | Sheet detents, iPadOS sidebar/inspector reveals, mini-player transitions |
| **`.bouncy(duration: 0.38, extraBounce: 0.12)`** | Subtle tactile playfulness | Delight moments only (favoriting, achievement pill, playful single-purpose apps) |

**Interruptibility Rule:** Always use spring animations (`withAnimation(.snappy)`) so rapid double-taps smoothly redirect velocity instead of jumping or locking out input.

---

## 2. Synchronized Haptics (`.sensoryFeedback`)

Pair key Liquid Glass state transitions with restrained native SwiftUI haptics—never buzz on every scroll pixel or minor hover:

```swift
.sensoryFeedback(.impact(flexibility: .soft, intensity: 0.7), trigger: isExpanded)
.sensoryFeedback(.selection, trigger: selectedTab)
.sensoryFeedback(.success, trigger: didCompleteAction)
```

- **Opening/morphing a floating glass cluster:** `.impact(flexibility: .soft, intensity: 0.6–0.75)`
- **Switching pill segments or scrubber ticks (*Lumy* dial feel):** `.selection`
- **Completing primary tinted action:** `.success`

---

## 3. Core Text Glass Typography & Reflections (*Return* Pattern)

If an atmospheric app renders large hero numerals *as* `.clear` Liquid Glass over live video/sky:
- **Prevent Digit Jitter:** `.monospacedDigit()` does not apply to a custom Core Text `Shape`. Wrap each character in a fixed-width cell (`fontSize * 0.6` for digits `0–9`, `fontSize * 0.3` for `:`) so updating seconds never shifts the `HStack`.
- **RTL Protection:** On timers/clocks in RTL locales, attach both `.environment(\.layoutDirection, .leftToRight)` AND `.flipsForRightToLeftLayoutDirection(false)` so digits never mirror backwards.
- **VoiceOver Hygiene for Reflections:** If adding a subtle flipped mirror reflection underneath glass digits (`.scaleEffect(x: 1, y: -1)` + top-to-bottom opacity mask), **always** add `.accessibilityHidden(true)` to the reflection so VoiceOver never reads the value twice.

---

## 4. Mandatory `accessibilityReduceMotion` Gating

Liquid Glass morphs and optical stretches can cause discomfort for users with vestibular sensitivity. Gate every custom morph and transition:

```swift
@Environment(\.accessibilityReduceMotion) private var reduceMotion

// 1. Animation gate
withAnimation(reduceMotion ? nil : .snappy(duration: 0.3)) {
    isExpanded.toggle()
}

// 2. Transition gate
secondaryPill
    .glassEffectTransition(reduceMotion ? .identity : .matchedGeometry)
    .transition(reduceMotion ? .opacity : .opacity.combined(with: .scale(scale: 0.94)))
```
