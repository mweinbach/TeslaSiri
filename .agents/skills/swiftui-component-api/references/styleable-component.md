# Making a custom view styleable

Make the look a style, so a style set at the root reaches every instance.

Model it on `PrimitiveButtonStyle`: the style owns interaction. The pieces are a configuration, a protocol, an environment value, a modifier, and the component.

## Contents
- Configuration
- Protocol, resolver, environment, modifier
- Component

## Configuration

Copy the component's inputs. Type-erase generic content in a nested `View` named like SwiftUI's (`Label`, `Content`), so one style works for every label type and you can add style-facing properties later:

```swift
struct RangeSliderStyleConfiguration {
    struct Label: View {
        let underlyingLabel: AnyView
        init(_ label: some View) {
            underlyingLabel = AnyView(label)
        }

        var body: some View {
            underlyingLabel
        }
    }

    @Binding var range: ClosedRange<Double>
    let bounds: ClosedRange<Double>?
    let label: Label
}
```

Leave out anything in the environment, like `isEnabled`, `controlSize`, `colorScheme`, or tint. Styles read those directly. `.disabled()` sets `\.isEnabled`, and `ButtonStyleConfiguration` has no disabled flag for the same reason.

## Protocol, resolver, environment, modifier

```swift
protocol RangeSliderStyle: DynamicProperty {
    associatedtype Body: View
    @MainActor @ContentBuilder
    func makeBody(configuration: Configuration) -> Body
    typealias Configuration = RangeSliderStyleConfiguration
}

private struct ResolvedRangeSliderStyle<Style: RangeSliderStyle>: View {
    var configuration: RangeSliderStyleConfiguration
    var style: Style
    var body: some View {
        style.makeBody(configuration: configuration)
    }
}

extension RangeSliderStyle {
    @MainActor
    func resolve(configuration: Configuration) -> some View {
        ResolvedRangeSliderStyle(configuration: configuration, style: self)
    }
}

extension EnvironmentValues {
    @Entry var rangeSliderStyle: any RangeSliderStyle = DefaultRangeSliderStyle()
}

extension View {
    func rangeSliderStyle(_ style: some RangeSliderStyle) -> some View {
        environment(\.rangeSliderStyle, style)
    }
}

extension RangeSliderStyle where Self == DefaultRangeSliderStyle {
    static var automatic: Self {
        .init()
    }
}
```

Both `DynamicProperty` and the generic resolver are required. SwiftUI installs a style's `@Environment` and `@State` only when the style is a stored property of a view and has a concrete type. Without them, the style's `@Environment` reads its default value and Xcode logs "Accessing Environment's value outside of being installed on a View". `resolve` opens the existential so the resolver gets the concrete type.

Mark `makeBody` and `resolve` `@MainActor`, like SwiftUI's own style requirements, or Swift 6 warns when a style builds views.

## Component

```swift
struct RangeSlider<Label: View>: View {
    @Binding var range: ClosedRange<Double>
    var bounds: ClosedRange<Double>?
    var label: Label
    @Environment(\.rangeSliderStyle) private var style

    init(range: Binding<ClosedRange<Double>>, in bounds: ClosedRange<Double>? = nil, @ContentBuilder label: () -> Label) {
        _range = range
        self.bounds = bounds
        self.label = label()
    }

    var body: some View {
        let configuration = RangeSliderStyleConfiguration(range: $range, bounds: bounds, label: .init(label))
        AnyView(style.resolve(configuration: configuration))
            .accessibilityElement(children: .combine)
            .accessibilityValue(Text(range.lowerBound, format: .percent))
            .accessibilityAdjustableAction { /* adjust range */ _ in }
    }
}
```

`AnyView` is unavoidable here because the style is only known at runtime. Keep it to this one place.

Put accessibility on the component, not in each style, so every style is accessible without extra work.

To let styles wrap the view (`RangeSlider(configuration)`) or combine with each other, the environment has to hold a stack instead of a single style. See `composing-styles.md`.
