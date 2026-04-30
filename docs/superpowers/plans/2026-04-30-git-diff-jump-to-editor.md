# Git Diff Jump to Editor — Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Cmd+Shift+Click on a `git diff` / `git show` line in a cmux terminal opens the corresponding file at the corresponding line in a user-configured external editor.

**Architecture:** Three loosely coupled pieces:
1. A pure-Swift parser (`GitDiffParser`) that maps `(lines, clickRow) → (path, line)`.
2. A Skim-style editor settings model (`GitDiffJumpEditorSettings`) with preset table, placeholder substitution, and process invocation that surfaces errors as `NSAlert` instead of silently falling back.
3. Terminal-side glue in `GhosttyTerminalView.mouseUp` that recognizes the cmd+shift modifier, snapshots viewport+scrollback (5 000 row cap), resolves the relative path against the terminal's CWD with a `.git` walk-up, and invokes the editor.

**Tech Stack:** Swift / AppKit / SwiftUI / XCTest. Builds via `xcodebuild`. Existing cmux conventions for settings (`@AppStorage` + JSON file store + JSON schema + `Localizable.xcstrings`).

**Spec:** `docs/superpowers/specs/2026-04-30-git-diff-jump-to-editor-design.md`

---

## File Structure

**New files:**

| Path | Responsibility |
|---|---|
| `Sources/GitDiffParser.swift` | Pure parser. Top-level `enum GitDiffJumpParser` + `enum GitDiffJumpTarget`. No app imports. |
| `Sources/GitDiffJumpEditorSettings.swift` | Preset table, placeholder substitution, `openOrAlert(path:line:)`. UserDefaults keys. |
| `cmuxTests/GitDiffParserTests.swift` | Hermetic unit tests for parser. |
| `cmuxTests/GitDiffJumpEditorSettingsTests.swift` | Hermetic unit tests for substitution + path-resolution walk-up. |
| `docs/git-diff-jump.md` | User-facing reference: gesture, preset table, placeholder grammar, Xcode quirk note. |

**Modified files:**

| Path | What changes |
|---|---|
| `Sources/GhosttyTerminalView.swift` | `mouseUp` recognizes cmd+shift; new `handleDiffJumpClickRelease(at:)` method. UI-test capture env var. Debug simulate function. |
| `Sources/cmuxApp.swift` | New `SettingsCardRow` "Git Diff Jump" with Preset / Command / Arguments fields. Wires `@AppStorage` to the new keys. Reset button updates. |
| `Sources/KeyboardShortcutSettingsFileStore.swift` | Adds 3 keys to `supportedSettingsJSONPaths`, JSON load, JSON snapshot, defaults block. |
| `Sources/SettingsSearchAliases.swift` | Aliases so the new card is findable via Settings search. |
| `Sources/SettingsNavigation.swift` | Anchor for jump-to-section. |
| `web/data/cmux-settings.schema.json` | 3 new properties under `app`. |
| `Resources/Localizable.xcstrings` | 9 new keys (card title, subtitle, placeholders, alert messages) with English + Japanese. |
| `GhosttyTabs.xcodeproj/project.pbxproj` | 4 file refs + build entries (2 source + 2 test). |

---

## Test commands (CI-preferred; local-safe alternatives noted)

- **Unit tests** (safe locally, but prefer CI per CLAUDE.md):
  ```bash
  xcodebuild -scheme cmux-unit -configuration Debug -destination 'platform=macOS' \
    -derivedDataPath /tmp/cmux-git-diff-jump-tests test
  ```
  Filter to a class:
  ```bash
  xcodebuild -scheme cmux-unit -configuration Debug -destination 'platform=macOS' \
    -derivedDataPath /tmp/cmux-git-diff-jump-tests \
    -only-testing:cmuxTests/GitDiffParserTests test
  ```
- **Build-only smoke** (compiles new files without launching app):
  ```bash
  xcodebuild -project GhosttyTabs.xcodeproj -scheme cmux -configuration Debug \
    -destination 'platform=macOS' -derivedDataPath /tmp/cmux-git-diff-jump build
  ```
- **End-to-end manual smoke** (only after all tasks): `./scripts/reload.sh --tag git-diff-jump --launch`

---

## Task 1: Scaffold parser + first failing test

**Files:**
- Create: `Sources/GitDiffParser.swift`
- Create: `cmuxTests/GitDiffParserTests.swift`
- Modify: `GhosttyTabs.xcodeproj/project.pbxproj`

- [ ] **Step 1: Add empty parser file**

Create `Sources/GitDiffParser.swift`:

```swift
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
```

- [ ] **Step 2: Register the new file in the Xcode project**

`Sources/PortScanner.swift` is a similar leaf module. Mirror its three pbxproj entries: `PBXBuildFile`, `PBXFileReference`, and the `Sources` group + Sources build phase. Generate two unique 24-char hex IDs (e.g. via `python3 -c "import secrets; print(secrets.token_hex(12).upper())"`) — one for the `BuildFile`, one for the `FileReference`.

Reference shape (replace `XX/YY` with the new IDs):

```
		XX0001 /* GitDiffParser.swift in Sources */ = {isa = PBXBuildFile; fileRef = YY0001 /* GitDiffParser.swift */; };
		YY0001 /* GitDiffParser.swift */ = {isa = PBXFileReference; lastKnownFileType = sourcecode.swift; path = GitDiffParser.swift; sourceTree = "<group>"; };
```

Add `YY0001` to the same `PBXGroup` that contains `PortScanner.swift` (search `A5001541` for the location). Add `XX0001` to the same `PBXSourcesBuildPhase` that contains the cmux app target's sources.

- [ ] **Step 3: Add empty test file**

Create `cmuxTests/GitDiffParserTests.swift`:

```swift
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
```

- [ ] **Step 4: Register the test file in the Xcode project**

Same pattern as Step 2, but the file goes in the cmuxTests target's group + Sources build phase. Search `PortScannerProcessCaptureTests` (or `PortScannerTests.swift`) in `project.pbxproj` to find the right group/build-phase IDs.

- [ ] **Step 5: Build and run the test**

```bash
xcodebuild -scheme cmux-unit -configuration Debug -destination 'platform=macOS' \
  -derivedDataPath /tmp/cmux-git-diff-jump-tests \
  -only-testing:cmuxTests/GitDiffParserTests/testReturnsNilWhenNoDiffHeaderAboveClick test
```

Expected: PASS (parser returns nil today, test asserts nil).

- [ ] **Step 6: Commit**

```bash
git add Sources/GitDiffParser.swift cmuxTests/GitDiffParserTests.swift GhosttyTabs.xcodeproj/project.pbxproj
git commit -m "feat: scaffold GitDiffJumpParser + first hermetic test"
```

---

## Task 2: Parser — single hunk, `+`/`-`/` ` rows

