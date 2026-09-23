import SwiftUI
import UIKit

enum RemuxAppPalette {
    static let background = Color(uiColor: .remuxAppBackground)
    static let rowSurface = Color(uiColor: .remuxAppRowSurface)
    static let separator = Color(uiColor: .remuxAppSeparator)
    static let sectionHeader = Color(uiColor: .remuxAppSectionHeader)
    static let toolbarTint = Color(uiColor: .remuxAppToolbarTint)
    static let controlAccent = Color(uiColor: .remuxAppControlAccent)
    static let rowIconForeground = Color(uiColor: .remuxAppRowIconForeground)
    static let rowIconSurface = Color(uiColor: .remuxAppRowIconSurface)
}

typealias LibraryHomePalette = RemuxAppPalette

extension TerminalTheme {
    var remuxAppColorScheme: ColorScheme {
        switch self {
        case .remuxLight:
            .light
        case .ghosttyDefault, .remuxDark, .tokyoNight:
            .dark
        }
    }

    var libraryColorScheme: ColorScheme {
        remuxAppColorScheme
    }
}

extension View {
    func remuxAppListRowSurface() -> some View {
        listRowBackground(RemuxAppPalette.rowSurface)
            .listRowSeparatorTint(RemuxAppPalette.separator)
    }

    func remuxAppChrome(theme: TerminalTheme) -> some View {
        preferredColorScheme(theme.remuxAppColorScheme)
            .tint(RemuxAppPalette.toolbarTint)
            .toolbarBackground(RemuxAppPalette.background, for: .navigationBar)
            .toolbarBackground(.visible, for: .navigationBar)
    }

    func remuxAppGroupedScrollBackground() -> some View {
        scrollContentBackground(.hidden)
            .background(RemuxAppPalette.background.ignoresSafeArea())
    }

    @ViewBuilder
    func remuxSheetPresentationBackground() -> some View {
        if #available(iOS 26.0, *) {
            self
        } else {
            presentationBackground(.regularMaterial)
        }
    }

    func libraryHomeListRowSurface() -> some View {
        remuxAppListRowSurface()
    }

    func libraryHomeChrome(theme: TerminalTheme) -> some View {
        remuxAppChrome(theme: theme)
    }

    func libraryHomeGroupedScrollBackground() -> some View {
        remuxAppGroupedScrollBackground()
    }
}

private extension UIColor {
    // Dark variants are the Tokyo Night family so Remux's own chrome matches
    // the terminal palette: bg #1a1b26, card #24283b, fg #c0caf5, muted
    // #a9b1d6, accent #7aa2f7.
    static let remuxAppBackground = UIColor { traits in
        switch traits.userInterfaceStyle {
        case .dark:
            UIColor(red: 0.102, green: 0.106, blue: 0.149, alpha: 1.0)
        default:
            .systemGroupedBackground
        }
    }

    static let remuxAppRowSurface = UIColor { traits in
        switch traits.userInterfaceStyle {
        case .dark:
            UIColor(red: 0.141, green: 0.157, blue: 0.231, alpha: 1.0)
        default:
            .secondarySystemGroupedBackground
        }
    }

    static let remuxAppSeparator = UIColor { traits in
        switch traits.userInterfaceStyle {
        case .dark:
            UIColor.white.withAlphaComponent(0.08)
        default:
            .separator
        }
    }

    static let remuxAppSectionHeader = UIColor { traits in
        switch traits.userInterfaceStyle {
        case .dark:
            UIColor(red: 0.663, green: 0.694, blue: 0.839, alpha: 1.0)
        default:
            .secondaryLabel
        }
    }

    static let remuxAppToolbarTint = UIColor { traits in
        switch traits.userInterfaceStyle {
        case .dark:
            UIColor(red: 0.753, green: 0.792, blue: 0.961, alpha: 1.0)
        default:
            .label
        }
    }

    static let remuxAppControlAccent = UIColor { traits in
        switch traits.userInterfaceStyle {
        case .dark:
            UIColor(red: 0.478, green: 0.635, blue: 0.969, alpha: 1.0)
        default:
            .systemBlue
        }
    }

    static let remuxAppRowIconForeground = UIColor { traits in
        switch traits.userInterfaceStyle {
        case .dark:
            UIColor(red: 0.663, green: 0.694, blue: 0.839, alpha: 1.0)
        default:
            .secondaryLabel
        }
    }

    static let remuxAppRowIconSurface = UIColor { traits in
        switch traits.userInterfaceStyle {
        case .dark:
            UIColor.white.withAlphaComponent(0.07)
        default:
            .tertiarySystemFill
        }
    }
}
