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
        presentAlert: @escaping (String, String) -> Void = { title, message in
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
                NSApp.sendAction(Selector(("showSettingsWindow:")), to: nil, from: nil)
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
