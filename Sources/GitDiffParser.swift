import Foundation

/// Result of resolving a click in a `git diff` / `git show` terminal buffer
/// to a (file, line) jump target.
enum GitDiffJumpTarget: Equatable {
    /// `relativePath` is whatever the diff header advertised (the `b/<...>`
    /// path), unmodified. Path resolution to an absolute path happens
    /// outside this parser.
    case fileLine(relativePath: String, line: Int)
}

/// Pure parser. No I/O, no AppKit, no main-thread assumptions.
/// Hermetic: input is an ANSI-stripped `[String]` snapshot of the terminal
/// (top-down: `lines[0]` is the topmost visible-or-scrollback row, the
/// click row index is into this same array).
enum GitDiffJumpParser {
    /// Resolve a click at `clickRow` in `lines`. Returns nil when the click
    /// is not inside a recognized diff context, when no `diff --git` header
    /// can be found within `maxScanRows` rows above `clickRow`, or when the
    /// diff metadata is malformed.
    ///
    /// The parser only reads rows in `[max(0, clickRow - maxScanRows), clickRow]`.
    static func resolve(
        lines: [String],
        clickRow: Int,
        maxScanRows: Int = 5_000
    ) -> GitDiffJumpTarget? {
        return nil
    }
}
