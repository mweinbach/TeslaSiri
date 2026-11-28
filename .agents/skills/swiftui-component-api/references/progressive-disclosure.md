# Progressive disclosure in component APIs

Write the call sites you want first, simplest use case first, then design declarations that make them compile. Don't start from the stored properties.

## Label overloads

When a component takes a label, provide two shapes, like `Button`:

```swift
Button("Next Page".localized()) { currentPage += 1 } // the 99% case
Button { currentPage += 1 } label: { // any view
    HStack {
        Text("Next Page".localized())
        NextPagePreview()
    }
}
```

Callers here pass `"…".localized()`, a `String`, so the `StringProtocol` initializer is the main path. Keep a `LocalizedStringKey` initializer beside it, and mark the `StringProtocol` one `@_disfavoredOverload` so a bare literal still resolves to the localizing overload:

```swift
extension RangeSlider where Label == Text {
    init(_ titleKey: LocalizedStringKey, range: Binding<ClosedRange<Double>>) {
        self.init(range: range) { Text(titleKey) }
    }

    @_disfavoredOverload
    init(_ title: some StringProtocol, range: Binding<ClosedRange<Double>>) {
        self.init(range: range) { Text(title) }
    }
}
```

## Conveniences come from the common case

From `Table`, fully specified down to minimal:

```swift
Table(sortOrder: $sortOrder) {
    TableColumn("Title".localized(), value: \Book.title) { Text($0.title) }
} rows: {
    ForEach(books) { TableRow($0) }
}

Table(books) { // collection replaces rows: { ForEach }
    TableColumn("Title".localized(), value: \.title) // String key path implies Text
} // no sortOrder: separate overload
```

- A builder that's almost always `ForEach(collection) { Row($0) }`: accept the collection.
- A closure that's almost always "show this string": constrain an overload to `String` key paths and drop the closure.
- An optional feature (sorting, selection) the simple case doesn't use: put it in a separate overload. Don't make it an optional parameter that everyone sees.

Keep what's essential required. `Button` always needs a label; `Table` always needs columns.

## Default to platform convention

Give every parameter a default that follows platform convention, and add an explicit API for the exceptions, as `ToolbarItem(placement:)` does for `toolbar`.

## Compose, don't enumerate

Don't add an `enum` of arrangements. `HStack(arrangement: .leading/.center/.trailing)` needs a new case for even spacing, space between items, or space before the last item. SwiftUI's `Spacer` covers all of these. To place a single view, follow `swiftui-layout`.

When the set of cases is open-ended, expose the building block. Small closed sets with no in-between, like `HorizontalAlignment`, can stay enums.
