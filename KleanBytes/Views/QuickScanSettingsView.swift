import Foundation
import SwiftUI

struct QuickScanSettingsView: View {
    let configuration: QuickScanConfiguration
    let configurationChanged: (QuickScanConfiguration) -> Void
    let resetAction: () -> Void

    @Environment(\.dismiss) private var dismiss
    @State private var rootItems: [QuickScanBrowserItem] = []
    @State private var isLoading = true
    @State private var loadError: String?
    @State private var confirmsReset = false

    var body: some View {
        VStack(spacing: 0) {
            header
            Divider()

            if isLoading {
                ProgressView("Чтение корня диска…")
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else if let loadError {
                ContentUnavailableView(
                    "Не удалось прочитать диск",
                    systemImage: "exclamationmark.triangle",
                    description: Text(loadError)
                )
            } else {
                ScrollView {
                    LazyVStack(alignment: .leading, spacing: 2) {
                        ForEach(rootItems) { item in
                            QuickScanSettingsRow(
                                item: item,
                                depth: 0,
                                configuration: configuration,
                                configurationChanged: configurationChanged
                            )
                        }
                    }
                    .padding(12)
                }
            }

            Divider()
            footer
        }
        .frame(minWidth: 720, idealWidth: 820, minHeight: 560, idealHeight: 650)
        .task { await loadRoot() }
        .confirmationDialog(
            "Вернуть стандартные настройки?",
            isPresented: $confirmsReset,
            titleVisibility: .visible
        ) {
            Button("Вернуть по умолчанию", role: .destructive, action: resetAction)
            Button("Отмена", role: .cancel) {}
        } message: {
            Text("Все добавленные и исключённые вручную пути будут сброшены.")
        }
    }

    private var header: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack {
                VStack(alignment: .leading, spacing: 3) {
                    Text("Настройка быстрого анализа")
                        .font(.title2.bold())
                    Text("Раскрывайте папки и нажимайте молнию, чтобы изменить состав анализа.")
                        .foregroundStyle(.secondary)
                }
                Spacer()
                Button("Готово", action: dismiss.callAsFunction)
                    .keyboardShortcut(.defaultAction)
            }
        }
        .padding()
    }

    private var footer: some View {
        HStack {
            Label("Зелёная — включено, серая — исключено, двухцветная — включена часть папки", systemImage: "bolt.fill")
                .font(.caption)
                .foregroundStyle(.secondary)
            Spacer()
            Button("Вернуть по умолчанию", systemImage: "arrow.counterclockwise") {
                confirmsReset = true
            }
            .disabled(configuration == .empty)
        }
        .padding()
    }

    private func loadRoot() async {
        do {
            rootItems = try await QuickScanDirectoryReader.children(of: URL(fileURLWithPath: "/"))
        } catch {
            loadError = error.localizedDescription
        }
        isLoading = false
    }
}

private struct QuickScanSettingsRow: View {
    let item: QuickScanBrowserItem
    let depth: Int
    let configuration: QuickScanConfiguration
    let configurationChanged: (QuickScanConfiguration) -> Void

    @State private var isExpanded = false
    @State private var children: [QuickScanBrowserItem]?
    @State private var isLoading = false
    @State private var loadFailed = false

    var body: some View {
        VStack(alignment: .leading, spacing: 2) {
            HStack(spacing: 8) {
                if item.canExpand {
                    Button {
                        isExpanded.toggle()
                        if isExpanded, children == nil {
                            loadChildren()
                        }
                    } label: {
                        Image(systemName: isExpanded ? "chevron.down" : "chevron.right")
                            .frame(width: 14)
                    }
                    .buttonStyle(.plain)
                } else {
                    Color.clear.frame(width: 14, height: 1)
                }

                Image(systemName: item.isDirectory ? "folder.fill" : "doc")
                    .foregroundStyle(item.isDirectory ? Color.accentColor : Color.secondary)

                Text(item.name)
                    .lineLimit(1)

                Spacer()

                if isLoading {
                    ProgressView().controlSize(.small)
                }

                Button {
                    var updated = configuration
                    updated.toggle(item.node)
                    configurationChanged(updated)
                } label: {
                    let membership = configuration.membership(of: item.node)
                    QuickScanBolt(membership: membership)
                        .frame(width: 28, height: 28)
                        .background { QuickScanButtonBackground(membership: membership) }
                        .overlay {
                            RoundedRectangle(cornerRadius: 6)
                                .stroke(.secondary.opacity(0.3))
                        }
                }
                .buttonStyle(.plain)
            }
            .padding(.leading, CGFloat(depth) * 20)
            .padding(.vertical, 4)
            .contentShape(Rectangle())
            .onTapGesture {
                guard item.canExpand else { return }
                isExpanded.toggle()
                if isExpanded, children == nil { loadChildren() }
            }

            if isExpanded {
                if loadFailed {
                    Text("Нет доступа к содержимому")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .padding(.leading, CGFloat(depth + 2) * 20)
                } else if let children {
                    ForEach(children) { child in
                        QuickScanSettingsRow(
                            item: child,
                            depth: depth + 1,
                            configuration: configuration,
                            configurationChanged: configurationChanged
                        )
                    }
                }
            }
        }
    }

    private func loadChildren() {
        isLoading = true
        Task {
            do {
                children = try await QuickScanDirectoryReader.children(of: item.url)
            } catch {
                loadFailed = true
            }
            isLoading = false
        }
    }
}

private struct QuickScanBrowserItem: Identifiable, Sendable {
    let id: URL
    let name: String
    let url: URL
    let isDirectory: Bool
    let isSymbolicLink: Bool
    let size: Int64

    var canExpand: Bool { isDirectory && !isSymbolicLink }

    var node: FileSystemNode {
        FileSystemNode(
            id: url,
            name: name,
            url: url,
            isDirectory: isDirectory,
            isSymbolicLink: isSymbolicLink,
            size: size,
            children: [],
            fileCount: isDirectory ? 0 : 1,
            directoryCount: isDirectory ? 1 : 0,
            isAccessible: true,
            scanStatus: .complete
        )
    }
}

private enum QuickScanDirectoryReader {
    static func children(of directory: URL) async throws -> [QuickScanBrowserItem] {
        try await Task.detached(priority: .utility) {
            let keys: Set<URLResourceKey> = [
                .nameKey, .isDirectoryKey, .isSymbolicLinkKey,
                .fileAllocatedSizeKey, .totalFileAllocatedSizeKey, .fileSizeKey
            ]
            let urls = try FileManager.default.contentsOfDirectory(
                at: directory,
                includingPropertiesForKeys: Array(keys),
                options: [.skipsPackageDescendants]
            )

            return urls.compactMap { url in
                guard url.lastPathComponent != ".localized",
                      !DiskScanExclusions.contains(url),
                      let values = try? url.resourceValues(forKeys: keys) else { return nil }
                let isDirectory = values.isDirectory == true
                return QuickScanBrowserItem(
                    id: url,
                    name: values.name ?? url.lastPathComponent,
                    url: url,
                    isDirectory: isDirectory,
                    isSymbolicLink: values.isSymbolicLink == true,
                    size: isDirectory ? Int64.max : Int64(
                        values.totalFileAllocatedSize
                        ?? values.fileAllocatedSize
                        ?? values.fileSize
                        ?? 0
                    )
                )
            }
            .sorted {
                if $0.isDirectory != $1.isDirectory { return $0.isDirectory }
                return $0.name.localizedStandardCompare($1.name) == .orderedAscending
            }
        }.value
    }
}
