import SwiftUI

struct ScanningView: View {
    let currentPath: String
    let progress: Double
    let isPreparing: Bool
    let cancelAction: () -> Void

    var body: some View {
        HStack(spacing: 0) {
            ScanningProgressPanel(currentPath: currentPath, progress: progress)
            ScanningStatusPanel(isPreparing: isPreparing, cancelAction: cancelAction)
        }
    }
}

private struct ScanningProgressPanel: View {
    let currentPath: String
    let progress: Double

    var body: some View {
        VStack(spacing: 22) {
            Image(systemName: "internaldrive.fill")
                .font(.system(size: 52))
                .foregroundStyle(.primary)

            Text("Сканирование диска")
                .font(.title.bold())

            ProgressView(value: progress, total: 1)
                .progressViewStyle(.linear)
                .tint(.primary)
                .frame(maxWidth: 450)

            Text(progress, format: .percent.precision(.fractionLength(0)))
                .font(.headline.monospacedDigit())

            Text(currentPath)
                .font(.system(.body, design: .monospaced))
                .foregroundStyle(.secondary)
                .lineLimit(1)
                .truncationMode(.middle)
                .frame(maxWidth: 520)
        }
        .padding(40)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(Color(nsColor: .underPageBackgroundColor))
    }
}

private struct ScanningStatusPanel: View {
    let isPreparing: Bool
    let cancelAction: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            Text(isPreparing ? "Подготовка сканирования…" : "Выполняется сканирование…")
                .font(.title3.bold())

            Spacer()

            Button("Отменить", role: .cancel, action: cancelAction)
                .keyboardShortcut(.cancelAction)
                .frame(maxWidth: .infinity)
        }
        .padding(26)
        .frame(maxHeight: .infinity, alignment: .topLeading)
        .background(alignment: .bottom) {
            SidebarBottomFade(height: 130)
        }
        .dashboardSidebar(width: 280)
    }
}
