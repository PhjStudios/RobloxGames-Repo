# Ant Tower Defense

Ant Tower Defense is a Roblox Luau tower-defense project built with Git, GitHub,
Rojo, Team Create, Rokit, StyLua, and Selene.

## Project status

The Playable Local Match (historical Phases 14–18), Persistent Lobby Loop
(Phases 19–23), and Squad Travel Loop (Phases 24–28) outcomes are complete. The
clean Content and Onboarding baseline is commit
`fe48b9fe2a9b597d6d169530877465654c8c4e96`; it passed `1,419` headless tests,
all four isolated builds, and the authorized private-staging Lobby/Match travel
loop. Production was not tested or changed.

Content and Onboarding combines historical Phases 29–33 and is complete on
`codex/content-onboarding`. The implementation adds the `Backyard Garden`
release map, four distinct three-level towers, six readable enemy roles, exact
20/30/40-wave Easy/Normal/Hard campaigns, seeded unbounded Endless play in the
existing authoritative runtime, difficulty-specific exactly-once rewards, and
a persistent server-observed onboarding journey across Lobby and Match.
Existing graybox/local, tower, enemy, banner, ticket, inventory, first-clear,
and result identifiers remain compatible; the graybox/local pair is a hidden,
non-rewarding direct-development fallback.

The private staging map and playable templates were authored under the bounded
Team Create roots after an exact identity check. The consolidated review is
clean, formatting/lint and all four builds passed, and current headless coverage
is `1,486/1,486`: its one full run found two stale expectations after
`1,484/1,486`, then only those affected specs passed `15/15` with the affected
Test build. Consolidated private-staging Studio sessions passed solo mobile
touch/camera/gameplay and four-client Garden integration; the final authorized
roots contained no scripts or runtime residue. Production remained untouched.
No new staging version was published, no uninstructed first-time-player test is
claimed, and Phase 34 has not begun.

- [Current delivery roadmap](ROADMAP.md)
- [Current contributor workflow](AGENTS.md)
- [Historical detailed development plan](docs/DEVELOPMENT_PLAN.md)
- [Game design decisions](docs/GAME_DESIGN.md)
- [Content and onboarding design lock](docs/CONTENT_ONBOARDING_DESIGN_LOCK.md)
- [Current content balance and reward policy](docs/CONTENT_BALANCE.md)
- [Roblox place and test-environment inventory](docs/PLACE_INVENTORY.md)
- [Verified toolchain baseline](docs/TOOLCHAIN.md)
- [Formatting, linting, and generated-output policy](docs/CODE_STYLE.md)
- [Bootstrap cleanup and Studio smoke-test evidence](docs/BOOTSTRAP_SMOKE_TEST.md)
- [Source layers and runnable-entrypoint rules](docs/SOURCE_LAYOUT.md)
- [Combined, lobby, and match Rojo projects](docs/ROJO_PROJECTS.md)
- [Typed place-role configuration and validation](docs/PLACE_ROLES.md)
- [Studio multi-place gate and live verification](docs/MULTI_PLACE_GATE.md)
- [Typed common service lifecycle contract](docs/SERVICE_LIFECYCLE.md)
- [Typed cleanup utility and ownership contract](docs/CLEANUP.md)
- [Structured logging and environment-context contract](docs/LOGGING.md)
- [Graceful server shutdown contract](docs/GRACEFUL_SHUTDOWN.md)
- [Shared ID and expected-result contracts](docs/IDS_AND_RESULTS.md)
- [Tower, enemy, and symbolic-asset schemas](docs/TOWER_ENEMY_SCHEMAS.md)
- [Map, difficulty, and wave schemas](docs/MAP_DIFFICULTY_WAVE_SCHEMAS.md)
- [Studio map contract, validator, loader, and authoring procedure](docs/MAP_RUNTIME_CONTRACT.md)
- [Match lifecycle, roster, Ready protocol, UI, and four-client evidence](docs/MATCH_LIFECYCLE_READY.md)
- [Phase 09 enemy simulation, replication, rendering, and Studio evidence](docs/ENEMY_SIMULATION.md)
- [Phase 10 defender-base runtime, replication, defeat, and Studio evidence](docs/BASE_RUNTIME.md)
- [Phase 11 authored-wave runtime, difficulty scheduler, replication, and Studio evidence](docs/WAVE_RUNTIME.md)
- [Phase 12 tower runtime, temporary loadout, model contract, and Studio evidence](docs/TOWER_RUNTIME.md)
- [Phase 13 placement preview, server validation, races, and Studio evidence](docs/TOWER_PLACEMENT.md)
- [Economy, banner, and default-settings schemas](docs/ECONOMY_BANNER_SETTINGS_SCHEMAS.md)
- [Whole-configuration validation and bootstrap gate](docs/CONFIGURATION_VALIDATION.md)
- [Phase 04 exit-gate audit](docs/PHASE_04_EXIT_AUDIT.md)
- [Automated test-runner decision and contract](docs/TEST_RUNNER.md)
- [Continuous-integration design and evidence](docs/CONTINUOUS_INTEGRATION.md)
- [Current automated, Studio, device, published, and destructive test matrix](docs/TEST_MATRIX.md)
- [Phase 05 combined exit-gate audit](docs/PHASE_05_EXIT_AUDIT.md)
- [Network protocol and remote-security architecture](docs/NETWORK_PROTOCOL.md)
- [Production remote security checklist](docs/REMOTE_SECURITY_CHECKLIST.md)
- [Unsaved Phase 06 Studio networking regression](docs/NETWORK_SECURITY_STUDIO_REGRESSION.md)
- [Phase 06 and Gate A combined exit audit](docs/PHASE_06_EXIT_AUDIT.md)
- [Project instructions](AGENTS.md)