**Files:**
- Modify: `Sources/GitDiffParser.swift`
- Modify: `cmuxTests/GitDiffParserTests.swift`

- [ ] **Step 1: Write failing tests for hunk-body math**

Append to `cmuxTests/GitDiffParserTests.swift`:

```swift
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
```

- [ ] **Step 2: Run, confirm all 6 fail**

```bash
xcodebuild -scheme cmux-unit -configuration Debug -destination 'platform=macOS' \
  -derivedDataPath /tmp/cmux-git-diff-jump-tests \
  -only-testing:cmuxTests/GitDiffParserTests test
```

Expected: 6 new failures (XCTAssertEqual mismatches; resolve still returns nil).

- [ ] **Step 3: Implement `resolve` for single-hunk case**

Replace the body of `resolve` in `Sources/GitDiffParser.swift`:

```swift
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
```

- [ ] **Step 4: Run tests, expect all 7 (1 nil + 6 new) to pass**

```bash
xcodebuild -scheme cmux-unit -configuration Debug -destination 'platform=macOS' \
  -derivedDataPath /tmp/cmux-git-diff-jump-tests \
  -only-testing:cmuxTests/GitDiffParserTests test
```

- [ ] **Step 5: Commit**

```bash
git add Sources/GitDiffParser.swift cmuxTests/GitDiffParserTests.swift
git commit -m "feat(git-diff-jump): parser handles single-hunk +/-/context math"
```

---

## Task 3: Parser — multiple hunks per file, multiple files

**Files:**
- Modify: `cmuxTests/GitDiffParserTests.swift`
- Modify: `Sources/GitDiffParser.swift` _(only if a test fails — implementation in Task 2 should already cover these; new failing tests confirm)_

- [ ] **Step 1: Write failing tests**

Append to `cmuxTests/GitDiffParserTests.swift`:

```swift
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
```

- [ ] **Step 2: Run; if all pass, the Task 2 implementation is sufficient**

```bash
xcodebuild -scheme cmux-unit -configuration Debug -destination 'platform=macOS' \
  -derivedDataPath /tmp/cmux-git-diff-jump-tests \
  -only-testing:cmuxTests/GitDiffParserTests test
```

If any fail, narrow the bug, fix in `GitDiffParser.swift`, re-run.

- [ ] **Step 3: Commit**

```bash
git add cmuxTests/GitDiffParserTests.swift Sources/GitDiffParser.swift
git commit -m "test(git-diff-jump): parser handles multi-hunk + multi-file diffs"
```

---

## Task 4: Parser — diff metadata rows → line 1

**Files:**
- Modify: `cmuxTests/GitDiffParserTests.swift`
- Modify: `Sources/GitDiffParser.swift`

- [ ] **Step 1: Write failing tests**

Append:

```swift
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
```

- [ ] **Step 2: Run, expect 4 failures**

The current implementation classifies `+++ b/x.go` as `.addition` (it starts with `+`). The guard in `hunkBodyKind` (`!line.hasPrefix("+++")`) handles that for hunk-body classification, but the click-on-`+++`-header test currently sees `hunkHeaderRow == nil` so it should already return line 1 — verify whether this passes or fails before fixing.

- [ ] **Step 3: Adjust implementation if needed**

If `testClickOnPlusPlusPlusHeaderResolvesToLine1` or its siblings fail, make sure these rows are recognized as "diff file metadata, not hunk-body":

In `resolve`, after computing `fileHeaderRow`, if `hunkHeaderRow == nil` we already return line 1 — that's correct. But the loop that finds `hunkHeaderRow` walks past `+++ b/x.go` (which doesn't match `parseHunkHeader` and isn't a `diff --git` line, so the loop continues). That means a click on row 4 sees `hunkHeaderRow == nil` correctly, returns line 1. Good — should pass without changes.

If any test fails, add the missing classification in `parseHunkHeader` or the walk loop and re-run.

- [ ] **Step 4: Run all tests, expect green**

```bash
xcodebuild -scheme cmux-unit -configuration Debug -destination 'platform=macOS' \
  -derivedDataPath /tmp/cmux-git-diff-jump-tests \
  -only-testing:cmuxTests/GitDiffParserTests test
```

- [ ] **Step 5: Commit**

```bash
git add cmuxTests/GitDiffParserTests.swift Sources/GitDiffParser.swift
git commit -m "test(git-diff-jump): clicks on diff metadata rows map to line 1"
```

---

## Task 5: Parser — renames, scan-limit, malformed input

**Files:**
- Modify: `cmuxTests/GitDiffParserTests.swift`
- Modify: `Sources/GitDiffParser.swift`

- [ ] **Step 1: Write failing tests**

Append:

```swift
extension GitDiffParserTests {
    private static let renameDiff: [String] = [
        "diff --git a/old/path.go b/new/path.go",
        "similarity index 90%",
        "rename from old/path.go",
        "rename to new/path.go",
        "--- a/old/path.go",
        "+++ b/new/path.go",
        "@@ -1,2 +1,2 @@",
        " a",
        "+b",        // row 8 → new/path.go:2
    ]

    func testRenameUsesPostRenamePath() {
        XCTAssertEqual(
            GitDiffJumpParser.resolve(lines: Self.renameDiff, clickRow: 8),
            .fileLine(relativePath: "new/path.go", line: 2)
        )
    }

    func testClickAboveScanLimitReturnsNil() {
        // 6 000 noise rows then a one-file diff.
        var lines = Array(repeating: "$ noise", count: 6_000)
        lines.append("diff --git a/x.go b/x.go")
        lines.append("--- a/x.go")
        lines.append("+++ b/x.go")
        lines.append("@@ -1,1 +1,2 @@")
        lines.append(" a")
        lines.append("+b")
        XCTAssertEqual(
            GitDiffJumpParser.resolve(lines: lines, clickRow: lines.count - 1),
            .fileLine(relativePath: "x.go", line: 2)
        )

        // Now shrink scan to 100 rows; the diff header is 6 005 rows above
        // the click → must return nil.
        XCTAssertNil(
            GitDiffJumpParser.resolve(
                lines: lines,
                clickRow: lines.count - 1,
                maxScanRows: 100
            )
        )
    }

    func testMalformedHunkHeaderReturnsNil() {
        let lines = [
            "diff --git a/x.go b/x.go",
            "--- a/x.go",
            "+++ b/x.go",
            "@@ this is not a hunk @@",
            "+something",
        ]
        // The click is on a `+` row but no valid `@@` header above → falls
        // through to the file-metadata branch, returns line 1.
        XCTAssertEqual(
            GitDiffJumpParser.resolve(lines: lines, clickRow: 4),
            .fileLine(relativePath: "x.go", line: 1)
        )
    }

    func testClickRowOutOfBoundsReturnsNil() {
        let lines = ["diff --git a/x b/x"]
        XCTAssertNil(GitDiffJumpParser.resolve(lines: lines, clickRow: 99))
        XCTAssertNil(GitDiffJumpParser.resolve(lines: lines, clickRow: -1))
    }

    func testGitShowCommitMetadataAboveDiffIsIgnored() {
        let lines = [
            "commit deadbeef",
            "Author: A B <a@b>",
            "Date:   Wed Apr 30 12:00:00 2026 +0900",
            "",
            "    subject line",
            "",
            "diff --git a/x.go b/x.go",
            "--- a/x.go",
            "+++ b/x.go",
            "@@ -1,1 +1,2 @@",
            " a",
            "+b",   // row 11 → x.go:2
        ]
        XCTAssertEqual(
            GitDiffJumpParser.resolve(lines: lines, clickRow: 11),
            .fileLine(relativePath: "x.go", line: 2)
        )
    }
}
```

