import Foundation

/// Agent state read from the server-side tmux pane-mark protocol (the
/// dotfiles' agent-state hooks). The pane options are user options; a pane
/// that has none of them set is simply `.idle`.
enum TmuxPaneAgentState: String, Equatable, Sendable {
    /// Stopped on a permission prompt; needs a human.
    case blocked
    /// Actively working.
    case working
    /// A turn ended in a non-active pane and has not been viewed since.
    case unseen
    case idle

    /// Badge precedence on one pane: blocked beats working beats unseen.
    var paneRank: Int {
        switch self {
        case .blocked: 0
        case .working: 1
        case .unseen: 2
        case .idle: 3
        }
    }

    /// Session-switcher ordering: attention needed first (blocked, then an
    /// unviewed finished turn), then live work, then idle.
    var sessionSortRank: Int {
        switch self {
        case .blocked: 0
        case .unseen: 1
        case .working: 2
        case .idle: 3
        }
    }

    static func sessionAggregate(of states: some Sequence<TmuxPaneAgentState>) -> TmuxPaneAgentState {
        states.min(by: { $0.sessionSortRank < $1.sessionSortRank }) ?? .idle
    }
}

struct TmuxPaneAgentInfo: Equatable, Sendable {
    var state: TmuxPaneAgentState
    var gitBranch: String?
    var gitRepo: String?
    var agentModel: String?
    var agentTool: String?
    var quotaPercent: Int?
    var doneAt: Date?

    var isBlocked: Bool {
        state == .blocked
    }

    var isWorking: Bool {
        state == .working
    }

    var isDone: Bool {
        doneAt != nil
    }

    func doneRelativeText(now: Date = Date()) -> String? {
        guard let doneAt else { return nil }
        let elapsed = now.timeIntervalSince(doneAt)
        guard elapsed >= 0 else { return nil }
        if elapsed < 60 {
            return "just now"
        } else if elapsed < 3600 {
            let minutes = max(1, Int(elapsed / 60))
            return "\(minutes)m"
        } else if elapsed < 86400 {
            let hours = max(1, Int(elapsed / 3600))
            return "\(hours)h"
        } else {
            let days = max(1, Int(elapsed / 86400))
            return "\(days)d"
        }
    }

    static let idle = TmuxPaneAgentInfo(state: .idle)

    init(
        state: TmuxPaneAgentState,
        gitBranch: String? = nil,
        gitRepo: String? = nil,
        agentModel: String? = nil,
        agentTool: String? = nil,
        quotaPercent: Int? = nil,
        doneAt: Date? = nil
    ) {
        self.state = state
        self.gitBranch = gitBranch
        self.gitRepo = gitRepo
        self.agentModel = agentModel
        self.agentTool = agentTool
        self.quotaPercent = quotaPercent
        self.doneAt = doneAt
    }
}

/// Parses the `list-panes` response that carries the agent-state user
/// options through the control channel.
enum TmuxPaneAgentMetadata {
    /// Field separator for the list-panes format. tmux format strings do not
    /// interpret C escapes, so the separator is the literal U+001F, which git
    /// branch names cannot contain and the flag values never use.
    static let fieldSeparator = "\u{1F}"

    static let formatString = [
        "#{pane_id}",
        "#{@ai_blocked}",
        "#{@claude_working}",
        "#{@ai_unseen}",
        "#{@pane_git_branch}",
        "#{@pane_git_repo}",
        "#{@pane_agent_model}",
        "#{@pane_agent_tool}",
        "#{@pane_agent_pct}",
        "#{@ai_done_at}",
    ].joined(separator: fieldSeparator)

    static let listPanesCommand = "list-panes -s -F '\(formatString)'"

    /// Mirrors tmux's `#{?option,...}` truthiness: any non-empty value other
    /// than "0" is true. An unset user option expands to the empty string.
    static func isTruthy(_ value: some StringProtocol) -> Bool {
        !value.isEmpty && value != "0"
    }

