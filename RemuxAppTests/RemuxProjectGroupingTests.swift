import XCTest
@testable import Remux

final class RemuxProjectGroupingTests: XCTestCase {
    /// The registry fixture mirrors the cockpit project list
    /// (config/projects/*.yaml). It is test data, not app behavior: the
    /// app builds its registry from observed pane directories.
    private static let registry: Set<String> = [
        "uni",
        "urchin",
        "smetl",
        "reporting_queries",
        "byron",
        "smonorepo",
        "sourcemedium.com",
        "dotfiles",
    ]

    private let home = "/Users/fei"

    private func derive(
        _ path: String,
        home: String? = nil,
        known: Set<String> = []
    ) -> RemuxProjectGrouping.Context? {
        RemuxProjectGrouping.derive(
            path: path,
            homeDirectory: home,
            knownProjects: known
        )
    }

    // MARK: Path → project directory

    func testLocalProjectDirectoryWins() {
        XCTAssertEqual(
            derive("/Users/fei/Local/uni", home: home),
            RemuxProjectGrouping.Context(projectKey: "uni", worktreeDetail: nil)
        )
    }

    func testNestedPathCollapsesToTopDirectoryUnderLocal() {
        XCTAssertEqual(
            derive("/Users/fei/Local/uni/RemuxApp/Sources", home: home),
            RemuxProjectGrouping.Context(projectKey: "uni", worktreeDetail: nil)
        )
    }

    func testDepthOneDirectoryUnderHomeDerives() {
        XCTAssertEqual(
            derive("/Users/fei/dotfiles", home: home),
            RemuxProjectGrouping.Context(projectKey: "dotfiles", worktreeDetail: nil)
        )
    }

    func testLinuxHomeInfersWithoutExplicitHomeDirectory() {
        XCTAssertEqual(
            derive("/home/fei/Local/urchin"),
            RemuxProjectGrouping.Context(projectKey: "urchin", worktreeDetail: nil)
        )
        XCTAssertEqual(
            derive("/home/fei/smetl"),
            RemuxProjectGrouping.Context(projectKey: "smetl", worktreeDetail: nil)
        )
    }

    func testHomeDirectoryItselfDerivesNothing() {
        XCTAssertNil(derive("/Users/fei", home: home))
        XCTAssertNil(derive("/Users/fei/"))
        XCTAssertNil(derive("/Users/fei"))
    }

    func testLocalRootDerivesNothing() {
        XCTAssertNil(derive("/Users/fei/Local", home: home))
        XCTAssertNil(derive("/Users/fei/Local/"))
    }

    func testRootAndNonHomePathsDeriveNothing() {
        XCTAssertNil(derive("/"))
        XCTAssertNil(derive("/tmp/build"))
        XCTAssertNil(derive("/var/log"))
        XCTAssertNil(derive("/opt/Local"))
        XCTAssertNil(derive(""))
        XCTAssertNil(derive("   "))
    }

    // MARK: Explicit worktree separators

    func testWorktreeSeparatorSplitsBaseAndDetail() {
        XCTAssertEqual(
            derive(
                "/Users/fei/Local/reporting_queries-worktree-adgroup.HdLq7V",
                known: Self.registry
            ),
            RemuxProjectGrouping.Context(
                projectKey: "reporting_queries",
                worktreeDetail: "adgroup"
            )
        )
    }

    func testWorktreeSeparatorSplitsWithoutRegistry() {
        XCTAssertEqual(
            derive("/Users/fei/Local/uni-worktree-review"),
            RemuxProjectGrouping.Context(projectKey: "uni", worktreeDetail: "review")
        )
    }

    func testWtSeparatorSplitsBaseAndDetail() {
        XCTAssertEqual(
            derive("/Users/fei/Local/smetl-wt-queue", known: Self.registry),
            RemuxProjectGrouping.Context(projectKey: "smetl", worktreeDetail: "queue")
        )
    }

    func testDanglingWorktreeSeparatorKeepsFullName() {
        XCTAssertEqual(
            derive("/Users/fei/Local/uni-worktree-", known: Self.registry),
            RemuxProjectGrouping.Context(projectKey: "uni-worktree-", worktreeDetail: nil)
        )
    }

    func testRandomSuffixIsOnlyStrippedFromWorktreeDetail() {
        XCTAssertEqual(
            derive("/Users/fei/Local/reporting_queries-worktree-mmm-currency.X9k2Pq"),
            RemuxProjectGrouping.Context(
                projectKey: "reporting_queries",
                worktreeDetail: "mmm-currency"
            )
        )
        // Short or letter-only tails are part of the task name.
        XCTAssertEqual(
            derive("/Users/fei/Local/uni-wt-build.v2"),
            RemuxProjectGrouping.Context(projectKey: "uni", worktreeDetail: "build.v2")
        )
        XCTAssertEqual(
            derive("/Users/fei/Local/uni-wt-build.abcdef"),
            RemuxProjectGrouping.Context(projectKey: "uni", worktreeDetail: "build.abcdef")
        )
    }

    // MARK: Plain dash names

    func testPlainDashCollapsesWhenBaseIsKnown() {
        XCTAssertEqual(
            derive(
                "/Users/fei/Local/reporting_queries-mmm-currency-blocker",
                known: Self.registry
            ),
            RemuxProjectGrouping.Context(
                projectKey: "reporting_queries",
                worktreeDetail: "mmm-currency-blocker"
            )
        )
    }

    func testPlainDashKeepsFullNameWithoutKnownBase() {
        XCTAssertEqual(
            derive("/Users/fei/Local/reporting_queries-mmm-currency-blocker"),
            RemuxProjectGrouping.Context(
                projectKey: "reporting_queries-mmm-currency-blocker",
                worktreeDetail: nil
            )
        )
    }

