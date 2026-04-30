import XCTest

#if canImport(cmux_DEV)
@testable import cmux_DEV
#elseif canImport(cmux)
@testable import cmux
#endif

final class GitDiffParserTests: XCTestCase {
    func testReturnsNilWhenNoDiffHeaderAboveClick() {
        let lines = [
            "$ ls",
            "Documents",
            "Downloads",
        ]
        XCTAssertNil(
            GitDiffJumpParser.resolve(lines: lines, clickRow: 1)
        )
    }
}

extension GitDiffParserTests {
    private static let singleHunkDiff: [String] = [
        "diff --git a/src/foo.go b/src/foo.go",
        "index 1111111..2222222 100644",
        "--- a/src/foo.go",
        "+++ b/src/foo.go",
        "@@ -10,5 +10,6 @@ func init() {",
        " ctx := context.Background()",     // row 5: context line, new line 10
        "-    oldCall(ctx)",                 // row 6: deletion, no increment
        "+    newCall(ctx)",                 // row 7: addition, new line 11
        "+    extraCall(ctx)",               // row 8: addition, new line 12
        " return ctx",                       // row 9: context line, new line 13
        "}",                                  // row 10: outside hunk
    ]

    func testContextLineMapsToNewFileLine() {
        XCTAssertEqual(
            GitDiffJumpParser.resolve(lines: Self.singleHunkDiff, clickRow: 5),
            .fileLine(relativePath: "src/foo.go", line: 10)
        )
    }

    func testDeletionLineMapsToNextSurvivingNewFileLine() {
        XCTAssertEqual(
            GitDiffJumpParser.resolve(lines: Self.singleHunkDiff, clickRow: 6),
            .fileLine(relativePath: "src/foo.go", line: 11)
        )
    }

    func testAdditionLineMapsToItsNewFileLine() {
        XCTAssertEqual(
            GitDiffJumpParser.resolve(lines: Self.singleHunkDiff, clickRow: 7),
            .fileLine(relativePath: "src/foo.go", line: 11)
        )
        XCTAssertEqual(
            GitDiffJumpParser.resolve(lines: Self.singleHunkDiff, clickRow: 8),
            .fileLine(relativePath: "src/foo.go", line: 12)
        )
    }

    func testTrailingContextMapsToNewFileLine() {
        XCTAssertEqual(
            GitDiffJumpParser.resolve(lines: Self.singleHunkDiff, clickRow: 9),
            .fileLine(relativePath: "src/foo.go", line: 13)
        )
    }

    func testRowAfterHunkBodyReturnsNil() {
        XCTAssertNil(
            GitDiffJumpParser.resolve(lines: Self.singleHunkDiff, clickRow: 10)
        )
    }

    func testHunkHeaderItselfReturnsNewStart() {
        XCTAssertEqual(
            GitDiffJumpParser.resolve(lines: Self.singleHunkDiff, clickRow: 4),
            .fileLine(relativePath: "src/foo.go", line: 10)
        )
    }
}

extension GitDiffParserTests {
    private static let multiHunkOneFile: [String] = [
        "diff --git a/main.py b/main.py",
        "--- a/main.py",
        "+++ b/main.py",
        "@@ -10,2 +10,3 @@",
        " a",
        "+b",                  // row 5 → line 11
        " c",
        "@@ -50,2 +60,3 @@",
        " x",
        "+y",                  // row 9 → line 61
        " z",
    ]

    func testSecondHunkUsesItsOwnHeader() {
        XCTAssertEqual(
            GitDiffJumpParser.resolve(lines: Self.multiHunkOneFile, clickRow: 9),
            .fileLine(relativePath: "main.py", line: 61)
        )
    }

    func testFirstHunkStillWorksWhenSecondHunkFollows() {
        XCTAssertEqual(
            GitDiffJumpParser.resolve(lines: Self.multiHunkOneFile, clickRow: 5),
            .fileLine(relativePath: "main.py", line: 11)
        )
    }

    private static let twoFileDiff: [String] = [
        "diff --git a/a.txt b/a.txt",
        "--- a/a.txt",
        "+++ b/a.txt",
        "@@ -1,1 +1,2 @@",
        " a",
        "+aa",                                // row 5 → a.txt:2
        "diff --git a/b.txt b/b.txt",
        "--- a/b.txt",
        "+++ b/b.txt",
        "@@ -100,1 +100,2 @@",
        " b",
        "+bb",                                // row 11 → b.txt:101
    ]

    func testClickInSecondFileResolvesToSecondFile() {
        XCTAssertEqual(
            GitDiffJumpParser.resolve(lines: Self.twoFileDiff, clickRow: 11),
            .fileLine(relativePath: "b.txt", line: 101)
        )
    }

    func testClickInFirstFileNotConfusedBySecondFileBelow() {
        XCTAssertEqual(
            GitDiffJumpParser.resolve(lines: Self.twoFileDiff, clickRow: 5),
            .fileLine(relativePath: "a.txt", line: 2)
        )
    }
}

extension GitDiffParserTests {
    private static let metadataDiff: [String] = [
        "diff --git a/x.go b/x.go",          // row 0
        "new file mode 100644",              // row 1
        "index 0000000..1111111",            // row 2
        "--- /dev/null",                     // row 3
        "+++ b/x.go",                        // row 4
        "@@ -0,0 +1,2 @@",                   // row 5
        "+package main",                     // row 6
    ]

    func testClickOnDiffGitHeaderResolvesToLine1() {
        XCTAssertEqual(
            GitDiffJumpParser.resolve(lines: Self.metadataDiff, clickRow: 0),
            .fileLine(relativePath: "x.go", line: 1)
        )
    }

    func testClickOnNewFileModeResolvesToLine1() {
        XCTAssertEqual(
            GitDiffJumpParser.resolve(lines: Self.metadataDiff, clickRow: 1),
            .fileLine(relativePath: "x.go", line: 1)
        )
    }

    func testClickOnIndexLineResolvesToLine1() {
        XCTAssertEqual(
            GitDiffJumpParser.resolve(lines: Self.metadataDiff, clickRow: 2),
            .fileLine(relativePath: "x.go", line: 1)
        )
    }

    func testClickOnPlusPlusPlusHeaderResolvesToLine1() {
        XCTAssertEqual(
            GitDiffJumpParser.resolve(lines: Self.metadataDiff, clickRow: 4),
            .fileLine(relativePath: "x.go", line: 1)
        )
    }
}