## Source of truth

- `src/` is authoritative for scripts.
- Roblox Studio and Team Create are authoritative for maps, terrain, models,
  animations, and instances that are not mapped by Rojo.
- Do not make lasting edits to Rojo-managed scripts in Roblox Studio.
- Never use Roblox Script Sync on folders managed by Rojo.

## Code layout

The repository separates shared, lobby-only, match-only, server, and client
responsibilities while later roadmap phases continue to fill those layers:

    src/
      shared/
        config/
        lifecycle/
        logging/
        network/
        types/
        util/
      server/
        common/
        lobby/
        match/
      client/
        common/
        lobby/
        match/
    tests/
      fixtures/
      negative/
      specs/
      studio/
      support/
    docs/

The Lobby and Match are separate places in the same Roblox experience. Separate
role-isolated Rojo projects synchronize them while both consume the shared
source modules.

## Initial setup

1. Install Git, GitHub Desktop, VS Code, Roblox Studio, and Rokit.
2. Clone the repository.
3. Open the repository in VS Code.
4. Run `rokit install`.
5. Run `rojo plugin install`.
6. When Studio work is required, start the correct Rojo project as a managed
   background process and confirm it is ready.
7. Open the matching place in Roblox Studio.
8. Connect Rojo and the built-in Studio MCP once, then reuse those connections.

## Development workflow

Use the risk-based ladder in `AGENTS.md` and selector details in
`docs/TEST_RUNNER.md`. The main entry points are:

- Selected headless specs/groups: `lune run tests/run.luau` with repeated
  `--spec` or `--group` selectors.
- Affected structural build, such as Match:
  `lune run tests/verify-builds.luau --builds-only --project Match`.
- Full headless suite plus all four project builds, once each:
  `lune run tests/verify-builds.luau`.

Run the correct `rojo serve` project only as a managed background process for
Studio validation; check readiness, connect once, reuse it, and stop it
deliberately.

`test.project.json` is build-only and has no place binding. Test specs,
fixtures, support modules, negative controls, and Lune never appear in Default,
Lobby, or Match builds; the structural verifier enforces this boundary.
`tests/studio` contains test-only runtime regression tools and guarded,
default-deny Edit-mode authoring/repair commands. None is mapped into any of the
four projects.

The default project intentionally contains all source layers for combined
development inspection. Use the lobby or match project for role-isolated Studio
testing once place-specific runnable code exists.