    func testPlainDashUsesLongestKnownPrefix() {
        XCTAssertEqual(
            derive(
                "/Users/fei/Local/sourcemedium.com-blog-redesign",
                known: Self.registry
            ),
            RemuxProjectGrouping.Context(
                projectKey: "sourcemedium.com",
                worktreeDetail: "blog-redesign"
            )
        )
    }

    // MARK: Numbered clones

    func testNumberedCloneCollapsesToKnownBase() {
        XCTAssertEqual(
            derive("/Users/fei/Local/uni2", known: Self.registry),
            RemuxProjectGrouping.Context(projectKey: "uni", worktreeDetail: nil)
        )
        XCTAssertEqual(
            derive("/Users/fei/Local/uni3", known: Self.registry),
            RemuxProjectGrouping.Context(projectKey: "uni", worktreeDetail: nil)
        )
    }

    func testNumberedCloneCollapsesWithoutRegistry() {
        XCTAssertEqual(
            derive("/Users/fei/Local/uni2"),
            RemuxProjectGrouping.Context(projectKey: "uni", worktreeDetail: nil)
        )
    }

    func testProjectLiterallyNamedWithTrailingDigitKeepsName() {
        // Registry has data but knows no `app` base: `app2` is its own project.
        XCTAssertEqual(
            derive("/Users/fei/Local/app2", known: Self.registry),
            RemuxProjectGrouping.Context(projectKey: "app2", worktreeDetail: nil)
        )
        XCTAssertEqual(
            derive("/Users/fei/Local/app2", known: ["app2"]),
            RemuxProjectGrouping.Context(projectKey: "app2", worktreeDetail: nil)
        )
    }

    func testLongDigitRunsDoNotCollapse() {
        XCTAssertEqual(
            derive("/Users/fei/Local/web2024"),
            RemuxProjectGrouping.Context(projectKey: "web2024", worktreeDetail: nil)
        )
    }

    func testDigitsWithoutBaseLookingPrefixDoNotCollapse() {
        XCTAssertEqual(
            derive("/Users/fei/Local/42"),
            RemuxProjectGrouping.Context(projectKey: "42", worktreeDetail: nil)
        )
        XCTAssertEqual(
            derive("/Users/fei/Local/a1"),
            RemuxProjectGrouping.Context(projectKey: "a1", worktreeDetail: nil)
        )
    }

    // MARK: Observed registry

    func testObservedProjectsCollectsNamesAndWorktreeBases() {
        let projects = RemuxProjectGrouping.observedProjects(paths: [
            "/Users/fei/Local/uni",
            "/Users/fei/Local/uni2",
            "/Users/fei/Local/reporting_queries-worktree-adgroup.HdLq7V",
            "/tmp/build",
            "",
        ])
        XCTAssertTrue(projects.contains("uni"))
        XCTAssertTrue(projects.contains("uni2"))
        XCTAssertTrue(projects.contains("reporting_queries"))
        XCTAssertFalse(projects.contains("build"))
    }

    func testObservedRegistryEnablesCrossPaneAttribution() {
        // One pane in the base checkout is enough evidence to attribute a
        // plain-dash sibling directory to the same project.
        let projects = RemuxProjectGrouping.observedProjects(paths: [
            "/Users/fei/Local/uni",
        ])
        XCTAssertEqual(
            derive("/Users/fei/Local/uni-review", known: projects),
            RemuxProjectGrouping.Context(projectKey: "uni", worktreeDetail: "review")
        )
    }

    // MARK: Session resolution

    func testSessionContextPrefersFocusedPane() {
        let context = RemuxProjectGrouping.sessionContext(
            RemuxProjectGrouping.PanePaths(
                focusedPath: "/Users/fei/Local/smetl-wt-queue",
                allPaths: [
                    "/Users/fei/Local/uni",
                    "/Users/fei/Local/uni2",
                    "/Users/fei/Local/smetl-wt-queue",
                ]
            ),
            knownProjects: ["uni"]
        )
        XCTAssertEqual(
            context,
            RemuxProjectGrouping.Context(projectKey: "smetl", worktreeDetail: "queue")
        )
    }

    func testSessionContextFallsBackToMajority() {
        let context = RemuxProjectGrouping.sessionContext(
            RemuxProjectGrouping.PanePaths(
                focusedPath: nil,
                allPaths: [
                    "/Users/fei/Local/smetl",
                    "/Users/fei/Local/uni",
                    "/Users/fei/Local/uni2",
                ]
            ),
            knownProjects: ["uni", "smetl"]
        )
        XCTAssertEqual(
            context,
            RemuxProjectGrouping.Context(projectKey: "uni", worktreeDetail: nil)
        )
    }

    func testSessionContextMajorityTieKeepsFirstSeen() {
        let context = RemuxProjectGrouping.sessionContext(
            RemuxProjectGrouping.PanePaths(
                focusedPath: nil,
                allPaths: ["/Users/fei/Local/smetl", "/Users/fei/Local/uni"]
            ),
            knownProjects: ["uni", "smetl"]
        )
        XCTAssertEqual(
            context,
            RemuxProjectGrouping.Context(projectKey: "smetl", worktreeDetail: nil)
        )
    }

    func testSessionContextIsNilWithoutDerivablePaths() {
        XCTAssertNil(
            RemuxProjectGrouping.sessionContext(
                RemuxProjectGrouping.PanePaths(
                    focusedPath: "/",
                    allPaths: ["/tmp/build", "/var/log"]
                )
            )
        )
        XCTAssertNil(
            RemuxProjectGrouping.sessionContext(
                RemuxProjectGrouping.PanePaths(focusedPath: nil, allPaths: [])
            )
        )
    }
}
