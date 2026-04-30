# Git Diff Jump to Editor

> Spec for cmd+shift+click on a `git diff` / `git show` line in the cmux
> terminal, jumping to the corresponding file and line in the user's editor —
> in the spirit of Skim's shift+cmd+click PDF→source navigation.

- **Status**: Draft, awaiting user review
- **Owner**: cmux app
- **Audience**: cmux maintainers
- **Date**: 2026-04-30

## Goals

1. When the user has `git diff` or `git show` output visible in a cmux
   terminal, holding cmd+shift and clicking on a hunk line opens that exact
   line in the user's chosen editor.
2. The feature is **additive**: existing cmd+click behavior and the existing
   `preferredEditorCommand` setting are not changed.
3. Configuration follows Skim's well-known PDF-Sync UI: a Preset dropdown
   that auto-fills Command and Arguments fields, plus a Custom mode that
   unlocks both fields for arbitrary editors.

## Non-goals

- Forward-jump (editor → diff) is out of scope.
- Side-by-side diff renderers (`delta`, `diff-so-fancy`, `diff-highlight`) are
  out of scope for v1; only standard `git` text output is recognized. A
  follow-up may add `delta` support if there is demand.
- Submodule diffs (`Submodule path/sub abc..def:`) are out of scope.
- Renamed files: the `b/` (post-rename) path is the jump target. Rename
  bookkeeping beyond that (e.g. opening the pre-rename file) is out of scope.
- Word-wrapped diff headers (paths longer than the terminal width) are not
  guaranteed to parse. Practically rare and not worth the complexity in v1.

## User flow

1. User runs `git diff`, `git show <commit>`, `git log -p`, or any other
   command whose output uses standard unified-diff format.
2. User holds cmd+shift and clicks on:
   - a `+` added line, or a ` ` context line, or a `-` removed line, **inside
     a hunk**, or
   - a `diff --git a/X b/Y` header, `+++ b/Y` header, or other diff metadata
     line **for** that file.
3. cmux:
   - Identifies the click target as a diff line and resolves
     `(absolute_file_path, line_number)`.
   - Substitutes `%file` / `%line` / `%urlfile` into the user's configured
     argument template.
   - Shells out via `/bin/sh -c "<command> <args>"`.
4. Editor opens (or activates) the file at the requested line.
5. If anything fails — config not set, diff parse failed, file not found,
   editor command exited non-zero — cmux shows a non-blocking banner with the
   reason. **No silent fallback.**

The modifier `cmd+shift+click` is fixed (not user-configurable), matching
Skim's identical convention and matching cmux's existing precedent of
hardcoding cmd+click for the "open path" gesture.

## Detection rules (which clicks count)

A click at terminal row `R`, column `C` is a "diff jump" iff, scanning the
visible viewport plus scrollback (cap: 5 000 lines above the click), we can
determine all of:

1. The nearest `diff --git a/<old> b/<new>` line **above or at** `R` exists,
   and there is no other `diff --git` line between it and `R`. The new path
   is `<new>`.
2. EITHER:
   - `R` itself is one of: `diff --git ...`, `index ...`, `--- a/...`,
     `+++ b/...`, `new file mode ...`, `deleted file mode ...`,
     `rename from ...`, `rename to ...`, `similarity index ...`. → Jump to
     line **1** of `<new>`.
   - OR the nearest `@@ -<oldStart>,<oldLen> +<newStart>,<newLen> @@` line
     above `R` exists, and `R` is one of `+` / `-` / ` ` (space) hunk lines
     beneath that header but before the next `@@` or `diff --git`. → Compute
     line per the next section.

Anything that does not satisfy the above is **not** a diff jump and the click
is a no-op. cmux does not fall back to cmd+click semantics; the user already
has cmd+click for that.

### Mapping a hunk-body click to a new-file line

Given hunk header `@@ -O,o +N,n @@` and the rows under it (in order):

```
new_line = N
walk rows top-down from the row right after the @@ header to the click row R:
  if row starts with '+': record candidate=new_line; new_line += 1
  if row starts with ' ': record candidate=new_line; new_line += 1
  if row starts with '-': record candidate=new_line  # do NOT increment
result = candidate
```

