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
