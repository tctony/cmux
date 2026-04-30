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
        guard clickRow >= 0, clickRow < lines.count else { return nil }

        let scanFrom = max(0, clickRow - maxScanRows)

        // 1) Find nearest hunk header at-or-above clickRow.
        var hunkHeaderRow: Int? = nil
        var hunkNewStart: Int = 0
        for row in stride(from: clickRow, through: scanFrom, by: -1) {
            if let parsed = parseHunkHeader(lines[row]) {
                hunkHeaderRow = row
                hunkNewStart = parsed.newStart
                break
            }
            if isDiffGitHeader(lines[row]) {
                // Reached the file boundary before any hunk header above us.
                break
            }
        }

        // 2) Find the diff --git header that owns whatever we're inside (hunk
        //    or just file metadata above the first hunk).
        let scanCeilingForFileHeader = hunkHeaderRow ?? clickRow
        var fileHeaderRow: Int? = nil
        for row in stride(from: scanCeilingForFileHeader, through: scanFrom, by: -1) {
            if isDiffGitHeader(lines[row]) {
                fileHeaderRow = row
                break
            }
        }
        guard let fileHeaderRow else { return nil }

        guard let relativePath = parseDiffGitHeader(lines[fileHeaderRow]) else {
            return nil
        }

        // 3a) Click on file metadata (above any hunk in this file) → line 1.
        if hunkHeaderRow == nil {
            return .fileLine(relativePath: relativePath, line: 1)
        }

        // 3b) Click on the hunk header itself → newStart.
        let headerRow = hunkHeaderRow!
        if clickRow == headerRow {
            return .fileLine(relativePath: relativePath, line: hunkNewStart)
        }

        // 3c) Walk forward from the header to clickRow, applying +/-/space math.
        var newLine = hunkNewStart
        var candidate = hunkNewStart
        for row in (headerRow + 1)...clickRow {
            let line = lines[row]
            switch hunkBodyKind(of: line) {
            case .addition:
                candidate = newLine
                newLine += 1
            case .context:
                candidate = newLine
                newLine += 1
            case .deletion:
                candidate = newLine
            case .endOfHunk:
                return nil
            }
        }
        return .fileLine(relativePath: relativePath, line: candidate)
    }

    // MARK: - Header parsers (private)

    private static func isDiffGitHeader(_ line: String) -> Bool {
        line.hasPrefix("diff --git ")
    }

    /// Returns the `b/<path>` portion of `diff --git a/X b/Y`, with the leading
    /// `b/` stripped. Returns nil for malformed headers.
    private static func parseDiffGitHeader(_ line: String) -> String? {
        guard line.hasPrefix("diff --git ") else { return nil }
        let tail = String(line.dropFirst("diff --git ".count))
        // Last `b/...` token wins. Paths cannot contain unescaped spaces in
        // standard git output unless they're quoted; out-of-scope.
        guard let bRange = tail.range(of: " b/") else { return nil }
        let afterB = tail[bRange.upperBound...]
        return String(afterB)
    }

    private struct ParsedHunkHeader {
        let newStart: Int
    }

    /// Parses lines like `@@ -10,5 +10,6 @@ optional context`. Returns nil
    /// if the line isn't a hunk header.
    private static func parseHunkHeader(_ line: String) -> ParsedHunkHeader? {
        guard line.hasPrefix("@@ ") else { return nil }
        // Find the second `@@` to anchor the range portion.
        guard let secondAtAt = line.range(of: "@@", range: line.index(line.startIndex, offsetBy: 3)..<line.endIndex) else {
            return nil
        }
        let range = line[line.index(line.startIndex, offsetBy: 3)..<secondAtAt.lowerBound]
            .trimmingCharacters(in: .whitespaces)
        // range is like `-10,5 +10,6` (count fields are optional).
        let parts = range.split(separator: " ")
        guard parts.count >= 2 else { return nil }
        let plus = parts.first(where: { $0.hasPrefix("+") }) ?? ""
        let plusBody = plus.dropFirst()  // drop the '+'
        let firstField = plusBody.split(separator: ",").first.map(String.init) ?? ""
        guard let newStart = Int(firstField), newStart > 0 else { return nil }
        return ParsedHunkHeader(newStart: newStart)
    }

    private enum HunkBodyKind {
        case addition
        case context
        case deletion
        case endOfHunk
    }

    /// Classify a line inside a hunk body. Returns `.endOfHunk` for anything
    /// that signals we've left the hunk (next `@@`, next `diff --git`, blank
    /// line, or unrecognized leading byte).
    private static func hunkBodyKind(of line: String) -> HunkBodyKind {
        if line.hasPrefix("+") && !line.hasPrefix("+++") { return .addition }
        if line.hasPrefix("-") && !line.hasPrefix("---") { return .deletion }
        if line.hasPrefix(" ") { return .context }
        if line.isEmpty { return .endOfHunk }
        return .endOfHunk
    }
}
