import SwiftUI
import XCTest
@testable import YamabikoChat

final class AppThemeTests: XCTestCase {
    func testThemeColorKeysMatchPersistedAppearanceOptions() {
        XCTAssertEqual(
            AppThemeColor.allCases.map(\.rawValue),
            ["BLUE_PURPLE", "BLUE", "GREEN", "YELLOW", "PINK", "ORANGE", "WHITE", "BLACK"]
        )
    }

    func testThemeColorSettingIsCaseInsensitive() {
        XCTAssertEqual(AppThemeColor(setting: "blue"), .blue)
        XCTAssertEqual(AppThemeColor(setting: "Pink"), .pink)
        XCTAssertEqual(AppThemeColor(setting: "ORANGE"), .orange)
    }

    func testUnknownThemeColorFallsBackToDefault() {
        XCTAssertEqual(AppThemeColor(setting: ""), .bluePurple)
        XCTAssertEqual(AppThemeColor(setting: "SEPIA"), .bluePurple)
    }

    func testChromaticAccentsKeepTheirGlyphColors() {
        XCTAssertEqual(AppThemeColor.yellow.onAccentColor, Color(uiColor: .black))
        for theme in [AppThemeColor.bluePurple, .blue, .green, .pink, .orange] {
            XCTAssertEqual(theme.onAccentColor, Color(uiColor: .white))
        }
    }

    func testMonochromeAccentsRemainReadableInBothAppearances() {
        for setting in ["WHITE", "BLACK"] {
            // Resolve the same palette again after an appearance change, as UIKit does.
            let theme = AppAccentTheme(themeColor: setting)
            for style in [UIUserInterfaceStyle.light, .dark] {
                let traits = UITraitCollection(userInterfaceStyle: style)
                let accent = UIColor(theme.color).resolvedColor(with: traits)
                let glyph = UIColor(theme.onAccentColor).resolvedColor(with: traits)
                XCTAssertGreaterThanOrEqual(contrast(accent, glyph), 4.5, "\(setting) filled button in \(style)")

                for surface in [UIColor.amoledSystemBackground, .amoledSecondarySystemBackground,
                                .amoledSystemGroupedBackground, .systemBackground,
                                .secondarySystemBackground, .tertiarySystemBackground] {
                    let background = surface.resolvedColor(with: traits)
                    XCTAssertGreaterThanOrEqual(contrast(accent, background), 4.5, "\(setting) link in \(style)")
                    let selectedBackground = blend(accent, over: background, opacity: 0.12)
                    XCTAssertGreaterThanOrEqual(contrast(accent, selectedBackground), 4.5, "\(setting) selected label in \(style)")
                }
            }
        }
    }

    func testMonochromeAccentsKeepPureColorWhereItIsVisible() {
        let dark = UITraitCollection(userInterfaceStyle: .dark)
        let light = UITraitCollection(userInterfaceStyle: .light)
        XCTAssertEqual(UIColor(AppThemeColor.white.color).resolvedColor(with: dark), .white)
        XCTAssertEqual(UIColor(AppThemeColor.black.color).resolvedColor(with: light), .black)
    }

    func testAccentThemeResolvesColorAndGlyphTogether() {
        let theme = AppAccentTheme(themeColor: "BLUE_PURPLE")
        XCTAssertEqual(theme.color, Color(uiColor: .systemIndigo))
        XCTAssertEqual(theme.onAccentColor, Color(uiColor: .white))
    }

    private func contrast(_ first: UIColor, _ second: UIColor) -> Double {
        let firstLuminance = luminance(first)
        let secondLuminance = luminance(second)
        return (max(firstLuminance, secondLuminance) + 0.05) / (min(firstLuminance, secondLuminance) + 0.05)
    }

    private func luminance(_ color: UIColor) -> Double {
        let components = components(color).map { value in
            value <= 0.04045 ? value / 12.92 : pow((value + 0.055) / 1.055, 2.4)
        }
        return components[0] * 0.2126 + components[1] * 0.7152 + components[2] * 0.0722
    }

    private func blend(_ foreground: UIColor, over background: UIColor, opacity: Double) -> UIColor {
        let blended = zip(components(foreground), components(background)).map { front, back in
            front * opacity + back * (1 - opacity)
        }
        return UIColor(red: blended[0], green: blended[1], blue: blended[2], alpha: 1)
    }

    private func components(_ color: UIColor) -> [Double] {
        var red: CGFloat = 0
        var green: CGFloat = 0
        var blue: CGFloat = 0
        var alpha: CGFloat = 0
        XCTAssertTrue(color.getRed(&red, green: &green, blue: &blue, alpha: &alpha))
        return [Double(red), Double(green), Double(blue)]
    }

    func testDefaultAccentThemeMatchesDefaultSetting() {
        XCTAssertEqual(AppAccentTheme.fallback, AppAccentTheme(themeColor: "BLUE_PURPLE"))
    }
}
