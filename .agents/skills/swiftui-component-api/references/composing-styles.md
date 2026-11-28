# Composing styles

## Contents
- Styles are a stack
- Modify the current style with a configuration initializer
- Choosing a style at runtime
- Giving a custom view the stack

## Styles are a stack

Each `.buttonStyle(_:)` (and every other built-in style modifier) pushes onto a stack that SwiftUI carries down the hierarchy. A styled view pops the innermost style and renders with it. Its content sees the remaining stack.

Consequences:
- Nested views of the same type don't inherit the style. An inner `GroupBox` falls back to `.automatic`, or to the next style down the stack. These two give the same result:
  ```swift
  GroupBox("A") { GroupBox("B") { GroupBox("C") {}.groupBoxStyle(.tagged("C")) }.groupBoxStyle(.tagged("B")) }.groupBoxStyle(.tagged("A"))
  GroupBox("A") { GroupBox("B") { GroupBox("C") {} } }.groupBoxStyle(.tagged("A")).groupBoxStyle(.tagged("B")).groupBoxStyle(.tagged("C"))
  ```
- For styles on containers that nest (group boxes, cards, sections), reapply the style inside `makeBody` with `.groupBoxStyle(self)`, so every property carries over. To vary by depth, increment an environment counter:
  ```swift
  struct NestingGroupBoxStyle: GroupBoxStyle {
      @Environment(\.groupBoxNestingLevel) private var level
      func makeBody(configuration: Configuration) -> some View {
          VStack(alignment: .leading) { configuration.label; configuration.content }
              .padding()
              .background(.tint.opacity(level.isMultiple(of: 2) ? 0.2 : 0.1), in: .rect(cornerRadius: 16))
              .transformEnvironment(\.groupBoxNestingLevel) { $0 += 1 }
              .groupBoxStyle(self)
      }
  }
  ```
  When a style reapplies itself, any modifier styles stacked on it don't reach the nested views.

## Modify the current style with a configuration initializer

`Button` (from a `PrimitiveButtonStyleConfiguration`), `Toggle`, `Label`, `LabeledContent`, `GroupBox`, `ControlGroup`, `Menu`, `ProgressView`, and `Form` have `init(_ configuration:)`, which rebuilds the view with the next style on the stack. Use it to modify a style you can't or don't want to reimplement. Other views, including `DisclosureGroup`, `Gauge`, `DatePicker`, and non-primitive `ButtonStyle`, have no configuration initializer. Their styles must build the whole view.

```swift
struct OutlinedButtonStyle: PrimitiveButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        Button(configuration)
            .overlay { RoundedRectangle(cornerRadius: 4).strokeBorder(.primary, lineWidth: 2) }
    }
}

Button("Done".localized()) {}
    .buttonStyle(OutlinedButtonStyle()) // modifier: closer to the view
    .buttonStyle(.borderedProminent) // base: farther out
```

Order matters. The modifier style goes before (inside) the base. Reversed, the base pops first and the modifier never runs. Use `PrimitiveButtonStyle`, since `Button(configuration)` takes a `PrimitiveButtonStyleConfiguration`.

The same trick scopes a modifier to one view type: `Button(configuration).font(...)` or `.labelStyle(...)` changes buttons without changing other views under it. A scoped style set higher in the hierarchy wins over the same kind of style set lower. To override it in a subtree, reapply the whole chain there.

## Choosing a style at runtime

`.buttonStyle(cond ? .bordered : .borderedProminent)` doesn't compile ("type 'ButtonStyle' has no member 'bordered'") because the modifier needs one concrete type. Don't branch the view to fix it. Branch inside a style instead:

```swift
struct ThemedButtonStyle: PrimitiveButtonStyle {
    @Environment(\.theme) private var theme
    func makeBody(configuration: Configuration) -> some View {
        switch theme {
        case .glass: Button(configuration).buttonStyle(.borderless)
        case .standard: Button(configuration).buttonStyle(.bordered)
        }
    }
}
```

Branch on a stored boolean the same way. Don't call another style's `makeBody` directly: that style's `@Environment` reads its default value.

## Giving a custom view the stack

A single environment style plus `Card(configuration)` inside a style loops forever: the rebuilt `Card` reads the same style. Store a stack and pop it in the component. This builds on `styleable-component.md`:

```swift
extension EnvironmentValues {
    @Entry var cardStyleStack: [any CardStyle] = []
}

extension View {
    func cardStyle(_ style: some CardStyle) -> some View {
        transformEnvironment(\.cardStyleStack) { $0.append(style) }
    }
}

struct Card<Content: View>: View {
    var content: Content
    @Environment(\.cardStyleStack) private var stack

    var body: some View {
        let style = stack.last ?? PlainCardStyle()
        AnyView(style.resolve(configuration: .init(content: .init(content))))
            .transformEnvironment(\.cardStyleStack) {
                if !$0.isEmpty {
                    $0.removeLast()
                }
            }
    }
}

extension Card where Content == CardStyleConfiguration.Content {
    init(_ configuration: CardStyleConfiguration) {
        content = configuration.content
    }
}
```

With the stack, nested `Card`s behave like nested `GroupBox`es, and `.cardStyle(.shadow).cardStyle(.plain)` composes.