    static func parseListPanesBody(_ body: String) -> [TmuxPaneID: TmuxPaneAgentInfo] {
        var infos: [TmuxPaneID: TmuxPaneAgentInfo] = [:]
        for line in body.split(separator: "\n", omittingEmptySubsequences: true) {
            let fields = line.split(
                separator: Character(fieldSeparator),
                omittingEmptySubsequences: false
            )
            guard fields.count >= 4,
                  let paneID = paneID(from: fields[0])
            else { continue }

            let marked: [TmuxPaneAgentState?] = [
                isTruthy(fields[1]) ? .blocked : nil,
                isTruthy(fields[2]) ? .working : nil,
                isTruthy(fields[3]) ? .unseen : nil,
            ]
            let state = marked.compactMap { $0 }
                .min(by: { $0.paneRank < $1.paneRank }) ?? .idle

            infos[paneID] = TmuxPaneAgentInfo(
                state: state,
                gitBranch: fields.count > 4 ? nilIfEmpty(fields[4]) : nil,
                gitRepo: fields.count > 5 ? nilIfEmpty(fields[5]) : nil,
                agentModel: fields.count > 6 ? nilIfEmpty(fields[6]) : nil,
                agentTool: fields.count > 7 ? nilIfEmpty(fields[7]) : nil,
                quotaPercent: fields.count > 8 ? parseQuotaPercent(fields[8]) : nil,
                doneAt: fields.count > 9 ? parseEpochDate(fields[9]) : nil
            )
        }
        return infos
    }

    static func parseEpochDate(_ field: some StringProtocol) -> Date? {
        let trimmed = field.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty, let seconds = TimeInterval(trimmed), seconds > 0 else { return nil }
        return Date(timeIntervalSince1970: seconds)
    }

    static func parseQuotaPercent(_ field: some StringProtocol) -> Int? {
        let trimmed = field.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return nil }
        var text = trimmed
        if text.hasPrefix("W") || text.hasPrefix("w") {
            text.removeFirst()
        }
        if text.hasSuffix("%") {
            text.removeLast()
        }
        text = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !text.isEmpty else { return nil }

        let lower = text.lowercased()
        if lower.contains("nan") || lower.contains("inf") {
            return nil
        }

        if let intVal = Int(text) {
            guard intVal >= 0 && intVal <= 1000 else { return nil }
            return intVal
        }
        if let doubleVal = Double(text), doubleVal.isFinite, !doubleVal.isNaN {
            let rounded = Int(doubleVal.rounded())
            guard rounded >= 0 && rounded <= 1000 else { return nil }
            return rounded
        }
        return nil
    }

    private static func paneID(from field: some StringProtocol) -> TmuxPaneID? {
        let text = field.hasPrefix("%") ? field.dropFirst() : field[...]
        guard let rawValue = UInt64(text) else { return nil }
        return TmuxPaneID(rawValue)
    }

    private static func nilIfEmpty(_ value: some StringProtocol) -> String? {
        value.isEmpty ? nil : String(value)
    }
}

/// Diffs consecutive agent-metadata snapshots so a blocked pane raises
/// exactly one alert per blocked episode: an episode ends when the pane
/// leaves the blocked state (or disappears), and a later block is a new one.
/// The first snapshot after a reset only establishes the baseline, so
/// attaching to a session with panes already blocked is not an alert burst.
struct TmuxAgentBlockedTracker: Equatable, Sendable {
    private(set) var blockedPaneIDs: Set<TmuxPaneID> = []
    private var hasBaseline = false

    /// Records the latest snapshot and returns the panes that newly entered
    /// the blocked state, in stable id order.
    mutating func update(
        with infos: [TmuxPaneID: TmuxPaneAgentInfo]
    ) -> [TmuxPaneID] {
        let nowBlocked = Set(infos.lazy.filter { $0.value.state == .blocked }.map { $0.key })
        defer {
            blockedPaneIDs = nowBlocked
            hasBaseline = true
        }
        guard hasBaseline else { return [] }
        return nowBlocked.subtracting(blockedPaneIDs).sorted()
    }

    mutating func reset() {
        blockedPaneIDs.removeAll()
        hasBaseline = false
    }
}

/// Rate floor for event-triggered agent-metadata repolls (topology churn,
/// foregrounding): they supplement the repeating poll but must not outpace
/// it. Timer-driven polls bypass admission yet still refresh the floor, so
/// an event right after a timer poll does not duplicate fresh data.
struct TmuxAgentMetadataRepollGate: Equatable, Sendable {
    private(set) var lastPollUptime: TimeInterval?
    let minimumInterval: TimeInterval

