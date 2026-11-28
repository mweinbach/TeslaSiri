---
name: macos-glass-motion
description: Implement and debug persistent Liquid Glass controls and coordinated macOS motion across AppKit and SwiftUI. Use for custom titlebar controls, sidebar collapse/reopen, window growth, geometry-following animations, stable control identity, NSGlassEffectView content and interaction, NSGlassEffectContainerView grouping, hosted environment propagation, interruption and completion races, or Xcode runtime motion verification. Includes Commander's measured sidebar implementation, failed approaches, reusable examples, and regression-test/debugger recipes.
---

# macOS Liquid Glass and coordinated motion

Build motion around **one owner for each animated property**, persistent control identity, and evidence from a running window. A view's destination state, current layout, and rendered position can be different values.

This is project-maintained engineering guidance. Current Commander behavior lives in [workspace chrome](../../../docs/workspace-chrome.md), and prior observations live in [the dated investigation](../../../docs/investigations/2026-09-sidebar-glass.md). Check the selected SDK when using a version-specific API.

## Read by task

| Task | Read |
| --- | --- |
| Continue Commander's sidebar/toggle work | [Implementation and geometry](../../../docs/workspace-chrome.md) |
| Trailing inspector toggle, terminal button, app-owned inspector column | [Implementation and geometry](../../../docs/workspace-chrome.md), trailing accessory section |
| Add native glass, foreground content, interactive feedback, or a glass container | [Liquid Glass](references/liquid-glass.md) |
| Fuse or peel SwiftUI glass and sequence its symbols | [Fused glass morphs](../fused-glass-morph/SKILL.md) and [fusion rules](../fused-glass-morph/references/fusion-rules.md) |
| Define custom animation states, reversal, completion, or teardown | [State and interruption](references/state-and-interruption.md) |
| Choose SwiftUI, AppKit, constraints, or Core Animation | [Motion engines](references/motion-engines.md) |
| Verify motion, identity, sizing, and input | [Runtime verification](references/runtime-verification.md) |
| Drive Xcode, sample a live app, or capture a window | [Xcode and LLDB recipes](references/xcode-lldb.md) |
| Understand earlier failures or check an API claim | [Evidence and failure ledger](../../../docs/investigations/2026-09-sidebar-glass.md) |

Read the relevant reference before changing that part of the implementation. Use the source files as the current implementation; this skill records the reasoning and invariants rather than maintaining a second copy of the app.

## Fast workflow

1. **Describe the effect.** Identify trigger, destination, visible properties, coordinate space, identity, interruption policy, and completion meaning.
2. **Map ownership.** Distinguish the native split controller, SwiftUI content, app-owned accessory, and framework-owned glass rendering.
3. **Check the geometry budget.** Pane minima, toolbar space, and content fitting must permit the requested window size.
4. **Choose a driver or a follower.** A driver interpolates a property. A follower reads the driver's current geometry and maps it directly; it must not introduce another spring or guessed duration.
5. **Preserve lifetime.** Keep the native button and its glass assembly together, and keep a hosted SwiftUI glass namespace stable. Use intentional insertion/removal only when choosing a matched-glass transition. Keep frame updates out of SwiftUI-wide observable state.
6. **Validate the API and foreground.** Check the deployment target and exact SDK declaration, especially macOS 26 glass versus macOS 27 interaction. Put AppKit controls in `contentView`, then inspect symbol legibility in the actual appearance and window state.
7. **Verify proportionally.** A styling change needs a build and real visual/input check, including the whole hit area and keyboard focus. A layout/motion change also needs temporal samples, interrupted toggles, Reduce Motion, and the existing regression test.
8. **Record the result.** Separate successful compilation, endpoint appearance, identity evidence, temporal behavior, and remaining verification work.

## Commander context

Read [workspace chrome](../../../docs/workspace-chrome.md) for native pane ownership, persistent accessories, geometry measurements, hosting environments, input routing, and live source links. Read [verification](../../../docs/verification.md) for the Offline host and actual regression suites. The dated investigation records earlier failures and evidence; it does not establish a current test pass.

## Reusable examples

- [GlassButtonExample.swift](examples/GlassButtonExample.swift): native circular glass around a persistent button, with macOS 27 interaction gated separately from macOS 26 glass.
- [MotionRequestState.swift](examples/MotionRequestState.swift): explicit desired/observed/phase state and revision-safe completion for a future **app-owned** animation.

These are reference declarations, not additional app-target files. The state example is useful when the app owns an animation engine; Commander's geometry follower does not need a parallel collapse state machine.

## Companion skills

Use these for deeper engine-specific implementation:

- [fused-glass-morph](../fused-glass-morph/SKILL.md): in-content peel/fuse (composer jump chip), [fusion eligibility](../fused-glass-morph/references/fusion-rules.md), and symbol choreography. Keep that guidance there instead of duplicating SwiftUI fusion timing in this native-controls skill.
- [nssplitview-control](../nssplitview-control/SKILL.md): pane feasibility, priorities, controller ownership, collapse policies, dividers.
- [appkit-animation-control](../appkit-animation-control/SKILL.md): animator proxies, constraint animation, model/presentation layers, SwiftUI curves in AppKit.
- [swiftui-animation-control](../swiftui-animation-control/SKILL.md): transaction scope, identity, springs, phases, keyframes, and interpolation.

For custom SwiftUI `Animatable`/`CustomAnimation` code, also load Apple's installed `swiftui-specialist` skill and its relevant animation reference. This project guide complements that guidance.

## Maintenance

Update this skill when the reusable motion procedure or API understanding changes. Commander implementation guidance and useful investigation evidence belong in [docs/](../../../docs/maintenance.md); routine fixes need no skill or ledger update. Re-discover Xcode tool signatures and workspace IDs in each session. Keep machine-local screenshot paths, launch IDs, and PIDs out of reusable instructions.
