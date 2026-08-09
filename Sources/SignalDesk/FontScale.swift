import AppKit
import SwiftUI

enum SignalDeskFontScale: Int, CaseIterable {
    case small = 0
    case medium = 1
    case standard = 2
    case large = 3
    case extraLarge = 4

    var dynamicTypeSize: DynamicTypeSize {
        switch self {
        case .small: .small
        case .medium: .medium
        case .standard: .large
        case .large: .xLarge
        case .extraLarge: .xxLarge
        }
    }

    var factor: CGFloat {
        switch self {
        case .small: 0.88
        case .medium: 0.94
        case .standard: 1.0
        case .large: 1.10
        case .extraLarge: 1.20
        }
    }

    var title: String {
        switch self {
        case .small: "小"
        case .medium: "较小"
        case .standard: "标准"
        case .large: "较大"
        case .extraLarge: "大"
        }
    }

    static func from(rawValue: Int) -> SignalDeskFontScale {
        let clamped = min(max(rawValue, 0), allCases.count - 1)
        return allCases[clamped]
    }
}

@MainActor
final class SignalDeskFontScaleStore: ObservableObject {
    static let defaultsKey = "SignalDesk.fontScale"

    @Published private(set) var rawValue: Int
    private var keyMonitor: Any?

    init() {
        rawValue = UserDefaults.standard.object(forKey: Self.defaultsKey) as? Int
            ?? SignalDeskFontScale.standard.rawValue

        keyMonitor = NSEvent.addLocalMonitorForEvents(matching: .keyDown) { [weak self] event in
            guard let self else { return event }
            let flags = event.modifierFlags.intersection(.deviceIndependentFlagsMask)
            guard flags.contains(.command), !flags.contains(.option), !flags.contains(.control) else {
                return event
            }

            let characters = event.charactersIgnoringModifiers ?? ""
            switch event.keyCode {
            case 24:
                // Main =/+ key or numeric keypad +; plus is Command-Shift-=
                self.adjust(by: 1)
                return nil
            case 69 where characters == "=" || characters == "+" || characters == "＋":
                self.adjust(by: 1)
                return nil
            case 27:
                // Main - key or numeric keypad -
                self.adjust(by: -1)
                return nil
            case 78 where characters == "-" || characters == "−" || characters == "－":
                self.adjust(by: -1)
                return nil
            default:
                return event
            }
        }
    }

    deinit {
        if let keyMonitor {
            NSEvent.removeMonitor(keyMonitor)
        }
    }

    var scale: SignalDeskFontScale {
        SignalDeskFontScale.from(rawValue: rawValue)
    }

    func adjust(by delta: Int) {
        let next = min(
            max(rawValue + delta, SignalDeskFontScale.small.rawValue),
            SignalDeskFontScale.extraLarge.rawValue
        )
        guard next != rawValue else { return }
        rawValue = next
        UserDefaults.standard.set(next, forKey: Self.defaultsKey)
    }

    func reset() {
        rawValue = SignalDeskFontScale.standard.rawValue
        UserDefaults.standard.set(rawValue, forKey: Self.defaultsKey)
    }
}