- [ ] **Step 2: Run, fix the implementation as needed**

```bash
xcodebuild -scheme cmux-unit -configuration Debug -destination 'platform=macOS' \
  -derivedDataPath /tmp/cmux-git-diff-jump-tests \
  -only-testing:cmuxTests/GitDiffParserTests test
```

The rename test should pass already (`parseDiffGitHeader` always returns the `b/<...>` part). The scan-limit test verifies the `stride` floor. The malformed-hunk test verifies that an unparseable `@@` is treated as "not a hunk header" so we fall through to "no hunk → line 1". The out-of-bounds test verifies the early guard.

If any fail, fix in `GitDiffParser.swift` and re-run.

- [ ] **Step 3: Commit**

```bash
git add cmuxTests/GitDiffParserTests.swift Sources/GitDiffParser.swift
git commit -m "test(git-diff-jump): parser handles rename, scan limit, malformed hunks"
```

---

## Task 6: Editor settings — preset table + substitution

**Files:**
- Create: `Sources/GitDiffJumpEditorSettings.swift`
- Create: `cmuxTests/GitDiffJumpEditorSettingsTests.swift`
- Modify: `GhosttyTabs.xcodeproj/project.pbxproj`

- [ ] **Step 1: Add the settings file with presets + substitution**

Create `Sources/GitDiffJumpEditorSettings.swift`:

```swift
import AppKit
import Foundation

struct GitDiffJumpEditorPreset: Equatable {
    let name: String        // shown in dropdown; persisted as `gitDiffJumpPreset`
    let command: String
    let arguments: String
}

enum GitDiffJumpEditorSettings {
    static let presetKey = "gitDiffJumpPreset"
    static let commandKey = "gitDiffJumpCommand"
    static let argumentsKey = "gitDiffJumpArguments"
    static let scrollbackLimitKey = "gitDiffJumpScrollbackLimit"
    static let defaultScrollbackLimit = 5_000

    static let customPresetName = "Custom"

    /// Curated from Skim's `InitialUserDefaults.plist > TeXEditors`, with
    /// dead editors dropped (TextWrangler, Atom, Aquamacs, AlphaCocoa,
    /// LyX, TeXMaker) and modern editors added (Cursor, Zed, JetBrains,
    /// Xcode). Order matches the Settings UI dropdown.
    static let presets: [GitDiffJumpEditorPreset] = [
        .init(name: "Visual Studio Code", command: "open",        arguments: "vscode://file\"%urlfile\":%line"),
        .init(name: "Cursor",             command: "open",        arguments: "cursor://file\"%urlfile\":%line"),
        .init(name: "Zed",                command: "zed",         arguments: "\"%file\":%line"),
        .init(name: "Sublime Text",       command: "subl",        arguments: "\"%file\":%line"),
        .init(name: "MacVim",             command: "mvim",        arguments: "--remote-silent +\"%line\" \"%file\""),
        .init(name: "Emacs",              command: "emacsclient", arguments: "--no-wait +%line \"%file\""),
        .init(name: "JetBrains IDE",      command: "idea",        arguments: "--line %line \"%file\""),
        .init(name: "Xcode",              command: "xed",         arguments: "--line %line \"%file\""),
        .init(name: "TextMate",           command: "mate",        arguments: "-l %line \"%file\""),
        .init(name: "BBEdit",             command: "bbedit",      arguments: "+%line \"%file\""),
        .init(name: "Nova",               command: "nova",        arguments: "open \"%file\" -l %line"),
    ]

    /// Substitute %file / %line / %urlfile placeholders in `arguments` with
    /// the given absolute path and 1-based line number. Pure; no quoting
    /// added beyond what the user wrote.
    static func substitute(arguments: String, file: String, line: Int) -> String {
        let urlEncoded = (file as NSString).addingPercentEncoding(
            withAllowedCharacters: .urlPathAllowed
        ) ?? file
        return arguments
            .replacingOccurrences(of: "%urlfile", with: urlEncoded)
            .replacingOccurrences(of: "%file", with: file)
            .replacingOccurrences(of: "%line", with: String(line))
    }
}
```

- [ ] **Step 2: Add the test file**

Create `cmuxTests/GitDiffJumpEditorSettingsTests.swift`:

```swift
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
```

- [ ] **Step 3: Register both files in `project.pbxproj`**

Same procedure as Task 1 Steps 2 and 4. Two new IDs each for the source and test files (4 total IDs, 4 total entries pairs).

- [ ] **Step 4: Run tests**

```bash
xcodebuild -scheme cmux-unit -configuration Debug -destination 'platform=macOS' \
  -derivedDataPath /tmp/cmux-git-diff-jump-tests \
  -only-testing:cmuxTests/GitDiffJumpEditorSettingsSubstitutionTests test
```

Expected: 4 PASS.

- [ ] **Step 5: Commit**

```bash
git add Sources/GitDiffJumpEditorSettings.swift cmuxTests/GitDiffJumpEditorSettingsTests.swift GhosttyTabs.xcodeproj/project.pbxproj
git commit -m "feat(git-diff-jump): preset table + placeholder substitution"
```

---

## Task 7: Editor settings — repo-root walk-up path resolution

**Files:**
- Modify: `Sources/GitDiffJumpEditorSettings.swift`
- Modify: `cmuxTests/GitDiffJumpEditorSettingsTests.swift`

- [ ] **Step 1: Add failing tests**

Append to `cmuxTests/GitDiffJumpEditorSettingsTests.swift`:

```swift
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
```

- [ ] **Step 2: Run, expect 4 failures (function does not exist)**

```bash
xcodebuild -scheme cmux-unit -configuration Debug -destination 'platform=macOS' \
  -derivedDataPath /tmp/cmux-git-diff-jump-tests \
  -only-testing:cmuxTests/GitDiffJumpEditorSettingsResolveTests test
```

- [ ] **Step 3: Implement `resolveAbsolutePath`**

Append to `Sources/GitDiffJumpEditorSettings.swift`:

