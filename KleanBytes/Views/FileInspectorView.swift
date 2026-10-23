import AppKit
import SwiftUI

struct FileInspectorView: View {
    let node: FileSystemNode?
    let scanMode: DiskScanMode
    let isUnlocked: Bool
    let quickScanMembership: QuickScanMembership?
    let revealAction: (FileSystemNode) -> Void
    let toggleQuickScanMembership: (FileSystemNode) -> Void
    let unlockAction: (FileSystemNode) async -> Void
    let lockAction: (FileSystemNode) -> Void
    let helpAction: (FileSystemNode) -> Void
    let selectedItemCount: Int
    let showSelectedItemsAction: () -> Void
    @State private var isConfirmingUnlock = false
    @State private var copyConfirmationID: UUID?

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            if let node {
                inspectorHeader(for: node)

                Divider()

                LabeledContent("Размер", value: displayedSize(for: node))

                InspectorPathView(
                    path: node.url.path,
                    didCopy: copyConfirmationID != nil
                ) {
                    copyPath(node.url.path)
                }

                if selectedItemCount > 0 {
                    selectedItemsButton
                }

                Spacer()

                Button("Показать в Finder", systemImage: "finder") {
                    revealAction(node)
                }
                .frame(maxWidth: .infinity)
            } else if selectedItemCount > 0 {
                selectedItemsButton
            } else {
                ContentUnavailableView(
                    "Выберите объект",
                    systemImage: "cursorarrow.click",
                    description: Text("Здесь появятся путь и размер выбранного файла или папки.")
                )
            }
        }
        .padding()
        .frame(
            minWidth: 280,
            idealWidth: 280,
            maxWidth: 280,
            maxHeight: .infinity,
            alignment: .topLeading
        )
        .background(alignment: .bottom) {
            SidebarBottomFade(height: 130)
        }
        .confirmationDialog(
            "Разблокировать объект?",
            isPresented: $isConfirmingUnlock,
            titleVisibility: .visible
        ) {
            Button("Продолжить") {
                guard let node else { return }
                Task { await unlockAction(node) }
            }
            Button("Отмена", role: .cancel) {}
        } message: {
            Text("После подтверждения объект можно будет выбрать до окончания текущего сканирования. Это не изменяет системные права доступа macOS.")
        }
        .onChange(of: node?.id) { _, _ in
            copyConfirmationID = nil
        }
    }

    private var selectedItemsButton: some View {
        Button("Посмотреть выбранное", systemImage: "checklist") {
            showSelectedItemsAction()
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    @ViewBuilder
    private func inspectorHeader(for node: FileSystemNode) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(alignment: .top, spacing: 10) {
                if FileAccessPolicy.isApplicationsDirectory(node.url) {
                    Image(systemName: "questionmark.circle")
                        .font(.title2)
                        .foregroundStyle(.secondary)

                    Text("Приложения")
                        .font(.headline)
                } else if let presentation = node.presentation {
                    presentationIcon(presentation.badge)
                        .frame(width: 28, height: 28)

                    Text(presentation.title)
                        .font(.headline)
                } else if node.accessPolicy.showsLock && node.isInSystemArea {
                    Label("Системный элемент macOS", systemImage: "lock.fill")
                        .font(.headline)
                        .foregroundStyle(.secondary)
                } else if showsPolicyDescription(node.accessPolicy) {
                    Image(systemName: "checkmark.circle")
                        .font(.title2)
                        .foregroundStyle(.secondary)

                    Text(node.accessPolicy.title)
                        .font(.headline)
                }

                Spacer(minLength: 4)

                if scanMode == .full, let quickScanMembership {
                    Button {
                        toggleQuickScanMembership(node)
                    } label: {
                        QuickScanBolt(membership: quickScanMembership)
                            .frame(width: 28, height: 28)
                            .background {
                                QuickScanButtonBackground(membership: quickScanMembership)
                            }
                            .overlay {
                                RoundedRectangle(cornerRadius: 6)
                                    .stroke(.secondary.opacity(0.3))
                            }
                    }
                    .buttonStyle(.plain)
                    .help(quickScanHelp(for: quickScanMembership))
                }

                if (node.accessPolicy.showsWarning && !node.accessPolicy.showsLock) || isUnlocked {
                    Image(systemName: "exclamationmark.triangle.fill")
                        .font(.title3)
                        .foregroundStyle(.orange)
                        .accessibilityLabel("Требует осторожности")
                }

                if node.accessPolicy.showsLock {
                    Button {
                        if isUnlocked {
                            lockAction(node)
                        } else {
                            isConfirmingUnlock = true
                        }
                    } label: {
                        Image(systemName: isUnlocked ? "lock.open.fill" : "lock.fill")
                            .font(.title3)
                            .foregroundStyle(.secondary)
                    }
                    .buttonStyle(.plain)
                    .help(isUnlocked ? "Заблокировать снова" : "Разблокировать до окончания сканирования")
                    .accessibilityLabel(isUnlocked ? "Заблокировать объект" : "Разблокировать объект")
                }

                if !FileAccessPolicy.isApplicationsDirectory(node.url) {
                    Button {
                        helpAction(node)
                    } label: {
                        Image(systemName: "questionmark.circle")
                            .font(.title3)
                    }
                    .buttonStyle(.plain)
                    .help("Спросить об этом объекте")
                }
            }

            if FileAccessPolicy.isApplicationsDirectory(node.url) {
                Text("Используйте деинсталлятор.")
                    .fixedSize(horizontal: false, vertical: true)
            } else if let presentation = node.presentation {
                Text(presentation.message)
                    .fixedSize(horizontal: false, vertical: true)
            } else if showsPolicyDescription(node.accessPolicy),
                      showsPolicyMessage(node.accessPolicy) {
                Text(node.accessPolicy.message)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
    }

    @ViewBuilder
    private func presentationIcon(_ badge: FileItemBadge) -> some View {
        switch badge {
        case .asset(let name):
            Image(name)
                .resizable()
                .scaledToFit()
        case .systemSymbol(let name):
            Image(systemName: name)
                .resizable()
                .scaledToFit()
                .foregroundStyle(.secondary)
        }
    }

    private func showsPolicyDescription(_ policy: FileAccessPolicy) -> Bool {
        switch policy {
        case .applicationContent, .topLevelFolder:
            true
        default:
            false
        }
    }

    private func showsPolicyMessage(_ policy: FileAccessPolicy) -> Bool {
        switch policy {
        case .topLevelFolder:
            false
        default:
            true
        }
    }

    private func copyPath(_ path: String) {
        let pasteboard = NSPasteboard.general
        pasteboard.clearContents()
        pasteboard.setString(path, forType: .string)
        let confirmationID = UUID()
        withAnimation(.easeInOut(duration: 0.2)) {
            copyConfirmationID = confirmationID
        }
        Task {
            try? await Task.sleep(for: .seconds(3.5))
            guard copyConfirmationID == confirmationID else { return }
            withAnimation(.easeInOut(duration: 0.2)) {
                copyConfirmationID = nil
            }
        }
    }

    private func displayedSize(for node: FileSystemNode) -> String {
        if FileAccessPolicy.isApplicationsDirectory(node.url), node.size < 0 {
            return "—"
        }
        return ByteSizeFormatter.string(from: node.size)
    }

    private func quickScanHelp(for membership: QuickScanMembership) -> String {
        switch membership {
        case .included:
            "Убрать из быстрого анализа"
        case .excluded:
            "Добавить в быстрый анализ"
        case .mixed:
            "Часть содержимого входит в быстрый анализ. Нажмите, чтобы добавить папку целиком"
        }
    }
}

private struct InspectorPathView: View {
    let path: String
    let didCopy: Bool
    let copyAction: () -> Void

    var body: some View {
        HStack(alignment: .bottom, spacing: 6) {
            Text(path)
                .font(.system(.caption, design: .monospaced))
                .foregroundStyle(.secondary)
                .lineLimit(3)
                .truncationMode(.middle)
                .textSelection(.enabled)
                .frame(maxWidth: .infinity, alignment: .leading)
                .layoutPriority(1)

            Button(action: copyAction) {
                Image(systemName: didCopy ? "checkmark" : "square.on.square")
                    .foregroundStyle(didCopy ? Color.green : Color.secondary)
                    .contentTransition(.symbolEffect(.replace))
            }
            .buttonStyle(.plain)
            .help("Копировать путь")
            .accessibilityLabel("Копировать путь")
            .fixedSize()
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }
}

struct QuickScanBolt: View {
    let membership: QuickScanMembership

    var body: some View {
        ZStack {
            Image(systemName: "bolt.fill")
                .foregroundStyle(membership == .included ? .green : .secondary)

            if membership == .mixed {
                Image(systemName: "bolt.fill")
                    .foregroundStyle(.green)
                    .mask(DiagonalHalfShape())
            }
        }
        .font(.body)
        .accessibilityLabel(accessibilityText)
    }

    private var accessibilityText: String {
        switch membership {
        case .included: "Входит в быстрый анализ"
        case .excluded: "Не входит в быстрый анализ"
        case .mixed: "Частично входит в быстрый анализ"
        }
    }
}

struct QuickScanButtonBackground: View {
    let membership: QuickScanMembership

    var body: some View {
        RoundedRectangle(cornerRadius: 6)
            .fill(backgroundStyle)
    }

    private var backgroundStyle: AnyShapeStyle {
        switch membership {
        case .included:
            AnyShapeStyle(Color.green.opacity(0.14))
        case .excluded:
            AnyShapeStyle(Color.secondary.opacity(0.09))
        case .mixed:
            AnyShapeStyle(
                LinearGradient(
                    stops: [
                        .init(color: .green.opacity(0.14), location: 0.49),
                        .init(color: .secondary.opacity(0.09), location: 0.51)
                    ],
                    startPoint: .topLeading,
                    endPoint: .bottomTrailing
                )
            )
        }
    }
}

struct DiagonalHalfShape: Shape {
    func path(in rect: CGRect) -> Path {
        Path { path in
            path.move(to: rect.origin)
            path.addLine(to: CGPoint(x: rect.maxX, y: rect.minY))
            path.addLine(to: CGPoint(x: rect.minX, y: rect.maxY))
            path.closeSubpath()
        }
    }
}
