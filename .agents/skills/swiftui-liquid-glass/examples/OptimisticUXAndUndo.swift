import SwiftUI

/// Demonstrates how engineering choices directly shape calm, trustworthy iOS 27 UX:
/// 1. Anticipatory clarity — derives human-readable status from domain state instead of raw fields
/// 2. Optimistic mutation — instant archive/complete on frame 1 with zero blocking spinners
/// 3. Forgiveness over nagging — transient `.materialize` Liquid Glass Undo pill instead of "Are you sure?"
/// 4. Spatial continuity — inset detented sheet keeps the live list/canvas visible & interactive underneath
/// 5. Non-ideal states as first-class UI — helpful `ContentUnavailableView` + quiet offline banner
@available(iOS 27, *)
struct OptimisticUXAndUndoScreen: View {
    struct TaskItem: Identifiable, Hashable {
        let id = UUID()
        var title: String
        var durationMinutes: Int
        var isDone: Bool = false
    }

    @State private var tasks: [TaskItem] = [
        .init(title: "Review flight gate changes", durationMinutes: 5),
        .init(title: "Finalize iOS 27 scroll edges", durationMinutes: 25),
        .init(title: "Profile glass container in Instruments", durationMinutes: 20)
    ]
    @State private var selectedTask: TaskItem?
    @State private var recentlyArchived: (item: TaskItem, index: Int)?
    @State private var isOffline = false
    @State private var feedbackTick = 0

    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    // Anticipatory clarity: compute the human summary instead of forcing mental math
    private var remainingSummary: String {
        let open = tasks.filter { !$0.isDone }
        let totalMinutes = open.reduce(0) { $0 + $1.durationMinutes }
        if open.isEmpty { return "All clear for today" }
        return "\(open.count) left · \(totalMinutes) min total"
    }

    var body: some View {
        NavigationStack {
            ZStack(alignment: .bottom) {
                if tasks.isEmpty {
                    // First-class empty state with plain-English guidance and immediate action
                    ContentUnavailableView {
                        Label("All Clear", systemImage: "checkmark.circle")
                    } description: {
                        Text("Your queue is empty. Capture something new whenever it comes up.")
                    } actions: {
                        Button("Add Sample Task") {
                            withAnimation(reduceMotion ? nil : .snappy) {
                                tasks.append(.init(title: "Plan tomorrow's timeline", durationMinutes: 10))
                            }
                        }
                        .buttonStyle(.glassProminent)
                    }
                } else {
                    ScrollView {
                        LazyVStack(alignment: .leading, spacing: 12) {
                            // Calm synthesized status header (tabular numerals prevent jitter)
                            HStack {
                                Text(remainingSummary)
                                    .font(.subheadline.weight(.medium))
                                    .foregroundStyle(.secondary)
                                    .monospacedDigit()

                                Spacer()

                                // Non-blocking offline indicator — data stays usable
                                if isOffline {
                                    Label("Offline", systemImage: "wifi.slash")
                                        .font(.caption.weight(.medium))
                                        .foregroundStyle(.secondary)
                                }
                            }
                            .padding(.horizontal, 4)

                            ForEach(tasks) { task in
                                TaskRowCard(
                                    task: task,
                                    onToggleDone: { toggleOptimistically(task) },
                                    onInspect: { selectedTask = task }
                                )
                                .swipeActions(edge: .trailing) {
                                    // Instant reversible archive — no nagging confirmation dialog
                                    Button("Archive", systemImage: "archivebox") {
                                        archiveOptimistically(task)
                                    }
                                    .tint(.indigo)
                                }
                            }
                        }
                        .padding()
                        .padding(.bottom, 72)
                    }
                    .swipeActionsContainer()
                    .scrollEdgeEffectStyle(.soft, for: .bottom)
                }

                // Transient `.materialize` Undo glass pill — forgiveness without modal friction
                if let archived = recentlyArchived {
                    HStack(spacing: 12) {
                        Text("Archived \"\(archived.item.title)\"")
                            .font(.footnote.weight(.medium))
                            .lineLimit(1)

                        Button("Undo") {
                            undoArchive()
                        }
                        .font(.footnote.weight(.semibold))
                        .foregroundStyle(.tint)
                    }
                    .padding(.horizontal, 16)
                    .frame(height: 44)
                    .glassEffect(.regular.interactive(), in: .capsule)
                    .glassEffectTransition(reduceMotion ? .identity : .materialize)
                    .transition(reduceMotion ? .opacity : .opacity.combined(with: .scale(scale: 0.95)))
                    .padding(.bottom, 16)
                    .task(id: archived.item.id) {
                        try? await Task.sleep(for: .seconds(4))
                        withAnimation(reduceMotion ? nil : .smooth(duration: 0.25)) {
                            if recentlyArchived?.item.id == archived.item.id {
                                recentlyArchived = nil
                            }
                        }
                    }
                }
            }
            .navigationTitle("Today")
            .sensoryFeedback(.selection, trigger: feedbackTick)
            // Spatial continuity: half-height inset sheet keeps the parent schedule visible & alive
            .sheet(item: $selectedTask) { task in
                TaskDetailSheet(task: task)
                    .presentationDetents([.medium, .large])
                    .presentationBackgroundInteraction(.enabled(upThrough: .medium))
            }
        }
    }