    init(minimumInterval: TimeInterval) {
        self.minimumInterval = minimumInterval
    }

    /// Admits an event-triggered poll once the floor has elapsed and records
    /// it; returns false while still inside the floor.
    mutating func admit(at uptime: TimeInterval) -> Bool {
        if let lastPollUptime, uptime - lastPollUptime < minimumInterval {
            return false
        }
        lastPollUptime = uptime
        return true
    }

    /// Records a poll that fired without admission (the repeating timer).
    mutating func recordPoll(at uptime: TimeInterval) {
        lastPollUptime = uptime
    }

    mutating func reset() {
        lastPollUptime = nil
    }
}

/// One "agent needs a human" alert for a pane that newly became blocked.
struct TmuxAgentBlockedNotification: Equatable, Sendable {
    let sessionName: String
    let paneID: TmuxPaneID
    let currentCommand: String
    let currentPath: String
}

/// One alert for an agent turn that completed in a background or unviewed pane.
struct TmuxAgentCompletedNotification: Equatable, Sendable {
    let sessionName: String
    let paneID: TmuxPaneID
    let agentTool: String?
    let currentCommand: String
    let currentPath: String
}

/// Diffs consecutive agent-metadata snapshots to detect when an agent completes a turn.
/// An agent completes when:
/// 1) Its `doneAt` timestamp is newer than previously recorded, OR
/// 2) Its state becomes `.unseen` while marked as done.
/// The first snapshot after a reset establishes a baseline so attaching does not fire alerts.
struct TmuxAgentCompletedTracker: Equatable, Sendable {
    private(set) var knownDoneAt: [TmuxPaneID: Date] = [:]
    private(set) var knownUnseenPanes: Set<TmuxPaneID> = []
    private var hasBaseline = false

    mutating func update(
        with infos: [TmuxPaneID: TmuxPaneAgentInfo]
    ) -> [TmuxPaneID] {
        var newlyCompleted: [TmuxPaneID] = []

        var currentDoneAt: [TmuxPaneID: Date] = [:]
        var currentUnseen: Set<TmuxPaneID> = []

        for (paneID, info) in infos {
            if let doneAt = info.doneAt {
                currentDoneAt[paneID] = doneAt
            }
            if info.state == .unseen {
                currentUnseen.insert(paneID)
            }

            if hasBaseline {
                let hasNewDoneAt: Bool
                if let doneAt = info.doneAt {
                    if let prev = knownDoneAt[paneID] {
                        hasNewDoneAt = doneAt > prev
                    } else {
                        hasNewDoneAt = true
                    }
                } else {
                    hasNewDoneAt = false
                }

                let newlyUnseen = info.state == .unseen && !knownUnseenPanes.contains(paneID)
                if hasNewDoneAt || (newlyUnseen && info.isDone) {
                    newlyCompleted.append(paneID)
                }
            }
        }

        knownDoneAt = currentDoneAt
        knownUnseenPanes = currentUnseen
        hasBaseline = true

        return newlyCompleted.sorted()
    }

    mutating func reset() {
        knownDoneAt.removeAll()
        knownUnseenPanes.removeAll()
        hasBaseline = false
    }
}

/// Decides whether a newly blocked pane should raise a local notification:
/// yes when the app is backgrounded, when another session is presented, or
/// when the blocked pane is not the one on screen. The one case with no
/// alert is the user already looking at the pane that blocked.
struct TmuxAgentBlockedAlertPolicy: Equatable, Sendable {
    var isAppActive: Bool
    var isSessionPresented: Bool
    var viewedPaneID: TmuxPaneID?

    func shouldNotify(paneID: TmuxPaneID) -> Bool {
        guard isAppActive, isSessionPresented else { return true }
        return paneID != viewedPaneID
    }
}

/// Attention model for a blocked agent needing user input.
struct TmuxBlockedAgentAttention: Equatable, Sendable {
    let paneID: TmuxPaneID
    let windowID: TmuxWindowID
    let windowName: String?
    let currentCommand: String
    let agent: AgentIdentity?

    var title: String {
        if let agent {
            return "\(agent.glyph) \(agent.displayName) needs input"
        }
        return "Agent needs input"
    }

    var location: String {
        if let windowName, !windowName.isEmpty {
            return "in \(windowName)"
        }
        return "in pane \(paneID.rawValue)"
    }
}

