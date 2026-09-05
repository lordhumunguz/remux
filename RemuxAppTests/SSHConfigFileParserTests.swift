import XCTest
@testable import Remux

final class SSHConfigFileParserTests: XCTestCase {
    private let home = "/Users/test"

    func testParsesBasicHostBlock() {
        let file = parse("""
            Host macpro
              HostName macpro.local
              User fei
              Port 2222
              IdentityFile ~/.ssh/id_ed25519
            """)

        XCTAssertEqual(file.hosts.count, 1)
        let host = file.hosts[0]
        XCTAssertEqual(host.alias, "macpro")
        XCTAssertEqual(host.hostName, "macpro.local")
        XCTAssertEqual(host.user, "fei")
        XCTAssertEqual(host.port, 2222)
        XCTAssertEqual(host.identityFile, "/Users/test/.ssh/id_ed25519")
    }

    func testSkipsCommentsAndBlankLines() {
        let file = parse("""
            # Leading comment.
            Host web
              # Indented comment.
              HostName web.example.test

              User deploy
            """)

        XCTAssertEqual(file.hosts.count, 1)
        XCTAssertEqual(file.hosts[0].hostName, "web.example.test")
        XCTAssertEqual(file.hosts[0].user, "deploy")
    }

    func testKeywordsAreCaseInsensitive() {
        let file = parse("""
            host web
              hostname web.example.test
              USER deploy
              pOrT 2200
              IDENTITYFILE ~/.ssh/key
            """)

        let host = file.hosts[0]
        XCTAssertEqual(host.alias, "web")
        XCTAssertEqual(host.hostName, "web.example.test")
        XCTAssertEqual(host.user, "deploy")
        XCTAssertEqual(host.port, 2200)
        XCTAssertEqual(host.identityFile, "/Users/test/.ssh/key")
    }

    func testSupportsEqualsSeparator() {
        let file = parse("""
            Host web
              HostName=web.example.test
              User = deploy
              Port=  2200
            """)

        let host = file.hosts[0]
        XCTAssertEqual(host.hostName, "web.example.test")
        XCTAssertEqual(host.user, "deploy")
        XCTAssertEqual(host.port, 2200)
    }

    func testStripsQuotedValuesAndKeepsQuotedSpaces() {
        let file = parse("""
            Host web
              HostName "web.example.test"
              IdentityFile "~/my keys/id_ed25519"
            """)

        let host = file.hosts[0]
        XCTAssertEqual(host.hostName, "web.example.test")
        XCTAssertEqual(host.identityFile, "/Users/test/my keys/id_ed25519")
    }

    func testMultiplePatternsBecomeSeparateHosts() {
        let file = parse("""
            Host macpro macpro-tailscale macair
              User fei
            """)

        XCTAssertEqual(file.hosts.map(\.alias), ["macpro", "macpro-tailscale", "macair"])
        XCTAssertEqual(Set(file.hosts.compactMap(\.user)), ["fei"])
    }

    func testWildcardHostStarIsSkippedButDefaultsAreHonored() {
        let file = parse("""
            Host web
              HostName web.example.test

            Host db
              HostName db.example.test
              User postgres

            Host *
              User fallback
              Port 2222
              IdentityFile ~/.ssh/default_key
            """)

        XCTAssertEqual(file.hosts.map(\.alias), ["web", "db"])
        let web = file.hosts[0]
        XCTAssertEqual(web.user, "fallback")
        XCTAssertEqual(web.port, 2222)
        XCTAssertEqual(web.identityFile, "/Users/test/.ssh/default_key")
        let db = file.hosts[1]
        XCTAssertEqual(db.user, "postgres")
        XCTAssertEqual(db.port, 2222)
    }

    func testWildcardPatternsInMixedBlockAreNotImported() {
        let file = parse("""
            Host macpro 100.* ?dmz
              User fei
            """)

        XCTAssertEqual(file.hosts.map(\.alias), ["macpro"])
    }

    func testWildcardBlockDefaultsApplyToMatchingAlias() {
        let file = parse("""
            Host 100.*
              User tailscale

            Host 100.64.0.1
              HostName macpro
            """)

        XCTAssertEqual(file.hosts.map(\.alias), ["100.64.0.1"])
        XCTAssertEqual(file.hosts[0].user, "tailscale")
        XCTAssertEqual(file.hosts[0].hostName, "macpro")
    }

    func testWildcardMatchingIsCaseInsensitive() {
        let file = parse("""
            Host PROD-*
              User ops

            Host prod-db
              HostName db.example.test
            """)

        XCTAssertEqual(file.hosts[0].user, "ops")
    }

    func testNegatedPatternExcludesAliasFromDefaults() {
        let file = parse("""
            Host * !bastion
              User fallback

            Host bastion
              HostName bastion.example.test

            Host web
              HostName web.example.test
            """)

        XCTAssertNil(file.hosts[0].user)
        XCTAssertEqual(file.hosts[1].user, "fallback")
    }

