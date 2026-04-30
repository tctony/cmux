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
