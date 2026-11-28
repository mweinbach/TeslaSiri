# Research and verify UI details with Xcode MCP

This workflow is shared by the split-view and animation skills. Tool names/signatures below were discovered on 2026-09-13; rediscover them when the server changes.

## 1. Separate three kinds of evidence

- **API contract:** Apple symbol documentation and current SDK declarations.
- **Engineering recommendation:** a design choice such as one animation owner or distinct pane priorities.
- **Runtime observation:** behavior reproduced on a named OS/build/window configuration.

Do not turn a local workaround into a universal contract. Documentation search results can contain overly broad wording or sample typos; verify important claims and compile executable examples.

## 2. Discover and query the documentation tool

In a Code Mode harness, discover the exact signature first:

```javascript
return search({ namespace: "Xcode", query: "DocumentationSearch", limit: 1 });
```

Then call the discovered tool. Independent documentation queries can run concurrently:

```javascript
return await Promise.all([
  tools.Xcode.DocumentationSearch({
    frameworks: ["AppKit"],
    query: "NSSplitViewItem preferResizingSiblingsWithFixedSplitView minimum size"
  }),
  tools.Xcode.DocumentationSearch({
    frameworks: ["SwiftUI"],
    query: "NSViewRepresentableContext animate changes completion transaction"
  })
]);
```

Use focused symbol-plus-behavior queries. A broad “AppKit animation interruption” search may return `NSAnimation` instead of `NSAnimationContext`. Narrow the query, inspect result titles and `uri`, and retain the discussion text containing the actual qualification.

The tool returns `documents` with `contents`, `title`, `kind`, `score`, and `uri`. A high score is semantic similarity, not a correctness or availability guarantee. Convert `/documentation/...` URIs to `https://developer.apple.com/documentation/...` for human-readable sources. Preserve overload-specific URIs when needed.

Useful query sequence:

```text
symbol overview -> exact property/method -> exception/limitation
-> caller/bridge API -> availability declaration -> smallest compiling example
```

## 3. Verify the SDK and language separately

Use `XcodeListWorkspaces`, `XcodeListTargets`, and `GetTargetBuildSettings` for the project context. Discover their signatures; use an explicit workspace identifier. Read deployment and Swift language settings through the build-settings tool.

For installed SDK evidence when search omits availability:

```sh
xcodebuild -version
xcrun --show-sdk-path
```

Search the selected SDK's framework headers or `.swiftinterface` for the exact declaration, then read the preceding availability attributes and enclosing extension. Prefer targeted content search to dumping an entire SwiftUI interface.

Important distinctions:

- A new SDK may expose a macro that back-deploys to old OS versions. SDK/compiler availability and runtime availability are different.
- `@backDeployed(before: macOS 15.4)` with `@available(macOS 15.0, *)` means deployment support begins at 15.0, not 15.4.
- `_originallyDefinedIn` is not the API's minimum OS.
- A framework re-export can put AppKit extensions in the SwiftUI interface; search both when necessary.
- Xcode version does not prove the target uses the newest Swift language mode or default isolation setting.

## 4. Choose verification proportional to the claim

| Claim | Evidence/tool |
| --- | --- |
| API exists and imports correctly | Standalone `swiftc -typecheck` or project build |
| Uses project-specific types correctly | `BuildProject`; inspect `GetBuildLog` for failures |
| A calculation or small API call returns a value | `RunCodeSnippet` in a real source context; print the values |
| View appears as intended at a state/size | `RenderPreview`, then open the returned snapshot |
| Window resize/focus/collapse works | Run in an actual window; interact and inspect |
| Motion is continuous under reversal | Recording/interactive observation and, when needed, Instruments |

`RunCodeSnippet` is not a unit-test runner. Use a factual purpose string such as “Inspect pane fitting widths”. `RenderPreview` returns a static image and supported override choices; use returned override values rather than inventing them. Do not run conflicting build/run/preview operations against the same workspace concurrently.

For standalone examples, a local type check is useful:

```sh
xcrun swiftc -typecheck -swift-version 6 -target arm64-apple-macos14.0 path/to/Example.swift
```

Use the host architecture and the file's stated deployment baseline. Newer APIs should be guarded/annotated. A type check verifies declarations and concurrency diagnostics, not window behavior.

## 5. Record what was actually checked

Keep source links close to non-obvious claims. In a guide's source ledger, record SDK version, research date, API-specific availability, and outstanding runtime work. If a sample was only compiled, say “type-checked,” not “tested on device.”

When information conflicts, explain the conflict and use a focused SDK check or minimal runtime experiment. Do not fabricate a documentation guarantee to justify a workaround.