```swift
extension GitDiffJumpEditorSettings {
    /// Resolve a `git diff` relative path (e.g. `src/foo.go` from
    /// `b/src/foo.go`) to an absolute path on disk.
    ///
    /// Strategy:
    ///   1. Try `cwd/<relativePath>`. If it exists, return it.
    ///   2. Walk up from `cwd` looking for an entry literally named `.git`
    ///      (file OR directory). The first ancestor that contains one is
    ///      treated as the repo root; try `<repoRoot>/<relativePath>`.
    ///   3. Otherwise, return nil.
    ///
    /// File existence is checked via `FileManager.default.fileExists`.
    /// All `stat` calls are bounded by the filesystem hierarchy depth and
    /// are safe to run from a background thread.
    static func resolveAbsolutePath(relativePath: String, cwd: String) -> String? {
        let fm = FileManager.default
        let direct = (cwd as NSString).appendingPathComponent(relativePath)
        if fm.fileExists(atPath: direct) {
            return direct
        }

        var current = cwd
        let root = "/"
        while current != root && !current.isEmpty {
            let dotGit = (current as NSString).appendingPathComponent(".git")
            if fm.fileExists(atPath: dotGit) {
                let candidate = (current as NSString).appendingPathComponent(relativePath)
                return fm.fileExists(atPath: candidate) ? candidate : nil
            }
            let parent = (current as NSString).deletingLastPathComponent
            if parent == current { break }
            current = parent
        }
        return nil
    }
}
```

- [ ] **Step 4: Run, expect all 4 PASS**

- [ ] **Step 5: Commit**

```bash
git add Sources/GitDiffJumpEditorSettings.swift cmuxTests/GitDiffJumpEditorSettingsTests.swift
git commit -m "feat(git-diff-jump): walk-up path resolution against .git ancestor"
```

---

## Task 8: Editor settings — process invocation + error alert

**Files:**
- Modify: `Sources/GitDiffJumpEditorSettings.swift`
- Modify: `cmuxTests/GitDiffJumpEditorSettingsTests.swift`

- [ ] **Step 1: Add invocation API + UI-test capture seam**

Append to `Sources/GitDiffJumpEditorSettings.swift`:

```swift
extension GitDiffJumpEditorSettings {
    /// Resolved (command, arguments) pair to actually invoke. nil if the
    /// user has not configured a command (treat as "not configured").
    struct ResolvedInvocation: Equatable {
        let command: String
        let arguments: String
    }

    /// Read the configured command/arguments. Treats whitespace-only as
    /// empty. Preset name is presentation-only and not consulted here.
    static func resolved(defaults: UserDefaults = .standard) -> ResolvedInvocation? {
        let command = (defaults.string(forKey: commandKey) ?? "")
            .trimmingCharacters(in: .whitespacesAndNewlines)
        guard !command.isEmpty else { return nil }
        let arguments = (defaults.string(forKey: argumentsKey) ?? "")
            .trimmingCharacters(in: .whitespacesAndNewlines)
        return ResolvedInvocation(command: command, arguments: arguments)
    }

    enum OpenOutcome: Equatable {
        case launched
        case notConfigured
        case launchFailed(reason: String)
    }

    /// Run `<command> <substitutedArguments>` via `/bin/sh -c`. Surfaces
    /// failures through `presentAlert` (a closure) and via a UI-test capture
    /// env var when set. Never falls back to NSWorkspace.shared.open.
    @MainActor
    @discardableResult
    static func openOrAlert(
        path: String,
        line: Int,
        defaults: UserDefaults = .standard,
        presentAlert: (String, String) -> Void = { title, message in
            let alert = NSAlert()
            alert.alertStyle = .warning
            alert.messageText = title
            alert.informativeText = message
            alert.addButton(withTitle: NSLocalizedString(
                "settings.app.gitDiffJump.openSettings",
                value: "Open Settings…", comment: ""
            ))
            alert.addButton(withTitle: NSLocalizedString(
                "alert.cancel",
                value: "Cancel", comment: ""
            ))
            if alert.runModal() == .alertFirstButtonReturn {
                NSApp.sendAction(#selector(NSApplication.showSettingsWindow(_:)),
                                 to: nil, from: nil)
            }
        }
    ) -> OpenOutcome {
        if CmuxUITestCapture.appendLineIfConfigured(
            envKey: "CMUX_UI_TEST_CAPTURE_DIFF_JUMP_PATH",
            line: "\(path)\t\(line)"
        ) {
            return .launched
        }

        guard let invocation = resolved(defaults: defaults) else {
            presentAlert(
                NSLocalizedString("settings.app.gitDiffJump.notConfigured.title",
                                  value: "Git Diff Jump is not configured", comment: ""),
                NSLocalizedString("settings.app.gitDiffJump.notConfigured.body",
                                  value: "Pick a preset (or fill in a custom command) under Settings → App → Git Diff Jump to enable cmd+shift+click jumps from diffs.",
                                  comment: "")
            )
            return .notConfigured
        }

        let substituted = substitute(arguments: invocation.arguments, file: path, line: line)
        let shellLine = "\(invocation.command) \(substituted)"

        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/bin/sh")
        process.arguments = ["-c", shellLine]
        let stderrPipe = Pipe()
        process.standardOutput = FileHandle.nullDevice
        process.standardError = stderrPipe

        do {
            try process.run()
        } catch {
            let reason = "Failed to launch /bin/sh -c: \(error.localizedDescription)"
            presentAlert(
                NSLocalizedString("settings.app.gitDiffJump.launchFailed.title",
                                  value: "Editor command failed to launch", comment: ""),
                "\(invocation.command)\n\n\(reason)"
            )
            return .launchFailed(reason: reason)
        }

        DispatchQueue.global(qos: .userInitiated).async {
            process.waitUntilExit()
            let status = process.terminationStatus
            if status != 0 {
                let stderrData = (try? stderrPipe.fileHandleForReading.readToEnd()) ?? Data()
                let stderr = String(data: stderrData.prefix(1024), encoding: .utf8) ?? ""
                let reason = "Exit \(status). stderr: \(stderr.isEmpty ? "(empty)" : stderr)"
                #if DEBUG
                cmuxDebugLog("git-diff-jump.failed cmd=\(shellLine) status=\(status) stderr=\(stderr)")
                #endif
                DispatchQueue.main.async {
                    presentAlert(
                        NSLocalizedString("settings.app.gitDiffJump.exitNonZero.title",
                                          value: "Editor command exited with error", comment: ""),
                        "\(invocation.command) exited with status \(status).\n\nstderr (first 1 KB):\n\(stderr.isEmpty ? "(empty)" : stderr)"
                    )
                }
            }
        }
        return .launched
    }
}
```

- [ ] **Step 2: Add tests for `resolved` + `openOrAlert` outcome paths**