    private func toggleOptimistically(_ task: TaskItem) {
        guard let idx = tasks.firstIndex(where: { $0.id == task.id }) else { return }
        withAnimation(reduceMotion ? nil : .snappy(duration: 0.25)) {
            tasks[idx].isDone.toggle()
        }
        feedbackTick += 1
        // Sync asynchronously in background without blocking the UI:
        // Task { try? await syncService.update(tasks[idx]) }
    }

    private func archiveOptimistically(_ task: TaskItem) {
        guard let idx = tasks.firstIndex(where: { $0.id == task.id }) else { return }
        withAnimation(reduceMotion ? nil : .snappy(duration: 0.28)) {
            let removed = tasks.remove(at: idx)
            recentlyArchived = (removed, idx)
        }
        feedbackTick += 1
    }

    private func undoArchive() {
        guard let archived = recentlyArchived else { return }
        withAnimation(reduceMotion ? nil : .snappy(duration: 0.28)) {
            let safeIndex = min(archived.index, tasks.count)
            tasks.insert(archived.item, at: safeIndex)
            recentlyArchived = nil
        }
        feedbackTick += 1
    }
}

@available(iOS 26, *)
private struct TaskRowCard: View {
    let task: OptimisticUXAndUndoScreen.TaskItem
    let onToggleDone: () -> Void
    let onInspect: () -> Void

    var body: some View {
        HStack(spacing: 12) {
            Button(action: onToggleDone) {
                Image(systemName: task.isDone ? "checkmark.circle.fill" : "circle")
                    .font(.title3)
                    .foregroundStyle(task.isDone ? Color.green : Color.secondary)
            }
            .buttonStyle(.plain)
            .accessibilityLabel(task.isDone ? "Mark incomplete" : "Mark complete")

            Button(action: onInspect) {
                HStack {
                    Text(task.title)
                        .font(.body.weight(.medium))
                        .strikethrough(task.isDone)
                        .foregroundStyle(task.isDone ? .secondary : .primary)
                    Spacer()
                    Text("\(task.durationMinutes)m")
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                        .monospacedDigit()
                }
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
        }
        .padding(16)
        .background(.background.secondary, in: ConcentricRectangle())
    }
}

private struct TaskDetailSheet: View {
    let task: OptimisticUXAndUndoScreen.TaskItem
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        NavigationStack {
            Form {
                Section("Focus Block") {
                    LabeledContent("Task", value: task.title)
                    LabeledContent("Estimated Time", value: "\(task.durationMinutes) min")
                }
            }
            .navigationTitle("Details")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("Done") { dismiss() }
                        .buttonStyle(.glassProminent)
                }
            }
        }
    }
}
