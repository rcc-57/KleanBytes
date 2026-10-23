import AppKit
import SwiftUI

struct ResultsView: View {
    let directory: FileSystemNode
    let canNavigateBack: Bool
    let checkedIDs: Set<URL>
    let selectedNodes: [FileSystemNode]
    let isDeletingSelection: Bool
    let unlockedIDs: Set<URL>
    let quickScanConfiguration: QuickScanConfiguration
    let scanMode: DiskScanMode
    @Binding var selection: URL?
    @State private var helpNode: FileSystemNode?
    @State private var scrollPositions: [URL: URL] = [:]
    @State private var showsSelectedItems = false
    let backAction: () -> Void
    let rescanAction: () -> Void
    let openAction: (FileSystemNode) -> Void
    let toggleChecked: (FileSystemNode) -> Void
    let removeFromSelection: (FileSystemNode) -> Void
    let toggleQuickScanMembership: (FileSystemNode) -> Void
    let unlockAction: (FileSystemNode) async -> Void
    let lockAction: (FileSystemNode) -> Void
    let revealAction: (FileSystemNode) -> Void
    let makeDeletionPlan: () async -> SecureDeletionPlan
    let deleteSelectedAction: (SecureDeletionPlan) async -> DiskScannerViewModel.DeletionOutcome
    let finishDeletionAction: (String) -> Void

    private var inspectedNode: FileSystemNode? {
        directory.children.first { $0.id == selection }
    }

    var body: some View {
        HStack(spacing: 0) {
            VStack(spacing: 0) {
                browserHeader
                Divider()
                browser
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .background(Color(nsColor: .underPageBackgroundColor))

            VStack(spacing: 0) {
                inspectorHeader
                Divider()
                FileInspectorView(
                    node: inspectedNode,
                    scanMode: scanMode,
                    isUnlocked: inspectedNode.map { unlockedIDs.contains($0.id) } ?? false,
                    quickScanMembership: inspectedNode.map { quickScanConfiguration.membership(of: $0) },
                    revealAction: revealAction,
                    toggleQuickScanMembership: toggleQuickScanMembership,
                    unlockAction: unlockAction,
                    lockAction: lockAction,
                    helpAction: { helpNode = $0 },
                    selectedItemCount: selectedNodes.count,
                    showSelectedItemsAction: { showsSelectedItems = true }
                )
            }
            .frame(maxHeight: .infinity, alignment: .top)
            .dashboardSidebar(width: 280)
        }
        .sheet(item: $helpNode) { node in
            HelpSearchView(node: node)
        }
        .sheet(isPresented: $showsSelectedItems) {
            SelectedItemsReviewView(
                items: selectedNodes,
                isDeleting: isDeletingSelection,
                makeDeletionPlan: makeDeletionPlan,
                deleteAction: deleteSelectedAction,
                removeAction: removeFromSelection,
                finishDeletionAction: finishDeletionAction
            )
        }
    }

    private var browserHeader: some View {
        HStack {
            Button(action: backAction) {
                Label("Назад", systemImage: "chevron.left")
            }
            .disabled(!canNavigateBack)

            Text(directory.url.path)
                .font(.system(.body, design: .monospaced))
                .lineLimit(1)
                .truncationMode(.middle)

            Spacer(minLength: 0)
        }
        .padding()
    }

    private var inspectorHeader: some View {
        HStack {
            Button("Сканировать повторно", systemImage: "arrow.clockwise") {
                rescanAction()
            }
            .help("Вернуться к выбору режима анализа")

            Spacer(minLength: 0)
        }
        .padding()
        .padding(.top, 32)
    }

    private var browser: some View {
        ScrollView {
            LazyVStack(spacing: 0) {
                ForEach(directory.sortedChildren) { node in
                    FileBrowserRow(
                        node: node,
                        isChecked: checkedIDs.contains(node.id),
                        isUnlocked: unlockedIDs.contains(node.id),
                        toggleChecked: { toggleChecked(node) }
                    )
                    .padding(.horizontal, 12)
                    .background(
                        selection == node.id
                            ? Color.accentColor.opacity(0.34)
                            : Color.clear,
                        in: RoundedRectangle(cornerRadius: 6)
                    )
                    .contentShape(Rectangle())
                    .simultaneousGesture(
                        TapGesture(count: 1)
                            .onEnded {
                                selection = node.id
                            }
                    )
                    .simultaneousGesture(
                        TapGesture(count: 2)
                            .onEnded {
                                if node.isDirectory && !FileAccessPolicy.isApplicationsDirectory(node.url) {
                                    openAction(node)
                                }
                            }
                    )
                    .id(node.id)
                }
            }
            .scrollTargetLayout()
            .padding(6)
        }
        .scrollPosition(id: scrollPositionBinding, anchor: .top)
        .id(directory.id)
    }

    private var scrollPositionBinding: Binding<URL?> {
        Binding(
            get: { scrollPositions[directory.id] },
            set: { newValue in
                if let newValue {
                    scrollPositions[directory.id] = newValue
                }
            }
        )
    }
}

private struct FileBrowserRow: View {
    let node: FileSystemNode
    let isChecked: Bool
    let isUnlocked: Bool
    let toggleChecked: () -> Void