Append to `cmuxTests/GitDiffJumpEditorSettingsTests.swift`:

```swift
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
```

- [ ] **Step 3: Run, expect green**

```bash
xcodebuild -scheme cmux-unit -configuration Debug -destination 'platform=macOS' \
  -derivedDataPath /tmp/cmux-git-diff-jump-tests \
  -only-testing:cmuxTests/GitDiffJumpEditorSettingsOpenTests test
```

- [ ] **Step 4: Commit**

```bash
git add Sources/GitDiffJumpEditorSettings.swift cmuxTests/GitDiffJumpEditorSettingsTests.swift
git commit -m "feat(git-diff-jump): process invocation + NSAlert error surfacing"
```

---

## Task 9: Settings storage — UserDefaults keys, JSON file store, schema

**Files:**
- Modify: `Sources/KeyboardShortcutSettingsFileStore.swift`
- Modify: `web/data/cmux-settings.schema.json`

- [ ] **Step 1: Add the three keys to `supportedSettingsJSONPaths`**

In `Sources/KeyboardShortcutSettingsFileStore.swift` near line 36 (after `"app.preferredEditor"`):

```swift
        "app.preferredEditor",
        "app.gitDiffJumpPreset",
        "app.gitDiffJumpCommand",
        "app.gitDiffJumpArguments",
        "app.openMarkdownInCmuxViewer",
```

- [ ] **Step 2: Add the JSON parse path**

Find the block near line 419 that handles `preferredEditor` and add three sibling blocks beneath it:

```swift
        if let value = jsonString(section["preferredEditor"]) {
            snapshot.managedUserDefaults[PreferredEditorSettings.key] = .string(value)
        }
        if let value = jsonString(section["gitDiffJumpPreset"]) {
            snapshot.managedUserDefaults[GitDiffJumpEditorSettings.presetKey] = .string(value)
        }
        if let value = jsonString(section["gitDiffJumpCommand"]) {
            snapshot.managedUserDefaults[GitDiffJumpEditorSettings.commandKey] = .string(value)
        }
        if let value = jsonString(section["gitDiffJumpArguments"]) {
            snapshot.managedUserDefaults[GitDiffJumpEditorSettings.argumentsKey] = .string(value)
        }
```

- [ ] **Step 3: Add to the JSON snapshot defaults block**

In the same file near line 1227 (`"preferredEditor": ""`), add three siblings:

```swift
                    "preferredEditor": "",
                    "gitDiffJumpPreset": "",
                    "gitDiffJumpCommand": "",
                    "gitDiffJumpArguments": "",
                    "openMarkdownInCmuxViewer": CmdClickMarkdownRouteSettings.defaultValue,
```

- [ ] **Step 4: Update the JSON schema**

In `web/data/cmux-settings.schema.json`, locate the `preferredEditor` property block (~line 89) and append three sibling properties immediately after it:

```jsonc
        "preferredEditor": {
          "type": "string",
          "default": "",
          "description": "Custom editor command used by cmux where applicable. Leave empty to use the default."
        },
        "gitDiffJumpPreset": {
          "type": "string",
          "default": "",
          "description": "Display name of the active Git Diff Jump preset (e.g. \"Visual Studio Code\", \"Custom\"). Presentation-only; the actual command and arguments come from gitDiffJumpCommand and gitDiffJumpArguments."
        },
        "gitDiffJumpCommand": {
          "type": "string",
          "default": "",
          "description": "Command (executable name or absolute path) invoked when cmd+shift+clicking a git diff line in a terminal. Leave empty to disable Git Diff Jump."
        },
        "gitDiffJumpArguments": {
          "type": "string",
          "default": "",
          "description": "Argument template for Git Diff Jump. Supports placeholders %file (absolute path), %line (1-based line), %urlfile (percent-encoded path). cmux does not auto-quote — wrap %file in double quotes if needed."
        },
```

- [ ] **Step 5: Build to verify the symbol references compile**

```bash
xcodebuild -project GhosttyTabs.xcodeproj -scheme cmux -configuration Debug \
  -destination 'platform=macOS' -derivedDataPath /tmp/cmux-git-diff-jump build
```

Expected: `BUILD SUCCEEDED`.

- [ ] **Step 6: Commit**

```bash
git add Sources/KeyboardShortcutSettingsFileStore.swift web/data/cmux-settings.schema.json
git commit -m "feat(git-diff-jump): persist Preset/Command/Arguments via JSON store + schema"
```

---

## Task 10: Settings UI — Preset dropdown, Command, Arguments fields

**Files:**
- Modify: `Sources/cmuxApp.swift`
- Modify: `Resources/Localizable.xcstrings`
- Modify: `Sources/SettingsSearchAliases.swift`

- [ ] **Step 1: Add `@AppStorage` bindings**

In `Sources/cmuxApp.swift` near line 5198 (the existing `@AppStorage(PreferredEditorSettings.key)` line), add three siblings:

```swift
    @AppStorage(PreferredEditorSettings.key) private var preferredEditorCommand = ""
    @AppStorage(GitDiffJumpEditorSettings.presetKey) private var gitDiffJumpPreset = ""
    @AppStorage(GitDiffJumpEditorSettings.commandKey) private var gitDiffJumpCommand = ""
    @AppStorage(GitDiffJumpEditorSettings.argumentsKey) private var gitDiffJumpArguments = ""
```

- [ ] **Step 2: Add the new SettingsCardRow immediately after "Open Files With"**

In `Sources/cmuxApp.swift`, after the closing brace of the `SettingsCardRow` for `app.preferredEditor` (around line 5949) and before the next `SettingsCardDivider()`:

```swift
                        SettingsCardDivider()

                        SettingsCardRow(
                            configurationReview: .json("app.gitDiffJumpCommand"),
                            String(localized: "settings.app.gitDiffJump", defaultValue: "Git Diff Jump"),
                            subtitle: String(
                                localized: "settings.app.gitDiffJump.subtitle",
                                defaultValue: "Cmd+Shift+Click on a git diff / git show line in the terminal opens that file at that line in your editor. Leave empty to disable. Placeholders: %file, %line, %urlfile."
                            )
                        ) {
                            VStack(alignment: .leading, spacing: 6) {
                                Picker(
                                    String(localized: "settings.app.gitDiffJump.preset", defaultValue: "Preset"),
                                    selection: Binding(
                                        get: {
                                            gitDiffJumpPreset.isEmpty
                                                ? GitDiffJumpEditorSettings.customPresetName
                                                : gitDiffJumpPreset
                                        },
                                        set: { newValue in
                                            if newValue == GitDiffJumpEditorSettings.customPresetName {
                                                gitDiffJumpPreset = GitDiffJumpEditorSettings.customPresetName
                                            } else if let preset = GitDiffJumpEditorSettings.presets.first(where: { $0.name == newValue }) {
                                                gitDiffJumpPreset = preset.name
                                                gitDiffJumpCommand = preset.command
                                                gitDiffJumpArguments = preset.arguments
                                            }
                                        }
                                    )
                                ) {
                                    ForEach(GitDiffJumpEditorSettings.presets, id: \.name) { preset in
                                        Text(preset.name).tag(preset.name)
                                    }
                                    Text(String(localized: "settings.app.gitDiffJump.preset.custom", defaultValue: "Custom"))
                                        .tag(GitDiffJumpEditorSettings.customPresetName)
                                }
                                .frame(width: 240)
                                TextField(
                                    String(localized: "settings.app.gitDiffJump.command.placeholder", defaultValue: "Command (e.g. open, code, mvim)"),
                                    text: Binding(
                                        get: { gitDiffJumpCommand },
                                        set: { newValue in
                                            gitDiffJumpCommand = newValue
                                            // Editing means we're in Custom now.
                                            if gitDiffJumpPreset != GitDiffJumpEditorSettings.customPresetName {
                                                gitDiffJumpPreset = GitDiffJumpEditorSettings.customPresetName
                                            }
                                        }
                                    )
                                )
                                .textFieldStyle(.roundedBorder)
                                .frame(width: 240)
                                .disabled(gitDiffJumpPreset != GitDiffJumpEditorSettings.customPresetName && !gitDiffJumpPreset.isEmpty)
                                TextField(
                                    String(localized: "settings.app.gitDiffJump.args.placeholder", defaultValue: "Arguments template, e.g. \"%file\":%line"),
                                    text: Binding(
                                        get: { gitDiffJumpArguments },
                                        set: { newValue in
                                            gitDiffJumpArguments = newValue
                                            if gitDiffJumpPreset != GitDiffJumpEditorSettings.customPresetName {
                                                gitDiffJumpPreset = GitDiffJumpEditorSettings.customPresetName
                                            }
                                        }
                                    )
                                )
                                .textFieldStyle(.roundedBorder)
                                .frame(width: 240)
                                .disabled(gitDiffJumpPreset != GitDiffJumpEditorSettings.customPresetName && !gitDiffJumpPreset.isEmpty)
                            }
                        }
```

- [ ] **Step 3: Reset defaults**

In `Sources/cmuxApp.swift` near line 7393 (the `preferredEditorCommand = ""` line in the reset block), add three siblings:

```swift
        preferredEditorCommand = ""
        gitDiffJumpPreset = ""
        gitDiffJumpCommand = ""
        gitDiffJumpArguments = ""
```

- [ ] **Step 4: Add 9 localized strings to `Resources/Localizable.xcstrings`**

For each key, add an entry with `extractionState: manual`, English source string, and a Japanese translation. The keys:

| Key | English | Japanese |
|---|---|---|
| `settings.app.gitDiffJump` | `Git Diff Jump` | `Git Diff ジャンプ` |
| `settings.app.gitDiffJump.subtitle` | `Cmd+Shift+Click on a git diff / git show line in the terminal opens that file at that line in your editor. Leave empty to disable. Placeholders: %file, %line, %urlfile.` | `ターミナルの git diff / git show 行を Cmd+Shift+クリックすると、そのファイルの該当行をエディタで開きます。空欄で無効化。プレースホルダ: %file, %line, %urlfile。` |
| `settings.app.gitDiffJump.preset` | `Preset` | `プリセット` |
| `settings.app.gitDiffJump.preset.custom` | `Custom` | `カスタム` |
| `settings.app.gitDiffJump.command.placeholder` | `Command (e.g. open, code, mvim)` | `コマンド (例: open, code, mvim)` |
| `settings.app.gitDiffJump.args.placeholder` | `Arguments template, e.g. "%file":%line` | `引数テンプレート (例: "%file":%line)` |
| `settings.app.gitDiffJump.notConfigured.title` | `Git Diff Jump is not configured` | `Git Diff ジャンプが設定されていません` |
| `settings.app.gitDiffJump.notConfigured.body` | `Pick a preset (or fill in a custom command) under Settings → App → Git Diff Jump to enable cmd+shift+click jumps from diffs.` | `設定 → App → Git Diff ジャンプ でプリセット（またはカスタムコマンド）を選んでください。` |
| `settings.app.gitDiffJump.launchFailed.title` | `Editor command failed to launch` | `エディタコマンドの起動に失敗しました` |
| `settings.app.gitDiffJump.exitNonZero.title` | `Editor command exited with error` | `エディタコマンドがエラー終了しました` |
| `settings.app.gitDiffJump.openSettings` | `Open Settings…` | `設定を開く…` |
| `alert.cancel` | `Cancel` | `キャンセル` _(may already exist; reuse if so)_ |

Open `Resources/Localizable.xcstrings` and follow the exact JSON structure of an existing entry such as `"settings.app.preferredEditor"` for each new key. Confirm with:

```bash
python3 -c "import json,sys; d=json.load(open('Resources/Localizable.xcstrings')); missing=[k for k in ['settings.app.gitDiffJump','settings.app.gitDiffJump.subtitle','settings.app.gitDiffJump.preset','settings.app.gitDiffJump.preset.custom','settings.app.gitDiffJump.command.placeholder','settings.app.gitDiffJump.args.placeholder','settings.app.gitDiffJump.notConfigured.title','settings.app.gitDiffJump.notConfigured.body','settings.app.gitDiffJump.launchFailed.title','settings.app.gitDiffJump.exitNonZero.title','settings.app.gitDiffJump.openSettings'] if k not in d['strings']]; print('missing:', missing)"
```

Expected: `missing: []`.

- [ ] **Step 5: Add Settings search aliases**

In `Sources/SettingsSearchAliases.swift`, add aliases that surface the new card under search terms like `git`, `diff`, `jump`, `cmd+shift`. Mirror the existing pattern (search for the row that aliases `preferredEditor`).

```swift
// Near other app-section aliases:
("settings.app.gitDiffJump", ["git", "diff", "jump", "cmd shift click", "cmd+shift", "shift cmd click", "diff editor"]),
```

- [ ] **Step 6: Build to verify**

```bash
xcodebuild -project GhosttyTabs.xcodeproj -scheme cmux -configuration Debug \
  -destination 'platform=macOS' -derivedDataPath /tmp/cmux-git-diff-jump build
```

Expected: `BUILD SUCCEEDED`.

- [ ] **Step 7: Commit**

```bash
git add Sources/cmuxApp.swift Resources/Localizable.xcstrings Sources/SettingsSearchAliases.swift
git commit -m "feat(git-diff-jump): Settings UI with preset dropdown + command/args fields"
```

---

## Task 11: Terminal integration — recognize cmd+shift+click in diff context

**Files:**
- Modify: `Sources/GhosttyTerminalView.swift`

