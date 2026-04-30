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

final class GitDiffJumpEditorSettingsResolveTests: XCTestCase {
    private var tempRoot: URL!

    override func setUpWithError() throws {
        tempRoot = URL(fileURLWithPath: NSTemporaryDirectory())
            .appendingPathComponent("cmux-git-diff-jump-\(UUID().uuidString)")
        try FileManager.default.createDirectory(
            at: tempRoot, withIntermediateDirectories: true
        )
    }

    override func tearDownWithError() throws {
        try? FileManager.default.removeItem(at: tempRoot)
    }

    func testCwdRelativePathResolvesWhenFileExists() throws {
        let target = tempRoot.appendingPathComponent("src/foo.go")
        try FileManager.default.createDirectory(
            at: target.deletingLastPathComponent(), withIntermediateDirectories: true
        )
        FileManager.default.createFile(atPath: target.path, contents: Data())

        let resolved = GitDiffJumpEditorSettings.resolveAbsolutePath(
            relativePath: "src/foo.go",
            cwd: tempRoot.path
        )
        XCTAssertEqual(resolved, target.path)
    }

    func testWalkUpFindsRepoRootViaDotGit() throws {
        // Layout:
        //   tempRoot/.git
        //   tempRoot/src/foo.go
        //   tempRoot/src/sub/   (cwd)
        let dotGit = tempRoot.appendingPathComponent(".git")
        try FileManager.default.createDirectory(at: dotGit, withIntermediateDirectories: true)

        let target = tempRoot.appendingPathComponent("src/foo.go")
        try FileManager.default.createDirectory(
            at: target.deletingLastPathComponent(), withIntermediateDirectories: true
        )
        FileManager.default.createFile(atPath: target.path, contents: Data())

        let cwd = tempRoot.appendingPathComponent("src/sub")
        try FileManager.default.createDirectory(at: cwd, withIntermediateDirectories: true)

        let resolved = GitDiffJumpEditorSettings.resolveAbsolutePath(
            relativePath: "src/foo.go",
            cwd: cwd.path
        )
        XCTAssertEqual(resolved, target.path)
    }

    func testReturnsNilWhenFileDoesNotExistEvenWithGitRoot() throws {
        let dotGit = tempRoot.appendingPathComponent(".git")
        try FileManager.default.createDirectory(at: dotGit, withIntermediateDirectories: true)
        XCTAssertNil(
            GitDiffJumpEditorSettings.resolveAbsolutePath(
                relativePath: "does/not/exist.go",
                cwd: tempRoot.path
            )
        )
    }

    func testGitFileNotJustDirectoryCountsAsRepoRoot() throws {
        // `.git` can be a file (worktree pointer) instead of a directory.
        let dotGit = tempRoot.appendingPathComponent(".git")
        try "gitdir: /elsewhere\n".write(to: dotGit, atomically: true, encoding: .utf8)

        let target = tempRoot.appendingPathComponent("src/foo.go")
        try FileManager.default.createDirectory(
            at: target.deletingLastPathComponent(), withIntermediateDirectories: true
        )
        FileManager.default.createFile(atPath: target.path, contents: Data())

        let cwd = tempRoot.appendingPathComponent("src")
        let resolved = GitDiffJumpEditorSettings.resolveAbsolutePath(
            relativePath: "src/foo.go",
            cwd: cwd.path
        )
        XCTAssertEqual(resolved, target.path)
    }
}

@MainActor
final class GitDiffJumpEditorSettingsOpenTests: XCTestCase {
    private var defaults: UserDefaults!
    private let suiteName = "cmux.git-diff-jump.tests"

    override func setUp() async throws {
        defaults = UserDefaults(suiteName: suiteName)
        defaults.removePersistentDomain(forName: suiteName)
    }

    func testResolvedReturnsNilWhenCommandEmpty() {
        XCTAssertNil(GitDiffJumpEditorSettings.resolved(defaults: defaults))
        defaults.set("   ", forKey: GitDiffJumpEditorSettings.commandKey)
        XCTAssertNil(GitDiffJumpEditorSettings.resolved(defaults: defaults))
    }

    func testResolvedReturnsCommandAndArguments() {
        defaults.set("zed", forKey: GitDiffJumpEditorSettings.commandKey)
        defaults.set("\"%file\":%line", forKey: GitDiffJumpEditorSettings.argumentsKey)
        let resolved = GitDiffJumpEditorSettings.resolved(defaults: defaults)
        XCTAssertEqual(resolved?.command, "zed")
        XCTAssertEqual(resolved?.arguments, "\"%file\":%line")
    }

    func testOpenOrAlertReturnsNotConfiguredWhenCommandEmpty() {
        var capturedTitle: String?
        var capturedBody: String?
        let outcome = GitDiffJumpEditorSettings.openOrAlert(
            path: "/x.go",
            line: 1,
            defaults: defaults,
            presentAlert: { title, body in
                capturedTitle = title
                capturedBody = body
            }
        )
        XCTAssertEqual(outcome, .notConfigured)
        XCTAssertNotNil(capturedTitle)
        XCTAssertNotNil(capturedBody)
    }

    func testOpenOrAlertCapturesViaUITestEnvAndSkipsLaunch() throws {
        // Hardcoded env-var name from the implementation.
        let envKey = "CMUX_UI_TEST_CAPTURE_DIFF_JUMP_PATH"
        let captureURL = URL(fileURLWithPath: NSTemporaryDirectory())
            .appendingPathComponent("cmux-diff-jump-capture-\(UUID().uuidString).log")
        setenv(envKey, captureURL.path, 1)
        defer {
            unsetenv(envKey)
            try? FileManager.default.removeItem(at: captureURL)
        }
        defaults.set("/usr/bin/false", forKey: GitDiffJumpEditorSettings.commandKey)
        defaults.set("\"%file\":%line", forKey: GitDiffJumpEditorSettings.argumentsKey)

        let outcome = GitDiffJumpEditorSettings.openOrAlert(
            path: "/repo/x.go",
            line: 42,
            defaults: defaults,
            presentAlert: { _, _ in XCTFail("alert should not be presented in capture mode") }
        )
        XCTAssertEqual(outcome, .launched)

        let captured = try String(contentsOf: captureURL, encoding: .utf8)
        XCTAssertEqual(captured, "/repo/x.go\t42\n")
    }
}
