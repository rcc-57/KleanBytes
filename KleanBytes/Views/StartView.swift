import AppKit
import SwiftUI

struct StartView: View {
    let volume: DiskVolume?
    let message: String?
    let hasFullDiskAccess: Bool
    let quickScanAction: () -> Void
    let quickScanSettingsAction: () -> Void
    let fullScanAction: () -> Void
    let uninstallerAction: () -> Void

    var body: some View {
        HStack(spacing: 0) {
            ModeDashboard(
                volume: volume,
                quickScanAction: quickScanAction,
                quickScanSettingsAction: quickScanSettingsAction,
                fullScanAction: fullScanAction,
                uninstallerAction: uninstallerAction
            )

            DiskSidebar(
                volume: volume,
                message: message,
                hasFullDiskAccess: hasFullDiskAccess
            )
        }
    }
}

private enum DashboardPalette {
    static let lightTileBackground = Color(red: 0.784, green: 0.827, blue: 0.898)
    static let darkTileBackground = Color(red: 0.13, green: 0.20, blue: 0.32)
    static let sidebarBackground = Color(red: 0.13, green: 0.20, blue: 0.32)
    static let sidebarSecondaryText = Color.secondary
    static let tileBackground = Color.white
    static let primaryText = Color(red: 0.07, green: 0.08, blue: 0.11)
    static let secondaryText = Color(red: 0.36, green: 0.39, blue: 0.46)
    static let softControl = Color(red: 0.93, green: 0.94, blue: 0.97)
    static let darkControl = Color(red: 0.08, green: 0.09, blue: 0.13)
}

private struct ModeDashboard: View {
    let volume: DiskVolume?
    let quickScanAction: () -> Void
    let quickScanSettingsAction: () -> Void
    let fullScanAction: () -> Void
    let uninstallerAction: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 28) {
            VStack(alignment: .leading, spacing: 5) {
                Text("KleanBytes")
                    .font(.system(size: 30, weight: .bold, design: .rounded))
                    .foregroundStyle(Color.primary)
                Text("Выберите режим работы")
                    .font(.title3)
                    .foregroundStyle(Color.secondary)
            }

            Spacer(minLength: 0)

            HStack(spacing: 14) {
                ScanModeTile(
                    quickScanAction: quickScanAction,
                    quickScanSettingsAction: quickScanSettingsAction,
                    fullScanAction: fullScanAction
                )

                UninstallerModeTile(action: uninstallerAction)
            }
        }
        .padding(22)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        .background(Color(nsColor: .underPageBackgroundColor))
        .overlay(alignment: .topTrailing) {
            DiskUsageRing(volume: volume)
                .frame(width: 190, height: 190)
                .padding(.top, 34)
                .padding(.trailing, 22)
        }
    }
}

private struct DiskUsageRing: View {
    let volume: DiskVolume?

    var body: some View {
        ZStack {
            Circle()
                .strokeBorder(Color.secondary.opacity(0.16), lineWidth: 16)

            Circle()
                .inset(by: 8)
                .trim(from: 0, to: freeFraction)
                .stroke(
                    Color.accentColor,
                    style: StrokeStyle(lineWidth: 16, lineCap: .round)
                )
                .rotationEffect(.degrees(-90))

            if volume != nil {
                VStack(spacing: 4) {
                    Text(freeFraction, format: .percent.precision(.fractionLength(0)))
                        .font(.system(size: 34, weight: .bold, design: .rounded))
                        .monospacedDigit()
                    Text("места свободно")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            } else {
                ProgressView()
            }
        }
        .accessibilityElement(children: .combine)
        .accessibilityLabel("Свободное место на диске")
        .accessibilityValue(
            volume.map { _ in freeFraction.formatted(.percent.precision(.fractionLength(0))) }
                ?? "Загрузка"
        )
    }

    private var freeFraction: Double {
        guard let volume else { return 0 }
        return max(0, min(1, 1 - volume.fractionUsed))
    }
}

private struct DiskSidebar: View {
    let volume: DiskVolume?
    let message: String?
    let hasFullDiskAccess: Bool

