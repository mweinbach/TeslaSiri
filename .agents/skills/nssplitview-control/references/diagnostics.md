# Split-view diagnosis and fine-detail verification

## Symptom -> first inspection -> likely correction

| Symptom | Inspect first | Correction to evaluate |
| --- | --- | --- |
| Window grows when sidebar opens | Effective minima, collapse behavior, available split bounds | Choose sibling-resize preference and a feasible minimum budget |
| Divider moves, then jumps back | Repeated restored-width writes; conflicting animation engines | Restore once; assign one geometry owner |
| Sidebar width drifts while resizing | Holding-priority order; descendant fitting constraints | Make intended flexible pane lowest priority |
| Sidebar cannot be dragged narrower | Child minimum, fixed SwiftUI frame, compression resistance | Correct content fitting or accept a real minimum |
| Inspector starts fixed width | Inspector initializer defaults | Set explicit min/max for a resizable inspector |
| Toggle state disagrees with visible pane | Automatic collapse, echo suppression, stale deferred callback | Reconcile intent and observed state with revisions |
| Hidden pane cannot be reopened | Toggle was inside collapsed subtree; minimum budget | Keep command reachable; resolve feasibility |
| Divider hard to grab | Drawn rect versus effective hit rect | Preserve/extend the system effective rect |
| Clicking adjacent control drags divider | Oversized effective/additional drag rectangle | Reduce overlap and convert coordinates correctly |
| Reopening loses scroll/selection | Controller/item/SwiftUI identity replacement | Retain controllers and semantic view identity |
| Persisted width becomes zero | Sampling collapsed or in-flight geometry | Preserve last meaningful expanded width |
| Appears smooth in preview, jumps in window | Window constraints, toolbar, live resize, actual hosting | Reproduce in an actual window |

## Capture one useful trace

For a reproducing action, log lightweight snapshots at request, meaningful observation, and completion/settling:

```text
timestamp and request revision
window identity and outer/content frame
split bounds and divider thickness
each item: isCollapsed, frame, min/max, holdingPriority, collapseBehavior
each relevant view: fitting size, ambiguous-layout flag
requested visibility and whether bridge is applying a model update
live-resize/full-screen/reduced-motion state
```

Do not serialize the entire view tree on every animation frame. Start with one window and one action so chronology is readable. A final `isCollapsed` Boolean does not tell you whether the trajectory jumped.

Use Xcode's view debugger and constraint diagnostics to find the view actually enforcing the width. Give app-created constraints identifiers so diagnostics are meaningful. Fix the constraint owner rather than immediately adding a competing higher-priority constraint.

## A useful minimal reproduction

1. Replace expensive pane content with simple colored Auto Layout containers while keeping the split policy.
2. Reproduce at a width just above and just below the calculated minimum budget.
3. Compare immediate collapse, classic item animator, and the modern SwiftUI-animation route separately.
4. Restore real hosted content one pane at a time.
5. Introduce autosave or app restoration last.

This sequence distinguishes geometry errors, animation ownership, content fitting, and restoration races without requiring a new abstraction at each step.

## Motion acceptance criteria

Define only criteria relevant to the requested change, using observable outcomes:

- **Window stability:** when the minima fit and fixed-split behavior is intended, compare start/end window frames and inspect the trajectory for transient growth.
- **Retargeting:** click collapse/expand several times before completion; final state follows the last command with no stale focus or visibility update.
- **Boundary behavior:** drag to both limits, double-click the divider if supported, collapse/reopen, and resize the window across the threshold.
- **Persistence:** reopen at different sizes; saved preferences clamp without generating constraint failures or overriding a fresh user drag.
- **Focus:** keyboard focus stays in visible content; the toggle remains accessible and accurately labeled.
- **Displays:** move between different backing scales; separators stay aligned and hit targets still track them.
- **Performance:** trace live resize and animation with representative content, not only placeholder rectangles.

Screenshots prove appearance at sampled times; recordings or interactive observation are needed to assess interruption and motion continuity. Do not claim “smooth” based solely on a build or preview snapshot.
