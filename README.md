# Ant Tower Defense

Ant Tower Defense is a Roblox Luau tower-defense project built with Git, GitHub,
Rojo, Team Create, Rokit, StyLua, and Selene.

## Project status

The project is in structured pre-production. The complete game specification has
been converted into a long-horizon roadmap made of small, independently
verifiable work packets. Gameplay implementation should follow that roadmap in
order. Phases 00–11 are complete; Gate A passed on 2026-08-26 and the Phase
07–09 exit gates passed on 2026-08-27. Phase 10 Packets 10.1–10.4 implement
the server-owned defender-base runtime, exact-once leak damage, bounded reliable
recovery, world-space base presentation, and one fail-closed defeat path into
Results. Phase 11 Packets 11.1–11.6 add the authenticated finite authored-wave
runtime, exact server-time scheduler, per-origin ownership and outcomes,
difficulty composition, strict-majority skip voting, and bounded full-state
client recovery. Its deterministic `742`-case/`56`-suite local gate, all four
structural builds, exact unsaved two-client Match Studio scenarios, and one
consolidated review passed on 2026-08-28. Every material review finding was
resolved. Exact-final-SHA CI is cited at handoff rather than through a
self-referential evidence commit.

Production networking contains ten Match-only reliable endpoints and six
client-request rate policies. `Enemies`, `Assets`, `Maps`, `Difficulties`,
`Waves`, and difficulty-specific `Economy` rules remain empty production
catalogs, so the Wave runtime is production-dormant until authenticated content
exists. Healthy finite completion deliberately leaves MatchLifecycle in
`WaveActive`; victory, rewards, Results UI, economy balances, and all Phase 12
systems remain unbegun. Phase 12 is next.

- [Detailed development roadmap](docs/DEVELOPMENT_PLAN.md)
- [Game design decisions](docs/GAME_DESIGN.md)
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
6. Run `rojo serve`.
7. Open the development place in Roblox Studio.
8. Connect through the Rojo plugin.

## Development commands

- Install tools: `rokit install`
- Start combined Studio synchronization: `rojo serve`
- Start lobby-only synchronization: `rojo serve lobby.project.json`
- Start match-only synchronization: `rojo serve match.project.json`
- Format source and tests: `stylua src tests`
- Check formatting: `stylua --check --verify src tests`
- Validate Selene configuration: `selene validate-config`
- Lint source and tests: `selene src tests`
- Run deterministic headless tests: `lune run tests/run.luau`
- Build and inspect all production/test projects: `lune run tests/verify-builds.luau`
- Build the combined project: `rojo build default.project.json -o build.rbxlx`
- Build the lobby project: `rojo build lobby.project.json -o lobby.rbxlx`
- Build the match project: `rojo build match.project.json -o match.rbxlx`
- Build the isolated test project: `rojo build test.project.json -o test.rbxlx`

Every implementation packet must format and lint changed Luau code, build its
applicable Rojo project, and describe any required Roblox Studio testing.

`test.project.json` is build-only and has no place binding. Test specs,
fixtures, support modules, negative controls, and Lune never appear in Default,
Lobby, or Match builds; the structural verifier enforces this boundary.
`tests/studio` contains three manual runtime-regression harness sources and one
default-deny Edit-mode authoring command. None is mapped into any of the four
projects.

The default project intentionally contains all source layers for combined
development inspection. Use the lobby or match project for role-isolated Studio
testing once place-specific runnable code exists.