    var body: some View {
        VStack(alignment: .leading, spacing: 24) {
            HStack(spacing: 10) {
                Image(systemName: "internaldrive.fill")
                    .font(.title2)
                Text(volume?.name ?? "Загрузочный диск")
                    .font(.headline)
                    .lineLimit(1)
            }

            if let volume {
                VStack(alignment: .leading, spacing: 13) {
                    CapacityRow(title: "Всего", value: volume.totalCapacity)
                    CapacityRow(title: "Занято", value: volume.usedCapacity)
                    CapacityRow(title: "Доступно", value: volume.availableCapacity)

                    ProgressView(value: volume.fractionUsed)
                        .tint(Color.primary)

                    Text(volume.fractionUsed, format: .percent.precision(.fractionLength(1)))
                        .font(.caption.monospacedDigit())
                        .foregroundStyle(DashboardPalette.sidebarSecondaryText)
                }
            } else {
                ProgressView("Чтение информации о диске…")
                    .controlSize(.small)
            }

            if let message {
                Label(message, systemImage: "checkmark.circle.fill")
                    .font(.caption)
                    .foregroundStyle(.green)
                    .fixedSize(horizontal: false, vertical: true)
            }

            Spacer()

            if !hasFullDiskAccess {
                Button {
                    openFullDiskAccessSettings()
                } label: {
                    VStack(alignment: .leading, spacing: 9) {
                        Label("Полный доступ к диску", systemImage: "lock.shield")
                            .font(.subheadline.weight(.semibold))
                            .foregroundStyle(.white)
                            .padding(.horizontal, 12)
                            .padding(.vertical, 9)
                            .background(Color.accentColor, in: Capsule())

                        Text("Разрешение macOS помогает увидеть больше пользовательских данных, но не обходит системную защиту.")
                            .font(.caption)
                            .foregroundStyle(DashboardPalette.sidebarSecondaryText)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .help("Открыть настройки полного доступа к диску")
            }
        }
        .foregroundStyle(Color.primary)
        .padding(26)
        .frame(maxHeight: .infinity, alignment: .topLeading)
        .background(alignment: .bottom) {
            if !hasFullDiskAccess {
                SidebarBottomFade(height: 230)
            }
        }
        .dashboardSidebar(width: 280)
    }

    private func openFullDiskAccessSettings() {
        let fullDiskAccessURL = URL(
            string: "x-apple.systempreferences:com.apple.preference.security?Privacy_AllFiles"
        )
        let privacyURL = URL(
            string: "x-apple.systempreferences:com.apple.settings.PrivacySecurity.extension"
        )

        if let fullDiskAccessURL, NSWorkspace.shared.open(fullDiskAccessURL) {
            return
        }
        if let privacyURL {
            NSWorkspace.shared.open(privacyURL)
        }
    }
}

private struct CapacityRow: View {
    let title: LocalizedStringKey
    let value: Int64

    var body: some View {
        HStack {
            Text(title)
                .foregroundStyle(DashboardPalette.sidebarSecondaryText)
            Spacer()
            Text(ByteSizeFormatter.string(from: value))
                .fontWeight(.semibold)
                .monospacedDigit()
        }
        .font(.subheadline)
    }
}

private struct ScanModeTile: View {
    let quickScanAction: () -> Void
    let quickScanSettingsAction: () -> Void
    let fullScanAction: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            ModeTitle("Анализ диска")

            ModeImage(name: "FinderScan") {
                VStack(alignment: .leading, spacing: 9) {
                    HStack(spacing: 9) {
                        ImageActionButton(
                            title: "Быстрый",
                            width: 87,
                            tint: Color(red: 0.91, green: 0.97, blue: 0.92),
                            foregroundStyle: Color(red: 0.10, green: 0.76, blue: 0.31),
                            isCompact: true,
                            action: quickScanAction
                        )

                        Button(action: quickScanSettingsAction) {
                            Image(systemName: "gearshape")
                                .frame(width: 40, height: 40)
                        }
                        .buttonStyle(DashboardUtilityButtonStyle())
                        .help("Настроить быстрый анализ")
                        .accessibilityLabel("Настроить быстрый анализ")
                    }

                    ImageActionButton(
                        title: "Полный",
                        width: 136,
                        tint: Color.white.opacity(0.92),
                        foregroundStyle: DashboardPalette.primaryText,
                        action: fullScanAction
                    )
                }
                .padding(12)
            }
        }
        .modeTile()
    }
}

private struct UninstallerModeTile: View {
    let action: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            ModeTitle("Деинсталлятор")

            ModeImage(name: "AppUninstaller") {
                HStack {
                    ImageActionButton(
                        title: "Запустить",
                        width: 146,
                        tint: Color.white.opacity(0.92),
                        foregroundStyle: DashboardPalette.primaryText,
                        action: action
                    )

                    Spacer()
                }
                .padding(12)
            }
        }
        .modeTile()
        .accessibilityElement(children: .contain)
    }
}

