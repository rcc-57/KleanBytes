import AppKit
import SwiftUI

struct HelpSearchView: View {
    let node: FileSystemNode

    @Environment(\.dismiss) private var dismiss
    @State private var pathComponents: [EditablePathComponent]
    @State private var isShowingPrompt = false
    @State private var promptText: String
    @State private var customComponentID: UUID?
    @State private var customValue = ""
    @State private var openingError: String?

    init(node: FileSystemNode) {
        self.node = node
        let components = EditablePathComponent.make(from: node.url)
        _pathComponents = State(initialValue: components)
        _promptText = State(initialValue: SearchPromptBuilder.prompt(for: Self.path(from: components)))
    }

    var body: some View {
        editor
        .frame(width: 560, height: isShowingPrompt ? 620 : 410)
        .animation(.easeInOut(duration: 0.2), value: isShowingPrompt)
        .onChange(of: customValue) { _, newValue in
            let sanitized = newValue.replacingOccurrences(of: "/", with: "")
            if sanitized != newValue {
                customValue = sanitized
            }
        }
        .alert("Не удалось открыть Safari", isPresented: openingErrorBinding) {
            Button("ОК", role: .cancel) {}
        } message: {
            Text(openingError ?? "Неизвестная ошибка")
        }
    }

    private var editor: some View {
        ScrollView(.vertical) {
            VStack(alignment: .leading, spacing: 14) {
            HStack {
                Label("Спросить об этом объекте", systemImage: "questionmark.circle")
                    .font(.title2.weight(.semibold))

                Spacer()

                Button("Отмена", role: .cancel) {
                    dismiss()
                }
            }

            Text("Отредактируйте или обезличьте путь перед отправкой в Google. Реальный файл или папка не будут изменены.")
                .foregroundStyle(.secondary)

            pathEditor

            if let customComponentID {
                customValueEditor(componentID: customComponentID)
            }

            Text("Итоговый путь")
                .font(.headline)

            Text(editedPath)
                .font(.system(.body, design: .monospaced))
                .textSelection(.enabled)
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(10)
                .background(.quaternary, in: RoundedRectangle(cornerRadius: 8))

            DisclosureGroup(isExpanded: $isShowingPrompt) {
                TextEditor(text: $promptText)
                    .font(.system(.body, design: .monospaced))
                    .scrollContentBackground(.hidden)
                    .padding(8)
                    .background(.quaternary, in: RoundedRectangle(cornerRadius: 8))
                    .frame(minHeight: 190)
                    .accessibilityLabel("Запрос, который будет отправлен в Google")
            } label: {
                Text(isShowingPrompt ? "Скрыть запрос" : "Показать запрос")
            }

            HStack {
                Text("Запрос будет отправлен в Google только после нажатия кнопки ниже.")
                    .font(.caption)
                    .foregroundStyle(.secondary)

                Spacer()

                Button("Получить справку", systemImage: "safari") {
                    openHelpInSafari()
                }
                .buttonStyle(.borderedProminent)
                .disabled(
                    customComponentID != nil ||
                    pathComponents.contains { $0.value.isEmpty } ||
                    promptText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
                )
            }
            }
            .padding(20)
        }
        .scrollIndicators(.automatic)
    }

    private var pathEditor: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("Путь")
                .font(.headline)

            PathFlowLayout(spacing: 6) {
                Text("/")
                    .foregroundStyle(.secondary)

                ForEach($pathComponents) { $component in
                    HStack(spacing: 2) {
                        Menu {
                            Button("имя_пользователя") {
                                replace(component.id, with: "имя_пользователя")
                            }
                            Button("папка") {
                                replace(component.id, with: "папка")
                            }
                            Button("файл.расширение") {
                                replace(component.id, with: "файл.расширение")
                            }
                            Divider()
                            Button("Ввести своё значение…") {
                                beginCustomEditing(component)
                            }
                            Button("Вернуть исходное значение") {
                                replace(component.id, with: component.originalValue)
                            }
                        } label: {
                            Text(component.value)
                                .font(.system(.body, design: .monospaced))
                                .lineLimit(1)
                                .padding(.horizontal, 9)
                                .padding(.vertical, 5)
                                .background(.blue.opacity(0.14), in: RoundedRectangle(cornerRadius: 6))
                        }
                        .menuStyle(.borderlessButton)

                        if component.id != pathComponents.last?.id {
                            Text("/")
                                .foregroundStyle(.secondary)
                        }
                    }
                }
            }
            .padding(.vertical, 4)

