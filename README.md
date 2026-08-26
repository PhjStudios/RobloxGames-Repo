# Ant Tower Defense

Ant Tower Defense is a Roblox Luau tower-defense project built with Git, GitHub,
Rojo, Team Create, Rokit, StyLua, and Selene.

## Project status

The project is in structured pre-production. The complete game specification has
been converted into a long-horizon roadmap made of small, independently
verifiable work packets. Gameplay implementation should follow that roadmap in
order. Phases 04 and 05 are complete, Phase 06 is active, and Packets 06.1–06.5
are complete. The isolated runner executes 200 deterministic cases across 16
suites, the four project structures pass, and the unsaved Lobby, Match, and
two-client Studio regressions pass. Phase 05 retains genuine least-privilege
GitHub workflow evidence; the fresh Phase 06/Gate A audit and its current clean
workflow evidence are the active checkpoint. The lasting production endpoint
registry and production rate-policy list remain empty; no gameplay remote or
Phase 07 system has been added.

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
- [Economy, banner, and default-settings schemas](docs/ECONOMY_BANNER_SETTINGS_SCHEMAS.md)
- [Whole-configuration validation and bootstrap gate](docs/CONFIGURATION_VALIDATION.md)
- [Phase 04 exit-gate audit](docs/PHASE_04_EXIT_AUDIT.md)
- [Automated test-runner decision and contract](docs/TEST_RUNNER.md)
- [Continuous-integration design and evidence](docs/CONTINUOUS_INTEGRATION.md)
- [Current automated, Studio, device, published, and destructive test matrix](docs/TEST_MATRIX.md)
- [Phase 05 combined exit-gate audit](docs/PHASE_05_EXIT_AUDIT.md)
- [Network protocol and remote-security architecture](docs/NETWORK_PROTOCOL.md)
- [Future remote security checklist](docs/REMOTE_SECURITY_CHECKLIST.md)
- [Unsaved Phase 06 Studio networking regression](docs/NETWORK_SECURITY_STUDIO_REGRESSION.md)
- [Project instructions](AGENTS.md)

## Source of truth

- `src/` is authoritative for scripts.
- Roblox Studio and Team Create are authoritative for maps, terrain, models,
  animations, and instances that are not mapped by Rojo.
- Do not make lasting edits to Rojo-managed scripts in Roblox Studio.
- Never use Roblox Script Sync on folders managed by Rojo.

## Planned code layout

The repository is currently a minimal scaffold. The roadmap will gradually
separate shared, lobby-only, match-only, server, and client responsibilities:

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
`tests/studio` contains manual, runtime-only regression harness source and is
not mapped into any of the four projects.

The default project intentionally contains all source layers for combined
development inspection. Use the lobby or match project for role-isolated Studio
testing once place-specific runnable code exists.
