# Ant Tower Defense Roadmap

This is the current delivery roadmap. Phases 00–13 and the Playable Local Match
outcome are complete; the Persistent Lobby Loop has not begun. The detailed
historical packet plan remains useful for requirements and design context, but
delivery now targets playable outcomes.

## Delivery outcomes

1. **Complete: Playable local match — Phases 14–18 plus minimum content from 29–31.**
   Complete authoritative combat, tower management, the match experience,
   victory/defeat/replay, and the vertical-slice gate. Pull forward only the
   minimum real map, tower, enemy, and wave content needed to make that local
   match genuinely playable and testable.
2. **Persistent lobby loop — Phases 19–23.** Add safe profiles, shared UI and
   settings, persistent inventory/loadouts, acquisition, and a coherent lobby.
3. **Squad travel loop — Phases 24–28.** Add parties, physical queues, safe match
   tickets and travel, persistent rewards/return, reconnect, and spectating.
4. **Content and onboarding — remaining Phases 29–33.** Finish the production
   map, tower and enemy rosters, authored waves, Endless mode, and onboarding
   work not already pulled into the playable local match.
5. **Platform, presentation, performance, and analytics — Phases 34–37.** Finish
   cross-platform/accessibility work, game feel, optimization, observability,
   and safe development tooling.
6. **Release candidate — Phases 38–40.** Complete security and resilience review,
   balance and comprehensive QA, then prepare a controlled closed-alpha
   candidate. Publishing still requires explicit approval.

Phases 41–45 remain the post-alpha backlog.

## Delivery model

- Treat each outcome as one coherent stream of implementation and verification.
- Use focused checks while editing, feature verification at meaningful subsystem
  boundaries, and one full milestone gate when the outcome is ready.
- Historical packets remain useful checklists, but packet history no longer
  implies separate prompts, branches, audits, reviews, or full verification
  cycles.
- Preserve server authority, security, cleanup, production/test isolation, and
  meaningful automated and Studio validation throughout each outcome.

See `AGENTS.md` for the active workflow and
`docs/DEVELOPMENT_PLAN.md` for historical phase and packet detail.
