# Use what SwiftUI already has

## Read the environment instead of adding a parameter

If SwiftUI already carries a value down the hierarchy, a component or style reads it. Callers then set it once, on any ancestor, with the modifier they already know, and the same call styles built-in views too.

| Instead of a parameter for… | Read | Callers set it with |
|---|---|---|
| Accent or fill color | `.tint` as a `ShapeStyle`: `.fill(.tint)`, `.foregroundStyle(.tint)` | `.tint(_:)` |
| Text and glyph color, font | Nothing. Content inherits them. Don't set them in the style unless the design fixes them | `.foregroundStyle(_:)`, `.font(_:)` |
| Surface color | `.background` as a `ShapeStyle`, or `\.backgroundStyle` | `.backgroundStyle(_:)` |
| Disabled | `@Environment(\.isEnabled)` | `.disabled(_:)` |
| Size step | `@Environment(\.controlSize)` | `.controlSize(_:)` |
| Hidden label | `@Environment(\.labelsVisibility)` | `.labelsHidden()` |
| Gap between icon and title | Nothing in a built-in label style. A custom `LabelStyle` reads `\.labelIconToTitleSpacing` (iOS 26) | `labelIconToTitleSpacing(_:)` |
| Placeholder or skeleton look | `@Environment(\.redactionReasons)` | `.redacted(reason:)` |
| Selected or emphasized row | `@Environment(\.backgroundProminence)` | `List` selection, or set by the container |

Callers pass the design system's values to these modifiers, for example `.tint(.palette.…)`. The style stays free of color literals.

`.buttonBorderShape(_:)` only reaches the built-in button styles. Custom styles can't read it.

If a value isn't in the environment and every instance needs it, such as a loading state, it's an input: put it in the configuration (see `styleable-component.md`). If it's ambient context a whole subtree shares, add it with `@Entry`.

## Build on a built-in view

Use the built-in view and a style for it. The built-in view already gives you accessibility traits, localized string initializers, `.disabled`, focus and keyboard behavior, the label conveniences from `progressive-disclosure.md`, and the style stack from `composing-styles.md`.

| Building… | View | Custom style |
|---|---|---|
| Anything tappable | `Button` | `ButtonStyle` (look only) or `PrimitiveButtonStyle` (owns the gesture) |
| On/off, or a button that stays selected | `Toggle` | `ToggleStyle` |
| Icon + title | `Label` | `LabelStyle` |
| Title + value or control | `LabeledContent` | `LabeledContentStyle` |
| Expand/collapse section | `DisclosureGroup` | `DisclosureGroupStyle` |
| Titled container or card | `GroupBox` | `GroupBoxStyle` |
| Spinner or progress bar | `ProgressView` | `ProgressViewStyle` |
| Value within a range | `Gauge` | `GaugeStyle` |
| Related controls together | `ControlGroup` | `ControlGroupStyle` |
| Button that opens a menu | `Menu` | `MenuStyle` |
| Settings or options screen | `Form` | `FormStyle` |
| Choose one of several | `Picker` | Built-in styles only |
| Text input | `TextField` | Built-in styles only |

**Make anything tappable a `Button`, not `.onTapGesture`.** A tap gesture has no button trait, doesn't respond to Full Keyboard Access or Voice Control, and has no pressed state. Use `.onTapGesture` only when `Button` can't do the job and say why in a comment.

**Show a meaningful icon on its own as a `Label` with `.labelStyle(.iconOnly)`,** not an `Image` with an `.accessibilityLabel`:

```swift
Button("Share".localized(), systemImage: "square.and.arrow.up") { share() }
    .labelStyle(.iconOnly)
```

**Don't hide what SwiftUI already hides.** Accessibility ignores content in a `.background { }` closure. A `Label` hides its icon and reads its title. Neither needs `.accessibilityHidden(true)`.

`PickerStyle` and `TextFieldStyle` have no public requirements you can implement. If a built-in style can't produce the design, build the control from `Button`s or `Toggle`s, or write a custom view.

Don't wrap a built-in view in a new view type (`MyButton`) to bake in a look. The wrapper has to copy every convenience initializer, and plain uses of the built-in view skip it. Put the look in a style and set it on an ancestor.

Write a custom view only when no row of the table fits. Then make it styleable with `styleable-component.md`.
