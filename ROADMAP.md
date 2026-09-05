# Ant Tower Defense Roadmap

This is the current delivery roadmap. Phases 00–28, the Playable Local Match,
the Persistent Lobby Loop, and the Squad Travel Loop outcomes are complete.
Squad Travel passed its final local gate, isolated Studio verification, and a
private published-client validation in the dedicated staging experience.
Production was neither tested nor modified. Content and Onboarding combines
historical Phases 29–33 on `codex/content-onboarding` and is complete. Its
verified clean baseline commit is `ddd01c9c0d459d91639c122c5ae784c1e59608c3`:
historical cumulative coverage `1,486/1,486`, all four builds, a clean review,
and bounded private-staging solo/mobile and four-client Studio checks. That
baseline gate was not rerun merely to begin this outcome.

Platform, Presentation, Performance, and Analytics has delivered its repository
implementation on `codex/platform-hardening`. Local milestone verification is
complete: clean consolidated review, cumulative `1,601/1,601` headless coverage,
formatting/lint and all four builds passed. The full gate ran once; two
ReadyController cases with stale English expectations were resolved by a
test-only correction and affected-suite verification. The delivery branch is
`codex/platform-hardening`.
Current Lobby geometry/input evidence is Studio-emulated; it does not complete
physical-device, sustained controller analog, console, or published full-loop
acceptance. Console hardware and human translation are conditional gates before
advertising console or another language. Owned-audio listening, independent
newcomer and
external analytics/dashboard acceptance remain separate gates. No new version
was published and no destination was configured. Work stops before Phase 38.
The detailed historical packet plan
remains useful for requirements and design context, but delivery targets
playable outcomes.

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
4. **Complete: Content and onboarding — Phases 29–33.** The
   additive content-v1 implementation selects the server-validated `Backyard
   Garden` map and Easy, Normal, Hard, or Endless difficulty from authenticated
   tickets while retaining the hidden non-rewarding graybox/local development
   fallback. It provides four strategic tower roles, six enemy roles, exact
   20/30/40-wave campaigns with bosses every ten waves, and lazy deterministic
   Endless generation with bounded runtime work and terminal rewards. Profile
   schema v6 supplies the resumable server-observed Lobby-to-Match tutorial,
   deterministic Dart/Bombardier starter loadout, safe skip, and replay/help
   path. Private staging identity, bounded Team Create authoring, the full
   milestone gate, and consolidated solo/mobile/four-client Studio acceptance
   are recorded in [the design lock](docs/CONTENT_ONBOARDING_DESIGN_LOCK.md).
   Production remained untouched; a new published staging-client run and an
   uninstructed first-time-player test remain separate optional acceptance gates
   if later desired or required.
5. **Implementation and local milestone complete; external acceptance pending: Platform, presentation,
   performance, and analytics — Phases 34–37.** One branch and outcome add the
   localization/message boundary, preference precedence, keyboard/touch/controller
   navigation, client-owned feedback/audio architecture, measured local budgets,
   bounded private analytics/logging, isolated development commands and a
   reproducible read-only balance report. Consult the
   [design lock](docs/PLATFORM_HARDENING_DESIGN_LOCK.md),
   [presentation contract](docs/PRESENTATION.md),
   [performance evidence](docs/PERFORMANCE_BUDGETS.md) and
   [analytics dictionary](docs/ANALYTICS.md). Deterministic, Studio-emulated,
   physical-device, published-client and external-service evidence remain
   distinct. Six Lobby layout classes were checked with Largest text, opaque
   panels, reduced motion, pseudo50 and 75% UI scale; a separate follow-up closed
   the recorded ProfileReadiness header overflow. Keyboard focus/Backspace and
   local controller Ready/placement have bounded observations. Sustained analog
   motion and complete controller upgrade/target/sell acceptance are pending.
   The audio manifest's 18 entries need approved owned assets and listening
   checks; English source and pseudolocalization do not establish another
   language. Console hardware and reviewed translations are required only for
   advertising those additional targets/languages. Private publication, physical
   phones/tablets, independent
   newcomers and Packet 37.6 analytics delivery remain unverified. Full
   acceptance is pending the applicable external criteria; no experience
   platform settings change is authorized, and VR remains deferred. Local
   cumulative coverage is `1,601/1,601` on `codex/platform-hardening`.
6. **Not begun; explicit stop boundary: Release candidate — Phases 38–40.**
   Complete security and resilience review,
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
