import AppKit
import SwiftUI

struct ApplicationUninstallerView: View {
    let closeAction: (String?) -> Void
    @State private var model = ApplicationUninstallerViewModel()
    @State private var confirmsPermanentDeletion = false

    var body: some View {
        HStack(spacing: 0) {
            ApplicationListPanel(model: model)
            UninstallInspectorPanel(
                model: model,
                closeAction: { closeAction(model.successMessage) },
                deleteAction: { confirmsPermanentDeletion = true }
            )
        }
        .task { await model.loadApplications() }
        .alert(
            "Удалить без возможности восстановления?",
            isPresented: $confirmsPermanentDeletion
        ) {
            Button("Отмена", role: .cancel) {}
            Button("Удалить навсегда", role: .destructive) {
                Task { await model.permanentlyDeleteSelectedApplication() }
            }
        } message: {
            if let plan = model.plan {
                Text(
                    "Выбранные объекты размером \(ByteSizeFormatter.string(from: selectedSize(plan))) будут удалены навсегда. "
                    + "Корзина не используется."
                    + (plan.requiresVendorUninstaller
                        ? " У приложения обнаружены управляемые компоненты; предпочтительнее штатный деинсталлятор."
                        : "")
                )
            }
        }
        .alert(
            "Приложение сейчас запущено",
            isPresented: Binding(
                get: { !model.runningApplicationsAwaitingTermination.isEmpty },
                set: { if !$0 { model.cancelRunningApplicationTermination() } }
            )
        ) {
            Button("Вернуться", role: .cancel) {
                model.cancelRunningApplicationTermination()
            }
            Button("Завершить и удалить", role: .destructive) {
                Task { await model.terminateRunningApplicationsAndDelete() }
            }
        } message: {
            Text(
                "Чтобы продолжить, нужно завершить: "
                + model.runningApplicationsAwaitingTermination.joined(separator: ", ")
                + ". Несохранённые изменения могут быть потеряны."
            )
        }
        .alert(
            "Ошибка деинсталлятора",
            isPresented: Binding(
                get: { model.errorMessage != nil },
                set: { if !$0 { model.errorMessage = nil } }
            )
        ) {
            Button("OK", role: .cancel) {}
        } message: {
            Text(model.errorMessage ?? "")
        }
    }

    private func selectedSize(_ plan: ApplicationUninstallPlan) -> Int64 {
        (model.isApplicationSelected ? plan.application.size : 0) + plan.relatedItems
            .filter { model.selectedRelatedIDs.contains($0.id) }
            .reduce(0) { $0 + $1.size }
    }
}

private struct ApplicationListPanel: View {
    let model: ApplicationUninstallerViewModel

