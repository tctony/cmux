import XCTest

#if canImport(cmux_DEV)
@testable import cmux_DEV
#elseif canImport(cmux)
@testable import cmux
#endif

final class GitDiffJumpEditorSettingsSubstitutionTests: XCTestCase {
    func testEachPresetSubstitutesFileAndLineCorrectly() {
        let file = "/repo/src/x.go"
        let line = 100
        let urlEncoded = "/repo/src/x.go"  // no percent-needed chars in this path

        let expected: [String: String] = [
            "Visual Studio Code": "vscode://file\"\(urlEncoded)\":100",
            "Cursor":             "cursor://file\"\(urlEncoded)\":100",
            "Zed":                "\"\(file)\":100",
            "Sublime Text":       "\"\(file)\":100",
            "MacVim":             "--remote-silent +\"100\" \"\(file)\"",
            "Emacs":              "--no-wait +100 \"\(file)\"",
            "JetBrains IDE":      "--line 100 \"\(file)\"",
            "Xcode":              "--line 100 \"\(file)\"",
            "TextMate":           "-l 100 \"\(file)\"",
            "BBEdit":             "+100 \"\(file)\"",
            "Nova":               "open \"\(file)\" -l 100",
        ]

        for preset in GitDiffJumpEditorSettings.presets {
            let actual = GitDiffJumpEditorSettings.substitute(
                arguments: preset.arguments, file: file, line: line
            )
            XCTAssertEqual(
                actual,
                expected[preset.name],
                "preset \(preset.name)"
            )
        }
    }

    func testUrlfilePercentEncodesSpacesAndPercent() {
        let arguments = "vscode://file\"%urlfile\":%line"
        let actual = GitDiffJumpEditorSettings.substitute(
            arguments: arguments,
            file: "/repo/Some Path/100% bug.go",
            line: 42
        )
        // Spaces become %20, '%' becomes %25.
        XCTAssertEqual(
            actual,
            "vscode://file\"/repo/Some%20Path/100%25%20bug.go\":42"
        )
    }

    func testFilePlaceholderIsLiteralNotPercentEncoded() {
        let actual = GitDiffJumpEditorSettings.substitute(
            arguments: "\"%file\":%line",
            file: "/repo/Some Path/x.go",
            line: 9
        )
        XCTAssertEqual(actual, "\"/repo/Some Path/x.go\":9")
    }

    func testPresetCountAndOrderAreLockedDown() {
        XCTAssertEqual(GitDiffJumpEditorSettings.presets.count, 11)
        XCTAssertEqual(GitDiffJumpEditorSettings.presets.first?.name, "Visual Studio Code")
        XCTAssertEqual(GitDiffJumpEditorSettings.presets.last?.name, "Nova")
    }
}
