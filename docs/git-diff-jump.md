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