- [ ] **Step 1: Extend `mouseUp` to dispatch on shift modifier**

In `Sources/GhosttyTerminalView.swift` near line 8034 (`mouseUp` of the surface view):

```swift
override func mouseUp(with event: NSEvent) {
    #if DEBUG
    cmuxDebugLog("terminal.mouseUp surface=\(terminalSurface?.id.uuidString.prefix(5) ?? "nil") mods=[\(debugModifierString(event.modifierFlags))]")
    #endif
    guard let surface = surface else { return }
    let point = convert(event.locationInWindow, from: nil)
    let consumed = ghostty_surface_mouse_button(surface, GHOSTTY_MOUSE_RELEASE, GHOSTTY_MOUSE_LEFT, modsFromEvent(event))

    let flags = event.modifierFlags
    if flags.contains(.command) && flags.contains(.shift) {
        _ = handleDiffJumpClickRelease(at: point)
        return
    }
    _ = handleCommandClickRelease(at: point, modifierFlags: flags, ghosttyConsumed: consumed)
}
```

- [ ] **Step 2: Add the new handler method**

Add inside the same surface-view class (place it near `handleCommandClickRelease`):

```swift
@MainActor
@discardableResult
private func handleDiffJumpClickRelease(at point: NSPoint) -> Bool {
    guard let termSurface = terminalSurface,
          let workspace = termSurface.owningWorkspace(),
          !workspace.isRemoteTerminalSurface(termSurface.id),
          let panel = workspace.terminalPanel(for: termSurface.id),
          let surface else {
        return false
    }
    guard let cwd = resolvedWordPathWorkingDirectory(workspace: workspace, terminalSurface: termSurface) else {
        return false
    }

    // 1) Map click point → row index in a flattened (scrollback + viewport) buffer.
    let size = ghostty_surface_size(surface)
    let rows = max(Int(size.rows), 1)
    let resolvedCellHeight = cellSize.height > 0 ? cellSize.height : CGFloat(size.cell_height_px)
    guard resolvedCellHeight > 0 else { return false }

    let scrollbackLimit = max(
        rows + 1,
        UserDefaults.standard.object(forKey: GitDiffJumpEditorSettings.scrollbackLimitKey) as? Int
            ?? GitDiffJumpEditorSettings.defaultScrollbackLimit
    )
    let visibleText = TerminalController.shared.readTerminalTextForSnapshot(
        terminalPanel: panel,
        includeScrollback: true,
        lineLimit: scrollbackLimit + rows
    ) ?? ""
    let allLines = visibleText.split(separator: "\n", omittingEmptySubsequences: false).map(String.init)

    let yInset = max(0, (bounds.height - (CGFloat(rows) * resolvedCellHeight)) / 2)
    let yFromTop = bounds.height - point.y
    let visibleRowFromTop = max(0, min(rows - 1, Int((yFromTop - yInset) / resolvedCellHeight)))
    // The "visible" portion is the last `rows` lines of `allLines` (when
    // includeScrollback=true). Map visibleRow → absolute row.
    let visibleStart = max(0, allLines.count - rows)
    let absoluteRow = visibleStart + visibleRowFromTop
    guard absoluteRow >= 0, absoluteRow < allLines.count else { return false }

    // 2) Parse.
    guard let target = GitDiffJumpParser.resolve(
        lines: allLines,
        clickRow: absoluteRow,
        maxScanRows: scrollbackLimit
    ) else {
        #if DEBUG
        cmuxDebugLog("git-diff-jump.miss row=\(absoluteRow) totalRows=\(allLines.count)")
        #endif
        return false
    }

    // 3) Resolve to absolute path.
    guard case let .fileLine(relativePath, line) = target,
          let absolutePath = GitDiffJumpEditorSettings.resolveAbsolutePath(
              relativePath: relativePath, cwd: cwd
          ) else {
        #if DEBUG
        cmuxDebugLog("git-diff-jump.unresolved relpath=\(target) cwd=\(cwd)")
        #endif
        return false
    }

    // 4) Open (or alert).
    GitDiffJumpEditorSettings.openOrAlert(path: absolutePath, line: line)
    return true
}

#if DEBUG
@discardableResult
func debugSimulateDiffJumpClick(at point: NSPoint) -> Bool {
    handleDiffJumpClickRelease(at: clampedDebugPoint(point))
}
#endif
```

- [ ] **Step 3: Mirror the simulate function on the outer wrapper**

