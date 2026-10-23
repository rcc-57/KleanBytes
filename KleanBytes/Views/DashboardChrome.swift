import AppKit
import SwiftUI

extension View {
    func dashboardSidebar(width: CGFloat) -> some View {
        modifier(DashboardSidebarModifier(width: width))
    }
}

struct SidebarBottomFade: View {
    let height: CGFloat

    var body: some View {
        ZStack {
            Rectangle()
                .fill(.ultraThinMaterial)
                .mask {
                    LinearGradient(
                        colors: [.clear, .black],
                        startPoint: .top,
                        endPoint: .bottom
                    )
                }

            LinearGradient(
                stops: [
                    .init(color: .clear, location: 0),
                    .init(color: tint.opacity(0.72), location: 0.58),
                    .init(color: tint, location: 1)
                ],
                startPoint: .top,
                endPoint: .bottom
            )
        }
        .frame(height: height)
        .allowsHitTesting(false)
        .accessibilityHidden(true)
    }

    private var tint: Color {
        Color(nsColor: .underPageBackgroundColor)
    }
}

private struct DashboardSidebarModifier: ViewModifier {
    @Environment(\.colorScheme) private var colorScheme

    let width: CGFloat

    func body(content: Content) -> some View {
        content
            .frame(width: width)
            .frame(maxHeight: .infinity)
            .background {
                ZStack {
                    BehindWindowSidebarMaterial()
                    (colorScheme == .dark ? Color.black : Color.white)
                        .opacity(0.30)
                }
            }
            .glassEffect(.clear, in: Rectangle())
            .overlay(alignment: .leading) {
                Rectangle()
                    .fill(colorScheme == .dark ? Color.black : Color.white)
                    .frame(width: 4)
                    .offset(x: -2)
                    .allowsHitTesting(false)
                    .zIndex(10)
            }
            .ignoresSafeArea(edges: .top)
    }
}

private struct BehindWindowSidebarMaterial: NSViewRepresentable {
    func makeNSView(context: Context) -> NSVisualEffectView {
        let effectView = NSVisualEffectView()
        configure(effectView)
        return effectView
    }

    func updateNSView(_ effectView: NSVisualEffectView, context: Context) {
        configure(effectView)
    }

    private func configure(_ effectView: NSVisualEffectView) {
        effectView.material = .sidebar
        effectView.blendingMode = .behindWindow
        effectView.state = .active
        effectView.isEmphasized = true
        effectView.alphaValue = 0.65
    }
}