Effect:

- Click on `+` line ⇒ that exact added line in the new file.
- Click on ` ` context line ⇒ that exact context line in the new file.
- Click on `-` removed line ⇒ the new-file line where the deletion happened
  (i.e. the next surviving line in the new file). This was the user-chosen
  behavior over alternatives (no-op, jump-to-old-version, jump-with-old-line).

If `R` precedes any `+`/` `/`-` row inside the hunk (e.g. clicked on the `@@`
header itself), result = `N` (start of the hunk in the new file).

### Resolving the path

The diff path `b/<new>` is repository-relative. Resolution order:

1. `<terminal_panel_cwd>/<new>` — if exists, use it.
2. Walk up from `<terminal_panel_cwd>` looking for a `.git` directory or
   file. The first ancestor that contains `.git` is treated as the repo
   root; try `<repo_root>/<new>`. If exists, use it.
3. Otherwise: banner error "Cannot resolve `<new>` against current
   working directory".

The walk-up is bounded by filesystem root and runs synchronously off the
main thread (it's a small number of `stat` calls). For remote workspaces
(`workspace.isRemoteTerminalSurface(...)`), the feature is disabled and the
click is a no-op — the same gating cmd+click already uses.

For the v1 scope of `git diff` / `git show` against the **working tree**,
this resolution is exact. For `git show <past-commit>` whose working-tree
file has since diverged, the line is computed on the diff's "new" side; the
opened working-tree file may not perfectly correspond to that line. This is
a known limitation; documented in the help text. (Materializing
`git show <commit>:<path>` to a temp file was rejected for complexity;
`-` line behavior already captures the same trade-off.)

## Settings

A new card in `Settings → App`, immediately below "Open Files With".

```
┌─ Git Diff Jump ─────────────────────────────────────────────────────────┐
│ Cmd+Shift+Click on a git diff line jumps to that line in your editor.  │
│                                                                         │
│ Preset:    [ Visual Studio Code  ▾ ]                                    │
│ Command:   [ open                                                  ]    │
│ Arguments: [ vscode://file"%urlfile":%line                          ]   │
│                                                                         │
│ Placeholders: %file, %line, %urlfile                                    │
└─────────────────────────────────────────────────────────────────────────┘
```

When `Preset ≠ Custom`, the Command and Arguments fields are filled from the
preset and **disabled** (read-only). When `Preset = Custom`, both fields are
editable.

### Preset list

Sourced from Skim's `InitialUserDefaults.plist > TeXEditors`, with dead
editors removed (TextWrangler, Atom, Aquamacs, AlphaCocoa, etc.) and modern
editors added (Cursor, Zed, JetBrains, Xcode):

| Preset                | Command       | Arguments                              |
| --------------------- | ------------- | -------------------------------------- |
| Visual Studio Code    | `open`        | `vscode://file"%urlfile":%line`        |
| Cursor                | `open`        | `cursor://file"%urlfile":%line`        |
| Zed                   | `zed`         | `"%file":%line`                        |
| Sublime Text          | `subl`        | `"%file":%line`                        |
| MacVim                | `mvim`        | `--remote-silent +"%line" "%file"`     |
| Emacs (emacsclient)   | `emacsclient` | `--no-wait +%line "%file"`             |
| JetBrains IDE         | `idea`        | `--line %line "%file"`                 |
| Xcode                 | `xed`         | `--line %line "%file"`                 |
| TextMate              | `mate`        | `-l %line "%file"`                     |
| BBEdit                | `bbedit`      | `+%line "%file"`                       |
| Nova                  | `nova`        | `open "%file" -l %line`                |
| Custom                | _user_        | _user_                                 |

URL-scheme entries (VS Code, Cursor) match Skim's choice for VS Code and
inherit Skim's reliability rationale: not dependent on a CLI shim being on
PATH, works across editor versions. Cursor uses the same `<scheme>://file...`
shape, confirmed at <https://github.com/openai/codex/issues/11190> and the
Cursor docs.

Xcode preset has a documented quirk in its subtitle: when Xcode is already
running, `xed --line N file` may not jump (Xcode bug, see
<https://stackoverflow.com/questions/63573436>). Listed as a known
limitation, not a cmux defect.

### Placeholders

| Placeholder | Substitution                                                     |
| ----------- | ---------------------------------------------------------------- |
| `%file`     | Absolute file path (literal, no auto-quoting — user adds quotes) |
| `%line`     | 1-based line number, decimal integer                             |
| `%urlfile`  | `%file` percent-encoded for use inside a `file://` / IDE URL     |

`%column` is intentionally not supported (YAGNI; we never know the column
from a diff click).

Substitution is **literal text replacement** in the Arguments string. cmux
does not introduce escaping beyond what the user wrote. Skim users will find
this familiar.

### Storage

```jsonc
// ~/.config/cmux/settings.json
{
  "app": {
    "gitDiffJumpPreset": "Visual Studio Code",   // or "Custom" or ""
    "gitDiffJumpCommand": "open",
    "gitDiffJumpArguments": "vscode://file\"%urlfile\":%line"
  }
}
```

UserDefaults keys mirror the JSON keys. Defaults: all three empty strings
(treated as "not configured"). Schema is added to
`web/data/cmux-settings.schema.json` and loaded/saved by
`KeyboardShortcutSettingsFileStore.swift` next to the existing
`app.preferredEditor` plumbing.

**"Configured" detection**: a single rule —
`gitDiffJumpCommand.trimmingWhitespace().isEmpty == false`. The Preset
field is presentation-only; it doesn't gate behavior. (This matters for
the migration story: a user who hand-edits only `gitDiffJumpCommand` and
`gitDiffJumpArguments` in `settings.json` without setting Preset still
gets the feature, with the UI showing "Custom".)

**Preset → field interactions** (in the Settings UI):

- Selecting a non-Custom preset: writes the preset's command and
  arguments to the two fields, persists all three keys. Both fields are
  visually disabled (read-only).
- Selecting Custom: leaves the current command/arguments values in
  place (so users can start from a preset and tweak). Both fields become
  editable.
- Editing either field while a non-Custom preset is selected (e.g. the
  user switches to Custom): UI snaps Preset to Custom automatically and
  the edit is committed. (Standard "leaving a preset means going Custom"
  pattern, matches Skim.)
- Hidden-default `gitDiffJumpScrollbackLimit` (Int, default 5000): UI
  does not surface this; advanced users tune it via `defaults write`.

### First-use banner

If a user cmd+shift+clicks a recognized diff line and `gitDiffJumpCommand`
is empty:

> "Configure 'Git Diff Jump' in Settings → App to open this line in your
> editor."  [Open Settings]

Banner uses the existing `TerminalNotificationStore` toast mechanism so it
matches the rest of the app. Shown at most once per app session.

## Implementation outline

Files touched:

- **`Sources/GitDiffParser.swift`** _(new, leaf module, no imports of app
  state)_. Sits next to existing domain-logic siblings like `PortScanner.swift`
  and `KeyboardLayout.swift`. Pure functions over a `[String]` slice plus a
  click row. Public API:

  ```swift
  enum GitDiffJumpTarget: Equatable {
      case fileLine(relativePath: String, line: Int)
  }

  enum GitDiffJumpParser {
      /// Resolve a click in a flattened terminal buffer to a (file, line)
      /// jump target. Returns nil when the click is not inside a recognized
      /// diff context, when the click is above any `diff --git` header
      /// within `maxScanRows`, or when the diff metadata is malformed.
      ///
      /// `lines` is the ANSI-stripped scrollback + viewport, top-down.
      /// `clickRow` is a 0-based index into `lines`. The parser only ever
      /// scans rows in `[max(0, clickRow - maxScanRows), clickRow]`.
      static func resolve(
          lines: [String],
          clickRow: Int,
          maxScanRows: Int = 5_000
      ) -> GitDiffJumpTarget?
  }
  ```

  Stateless, fast, exhaustively unit-testable.

- **`Sources/cmuxApp.swift`** — add `GitDiffJumpEditorSettings` enum
  alongside `PreferredEditorSettings`. Methods:

  ```swift
  enum GitDiffJumpEditorSettings {
      static let presetKey = "gitDiffJumpPreset"
      static let commandKey = "gitDiffJumpCommand"
      static let argumentsKey = "gitDiffJumpArguments"

      static let presets: [GitDiffJumpEditorPreset] = [...]

      static func openOrNotify(
          path: String,
          line: Int,
          notify: (BannerDescriptor) -> Void
      )

      static func substitute(
          arguments: String,
          file: String,
          line: Int
      ) -> String   // pure, unit-testable
  }
  ```

  `openOrNotify` runs the configured shell command, captures stderr, and
  posts a banner on non-zero exit instead of falling back to
  `NSWorkspace.shared.open`.

- **`Sources/GhosttyTerminalView.swift`** — extend `mouseUp` /
  `handleCommandClickRelease` to recognize cmd+shift modifier; on hit, call
  a new sibling `handleDiffJumpClickRelease` that:
  1. Reads `TerminalController.shared.readTerminalTextForSnapshot(panel,
     includeScrollback: true, lineLimit: max(viewport_rows + 5_000, ...))`.
  2. Splits into `[String]`, ANSI-stripped (helper already exists).
  3. Computes the click row index in this array (uses existing cell-to-row
     math, mirrors `resolveVisibleWordPath`).
  4. Calls `GitDiffJumpParser.resolve(...)`.
  5. Resolves the relative path against panel CWD with the walk-up rule.
  6. Calls `GitDiffJumpEditorSettings.openOrNotify(...)`.

- **`Sources/Settings/...` & `Sources/cmuxApp.swift`** — add the new
  `SettingsCardRow` for "Git Diff Jump" with Preset / Command / Arguments
  fields. Reuse `@AppStorage` and the same shape as the existing "Open
  Files With" row.

- **`web/data/cmux-settings.schema.json`** — add three string properties
  under `app`. Update the schema's `preferredEditor` neighbor to keep
  ordering coherent.

- **`Sources/KeyboardShortcutSettingsFileStore.swift`** — load/save the
  three new keys; add to the managed-keys list and the defaults snapshot.

- **`Resources/Localizable.xcstrings`** — three new keys for the card
  title/subtitle/placeholder, plus three banner strings (config-not-set,
  parse-failed, command-failed). All with English defaults and Japanese
  translations per the existing Localizable convention.

- **`Sources/SettingsSearchAliases.swift`** & **`SettingsNavigation.swift`**
  — register the new setting so it's findable via Settings search.

## Threading & performance

- ANSI strip + diff parse runs **on the main thread** (the click handler is
  already on main), but is bounded to ≤ 5 000 lines and is O(n) with cheap
  string operations. Worst case is small enough to not need off-loading.
- The resulting shell command is launched with `Process()` exactly like
  `PreferredEditorSettings.open`, with stdout/stderr piped; exit-status
  check runs on a background `DispatchQueue.global(qos: .userInitiated)`,
  same pattern. Banner posting is dispatched back to main.
- Repo-root walk-up is a small number of `stat` calls; runs on background
  thread. The eventual `process.run()` does not block main.

## Error handling

| Condition                                  | Behavior                                                   |
| ------------------------------------------ | ---------------------------------------------------------- |
| Click is not in a recognized diff context  | No-op. No banner. (Avoids noise on accidental modifier holds.) |
| `gitDiffJumpCommand` is empty              | Banner: "Configure 'Git Diff Jump' in Settings…" + Open Settings button |
| Path cannot be resolved against CWD        | Banner: "Cannot find `<relpath>` from terminal CWD"        |
| Editor command exits non-zero              | Banner: "Editor command failed: `<command>` exited <N>. See debug log." + first 1 KB of stderr in cmuxDebugLog |
| Editor command not found (`exec` failure)  | Same banner shape. The 127 / not-found case is detected from `terminationStatus` like the existing code already does |
| Remote workspace                           | No-op. (Same gating as cmd+click.) |

No path falls back to `NSWorkspace.shared.open` — that would silently open
the file at line 1 in whatever default app the user has, which defeats the
purpose of "jump to specific line in my editor".

## Testing

A regression-grade test set, all hermetic, no editor launch:

1. **`GitDiffParserTests`** — unit tests over `GitDiffJumpParser.resolve`:
   - `git diff` on a single file: hunk with `+`/`-`/` ` mix; click each
     row and assert `(path, line)`.
   - `git show abc123` output: commit metadata above first `diff --git`,
     two file diffs in one show.
   - Multiple hunks per file: click in 2nd hunk, ensure the right
     `@@` header is selected (not the first one).
   - Multiple files in one diff: click on file B's hunk after file A's
     hunk; assert `b/` of the right header is used.
   - Click on diff metadata rows (`diff --git`, `+++ b/X`, `index ...`,
     `new file mode`, `rename to`) → line 1 of the right file.
   - Click on `-` line at the very start of a hunk (no preceding `+`/` `)
     → line `N` (hunk's `+N` start).
   - Click row outside any diff context → `nil`.
   - Scanning above the click finds no `diff --git` within
     `maxScanRows=5_000` → `nil`.
   - Renamed file: `diff --git a/old b/new` + `rename from old` +
     `rename to new` + hunk → uses `b/new`.

2. **`GitDiffJumpSubstitutionTests`** — for each of the 11 presets in the
   table, assert the substituted command string for `(file, line) =
   ("/repo/src/x.go", 100)`. Locks in the preset table and the substitution
   semantics.

3. **`GitDiffJumpPathResolutionTests`** — temp directories with `.git`
   markers; assert the walk-up resolves to the right absolute path; assert
   non-existent files return nil.

4. **One end-to-end test in `cmuxTests`** that mounts a fake `TerminalPanel`
   buffer containing `git diff` output and simulates a cmd+shift+click via
   the existing `debugSimulateCommandClick` test seam (extended to take a
   `modifierFlags` parameter), asserting the resulting `(path, line)` is
   surfaced through a UI-test capture env var (analogous to
   `CMUX_UI_TEST_CAPTURE_OPEN_PATH`). New env var:
   `CMUX_UI_TEST_CAPTURE_DIFF_JUMP_PATH` — single line per call,
   `<path>\t<line>\n`.

5. **No on-disk editor presence required.** All preset-substitution tests
   produce a command string only; no `Process()` is launched in tests.

Tests run via `xcodebuild -scheme cmux-unit` (the unit-test target), which
the agent notes already mark as safe to run, but we prefer CI per the
testing policy.

## Documentation

- **`docs/keyboard-shortcuts.md`** (or wherever shortcuts live; verify on
  implementation): one paragraph documenting cmd+shift+click and pointing
  to the Settings card.
- **`docs/cli-contract.md`** (if applicable; otherwise a new
  `docs/git-diff-jump.md`): document the placeholder grammar (`%file`,
  `%line`, `%urlfile`), the preset table, and the Xcode quirk.
- **`Sources/cmuxApp.swift`** — code comments where the placeholder
  substitution lives, with a one-line link to the spec doc.

## Open questions resolved (transcript reference)

1. Scope of cmd+shift+click → **Option C**: only acts inside recognized
   diff context (hunk body OR diff/file headers). No fallback.
2. Behavior on `-` lines → **Option A**: jump to "next surviving line in
   new file" (i.e. the new-file line where the deletion sits).
3. Editor configuration shape → Skim-style preset+command+args, **separate
   setting** (`gitDiffJumpCommand` / `gitDiffJumpArguments`) — not coupled
   to the existing `preferredEditorCommand`.
4. Failure handling → banner + log; **no fallback to NSWorkspace**.
5. Preset list → directly extracted from Skim's source
   (`InitialUserDefaults.plist > TeXEditors`), curated to drop dead editors
   and add modern ones (Cursor / Zed / JetBrains / Xcode).
6. Modifier configurability → **fixed cmd+shift+click**, mirroring Skim and
   matching cmux's existing precedent of hardcoding cmd+click.
7. Scrollback scan distance → **5 000 lines** above click, configurable via
   hidden default `gitDiffJumpScrollbackLimit` for power users.

## Out-of-scope follow-ups (deliberately deferred)

- `delta` / `diff-so-fancy` / `diff-highlight` output recognition.
- Submodule jumps.
- Forward jumps (editor → cmux/diff).
- Configurable mouse modifier.
- Per-workspace editor override.
- Materializing `git show <commit>:<path>` to a temp file for accurate
  historical jumps.