    private var contentOpacity: Double {
        node.isHidden ? 0.55 : 1
    }

    var body: some View {
        HStack(spacing: 12) {
            leadingControl

            nodeIcon
                .opacity(contentOpacity)

            Text(node.name)
                .font(.body.weight(.medium))
                .lineLimit(1)
                .opacity(contentOpacity)

            Spacer()

            Text(displayedSize)
                .monospacedDigit()
                .foregroundStyle(.secondary)
                .opacity(contentOpacity)
        }
        .padding(.vertical, 7)
    }

    private var displayedSize: String {
        if FileAccessPolicy.isApplicationsDirectory(node.url), node.size < 0 {
            return "—"
        }
        return ByteSizeFormatter.string(from: node.size)
    }

    private var nodeIcon: some View {
        ZStack(alignment: .bottomTrailing) {
            Image(nsImage: NSWorkspace.shared.icon(forFile: node.url.path))
                .resizable()
                .scaledToFit()

            if let presentation = node.presentation {
                badgeImage(presentation.badge)
                    .frame(width: 18, height: 18)
                    .background(.background, in: RoundedRectangle(cornerRadius: 4))
            }
        }
        .frame(width: 38, height: 38)
    }

    @ViewBuilder
    private func badgeImage(_ badge: FileItemBadge) -> some View {
        switch badge {
        case .asset(let name):
            Image(name)
                .resizable()
                .scaledToFit()
        case .systemSymbol(let name):
            Image(systemName: name)
                .resizable()
                .scaledToFit()
                .padding(2)
        }
    }

    @ViewBuilder
    private var leadingControl: some View {
        if FileAccessPolicy.isApplicationsDirectory(node.url) {
            Color.clear
                .frame(width: 20, height: 20)
                .accessibilityHidden(true)
        } else if node.accessPolicy.showsLock && !isUnlocked {
            Image(systemName: "lock.fill")
                .font(.title3)
                .foregroundStyle(.secondary)
                .frame(width: 20, height: 20)
                .help("Защищённый объект")
        } else if node.accessPolicy.isSelectable || isUnlocked {
            Button(action: toggleChecked) {
                Image(systemName: isChecked ? "checkmark.square.fill" : "square")
                    .font(.title3)
                    .frame(width: 20, height: 20)
            }
            .buttonStyle(.plain)
            .help(isChecked ? "Снять выбор" : "Выбрать")
        } else {
            Color.clear
                .frame(width: 20, height: 20)
                .accessibilityHidden(true)
        }
    }
}

private struct SelectedItemsReviewView: View {
    let items: [FileSystemNode]
    let isDeleting: Bool
    let makeDeletionPlan: () async -> SecureDeletionPlan
    let deleteAction: (SecureDeletionPlan) async -> DiskScannerViewModel.DeletionOutcome
    let removeAction: (FileSystemNode) -> Void
    let finishDeletionAction: (String) -> Void
    @Environment(\.dismiss) private var dismiss
    @State private var isConfirmingDeletion = false
    @State private var plan: SecureDeletionPlan?
    @State private var deletionAlert: SelectionDeletionAlert?

    private var totalSize: Int64 {
        items.reduce(0) { $0 + $1.size }
    }

