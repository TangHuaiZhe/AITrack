import SwiftUI

private struct SignalDeskFontScaleFactorKey: EnvironmentKey {
    static let defaultValue: CGFloat = 1
}

extension EnvironmentValues {
    var signalDeskFontScaleFactor: CGFloat {
        get { self[SignalDeskFontScaleFactorKey.self] }
        set { self[SignalDeskFontScaleFactorKey.self] = newValue }
    }
}

extension View {
    func scaledFont(_ font: Font) -> some View {
        modifier(ScaledFontModifier(font: font))
    }
}

private struct ScaledFontModifier: ViewModifier {
    let font: Font
    @Environment(\.signalDeskFontScaleFactor) private var factor

    @ViewBuilder
    func body(content: Content) -> some View {
        if factor == 1 {
            content.font(font)
        } else if #available(macOS 26.0, *) {
            content.font(font.scaled(by: factor))
        } else {
            // Font.scaled(by:) is macOS 26+. Keep a visual-only fallback for macOS 14–25.
            content
                .font(font)
                .scaleEffect(factor, anchor: .center)
        }
    }
}
