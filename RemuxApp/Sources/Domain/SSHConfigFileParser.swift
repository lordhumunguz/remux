import Foundation

struct SSHConfigHost: Equatable, Sendable {
    let alias: String
    let hostName: String
    let user: String?
    let port: Int?
    let identityFile: String?
}

struct SSHConfigFile: Equatable, Sendable {
    let hosts: [SSHConfigHost]
}

/// Parses OpenSSH `ssh_config` text into concrete host entries.
///
/// Keywords are case-insensitive and accept both `Keyword value` and
/// `Keyword = value` forms. Values may be double-quoted. Lines whose first
/// non-whitespace character is `#` are comments. Following OpenSSH, the
/// first obtained value for each keyword wins: `Host *` (and other wildcard)
/// blocks never produce entries but supply defaults for concrete aliases
/// they match, including aliases declared earlier in the file. `Include`
/// directives are not resolved here; see `SSHConfigFileComposer`.
enum SSHConfigFileParser {
    static func parse(_ text: String, homeDirectoryPath: String) -> SSHConfigFile {
        let blocks = parseBlocks(text)
        var aliases: [String] = []
        var seenAliases = Set<String>()
        for block in blocks {
            guard let patterns = block.patterns else { continue }
            for pattern in patterns where isConcretePattern(pattern) {
                if seenAliases.insert(pattern.lowercased()).inserted {
                    aliases.append(pattern)
                }
            }
        }

        return SSHConfigFile(
            hosts: aliases.map { alias in
                makeHost(alias: alias, blocks: blocks, homeDirectoryPath: homeDirectoryPath)
            }
        )
    }

    private struct Block {
        /// `nil` for the global scope before the first `Host` line.
        let patterns: [String]?
        var values: [String: String]
    }

    private static func parseBlocks(_ text: String) -> [Block] {
        var blocks: [Block] = []
        var current = Block(patterns: nil, values: [:])
        var currentHasContent = false

        for rawLine in text.components(separatedBy: .newlines) {
            guard let directive = SSHConfigSyntax.parseDirective(from: rawLine) else { continue }
            switch directive.keyword {
            case "host":
                if currentHasContent {
                    blocks.append(current)
                }
                current = Block(
                    patterns: SSHConfigSyntax.tokenize(directive.argument),
                    values: [:]
                )
                currentHasContent = true
            case "match":
                // `Match` blocks are unsupported, but the line still closes
                // the current block; the negated-glob placeholder keeps the
                // Match body from leaking into the preceding `Host` block.
                if currentHasContent {
                    blocks.append(current)
                }
                current = Block(patterns: ["!*"], values: [:])
                currentHasContent = true
            case "include":
                continue
            default:
                if current.values[directive.keyword] == nil {
                    current.values[directive.keyword] = SSHConfigSyntax
                        .tokenize(directive.argument)
                        .first
                }
                currentHasContent = true
            }
        }
        if currentHasContent {
            blocks.append(current)
        }
        return blocks
    }

    private static func makeHost(
        alias: String,
        blocks: [Block],
        homeDirectoryPath: String
    ) -> SSHConfigHost {
        var hostName: String?
        var user: String?
        var port: Int?
        var identityFile: String?

        for block in blocks where matches(block: block, alias: alias) {
            if hostName == nil, let value = block.values["hostname"] {
                hostName = expandHostTokens(value, alias: alias)
            }
            if user == nil, let value = block.values["user"] {
                user = value
            }
            if port == nil, let value = block.values["port"], let parsed = Int(value),
               (1...65_535).contains(parsed) {
                port = parsed
            }
            if identityFile == nil, let value = block.values["identityfile"] {
                identityFile = SSHConfigSyntax.expandHome(
                    value,
                    homeDirectoryPath: homeDirectoryPath
                )
            }
        }

        return SSHConfigHost(
            alias: alias,
            hostName: hostName ?? alias,
            user: user,
            port: port,
            identityFile: identityFile
        )
    }

    private static func matches(block: Block, alias: String) -> Bool {
        guard let patterns = block.patterns else { return true }
        var matched = false
        for pattern in patterns {
            if pattern.hasPrefix("!") {
                if globMatches(String(pattern.dropFirst()), alias) { return false }
            } else if globMatches(pattern, alias) {
                matched = true
            }
        }
        return matched
    }

    private static func isConcretePattern(_ pattern: String) -> Bool {
        !pattern.hasPrefix("!") && !pattern.contains("*") && !pattern.contains("?")
    }

    static func globMatches(_ pattern: String, _ value: String) -> Bool {
        guard pattern.contains("*") || pattern.contains("?") else {
            return pattern.caseInsensitiveCompare(value) == .orderedSame
        }
        var regex = "^"
        for character in pattern {
            switch character {
            case "*":
                regex += ".*"
            case "?":
                regex += "."
            default:
                regex += NSRegularExpression.escapedPattern(for: String(character))
            }
        }
        regex += "$"
        return value.range(of: regex, options: [.regularExpression, .caseInsensitive]) != nil
    }

