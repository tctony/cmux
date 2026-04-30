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
