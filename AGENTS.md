# Remux (personal fork)

This checkout is the lordhumunguz fork of h3nock/remux, for personal
consumption only. Read docs/personalization.md first; it is the source of
truth for the fork's topology, sync procedure, and the delta inventory.

## Fork rules

- Never push to `origin` (its push URL is DISABLED). Never open PRs or
  issues against h3nock/remux. Push only to `personal`.
- Upstream syncs merge `origin/main` into `main`; never rebase the
  personalization stack. Tag a `personal-<date>` checkpoint before syncing.
- New work goes on short-lived topic branches off `main`, one commit per
  feature, then merge with `--no-ff` and delete the branch.
- Keep personalization logic in personalization-owned files (see the delta
  inventory in docs/personalization.md). Minimize hooks into shared files:
  those hunks are where sync conflicts land.
- Several features depend on server-side conventions from ~/.dotfiles
  (tmux pane options `@ai_blocked`, `@claude_working`, `@ai_unseen`,
  `@pane_git_branch`; the `client-attached detach-client` seat hook;
  `@responsive_accordion`). Everything must degrade to upstream behavior on
  servers without those conventions. When in doubt, read the dotfiles repo
  for the exact option names and formats.

## Build and test

- XcodeGen: run `xcodegen generate` after adding/removing files (project.yml
  scans directories) and commit the regenerated pbxproj.
- GhosttyKit lives outside the repo at
  ../ghostty-remux-upstream-rebuild/macos/GhosttyKit.xcframework. If stale or
  missing, run scripts/fetch_ghosttykit.sh.
- Simulator build/test (this machine):
  `xcodebuild -scheme Remux -destination 'platform=iOS Simulator,name=iPhone 16,OS=18.5' build`
  The test target is `RemuxTests` (not RemuxAppTests). Use focused
  `-only-testing:RemuxTests/<Class>` runs while iterating; a full local gate
  only for broad changes.
- Known environment failures on this machine: GhosttyComposerModelStatusMessageTests
  and GhosttyComposerSubmissionControllerTests crash with a malloc error in
  SpeechAnalyzer setup. They fail identically on upstream commits; do not
  chase them as regressions.
- Never pipe a gate through tail/head so the exit code is masked.
- tmux behavior probes only via $HOME/.dotfiles/scripts/tmux/tmux-sandbox.sh;
  never touch a live tmux server.

## Distribution

- Bundle ID `dev.remux.personal`, display name "Remux Dev", signing team
  KUASJDH44X (automatic). Distinct from upstream's TestFlight build so both
  coexist on one phone.
- TestFlight: `scripts/archive_testflight.sh [--upload]` defaults to the
  personal team (REMUX_TEAM_ID overrides). Requires the Apple ID session in
  Xcode Settings > Accounts to be valid and an App Store Connect app record.

## Style

- Commit messages: short imperative, lowercase (e.g. "badge panes with agent
  state"). No AI attribution.
- Match the existing projection/adapter patterns (views read projections;
  logic lives in pure, unit-tested domain types).