    func testHostNameExpandsPercentTokens() {
        let file = parse("""
            Host web
              HostName %h.internal.example.test

            Host literal
              HostName 100%%-cpu.example.test

            Host untouched
              HostName %r@example.test
            """)

        XCTAssertEqual(file.hosts[0].hostName, "web.internal.example.test")
        XCTAssertEqual(file.hosts[1].hostName, "100%-cpu.example.test")
        XCTAssertEqual(file.hosts[2].hostName, "%r@example.test")
    }

    func testMissingFieldsDefaultToAliasAndNil() {
        let file = parse("""
            Host web
              ServerAliveInterval 15
            """)

        let host = file.hosts[0]
        XCTAssertEqual(host.hostName, "web")
        XCTAssertNil(host.user)
        XCTAssertNil(host.port)
        XCTAssertNil(host.identityFile)
    }

    func testDuplicateAliasMergesWithFirstValueWins() {
        let file = parse("""
            Host web
              HostName web.example.test
              User deploy

            Host web
              HostName other.example.test
              Port 2200
            """)

        XCTAssertEqual(file.hosts.count, 1)
        let host = file.hosts[0]
        XCTAssertEqual(host.hostName, "web.example.test")
        XCTAssertEqual(host.user, "deploy")
        XCTAssertEqual(host.port, 2200)
    }

    func testFirstMatchingBlockWinsPerKey() {
        let file = parse("""
            Host web
              User first

            Host *
              User fallback
            """)

        XCTAssertEqual(file.hosts[0].user, "first")
    }

    func testExpandsTildeFormsInIdentityFile() {
        let file = parse("""
            Host a
              IdentityFile ~

            Host b
              IdentityFile ~/.ssh/id_ed25519

            Host c
              IdentityFile /etc/ssh/key

            Host d
              IdentityFile ~other/keys/id
            """)

        XCTAssertEqual(file.hosts[0].identityFile, "/Users/test")
        XCTAssertEqual(file.hosts[1].identityFile, "/Users/test/.ssh/id_ed25519")
        XCTAssertEqual(file.hosts[2].identityFile, "/etc/ssh/key")
        XCTAssertEqual(file.hosts[3].identityFile, "~other/keys/id")
    }

    func testIgnoresInvalidAndOutOfRangePorts() {
        let file = parse("""
            Host a
              Port abc

            Host b
              Port 70000

            Host c
              Port 0
            """)

        XCTAssertNil(file.hosts[0].port)
        XCTAssertNil(file.hosts[1].port)
        XCTAssertNil(file.hosts[2].port)
    }

    func testGlobalScopeSettingsApplyAsDefaults() {
        let file = parse("""
            User global
            Port 2200

            Host web
              HostName web.example.test
            """)

        let host = file.hosts[0]
        XCTAssertEqual(host.user, "global")
        XCTAssertEqual(host.port, 2200)
    }

    func testComposerSplicesIncludedFileAtDirectivePosition() {
        let root = """
            Include /etc/ssh/config.local

            Host web
              HostName web.example.test
            """
        let included = """
            Host secret
              HostName secret.example.test
              User ops
            """

        let composed = SSHConfigFileComposer.compose(
            rootText: root,
            homeDirectoryPath: home
        ) { path in
            path == "/etc/ssh/config.local" ? included : nil
        }
        let file = parse(composed)

        XCTAssertEqual(file.hosts.map(\.alias), ["secret", "web"])
        XCTAssertEqual(file.hosts[0].user, "ops")
    }

    func testComposerToleratesMissingInclude() {
        let root = """
            Include /etc/ssh/missing

            Host web
              HostName web.example.test
            """

        let composed = SSHConfigFileComposer.compose(
            rootText: root,
            homeDirectoryPath: home
        ) { _ in nil }
        let file = parse(composed)

        XCTAssertEqual(file.hosts.map(\.alias), ["web"])
    }

    func testComposerDoesNotFollowNestedIncludes() {
        let root = "Include /one"
        let composed = SSHConfigFileComposer.compose(
            rootText: root,
            homeDirectoryPath: home
        ) { path in
            switch path {
            case "/one":
                return "Include /two\nHost one\n  HostName one.example.test"
            case "/two":
                return "Host two\n  HostName two.example.test"
            default:
                return nil
            }
        }
        let file = parse(composed)

        XCTAssertEqual(file.hosts.map(\.alias), ["one"])
    }

    func testComposerHandlesMultipleAndQuotedIncludePaths() {
        let root = "Include /one \"~/dir with spaces/two\""
        let composed = SSHConfigFileComposer.compose(
            rootText: root,
            homeDirectoryPath: home
        ) { path in
            switch path {
            case "/one":
                return "Host one"
            case "/Users/test/dir with spaces/two":
                return "Host two"
            default:
                return nil
            }
        }
        let file = parse(composed)

        XCTAssertEqual(file.hosts.map(\.alias), ["one", "two"])
    }