private struct FutureModeTile: View {
    var body: some View {
        VStack(spacing: 12) {
            Image(systemName: "plus")
                .font(.system(size: 34, weight: .light))
                .foregroundStyle(DashboardPalette.secondaryText.opacity(0.55))
            Text("Новый режим")
                .font(.caption.weight(.medium))
                .foregroundStyle(DashboardPalette.secondaryText.opacity(0.7))
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .modeTile()
        .accessibilityElement(children: .combine)
        .accessibilityLabel("Место для будущего режима")
    }
}

private struct ModeImage<Overlay: View>: View {
    let name: String
    @ViewBuilder let overlay: () -> Overlay

    var body: some View {
        ZStack(alignment: .bottomLeading) {
            GeometryReader { proxy in
                Image(name)
                    .resizable()
                    .scaledToFill()
                    .frame(
                        width: proxy.size.width,
                        height: proxy.size.height,
                        alignment: .center
                    )
                    .scaleEffect(name == "FinderScan" ? 1.08 : 1)
                    .clipped()
            }

            overlay()
        }
        .frame(height: 224)
        .clipShape(RoundedRectangle(cornerRadius: 16))
    }
}

private struct ModeTitle: View {
    @Environment(\.colorScheme) private var colorScheme

    let title: LocalizedStringKey

    init(_ title: LocalizedStringKey) {
        self.title = title
    }

    var body: some View {
        Text(title)
            .font(.title2.bold())
            .foregroundStyle(colorScheme == .dark ? Color.white : DashboardPalette.primaryText)
            .lineLimit(1)
    }
}

private struct ImageActionButton: View {
    let title: LocalizedStringKey
    let width: CGFloat
    let tint: Color
    let foregroundStyle: Color
    var isCompact = false
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            Group {
                if isCompact {
                    ZStack {
                        Text(title)
                            .frame(maxWidth: .infinity, alignment: .leading)
                        Image(systemName: "arrow.right")
                            .frame(maxWidth: .infinity, alignment: .trailing)
                    }
                } else {
                    HStack(spacing: 6) {
                        Text(title)
                            .lineLimit(1)
                        Spacer()
                        Image(systemName: "arrow.right")
                    }
                }
            }
            .lineLimit(1)
            .font(.subheadline.weight(.semibold))
            .foregroundStyle(foregroundStyle)
            .padding(.horizontal, 7)
            .frame(width: width)
            .frame(minHeight: 40)
        }
        .buttonStyle(ImageActionButtonStyle(tint: tint))
    }
}

private struct ImageActionButtonStyle: ButtonStyle {
    let tint: Color

    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .background(tint.opacity(configuration.isPressed ? 0.82 : 1), in: Capsule())
            .scaleEffect(configuration.isPressed ? 0.985 : 1)
            .shadow(color: .black.opacity(0.12), radius: 5, y: 2)
    }
}

private struct DashboardButton: View {
    let title: LocalizedStringKey
    let systemImage: String
    let isPrimary: Bool
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            HStack {
                Label(title, systemImage: systemImage)
                Spacer()
                Image(systemName: "chevron.right")
                    .font(.caption.bold())
            }
            .frame(maxWidth: .infinity, minHeight: 36)
            .padding(.horizontal, 12)
        }
        .buttonStyle(DashboardActionButtonStyle(isPrimary: isPrimary))
    }
}

private struct DashboardActionButtonStyle: ButtonStyle {
    let isPrimary: Bool

    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(.subheadline.weight(.semibold))
            .foregroundStyle(isPrimary ? Color.white : DashboardPalette.primaryText)
            .background(
                isPrimary
                    ? DashboardPalette.darkControl.opacity(configuration.isPressed ? 0.78 : 1)
                    : DashboardPalette.softControl.opacity(configuration.isPressed ? 0.72 : 1),
                in: Capsule()
            )
            .scaleEffect(configuration.isPressed ? 0.985 : 1)
    }
}

private struct DashboardUtilityButtonStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .foregroundStyle(DashboardPalette.primaryText)
            .background(
                Color.white.opacity(configuration.isPressed ? 0.78 : 0.94),
                in: Circle()
            )
            .shadow(color: .black.opacity(0.16), radius: 5, y: 2)
    }
}

private extension View {
    func modeTile() -> some View {
        padding(12)
            .frame(maxWidth: .infinity, minHeight: 275, maxHeight: 275, alignment: .topLeading)
            .background {
                DashboardTileBackground()
            }
            .clipShape(RoundedRectangle(cornerRadius: 20))
            .shadow(color: .black.opacity(0.10), radius: 12, y: 5)
    }
}

private struct DashboardTileBackground: View {
    @Environment(\.colorScheme) private var colorScheme

    var body: some View {
        RoundedRectangle(cornerRadius: 20)
            .fill(
                colorScheme == .dark
                    ? DashboardPalette.darkTileBackground
                    : DashboardPalette.lightTileBackground
            )
    }
}
