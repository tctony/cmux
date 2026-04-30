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