    func testComposerExpandsTildeInIncludePath() {
        var readPaths: [String] = []
        _ = SSHConfigFileComposer.compose(
            rootText: "Include ~/.ssh/config.local",
            homeDirectoryPath: home
        ) { path in
            readPaths.append(path)
            return nil
        }

        XCTAssertEqual(readPaths, ["/Users/test/.ssh/config.local"])
    }

    func testParsesDotfilesStyleConfigWithLocalInclude() {
        let root = """
            # Managed by dotfiles.
            Include ~/.ssh/config.local

            Host github.com
              HostName ssh.github.com
              Port 443
              User git
              IdentityFile ~/.ssh/id_ed25519
              IdentitiesOnly yes

            Host macpro macpro-tailscale macair 100.*
              ConnectTimeout 5
              ConnectionAttempts 4

            Host *
              AddKeysToAgent yes
              UseKeychain yes
            """
        let local = """
            Host macpro
              HostName 100.64.0.1
              User fei
            """
        let composed = SSHConfigFileComposer.compose(
            rootText: root,
            homeDirectoryPath: home
        ) { path in
            path == "/Users/test/.ssh/config.local" ? local : nil
        }
        let file = parse(composed)

        XCTAssertEqual(
            file.hosts.map(\.alias),
            ["macpro", "github.com", "macpro-tailscale", "macair"]
        )

        let macpro = file.hosts[0]
        XCTAssertEqual(macpro.hostName, "100.64.0.1")
        XCTAssertEqual(macpro.user, "fei")

        let github = file.hosts[1]
        XCTAssertEqual(github.hostName, "ssh.github.com")
        XCTAssertEqual(github.port, 443)
        XCTAssertEqual(github.user, "git")
        XCTAssertEqual(github.identityFile, "/Users/test/.ssh/id_ed25519")

        let tailscaleAlias = file.hosts[2]
        XCTAssertEqual(tailscaleAlias.hostName, "macpro-tailscale")
        XCTAssertNil(tailscaleAlias.user)
        XCTAssertNil(tailscaleAlias.port)
    }

    func testMatchClosesPrecedingHostBlock() {
        let file = parse("""
            Host web
              HostName web.example.test
              User deploy

            Match host web
              User root
              Port 2222

            Host db
              HostName db.example.test
            """)

        XCTAssertEqual(file.hosts.map(\.alias), ["web", "db"])
        let web = file.hosts[0]
        XCTAssertEqual(web.user, "deploy")
        XCTAssertNil(web.port)
    }

    func testMatchKeywordIsCaseInsensitive() {
        let file = parse("""
            Host web
              HostName web.example.test
            match all
              User root
            """)

        XCTAssertEqual(file.hosts.map(\.alias), ["web"])
        XCTAssertNil(file.hosts[0].user)
    }

    func testComposerExpandsGlobIncludeAgainstParentDirectory() {
        let root = """
            Include ~/.ssh/config.d/*

            Host web
              HostName web.example.test
            """
        let composed = SSHConfigFileComposer.compose(
            rootText: root,
            homeDirectoryPath: home,
            listDirectory: { path in
                path == "/Users/test/.ssh/config.d" ? ["20-misc", "10-macpro", "notes.txt"] : nil
            }
        ) { path in
            switch path {
            case "/Users/test/.ssh/config.d/10-macpro":
                return "Host macpro\n  HostName 100.64.0.1"
            case "/Users/test/.ssh/config.d/20-misc":
                return "Host macair\n  HostName 100.64.0.2"
            default:
                return nil
            }
        }
        let file = parse(composed)

        XCTAssertEqual(file.hosts.map(\.alias), ["macpro", "macair", "web"])
    }

    func testComposerResolvesRelativeIncludeAgainstDotSSHDirectory() {
        var readPaths: [String] = []
        _ = SSHConfigFileComposer.compose(
            rootText: "Include config.local",
            homeDirectoryPath: home
        ) { path in
            readPaths.append(path)
            return nil
        }

        XCTAssertEqual(readPaths, ["/Users/test/.ssh/config.local"])
    }

    func testComposerToleratesMissingGlobDirectory() {
        let root = """
            Include ~/.ssh/config.d/*.conf

            Host web
              HostName web.example.test
            """
        let composed = SSHConfigFileComposer.compose(
            rootText: root,
            homeDirectoryPath: home,
            listDirectory: { _ in nil }
        ) { _ in nil }
        let file = parse(composed)

        XCTAssertEqual(file.hosts.map(\.alias), ["web"])
    }

    private func parse(_ text: String) -> SSHConfigFile {
        SSHConfigFileParser.parse(text, homeDirectoryPath: home)
    }
}