Find the existing `debugSimulateCommandClick` in `GhosttySurfaceScrollView` (or wherever it's exposed near line 9587) and add a sibling:

```swift
#if DEBUG
@discardableResult
func debugSimulateDiffJumpClick(at point: NSPoint) -> Bool {
    surfaceView.debugSimulateDiffJumpClick(at: debugPointInSurface(point))
}
#endif
```

- [ ] **Step 4: Build to verify**

```bash
xcodebuild -project GhosttyTabs.xcodeproj -scheme cmux -configuration Debug \
  -destination 'platform=macOS' -derivedDataPath /tmp/cmux-git-diff-jump build
```

Expected: `BUILD SUCCEEDED`.

- [ ] **Step 5: Run the parser and substitution test suites again to confirm we didn't regress them**

```bash
xcodebuild -scheme cmux-unit -configuration Debug -destination 'platform=macOS' \
  -derivedDataPath /tmp/cmux-git-diff-jump-tests \
  -only-testing:cmuxTests/GitDiffParserTests \
  -only-testing:cmuxTests/GitDiffJumpEditorSettingsSubstitutionTests \
  -only-testing:cmuxTests/GitDiffJumpEditorSettingsResolveTests \
  -only-testing:cmuxTests/GitDiffJumpEditorSettingsOpenTests test
```

Expected: all green.

- [ ] **Step 6: Commit**

```bash
git add Sources/GhosttyTerminalView.swift
git commit -m "feat(git-diff-jump): cmd+shift+click in terminal triggers diff jump"
```

---

## Task 12: User docs

**Files:**
- Create: `docs/git-diff-jump.md`

- [ ] **Step 1: Write the doc**

Create `docs/git-diff-jump.md`:

```markdown
# Git Diff Jump

Cmd+Shift+Click on a `git diff` or `git show` line in a cmux terminal opens
that file at that exact line in your editor. The gesture is fixed (matches
Skim's PDF→source convention).

## Setup

`Settings → App → Git Diff Jump`:

1. Pick your editor from the **Preset** dropdown.
2. The **Command** and **Arguments** fields auto-fill and become read-only.
3. To use an editor not in the list, choose **Custom** and fill both fields.

## Placeholders (Custom mode)

| Token | Substitution |
|---|---|
| `%file` | Absolute file path (no auto-quoting — wrap in `"..."` yourself) |
| `%line` | 1-based line number |
| `%urlfile` | `%file` percent-encoded for use inside URLs |

## What can I click?

Inside a recognized diff (anything between `diff --git a/X b/Y` and the next
such header):

- `+` added lines → that exact line in the new file
- ` ` context lines → that exact line in the new file
- `-` removed lines → the next surviving line in the new file
- `diff --git`, `+++ b/X`, `index ...`, `new file mode`, `rename to`, etc. → line 1

Clicks elsewhere (regular shell output, command lines) are no-ops. cmux scans
up to 5 000 rows above the click looking for a `diff --git` header; tune via
`defaults write com.cmuxterm.app gitDiffJumpScrollbackLimit -int <N>`.

## Known caveats

- **Xcode (`xed`)**: when Xcode is already running, `xed --line N` may not
  jump to the line. This is a long-standing Xcode bug
  ([Stack Overflow](https://stackoverflow.com/questions/63573436)), not a
  cmux issue. Workaround: close the file in Xcode first.
- **`git show <past-commit>`**: cmux opens the working-tree file with the
  line number computed from the diff's "new" side. If the working-tree file
  has diverged significantly from the commit being viewed, the line may be
  off by a few. For exact historical inspection, fall back to manual
  navigation in your editor.
- **`delta` / `diff-so-fancy` / other diff renderers**: only standard `git`
  text output is recognized in v1.
- **Submodule diffs**: not supported.
- **Renamed files**: jump targets the new (`b/`) path; the pre-rename file
  is not opened.

## Comparison with Cmd-Click

| Gesture | What it does | Setting |
|---|---|---|
| Cmd+Click on a path | Open file via system default or `preferredEditorCommand` | "Open Files With" |
| Cmd+Shift+Click on a diff line | Open that file at that line via `gitDiffJumpCommand` | "Git Diff Jump" |

The two settings are independent. You can configure one without the other.
```

- [ ] **Step 2: Commit**

```bash
git add docs/git-diff-jump.md
git commit -m "docs: git diff jump user reference"
```

---

## Task 13: Smoke build the dev app + manual verification checklist

**Files:** none modified; this task is verification.

- [ ] **Step 1: Build the dev app under a tagged derived data path**

```bash
./scripts/reload.sh --tag git-diff-jump
```

Capture the `App path:` line from output. Format the cmd-clickable URL per the CLAUDE.md template (Codex format if running as Codex; Claude Code format if running as Claude Code).

- [ ] **Step 2: Manual smoke-test checklist** _(record results in the commit message of any follow-up fix)_

Hand off this list to the user; they'll cmd-click the App path link to launch.

In the launched dev app:

- [ ] Open `Settings → App → Git Diff Jump`. Pick "Visual Studio Code" from the preset dropdown. Verify Command becomes `open`, Arguments becomes `vscode://file"%urlfile":%line`, both fields are read-only.
- [ ] Switch to "Custom". Verify both fields become editable. Switch back to "Visual Studio Code". Verify they refill.
- [ ] In a terminal: `cd ~/Develop/Projects/cmux && git diff HEAD~1`. Cmd+Shift+Click on a `+` line in any hunk. Verify VS Code (or your configured editor) opens the file at that line.
- [ ] Cmd+Shift+Click on a `-` line. Verify it opens at the "next surviving" line.
- [ ] Cmd+Shift+Click on the `diff --git` header. Verify it opens the file at line 1.
- [ ] Cmd+Shift+Click on regular shell output (e.g. on the `$ git diff` prompt line). Verify nothing happens.
- [ ] In Settings, clear the Command field. Cmd+Shift+Click on a diff line. Verify the "Git Diff Jump is not configured" alert appears with an "Open Settings…" button.
- [ ] Set Command to `/usr/bin/false` (which always exits 1). Cmd+Shift+Click on a diff line. Verify the "Editor command exited with error" alert appears within ~1 sec.
- [ ] Verify Cmd+Click (no shift) still opens files normally and `Settings → App → Open Files With` is unchanged.

If any item fails, treat as a bug and add a regression test before fixing.

- [ ] **Step 3: If everything works, no commit needed for this task.** If any fix was made, commit it with `fix(git-diff-jump): <description>`.

---

## Self-Review

**1. Spec coverage**

| Spec section | Covered by task |
|---|---|
| Goals 1 (cmd+shift+click jump) | Task 11 (handler) + Task 8 (open) |
| Goals 2 (additive, no `preferredEditorCommand` change) | Task 9 (separate keys) + Task 11 (separate code path) |
| Goals 3 (Skim-style preset+command+args UI) | Task 10 |
| Non-goals (forward jump, delta, submodules, renames pre-rename, wrap) | Documented in Task 12 |
| Detection rules (file metadata vs hunk body) | Tasks 2, 3, 4 |
| Hunk math for +/-/space | Task 2 |
| Path resolution (CWD then walk-up to .git) | Task 7 |
| Storage (3 UserDefaults keys, JSON, schema) | Task 9 |
| First-use alert | Task 8 (`OpenOutcome.notConfigured` + alert) |
| Preset table (11 entries) | Task 6 |
| Placeholders (%file, %line, %urlfile, no %column) | Task 6 |
| Modifier fixed cmd+shift+click | Task 11 (mouseUp dispatch) |
| Scan distance 5 000 lines, hidden default | Task 11 (`scrollbackLimitKey`) |
| Error handling — never falls back to NSWorkspace | Task 8 |
| Threading — main-thread parse, background process wait | Task 8 + Task 11 |
| Tests — parser, substitution, path resolution | Tasks 2-7 |
| Localization (English + Japanese) | Task 10 Step 4 |
| Settings search findability | Task 10 Step 5 |
| Documentation | Task 12 |

**2. Placeholder scan**: Searched the plan for "TBD", "TODO", "implement later", "Add appropriate error handling", "Similar to Task N". None present.

**3. Type consistency**: `GitDiffJumpTarget`, `GitDiffJumpParser`, `GitDiffJumpEditorSettings`, `GitDiffJumpEditorPreset`, `ResolvedInvocation`, `OpenOutcome`, keys `presetKey`/`commandKey`/`argumentsKey`/`scrollbackLimitKey` — all referenced consistently across tasks. Method names `resolve(lines:clickRow:maxScanRows:)`, `substitute(arguments:file:line:)`, `resolveAbsolutePath(relativePath:cwd:)`, `resolved(defaults:)`, `openOrAlert(path:line:defaults:presentAlert:)`, `handleDiffJumpClickRelease(at:)` — consistent.

---

## Execution Handoff

**Plan complete and saved to `docs/superpowers/plans/2026-04-30-git-diff-jump-to-editor.md`. Two execution options:**

**1. Subagent-Driven (recommended)** - I dispatch a fresh subagent per task, review between tasks, fast iteration

**2. Inline Execution** - Execute tasks in this session using executing-plans, batch execution with checkpoints

**Which approach?**