    var body: some View {
        Group {
            if model.state == .loadingApplications {
                ProgressView("Загрузка")
                    .controlSize(.large)
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else {
                VStack(spacing: 0) {
                    HStack {
                        Text("Приложения")
                            .font(.title2.bold())
                        Spacer()
                        Text("\(model.applications.count)")
                            .foregroundStyle(.secondary)
                    }
                    .padding()

                    Divider()

                    if model.applications.isEmpty {
                        ContentUnavailableView("Приложения не найдены", systemImage: "app.dashed")
                    } else {
                        ScrollView {
                            LazyVStack(spacing: 4) {
                                ForEach(model.applications) { application in
                                    Button {
                                        Task { await model.select(application) }
                                    } label: {
                                        ApplicationRow(
                                            application: application,
                                            isSelected: model.selectedApplicationID == application.id
                                        )
                                    }
                                    .buttonStyle(.plain)
                                }
                            }
                            .padding(8)
                        }
                    }
                }
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(Color(nsColor: .underPageBackgroundColor))
    }
}

private struct ApplicationRow: View {
    let application: InstalledApplication
    let isSelected: Bool

    var body: some View {
        HStack(spacing: 12) {
            Image(nsImage: NSWorkspace.shared.icon(forFile: application.url.path))
                .resizable()
                .scaledToFit()
                .frame(width: 42, height: 42)

            VStack(alignment: .leading, spacing: 3) {
                Text(application.name)
                    .font(.body.weight(.medium))
                    .lineLimit(1)
                HStack(spacing: 8) {
                    if let version = application.version {
                        Text(version)
                    }
                    Text(ByteSizeFormatter.string(from: application.size))
                }
                .font(.caption)
                .foregroundStyle(.secondary)
            }

            Spacer()
        }
        .padding(8)
        .background(
            isSelected ? Color.accentColor.opacity(0.34) : Color.clear,
            in: RoundedRectangle(cornerRadius: 9)
        )
        .contentShape(Rectangle())
    }
}

private struct UninstallInspectorPanel: View {
    let model: ApplicationUninstallerViewModel
    let closeAction: () -> Void
    let deleteAction: () -> Void

    var body: some View {
        Group {
            if model.state == .loadingApplications {
                Color.clear
            } else {
                VStack(spacing: 0) {
                    HStack {
                        Button("Начать заново", systemImage: "arrow.clockwise", action: closeAction)
                        Spacer()
                    }
                    .padding()
                    .padding(.top, 28)

                    Divider()

                    if model.state == .loadingPlan {
                        ProgressView("Поиск связанных файлов…")
                            .frame(maxWidth: .infinity, maxHeight: .infinity)
                    } else if let plan = model.plan {
                        UninstallPlanView(model: model, plan: plan, deleteAction: deleteAction)
                    } else {
                        ContentUnavailableView(
                            "Выберите приложение",
                            systemImage: "cursorarrow.click",
                            description: Text("KleanBytes покажет пакет приложения и подтверждённые связанные файлы.")
                        )
                    }
                }
                .frame(maxHeight: .infinity, alignment: .top)
            }
        }
        .dashboardSidebar(width: 280)
    }
}

private struct UninstallPlanView: View {
    let model: ApplicationUninstallerViewModel
    let plan: ApplicationUninstallPlan
    let deleteAction: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            HStack(spacing: 12) {
                Image(nsImage: NSWorkspace.shared.icon(forFile: plan.application.url.path))
                    .resizable()
                    .scaledToFit()
                    .frame(width: 52, height: 52)
                VStack(alignment: .leading, spacing: 3) {
                    Text(plan.application.name).font(.title3.bold())
                    Text(plan.application.bundleIdentifier)
                        .font(.caption.monospaced())
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                }
            }

            SlashWrappingPathView(path: plan.application.url.path)

            if plan.requiresVendorUninstaller {
                Image(systemName: "exclamationmark.triangle.fill")
                    .font(.title3)
                .foregroundStyle(.orange)
                    .help("Для этого приложения рекомендуется штатный деинсталлятор разработчика.")
                    .accessibilityLabel("Рекомендуется штатный деинсталлятор")
            }

            Divider()

            Text("Будет удалено")
                .font(.headline)

            ScrollView {
                LazyVStack(spacing: 6) {
                    SelectableApplicationItem(
                        application: plan.application,
                        isSelected: model.isApplicationSelected,
                        toggleAction: model.toggleApplicationSelection
                    )
                    ForEach(plan.relatedItems) { item in
                        RelatedApplicationItem(
                            item: item,
                            isSelected: model.selectedRelatedIDs.contains(item.id),
                            toggleAction: { model.toggle(item) }
                        )
                    }
                }
            }

            Button("Удалить выбранное навсегда", role: .destructive, action: deleteAction)
                .disabled(
                    model.state == .deleting
                        || (!model.isApplicationSelected && model.selectedRelatedIDs.isEmpty)
                )
                .frame(maxWidth: .infinity)
        }
        .padding()
    }

}

private struct SelectableApplicationItem: View {
    let application: InstalledApplication
    let isSelected: Bool
    let toggleAction: () -> Void

