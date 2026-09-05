# Personalization (fork maintenance)

This file exists only on the fork's `main` (github.com/lordhumunguz/remux,
remote `personal`). It tracks the personalization delta against upstream
(github.com/h3nock/remux, remote `origin`) and how to keep it healthy.

This fork is for personal consumption only. Nothing here is ever PR'd back
to upstream; upstream is just a code feed. Every maintenance decision below
optimizes for exactly one thing: cheap, safe syncs.

## Topology

- `origin`: upstream h3nock/remux. Treat as read-only.
- `personal`: the fork. `main` tracks `personal/main` and carries upstream
  plus the personalization commits.
- `upstream-main`: local branch tracking `origin/main`.
  `git diff upstream-main..main` is always the current delta.
- Tags like `personal-2026-09-05` mark checkpoints before each upstream sync.

## Sync procedure

Merge, never rebase. Each conflict is resolved once and stays recorded.

```bash
git fetch origin personal
git merge origin/main        # resolve conflicts
xcodebuild build -project Remux.xcodeproj -scheme Remux \
  -destination 'platform=iOS Simulator,name=iPhone 16,OS=18.5'
# then the focused test gate for touched areas
git tag personal-<date> && git push personal main --tags
```

Tag before merging when the previous checkpoint is old.

## Delta inventory

Personal features and the files that own them. Personal logic lives in
personal files; hooks into shared files are kept minimal because those hunks
are where sync conflicts land.

| Feature | Owned files |
| --- | --- |
| Agent-state protocol (pane marks, badges, urgency ordering, blocked alerts) | `Tmux/TmuxPaneAgentState.swift`, `Tmux/TmuxAgentStateNotifier.swift`, `Ghostty/TmuxAgentStateBadge.swift` |
| Single-seat contract (seat handoff, accordion coordination, clean detach) | `Tmux/TmuxSeatContract.swift`, `Tmux/TmuxResponsiveAccordion.swift`, `SSH/TmuxSeatOccupancyProbe.swift` |
| Project/worktree grouping | `Domain/RemuxProjectGrouping.swift` |
| Agent identity and quick actions (glyphs, snippets, resume commands) | `Domain/AgentIdentity.swift`, `Domain/AgentPromptSnippets.swift` |
| Fleet import (ssh config, Tailscale peers) | `Domain/SSHConfigFileParser.swift`, `Domain/TailscaleStatusParser.swift`, `Domain/ServerImportPlanner.swift`, `App/ServerImportLoader.swift`, `App/ServerImportSheet.swift` |
| Tokyo Night theme, Option-as-Alt, narrow-pane preview skip | inline in `Domain/TerminalSettings.swift`, `Ghostty/GhosttyTerminalResponderView.swift`, `Ghostty/PanePreviewLayout.swift` |

Shared files with personal hooks (expect conflicts here when syncing):
`SessionSwitcherView.swift`, `GhosttySurfaceSelectionSheet.swift`,
`GhosttyTerminalPresentationProjector.swift`, `TmuxTerminalSession.swift`,
`TmuxTerminalScreenAdapter.swift`, `RemuxRootModel.swift`, `RootView.swift`.

The agent-state, seat-contract, and grouping features depend on server-side
conventions from ~/.dotfiles (pane options like `@ai_blocked`, the
`client-attached detach-client` hook, `@responsive_accordion`). On servers
without those dotfiles every feature degrades to upstream behavior.

## Rules

- Never open PRs or issues against h3nock/remux. Never push to `origin`.
  Upstream fixes we make locally stay local; if upstream independently fixes
  the same thing later, the sync conflict resolves in their favor.
- New personalization work goes on short-lived topic branches off the fork's
  `main`, never off upstream.
- If upstream lands an overlapping feature, adopt theirs and drop the local
  hook. The goal is the smallest delta, not the most features. That rule
  exists to shrink merge conflicts, not to be a good citizen.
- Because nothing goes upstream, personal convenience beats upstream
  conventions: keep the fork's own bundle ID, signing, and build numbering,
  and don't contort a change to be "upstreamable".
- After each sync, run the focused tests for the areas the sync touched, not
  the whole suite.
