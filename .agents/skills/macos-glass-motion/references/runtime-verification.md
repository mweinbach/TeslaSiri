# Verify the actual window, not just the build

## Match evidence to the claim

| Claim | Required evidence |
| --- | --- |
| API usage is valid | Build or type-check against the target SDK/deployment |
| Glass looks correct at an endpoint | Screenshot of a real window or suitable preview |
| A mouse/keyboard action works | Deliver input and verify actual collapse state before/after |
| One control remains alive | Compare object identity over multiple points in the transition |
| Travel is continuous | Observe motion and sample intermediate geometry in a running event loop |
| Reopening does not enlarge the window | Sample the whole window frame during transitions |
| Reversal is safe | Interrupt before completion, repeat, and inspect final state and motion |

A successful build cannot establish any of the runtime claims. A static screenshot cannot prove a continuous path. An action dispatcher returning `true` does not prove the intended split view changed state.

## Commander regression and host

Project-specific suites, Offline configuration, startup guards, and source links live in [docs/verification.md](../../../../docs/verification.md). Prior mouse-event, accessibility, recording, and test-count observations live in [the dated investigation](../../../../docs/investigations/2026-09-sidebar-glass.md). Read the current test source instead of copying its thresholds or helper implementation into a skill.

Use an asynchronous main-actor sampling test so both SwiftUI layout commits and native animation can advance. A nested synchronous run loop can leave actor-scheduled work blocked and produce stale geometry. Display and yield before comparing completed layout when the tested follower defers measurement. This does not guarantee sampling every rendered frame.

A real target/action dispatch must be followed by a check that the intended state changed. It does not synthesize a physical click or native shortcut. Verify activation and first-responder state for keyboard coverage. An empty lazy accessibility tree is not evidence that controls are absent.

Discover current Xcode tool signatures and workspace identifiers before running targeted checks. Keep build/run/preview/test operations sequential against the same workspace. Inspect final counts and individual results; retain relevant failed/retried diagnostics rather than calling every retry a clean pass.

## Additional scenarios for future changes

Use this matrix when the affected behavior warrants it; these are not all claimed as completed checks:

| Change | Add verification for |
| --- | --- |
| Track attachment/lifetime | Close/detach while moving, move between windows, recreate workspace |
| Native titlebar integration | Fullscreen, hidden/revealed titlebar, toolbar visibility, title/accessory collisions |
| Geometry model | Drag sidebar divider through allowed widths, resize during motion, initial hidden sidebar |
| Input routing | Native shortcut, menu validation, keyboard focus, multiple active windows |
| Material/interaction | Active/inactive, light/dark, hover/press, Reduce Transparency, Increase Contrast |
| Custom timing | Reduce Motion, repeated same target, mid-flight reversal, gesture cancellation |
| Dynamic detail content | Switch thread during motion, long transcript, diff/output scrollers, background UI updates |
| Generalized coordinate system | RTL layout, different display scale, altered clipping/ancestor geometry |

Do not claim window stability at an infeasible expanded width. State the tested widths and pane minima. If new content introduces a larger minimum, revisit the constraint budget before blaming the animation engine.

## Result template

```text
Environment: Xcode __ / SDK __ / runtime __ / deployment __
Source revision or working-tree description: __
Control owner / driver / measured geometry: __
Build or type-check: __
Runtime input and actual before/after state: __
Window widths / frame extrema: __
Button, parent, and material identity checks: __
Motion samples / reversal behavior: __
Regression identifier and final counts: __
Visual states inspected: __
Unverified relevant scenarios: __
```

Use concise summaries in user responses. Keep useful detailed evidence in the project investigation, issue, or test record rather than conflating an implementation claim with a build result. Routine changes need no permanent evidence record.