    var body: some View {
        VStack(spacing: 0) {
            HStack {
                VStack(alignment: .leading, spacing: 3) {
                    Text("Выбранные объекты")
                        .font(.title2.bold())
                    Text("\(items.count) шт. · \(ByteSizeFormatter.string(from: totalSize))")
                        .foregroundStyle(.secondary)
                }
                Spacer()
                Button("Закрыть") { dismiss() }
                    .disabled(isDeleting)
            }
            .padding()

            Divider()

            List(items) { node in
                SelectedItemRow(
                    node: node,
                    assessment: assessment(for: node),
                    isDeleting: isDeleting,
                    removeAction: { removeAction(node) }
                )
            }
            .listStyle(.inset)

            Divider()

            HStack {
                Text(footerMessage)
                    .font(.callout)
                    .foregroundStyle(.secondary)
                Spacer()
                Button(role: .destructive) {
                    isConfirmingDeletion = true
                } label: {
                    if isDeleting {
                        ProgressView()
                            .controlSize(.small)
                    } else {
                        Label("Стереть", systemImage: "trash.fill")
                    }
                }
                .buttonStyle(.borderedProminent)
                .tint(.red)
                .disabled(plan?.deletableTargets.isEmpty != false || isDeleting)
            }
            .padding()
        }
        .frame(minWidth: 600, minHeight: 480)
        .task(id: Set(items.map(\.id))) {
            plan = await makeDeletionPlan()
        }
        .alert("Стереть выбранное навсегда?", isPresented: $isConfirmingDeletion) {
            Button("Отмена", role: .cancel) {}
            Button("Стереть", role: .destructive) {
                Task {
                    guard let plan else { return }
                    switch await deleteAction(plan) {
                    case .completed(let message):
                        deletionAlert = SelectionDeletionAlert(
                            title: "Удаление выполнено",
                            message: message,
                            returnsToStart: true
                        )
                    case .partiallyCompleted(let message):
                        deletionAlert = SelectionDeletionAlert(
                            title: "Удаление выполнено частично",
                            message: message,
                            returnsToStart: true
                        )
                    case .nothingDeleted(let message):
                        deletionAlert = SelectionDeletionAlert(
                            title: "Удаление не выполнено",
                            message: message,
                            returnsToStart: false
                        )
                    }
                }
            }
        } message: {
            if plan?.requiresUnlockWarning == true {
                Text(unlockWarningMessage)
            } else {
                Text("Будет удалено объектов: \(items.count). Отменить это действие будет невозможно. Для объектов, которым нужны повышенные права, macOS отдельно запросит пароль администратора.")
            }
        }
        .alert(item: $deletionAlert) { alert in
            Alert(
                title: Text(alert.title),
                message: Text(alert.message),
                dismissButton: .default(Text("OK")) {
                    if alert.returnsToStart {
                        finishDeletionAction(alert.message)
                    } else {
                        dismiss()
                    }
                }
            )
        }
    }

    private var footerMessage: String {
        guard let plan else { return "Проверка возможности удаления…" }
        if plan.protectedTargets.isEmpty {
            return "Удаление выполняется навсегда, без Корзины."
        }
        if plan.deletableTargets.isEmpty {
            return "Выбранные объекты защищены macOS и не будут удалены."
        }
        return "Системные объекты будут пропущены; остальные удалятся навсегда."
    }

    private func assessment(for node: FileSystemNode) -> DeletionTargetAssessment? {
        plan?.targets.first { $0.url.standardizedFileURL == node.url.standardizedFileURL }
    }

    private var unlockWarningMessage: String {
        guard let plan else { return "" }
        let names = plan.deletableTargets.compactMap { assessment -> String? in
            guard case .requiresUnlockWarning = assessment.risk else { return nil }
            return "«\(assessment.url.lastPathComponent)»"
        }.joined(separator: "\n")
        return "Эти файлы были разблокированы вручную:\n\n\(names)\n\nИх удаление потенциально опасно и может привести к потере данных или нарушить работу программ. Подтвердите удаление ещё раз."
    }
}

private struct SelectionDeletionAlert: Identifiable {
    let id = UUID()
    let title: String
    let message: String
    let returnsToStart: Bool
}

private struct SelectedItemRow: View {
    let node: FileSystemNode
    let assessment: DeletionTargetAssessment?
    let isDeleting: Bool
    let removeAction: () -> Void

    var body: some View {
        HStack(spacing: 12) {
            Image(nsImage: NSWorkspace.shared.icon(forFile: node.url.path))
                .resizable()
                .scaledToFit()
                .frame(width: 34, height: 34)

            VStack(alignment: .leading, spacing: 3) {
                Text(node.name)
                    .fontWeight(.medium)
                    .lineLimit(1)
                Text(node.url.deletingLastPathComponent().path)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
                    .truncationMode(.middle)
            }

            Spacer()

            Text(ByteSizeFormatter.string(from: node.size))
                .monospacedDigit()
                .foregroundStyle(.secondary)

            if let status {
                Label(status.text, systemImage: status.symbol)
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(status.color)
            }

            Button(action: removeAction) {
                Image(systemName: "xmark.circle.fill")
                    .foregroundStyle(.secondary)
            }
            .buttonStyle(.plain)
            .disabled(isDeleting)
            .help("Убрать из выборки")
            .accessibilityLabel("Убрать \(node.name) из выборки")
        }
        .padding(.vertical, 4)
    }

    private var status: (text: String, symbol: String, color: Color)? {
        guard let assessment else { return nil }
        switch assessment.risk {
        case .systemProtected:
            return nil
        case .requiresUnlockWarning:
            return nil
        case .requiresAdministrator:
            return ("Нужны права администратора", "person.badge.key.fill", .orange)
        case .normal:
            return nil
        }
    }
}