            Text("Разделители «/» являются частью структуры пути и не редактируются.")
                .font(.caption)
                .foregroundStyle(.secondary)
        }
    }

    private func customValueEditor(componentID: UUID) -> some View {
        HStack(spacing: 10) {
            TextField("Новое значение компонента", text: $customValue)
                .textFieldStyle(.roundedBorder)

            Button("Применить") {
                let value = customValue.trimmingCharacters(in: .whitespacesAndNewlines)
                replace(componentID, with: value)
                customComponentID = nil
            }
            .disabled(customValue.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)

            Button("Отмена", role: .cancel) {
                customComponentID = nil
                customValue = ""
            }
        }
    }

    private var openingErrorBinding: Binding<Bool> {
        Binding(
            get: { openingError != nil },
            set: { isPresented in
                if !isPresented {
                    openingError = nil
                }
            }
        )
    }

    private var editedPath: String {
        Self.path(from: pathComponents)
    }

    private static func path(from components: [EditablePathComponent]) -> String {
        guard !components.isEmpty else { return "/" }
        return "/" + components.map(\.value).joined(separator: "/")
    }

    private func replace(_ id: UUID, with value: String) {
        guard !value.isEmpty, !value.contains("/"),
              let index = pathComponents.firstIndex(where: { $0.id == id }) else { return }
        pathComponents[index].value = value
        promptText = SearchPromptBuilder.prompt(for: editedPath)
        customComponentID = nil
    }

    private func beginCustomEditing(_ component: EditablePathComponent) {
        customComponentID = component.id
        customValue = component.value
    }

    private func openHelpInSafari() {
        guard let url = SearchPromptBuilder.googleURL(for: promptText) else { return }
        guard let safariURL = NSWorkspace.shared.urlForApplication(
            withBundleIdentifier: "com.apple.Safari"
        ) else {
            openingError = "Safari не найден на этом Mac."
            return
        }

        NSWorkspace.shared.open(
            [url],
            withApplicationAt: safariURL,
            configuration: NSWorkspace.OpenConfiguration()
        ) { _, error in
            let errorDescription = error?.localizedDescription
            Task { @MainActor in
                if let errorDescription {
                    openingError = errorDescription
                } else {
                    dismiss()
                }
            }
        }
    }
}

private struct PathFlowLayout: Layout {
    let spacing: CGFloat

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
        let result = layout(
            proposal: ProposedViewSize(width: bounds.width, height: proposal.height),
            subviews: subviews
        )
        for (index, point) in result.points.enumerated() {
            subviews[index].place(at: CGPoint(x: bounds.minX + point.x, y: bounds.minY + point.y), proposal: .unspecified)
        }
    }

    private func layout(proposal: ProposedViewSize, subviews: Subviews) -> (size: CGSize, points: [CGPoint]) {
        let maximumWidth = proposal.width ?? 520
        var points: [CGPoint] = []
        var x: CGFloat = 0
        var y: CGFloat = 0
        var lineHeight: CGFloat = 0

        for subview in subviews {
            let size = subview.sizeThatFits(.unspecified)
            if x > 0, x + size.width > maximumWidth {
                x = 0
                y += lineHeight + spacing
                lineHeight = 0
            }
            points.append(CGPoint(x: x, y: y))
            x += size.width + spacing
            lineHeight = max(lineHeight, size.height)
        }

        return (CGSize(width: maximumWidth, height: y + lineHeight), points)
    }
}

private struct EditablePathComponent: Identifiable {
    let id = UUID()
    let originalValue: String
    var value: String

    static func make(from url: URL) -> [EditablePathComponent] {
        url.standardizedFileURL.pathComponents
            .filter { $0 != "/" }
            .map { EditablePathComponent(originalValue: $0, value: $0) }
    }
}

private enum SearchPromptBuilder {
    static func prompt(for path: String) -> String {
        "Что представляет собой объект macOS по пути \(path)? Определи, является ли он системным или к какому приложению относится; какие данные хранит; можно ли безопасно удалить сам объект или его содержимое; каковы последствия и риски потери данных, настроек, лицензий, авторизации, резервных копий или синхронизации; есть ли штатный способ очистки через приложение, Finder, настройки macOS, деинсталлятор или инструменты разработчика. Учитывай актуальные версии macOS. Если назначение нельзя определить достоверно, не рекомендуй ручное удаление."
    }

    static func googleURL(for prompt: String) -> URL? {
        var components = URLComponents(string: "https://www.google.com/search")
        components?.queryItems = [
            URLQueryItem(name: "q", value: prompt)
        ]
        return components?.url
    }
}
