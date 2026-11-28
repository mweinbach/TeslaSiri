---
name: "swiftui-component-api"
description: "SwiftUI component API design: built-in views, environment values, initializers, and style protocols. Use when writing a view for something that is a button, icon + title, title + value row, toggle, expandable section, titled container, progress indicator, menu, or form; adding a color, tint, disabled, size, or font parameter; using .onTapGesture, an icon without a title, or .accessibilityHidden; adding initializers, overloads, or a closure parameter that builds views to a reusable view; adding an enum of cases to a component; writing a custom style protocol or a ButtonStyle/GroupBoxStyle that wraps another style; or when a style doesn't apply, loops forever, reads a default @Environment value, or won't compile in a ternary."
---

# SwiftUI component API

Every reusable view is an API. Design it from the call site, not the declaration site: the call site's complexity should grow with the use case's complexity (progressive disclosure).

Use what SwiftUI already has before writing anything:
1. **Read context from the environment; don't add a parameter for it.** Tint, disabled state, control size, font, color scheme, and the rest already flow down the hierarchy, and callers already know the modifiers that set them. A style fills with `.tint`, not with a `color:` passed into it.
2. **Build on the built-in view that already is the thing, and change its look with a style.** Icon + title is a `Label`, title + value is `LabeledContent`, expand/collapse is `DisclosureGroup`, a titled container is a `GroupBox`. Don't write a new view type, and don't wrap a built-in view to bake in a look.
3. **Write a custom view, with its own style protocol, only when no built-in view fits.**

Then design the call site:
1. Find the common use cases and give them the shortest spelling.
2. Default everything the common case doesn't care about.
3. Every character at the call site must carry information. Ask "what's essential?" and "what's common enough for a convenience?"
4. Compose, don't enumerate. If you're listing cases, expose a composable piece instead.

Mark every closure parameter, property, and function that builds views `@ContentBuilder`.

Placing views (alignment, `Spacer`, frames, overlays) follows the `swiftui-layout` skill.

# References
- `references/built-in-first.md`: Use before adding a parameter to a component or style, or before writing a new view type. Has a table of environment values to read instead of parameters, a table of built-in views with style protocols matched to what you're building (including the ones whose styles can't be customized), and the accessibility rules: `Button` over `.onTapGesture`, an `.iconOnly` `Label` for an icon that means something, and what SwiftUI already hides from VoiceOver.
- `references/progressive-disclosure.md`: Use when designing or reviewing a component's initializers, overloads, and parameters. Covers the label-overload pattern, `LocalizedStringKey` vs. `@_disfavoredOverload` `StringProtocol` initializers, collection and key-path conveniences, dropping optional features into separate overloads, and when an enum should become a composable piece.
- `references/styleable-component.md`: Use when making a custom view styleable. Covers the configuration with a type-erased `Label`, the environment-stored existential style, the `DynamicProperty` + generic resolver view that makes `@Environment` work inside custom styles, `.automatic`-style static members, and putting accessibility on the component, not the style.
- `references/composing-styles.md`: Use when a style wraps or modifies another style, styles combine, or style propagation surprises you. Covers the style stack (why nested same-type views get the default style), configuration initializers like `Button(configuration)`, modifier order, choosing a style at runtime, and implementing the stack for a custom view.