    private static func expandHostTokens(_ value: String, alias: String) -> String {
        var result = ""
        var index = value.startIndex
        while index < value.endIndex {
            let character = value[index]
            let next = value.index(after: index)
            if character == "%" {
                if next < value.endIndex {
                    switch value[next] {
                    case "h":
                        result += alias
                    case "%":
                        result += "%"
                    default:
                        result.append(character)
                        result.append(value[next])
                    }
                    index = value.index(after: next)
                } else {
                    result.append(character)
                    index = next
                }
            } else {
                result.append(character)
                index = next
            }
        }
        return result
    }
}

/// Shared ssh_config line syntax helpers.
enum SSHConfigSyntax {
    /// Splits a line into a lowercased keyword and its raw argument, accepting
    /// both `Keyword value` and `Keyword = value`. Returns `nil` for blank
    /// lines and comments.
    static func parseDirective(from line: String) -> (keyword: String, argument: String)? {
        let trimmed = line.trimmingCharacters(in: .whitespaces)
        guard !trimmed.isEmpty, !trimmed.hasPrefix("#") else { return nil }

        var keywordEnd = trimmed.startIndex
        while keywordEnd < trimmed.endIndex {
            let character = trimmed[keywordEnd]
            if character == " " || character == "\t" || character == "=" { break }
            keywordEnd = trimmed.index(after: keywordEnd)
        }
        guard keywordEnd > trimmed.startIndex else { return nil }
        let keyword = trimmed[trimmed.startIndex..<keywordEnd].lowercased()

        var rest = trimmed[keywordEnd...].drop(while: { $0 == " " || $0 == "\t" })
        if rest.first == "=" {
            rest = rest.dropFirst().drop(while: { $0 == " " || $0 == "\t" })
        }
        return (keyword, String(rest))
    }

    /// Splits an argument on whitespace, keeping double-quoted sections
    /// (including their spaces) as single tokens and stripping the quotes.
    static func tokenize(_ argument: String) -> [String] {
        var tokens: [String] = []
        var current = ""
        var inQuotes = false
        var hasCurrent = false
        for character in argument {
            if character == "\"" {
                inQuotes.toggle()
                hasCurrent = true
            } else if (character == " " || character == "\t"), !inQuotes {
                if hasCurrent {
                    tokens.append(current)
                    current = ""
                    hasCurrent = false
                }
            } else {
                current.append(character)
                hasCurrent = true
            }
        }
        if hasCurrent {
            tokens.append(current)
        }
        return tokens
    }

    /// Expands a leading `~` against the given home directory. `~user` forms
    /// are left untouched.
    static func expandHome(_ path: String, homeDirectoryPath: String) -> String {
        if path == "~" { return homeDirectoryPath }
        if path.hasPrefix("~/") {
            return homeDirectoryPath + path.dropFirst(1)
        }
        return path
    }
}

/// Resolves `Include` directives one level deep by splicing the referenced
/// file contents into the root text at the directive's position, matching
/// OpenSSH's inline semantics. Relative paths resolve against `~/.ssh/`,
/// matching OpenSSH's rule for the user config file, and glob metacharacters
/// in the final path component expand against the parent directory listing
/// in sorted order. Missing or unreadable files and directories are skipped,
/// and includes inside included files are not followed.
enum SSHConfigFileComposer {
    static func compose(
        rootText: String,
        homeDirectoryPath: String,
        listDirectory: (String) -> [String]? = { _ in nil },
        readFile: (String) -> String?
    ) -> String {
        var lines: [String] = []
        for rawLine in rootText.components(separatedBy: .newlines) {
            if let directive = SSHConfigSyntax.parseDirective(from: rawLine),
               directive.keyword == "include" {
                for token in SSHConfigSyntax.tokenize(directive.argument) {
                    for path in resolveIncludePaths(
                        token,
                        homeDirectoryPath: homeDirectoryPath,
                        listDirectory: listDirectory
                    ) {
                        if let contents = readFile(path) {
                            lines.append(contents)
                        }
                    }
                }
            } else {
                lines.append(rawLine)
            }
        }
        return lines.joined(separator: "\n")
    }

    /// Resolves one `Include` token to concrete file paths: tilde-expanded,
    /// relative paths anchored at `~/.ssh/`, and globs expanded against the
    /// parent directory. Unmatched patterns and missing directories yield no
    /// paths.
    private static func resolveIncludePaths(
        _ token: String,
        homeDirectoryPath: String,
        listDirectory: (String) -> [String]?
    ) -> [String] {
        var path = SSHConfigSyntax.expandHome(token, homeDirectoryPath: homeDirectoryPath)
        if !path.hasPrefix("/") {
            path = homeDirectoryPath + "/.ssh/" + path
        }
        guard path.contains("*") || path.contains("?") else {
            return [path]
        }
        let directory = (path as NSString).deletingLastPathComponent
        let pattern = (path as NSString).lastPathComponent
        guard let entries = listDirectory(directory) else { return [] }
        return entries
            .filter { SSHConfigFileParser.globMatches(pattern, $0) }
            .sorted()
            .map { directory + "/" + $0 }
    }
}
