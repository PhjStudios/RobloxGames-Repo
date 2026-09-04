# Ant Tower Defense Roadmap

This is the current delivery roadmap. Phases 00–28, the Playable Local Match,
the Persistent Lobby Loop, and the Squad Travel Loop outcomes are complete.
Squad Travel passed its final local gate, isolated Studio verification, and a
private published-client validation in the dedicated staging experience.
Production was neither tested nor modified, and Content and Onboarding has not
begun. The detailed historical packet plan remains useful for requirements and
design context, but delivery now targets playable outcomes.

## Delivery outcomes

1. **Complete: Playable local match — Phases 14–18 plus minimum content from 29–31.**
   Complete authoritative combat, tower management, the match experience,
   victory/defeat/replay, and the vertical-slice gate. Pull forward only the
   minimum real map, tower, enemy, and wave content needed to make that local
   match genuinely playable and testable.
2. **Complete: Persistent lobby loop — Phases 19–23.** Safe profiles, shared UI
   and settings, persistent inventory/loadouts, earn-only acquisition, and a
   coherent lobby now form one player loop.
3. **Complete: Squad travel loop — Phases 24–28.** Server-owned parties,
   physical and accessible queues, bounded match tickets, isolated
   reserved-server travel, authenticated admission, exactly-once persistent
   rewards, safe return, reconnect, and read-only spectating form one coherent
   loop. Private staging clients confirmed real solo and three-player
   reserved-server travel, expected-roster admission, unanimous rematch into a
   fresh match, in-match reconnect with retained state and owner control,
   reward/Gold refresh, and return to Lobby. Timing-, privacy-, and adversarial
   edge cases—including unexpected arrival, the exact 30-second never-arrived
   boundary, late-spectator authority restrictions, stale-route fail-open,
   duplicate reward claims, and canonical ID freshness—were verified by
   deterministic server-authority tests and are not claimed as published-client
   observations.
4. **Not begun: Content and onboarding — remaining Phases 29–33.** Finish the
   production map, tower and enemy rosters, authored waves, Endless mode, and
   onboarding work not already pulled into the playable local match.
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
