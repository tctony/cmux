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