    var body: some View {
        Button(action: toggleAction) {
            HStack(spacing: 9) {
                Image(systemName: isSelected ? "checkmark.square.fill" : "square")
                VStack(alignment: .leading, spacing: 2) {
                    Text("Пакет приложения")
                    Text(application.url.lastPathComponent)
                        .font(.caption.monospaced())
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                }
                Spacer()
                Text(ByteSizeFormatter.string(from: application.size))
                    .font(.caption.monospacedDigit())
                    .foregroundStyle(.secondary)
            }
            .padding(8)
            .background(Color.white.opacity(0.06), in: RoundedRectangle(cornerRadius: 8))
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .contextMenu {
            Button("Показать в Finder", systemImage: "folder") {
                NSWorkspace.shared.activateFileViewerSelecting([application.url])
            }
        }
    }
}

private struct RelatedApplicationItem: View {
    let item: ApplicationRelatedItem
    let isSelected: Bool
    let toggleAction: () -> Void

    var body: some View {
        Button(action: toggleAction) {
            HStack(spacing: 9) {
                Image(systemName: isSelected ? "checkmark.square.fill" : "square")
                VStack(alignment: .leading, spacing: 2) {
                    Text(item.category.rawValue)
                    Text(item.url.lastPathComponent)
                        .font(.caption.monospaced())
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                }
                Spacer()
                if !item.isSizeCalculated {
                    ProgressView()
                        .controlSize(.mini)
                } else {
                    Text(ByteSizeFormatter.string(from: item.size))
                        .font(.caption.monospacedDigit())
                        .foregroundStyle(.secondary)
                }
            }
            .padding(8)
            .background(Color.white.opacity(0.06), in: RoundedRectangle(cornerRadius: 8))
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .contextMenu {
            Button("Показать в Finder", systemImage: "folder") {
                NSWorkspace.shared.activateFileViewerSelecting([item.url])
            }
        }
    }
}

private struct SlashWrappingPathView: View {
    let path: String

    private var components: [String] {
        path.split(separator: "/", omittingEmptySubsequences: true).map { "/" + $0 }
    }

    var body: some View {
        SlashWrappingLayout(lineSpacing: 2) {
            ForEach(Array(components.enumerated()), id: \.offset) { _, component in
                Text(component)
                    .font(.caption.monospaced())
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
                    .truncationMode(.tail)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .accessibilityLabel(path)
    }
}

private struct SlashWrappingLayout: Layout {
    let lineSpacing: CGFloat

    func sizeThatFits(
        proposal: ProposedViewSize,
        subviews: Subviews,
        cache: inout ()
    ) -> CGSize {
        layout(proposal: proposal, subviews: subviews).size
    }

    func placeSubviews(
        in bounds: CGRect,
        proposal: ProposedViewSize,
        subviews: Subviews,
        cache: inout ()
    ) {
        let result = layout(proposal: ProposedViewSize(width: bounds.width, height: proposal.height), subviews: subviews)
        for placement in result.placements {
            subviews[placement.index].place(
                at: CGPoint(x: bounds.minX + placement.origin.x, y: bounds.minY + placement.origin.y),
                proposal: ProposedViewSize(width: placement.size.width, height: placement.size.height)
            )
        }
    }

    private func layout(proposal: ProposedViewSize, subviews: Subviews) -> LayoutResult {
        let maximumWidth = max(proposal.width ?? 0, 1)
        var x: CGFloat = 0
        var y: CGFloat = 0
        var lineHeight: CGFloat = 0
        var placements: [Placement] = []

        for index in subviews.indices {
            let idealSize = subviews[index].sizeThatFits(.unspecified)
            let itemWidth = min(idealSize.width, maximumWidth)
            let itemSize = subviews[index].sizeThatFits(
                ProposedViewSize(width: itemWidth, height: nil)
            )

            if x > 0, x + itemSize.width > maximumWidth {
                x = 0
                y += lineHeight + lineSpacing
                lineHeight = 0
            }

            placements.append(
                Placement(index: index, origin: CGPoint(x: x, y: y), size: itemSize)
            )
            x += itemSize.width
            lineHeight = max(lineHeight, itemSize.height)
        }

        return LayoutResult(
            size: CGSize(width: maximumWidth, height: y + lineHeight),
            placements: placements
        )
    }

    private struct Placement {
        let index: Int
        let origin: CGPoint
        let size: CGSize
    }

    private struct LayoutResult {
        let size: CGSize
        let placements: [Placement]
    }
}
