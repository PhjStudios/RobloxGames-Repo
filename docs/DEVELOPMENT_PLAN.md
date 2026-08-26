# Ant Tower Defense — Long-Horizon Development Roadmap

## Document purpose

This is the authoritative implementation roadmap for Ant Tower Defense. It
converts the approved design specification into small work packets intended to
be completed across many separate prompts over a long period.

This document is deliberately more granular than a normal milestone list:

- One work packet is normally one implementation prompt.
- A packet may take more than one prompt when Roblox Studio work, manual asset
  creation, publishing, or user approval is required.
- Packets are completed in order unless this document explicitly says they are
  independent.
- A phase is not complete until its exit gate is verified.
- Later phases must not be pulled forward merely because their code looks easy.
- Each phase should leave the game runnable and the repository understandable.

The roadmap is a living document. Numerical balance values, content names, and
art direction may change, but dependency boundaries and security rules should
only change through an explicit architecture decision recorded here.

## Current status

- Roadmap state: active; approved defaults are recorded in `docs/GAME_DESIGN.md`.
- Gameplay state: minimal Rojo scaffold with harmless Studio-only client and
  server bootstraps; temporary example behavior has been removed.
- Current implementation phase: Phase 05 complete; Phase 06 is active.
  Phase 04's separate exit-gate audit also passed on 2026-08-26.
- Completed packets: 00.1 on 2026-08-24; 00.2, 00.3, 01.1, 01.2, 01.3, 02.1,
  02.2, 02.3, 02.4, 03.1, 03.2, 03.3, 03.4, 04.1, and 04.2 on 2026-08-25.
  Packets 04.3, 04.4, 04.5, 05.1, 05.2, 05.3, 05.4, 06.1, and 06.2 completed on
  2026-08-26.
- Current checkpoint: Packet 06.2 is complete; Packet 06.3 is next but not
  begun. The current deterministic suite passes 128 cases across eleven suites,
  all four structural builds pass, and the lasting production registry remains
  empty. No gameplay remote or Phase 07 system has begun. Phase 06 and Gate A
  remain open.
- Publishing state: the user authorized and completed the Packet 02.4 Match-place
  creation; no additional publishing is authorized.

## Approved product foundation

The game is a cooperative Roblox tower-defense experience with:

- A lobby place and a separate match place in one Roblox experience.
- Solo, friends-only, and public squad formation.
- Physical queue squares where the first entrant becomes captain.
- Captain-controlled map and difficulty selection.
- A five-tower equipped loadout and a persistent tower inventory.
- Persistent Gold used in the lobby.
- Match-only Battle Cash used for placements and upgrades.
- Server-authoritative enemies, combat, currencies, gacha, and rewards.
- Fixed map-authored enemy routes from an ant nest to a defender base.
- Ready checks, timed waves, five-second early-clear intermissions, skip voting,
  boss waves, multiple difficulties, and true Endless mode.
- Translucent placement previews, range indicators, server-validated placement,
  tower rotation, targeting modes, upgrades, and selling.
- Chest/gacha acquisition with disclosed odds, pity support, duplicates, and
  future merge compatibility.
- Cross-platform UI for mouse/keyboard, touch, and gamepad.
- Accessibility, performance, analytics, security, data resilience, and testing
  treated as product requirements rather than final polish.

## Non-negotiable engineering rules

1. `src/` is the lasting source of truth for Luau scripts.
2. Studio and Team Create remain authoritative for maps, terrain, models,
   animations, and unmapped instances.
3. The client requests actions; the server decides outcomes.
4. Clients never decide damage, costs, inventory ownership, gacha results,
   readiness membership, wave completion, base health, victory, or rewards.
5. Every client-triggered server operation receives type, range, context,
   permission, and rate-limit validation.
6. Persistent mutations use idempotent transaction identifiers where duplicate
   processing could create currency or inventory.
7. Secure profile or match information is never trusted from teleport data.
8. New maps, ordinary enemies, ordinary towers, waves, and difficulties should
   be added through definitions and authored assets, not copied gameplay loops.
9. No phase ends with knowingly broken formatting, lint, build, or relevant
   automated tests.
10. No game publishing, monetization enablement, or production-data migration
    occurs without explicit user approval.
11. Never commit secrets, API keys, cookies, passwords, or environment files.
12. Existing user work is preserved; unrelated dirty-tree changes are not
    overwritten.

## Currency and terminology contract

- **Gold:** persistent lobby currency. It pays for chests and future persistent
  progression. It never appears as spendable tower money during a match.
- **Battle Cash:** match-scoped currency. It pays for tower placement and
  upgrades, resets every match, and is not awarded as persistent currency.
- **Tower definition:** immutable design data shared by all copies of one tower.
- **Unit record:** a persistent player-owned copy of a tower definition.
- **Placed tower:** the match-scoped server entity created from an equipped unit.
- **Captain:** first valid player in a queue square; controls queue configuration.
- **Party:** social grouping that exists independently of a physical queue.
- **Squad:** players currently committed to one queue/match.
- **Match ticket:** short-lived, server-created record that identifies the
  expected roster and selected match configuration.

## Recommended defaults to retain until a balance review

- Maximum match size: 4 players.
- Equipped loadout: 5 towers.
- Difficulties: Easy 20 waves, Normal 30 waves, Hard 40 waves, Endless unlimited.
- Boss cadence: every 10 waves.
- Early-clear intermission: 5 seconds.
- Initial ready timeout: 45 seconds.
- Skip threshold: strict majority of current active players.
- Sell refund: 70% of the placed tower's total Battle Cash investment.
- Battle economy: individual Battle Cash plus team wave stipends.
- Standard target modes: First, Last, Strongest, Weakest, Closest.
- Queue privacy: Solo, Friends, Public.
- Initial squad formation: same-server queue square.
- Later public matchmaking: cross-server MemoryStore queue.

These are implementation defaults, not immutable balance promises.

## Target experience architecture

The experience will ultimately contain:

1. **Lobby place**
   - Loads profiles.
   - Hosts lobby UI, inventory, loadouts, settings, chests, parties, and queues.
   - Creates match tickets and teleports complete squads.
2. **Match place**
   - Accepts only valid match-ticket rosters.
   - Loads the selected map/difficulty.
   - Runs ready, wave, enemy, tower, economy, result, and reward systems.
   - Offers retry or return-to-lobby flows.
3. **Shared source**
   - Contains immutable content definitions, types, network contracts, and
     utilities used by both places and both execution contexts.

Secure persistent state is held by DataStore-backed server code. Short-lived
cross-server queue, ticket, and active-match routing data can use MemoryStore.
Teleport data carries only an opaque identifier and non-secure presentation
information.

## Planned repository structure

The exact tree will be introduced incrementally. Empty architecture folders
should not be created merely to imitate this diagram.

    docs/
      DEVELOPMENT_PLAN.md
      GAME_DESIGN.md
      CONTENT_BALANCE.md
      TEST_MATRIX.md
      OPERATIONS.md
    src/
      shared/
        config/
          Banners.luau
          Difficulties.luau
          Economy.luau
          Enemies.luau
          Maps.luau
          Towers.luau
          Waves.luau
        lifecycle/
          ServiceLifecycle.luau
        logging/
          EnvironmentContext.luau
          Log.luau
        network/
          Protocol.luau
          RemoteNames.luau
        types/
          ConfigTypes.luau
          MatchTypes.luau
          ProfileTypes.luau
          QueueTypes.luau
        util/
          Cleanup.luau
          Ids.luau
          Result.luau
          TableUtil.luau
          Validation.luau
      server/
        common/
          bootstrap/
          networking/
          services/
            ProfileService.luau
            InventoryService.luau
            SettingsService.luau
        lobby/
          bootstrap/
          services/
            GachaService.luau
            InviteService.luau
            LobbyQueueService.luau
            MatchTicketService.luau
            PartyService.luau
            SafeTeleportService.luau
        match/
          bootstrap/
          services/
            BaseService.luau
            BattleEconomyService.luau
            CombatService.luau
            EnemyService.luau
            MatchService.luau
            PlacementService.luau
            RewardService.luau
            TowerService.luau
            WaveService.luau
      client/
        common/
          bootstrap/
          controllers/
            AudioController.luau
            InputController.luau
            NotificationController.luau
            SettingsController.luau
          ui/
            components/
            theme/
        lobby/
          bootstrap/
          controllers/
            GachaController.luau
            InventoryController.luau
            LobbyController.luau
            PartyController.luau
            QueueController.luau
          ui/
            screens/
        match/
          bootstrap/
          controllers/
            CameraController.luau
            CombatEffectsController.luau
            EnemyRenderController.luau
            MatchHudController.luau
            PlacementController.luau
            TowerSelectionController.luau
          ui/
            screens/
    tests/
      shared/
      server/
      fixtures/
    default.project.json
    lobby.project.json
    match.project.json
    test.project.json

Names may be simplified if implementation proves a layer unnecessary. The
architectural rule is separation of concerns, not maximum folder count.

## Standard workflow for every implementation prompt

Every prompt that completes a work packet should follow this sequence:

1. Read this roadmap, `AGENTS.md`, and the current Git status.
2. Confirm the target packet and its dependencies.
3. Inspect relevant existing files and preserve unrelated changes.
4. State any safe assumptions before implementation.
5. Implement only the packet's bounded scope.
6. Add or update focused tests and validators where applicable.
7. Format changed Luau with `stylua src tests` when both roots exist.
8. Run `stylua --check --verify src tests`.
9. Run `selene validate-config` and `selene src tests`.
10. Run `lune run tests/run.luau`; zero discovery and every failure are fatal.
11. Run `lune run tests/verify-builds.luau` to build and structurally inspect
    Default, Lobby, Match, and Test, including production test exclusion and
    place-role isolation.
12. Inspect status and the complete diff for accidental scope growth, secrets,
    and generated-output residue; remove only exact generated outputs.
13. Run `git diff --check`.
14. Report changed files, test results, and exact Studio testing required.
15. Update roadmap status only when the packet's completion evidence exists.

If Studio work is required, code completion and Studio verification are separate
checkpoints. A phase is not marked complete simply because its code compiles.

## Phase gates

- **Gate A — Foundation:** repository, multi-place layout, lifecycle, definitions,
  tests, and network boundary are stable.
- **Gate B — Graybox vertical slice:** a local match can be readied, defended,
  won/lost, and replayed with placeholder content.
- **Gate C — Persistent player loop:** profile, UI shell, settings, inventory, and
  gacha are safe and usable.
- **Gate D — Lobby-to-match loop:** parties, physical queues, teleports, persistent
  rewards, return, and reconnect behavior work.
- **Gate E — First content complete:** first production map, tower roster, enemy
  roster, authored difficulties, bosses, Endless, and onboarding are complete.
- **Gate F — Platform-ready build:** accessibility, inputs, presentation,
  performance, analytics, security, and resilience pass their audits.
- **Gate G — Closed alpha candidate:** balance, QA, operations, and release gates
  are satisfied.

# Milestone A — Foundation

## Phase 00 — Roadmap review and decision lock

**Objective:** Approve the implementation order and record the few product
decisions that materially alter architecture.

### Packet 00.1 — Roadmap repository documentation

**Status:** Complete — 2026-08-24. Evidence: `README.md` and this roadmap.

- Replace the placeholder README identity with Ant Tower Defense.
- Add this roadmap and planned code structure.
- Confirm that no gameplay code is changed.
- Verify Markdown links and Git diff.

### Packet 00.2 — Product decision register

**Status:** Complete — 2026-08-25. Evidence: `docs/GAME_DESIGN.md`.

- Confirm or change the recommended defaults listed above.
- Decide provisional names for persistent Gold and Battle Cash.
- Confirm whether the first release supports public strangers or only solo/friends.
- Confirm whether Gold will ever be purchasable with Robux.
- Confirm whether duplicate copies are unique unit records or compact copy counts.
- Record decisions in `docs/GAME_DESIGN.md` without implementing them.

### Packet 00.3 — Place and ownership inventory

**Status:** Complete — 2026-08-25. Evidence: `docs/PLACE_INVENTORY.md`. The user
confirmed the Roblox owner as PHJGAMES, Group ID `35420107`.

- Record lobby PlaceId, future match PlaceId, experience owner/group, supported
  platforms, and test-universe strategy.
- Do not store credentials.
- Identify which assets and places must be manually created in Studio.
- Record which place is safe for DataStore API testing.

**Exit gate:** Passed — 2026-08-25. The user approved the roadmap and
architecture-affecting decisions, and the place/ownership inventory is recorded.

## Phase 01 — Toolchain baseline and scaffold cleanup

**Objective:** Establish a trustworthy baseline before adding systems.

### Packet 01.1 — Toolchain verification

**Status:** Complete — 2026-08-25. Evidence: `docs/TOOLCHAIN.md`.

- Run `rokit install` if needed.
- Record actual Rojo, StyLua, and Selene versions.
- Confirm all documented commands work on the empty scaffold.
- Build the current project without changing game behavior.

### Packet 01.2 — Formatting and lint policy

**Status:** Complete — 2026-08-25. Evidence: `docs/CODE_STYLE.md`.

- Add or refine StyLua configuration if the defaults are insufficient.
- Review Selene configuration and enable only rules appropriate for Roblox Luau.
- Document generated/build outputs that must remain untracked.
- Avoid broad formatting of unrelated user work.

### Packet 01.3 — Remove temporary example behavior

**Status:** Complete — 2026-08-25. Evidence:
`docs/BOOTSTRAP_SMOKE_TEST.md`.

- Replace jumping-brick and print-only demonstrations with minimal bootstraps.
- Remove `Example.luau` only after nothing references it.
- Make both client and server boot visibly but harmlessly in development.
- Build and run a Studio smoke test.

**Exit gate:** Passed — 2026-08-25. Client and server booted cleanly in a local
Studio Play test; format, lint, and build succeeded; no temporary gameplay
behavior remained.

## Phase 02 — Multi-place Rojo structure

**Objective:** Separate common, lobby-only, and match-only code before systems are
large enough to make the split risky.

### Packet 02.1 — Source-directory split

**Status:** Complete — 2026-08-25. Evidence: `docs/SOURCE_LAYOUT.md`.

- Introduce `server/common`, `server/lobby`, `server/match` and matching client
  directories.
- Move bootstraps with history-preserving edits.
- Keep shared code in `src/shared`.
- Confirm no place starts both lobby and match services.

### Packet 02.2 — Rojo project definitions

**Status:** Complete — 2026-08-25. Evidence: `docs/ROJO_PROJECTS.md`.

- Keep `default.project.json` as the convenient documented development default.
- Add lobby and match project files.
- Map common plus place-specific code into predictable DataModel folders.
- Ensure unknown Studio-authored instances remain preserved.
- Build each project independently.

### Packet 02.3 — Place identity configuration

**Status:** Complete — 2026-08-25. Evidence: `docs/PLACE_ROLES.md`.

- Add a single shared place-role configuration.
- Detect incorrect project/place pairing and fail clearly in development.
- Avoid scattered raw PlaceIds.
- Add safe placeholders until the match place exists.

### Packet 02.4 — Studio multi-place manual gate

**Status:** Complete — 2026-08-25. Evidence: `docs/MULTI_PLACE_GATE.md`.

- Manually create or identify the match place in the same experience.
- Connect the correct Rojo project to each place.
- Confirm lobby-only code never runs in match and vice versa.
- Publishing requires separate explicit approval.

**Exit gate:** Passed — 2026-08-25. Both isolated place projects build and boot
with common plus only their intended place layer; wrong pairing fails closed.

## Phase 03 — Bootstrap, service lifecycle, and cleanup

**Objective:** Prevent every future system from inventing its own startup order
and connection cleanup.

### Packet 03.1 — Bootstrap lifecycle contract

**Status:** Complete — 2026-08-25. Evidence:
`docs/SERVICE_LIFECYCLE.md`.

- Define service registration, initialization, start, and shutdown stages.
- Reject duplicate service names.
- Make dependency order explicit.
- Provide clear development errors with service context.

### Packet 03.2 — Cleanup utility

**Status:** Complete — 2026-08-25. Evidence: `docs/CLEANUP.md`.

- Implement a small typed cleanup utility for connections, instances, callbacks,
  threads, and nested cleanup containers.
- Add focused tests.
- Use it in bootstraps and controllers.

### Packet 03.3 — Logging and environment context

**Status:** Complete — 2026-08-25. Evidence: `docs/LOGGING.md`.

- Add consistent log categories and development-only verbosity.
- Include place role and server/client context.
- Never log profile contents, teleport access codes, or purchase details.
- Define warn/error behavior without creating a global logging framework.

### Packet 03.4 — Graceful shutdown skeleton

**Status:** Complete — 2026-08-25. Evidence:
`docs/GRACEFUL_SHUTDOWN.md`.

- Add server shutdown hooks.
- Define time-bounded cleanup order.
- Do not add profile saving until ProfileService exists.
- Confirm shutdown does not hang Studio tests.

**Exit gate:** Passed — 2026-08-25. Services start deterministically and clean
up without leaked connections in repeated Studio sessions. Evidence:
`docs/SERVICE_LIFECYCLE.md`, `docs/CLEANUP.md`, `docs/LOGGING.md`, and
`docs/GRACEFUL_SHUTDOWN.md`.

## Phase 04 — Shared types, configuration schemas, and validation

**Objective:** Define content contracts before gameplay systems consume them.

### Packet 04.1 — Shared ID and result types

**Status:** Complete — 2026-08-25. Evidence: `docs/IDS_AND_RESULTS.md`.

- Define branded/string ID conventions for towers, enemies, maps, waves, banners,
  units, queues, matches, and transactions.
- Define success/failure result shapes for expected failures.
- Avoid using arbitrary Instances as persistent or network identifiers.

### Packet 04.2 — Tower and enemy schema

**Status:** Complete — 2026-08-25. Evidence:
`docs/TOWER_ENEMY_SCHEMAS.md`.

- Define required and optional fields.
- Separate immutable content data from runtime state.
- Support future status effects, resistances, attack behaviors, and merge ranks
  without implementing them.
- Validate non-negative values, finite numbers, referenced assets, and unique IDs.

### Packet 04.3 — Map, difficulty, and wave schema

**Status:** Complete — 2026-08-26. Evidence:
`docs/MAP_DIFFICULTY_WAVE_SCHEMAS.md`.

- Define lanes, wave groups, spawn timings, wave deadlines, boss markers, base
  configuration, difficulty modifiers, and reward metadata.
- Support authored finite modes and generated Endless inputs.
- Validate all cross-references.

### Packet 04.4 — Economy, banner, and settings schema

**Status:** Complete — 2026-08-26. Evidence:
`docs/ECONOMY_BANNER_SETTINGS_SCHEMAS.md`.

- Define Battle Cash rules, Gold rewards, sell rate, banner outcomes, pity rules,
  and default settings.
- Require banner probabilities to total 100% within a documented tolerance.
- Define version fields for persistent-facing configurations.

### Packet 04.5 — Configuration validator report

**Status:** Complete — 2026-08-26. Evidence:
`docs/CONFIGURATION_VALIDATION.md`.

- Add a validator that checks all loaded definitions together.
- Produce actionable paths such as `Waves.Easy.10.Groups.2.enemyId`.
- Fail development boot on invalid core configuration.
- Make production failure safe and observable.

**Exit gate:** Passed — 2026-08-26. Empty and synthetic fixture definitions
validated, invalid fixtures failed for the correct stable codes and exact paths,
and no gameplay service requires an untyped configuration table. The fresh
combined-state audit, including 376 assertions in each place and three final
Play/Stop cycles per place, is recorded in `docs/PHASE_04_EXIT_AUDIT.md`.

## Phase 05 — Automated test and continuous-integration foundation

**Objective:** Make pure logic testable without depending entirely on manual
Studio play.

### Packet 05.1 — Test-runner decision and setup

**Status:** Complete — 2026-08-26. Evidence: `docs/TEST_RUNNER.md`.

- Evaluate a lightweight Luau/Roblox-compatible test runner.
- Record the dependency decision before adding third-party code.
- Add `test.project.json` or an equivalent isolated test environment.
- Ensure tests do not ship in production place builds.

### Packet 05.2 — Initial unit-test suite

**Status:** Complete — 2026-08-26. Evidence: `docs/TEST_RUNNER.md`.

- Test cleanup behavior.
- Test definition validation.
- Test ID and result utilities.
- Add deterministic fixtures for towers, enemies, maps, and waves.

The canonical suite contains 76 ordered cases across eight suites. It covers
Cleanup ownership and failure isolation; all current ID, Result, and Validation
contracts; every Phase 04 schema and whole-configuration dependency boundary;
test-only finite and Endless fixtures; exact error codes, paths, related paths,
issue order, and blocked-family order; lasting empty/policy configuration;
authentication, freezing, privacy, malformed roots, and source-load containment.
Three consecutive runs produced byte-identical output. No production source or
lasting catalog changed, and an independent adversarial review found no
unresolved P0, P1, or P2 issue.

### Packet 05.3 — GitHub continuous integration

**Status:** Complete — 2026-08-26. The least-privilege workflow, pinned
bootstrap, genuine formatting, Selene-lint, broken-expectation, and
broken-definition controls, ordinary restoring commits, and final clean GitHub
run are recorded in `docs/CONTINUOUS_INTEGRATION.md`.

- Add a workflow that installs pinned tools.
- Run formatting checks, Selene, tests, and Rojo builds.
- Do not add publishing credentials or deployment.
- Cache only safe tool artifacts.

### Packet 05.4 — Test documentation

**Status:** Complete — 2026-08-26. The authoritative current/deferred test
inventory is `docs/TEST_MATRIX.md`. Its initial 37 records cover all six required
categories with explicit environment, procedure, players/devices, authorization,
external-service/publication, risk, evidence, cleanup, and prerequisite fields.
Formatting, linting, the 76-case suite, four-project verifier, local-link audit,
and independent documentation/security reviews passed with no unresolved P0,
P1, or P2 finding.

- Create `docs/TEST_MATRIX.md`.
- Separate automated, Studio solo, multi-client, published-client, device, and
  destructive-production tests.
- Record currently unavailable or deferred tests and the exact environment,
  authorization, device, or production-safety prerequisite for each one.

**Exit gate:** Passed — 2026-08-26. Deliberate formatting, Selene-lint,
broken-expectation, and broken-definition controls failed through their intended
paths; the restored project passed every local combined-state gate and three
byte-identical consecutive test runs; production builds contain no test code;
and the final Packet 05.4/documentation/audit commit passed the genuine
least-privilege GitHub workflow with zero retained artifacts. Exact evidence is
recorded in `docs/PHASE_05_EXIT_AUDIT.md`. Phase 06 subsequently began with
Packet 06.1.

## Phase 06 — Network protocol and remote-security foundation

**Objective:** Create one audited client/server boundary before feature remotes
proliferate.

### Packet 06.1 — Remote registry

**Status:** Complete — 2026-08-26. The fixed typed registry, empty lasting
production definitions, server-owned parent-last runtime, bounded production-
anchored client lookup, lifecycle/Cleanup integration, role isolation, and
test-only fixtures are implemented. The 106-case suite, four-project verifier,
and targeted architecture/security review passed with no unresolved P0, P1, or
P2 finding. Exact architecture and evidence are in `docs/NETWORK_PROTOCOL.md`.

- Define remote names and direction in shared code.
- Create remotes from one server-owned registry.
- Prevent clients from choosing arbitrary remote or instance paths.
- Separate request, event, and optional response semantics.

### Packet 06.2 — Payload validation

**Status:** Complete — 2026-08-26. The authenticated frozen shared schema API
strictly validates bounded strings/enums, all typed ID families, booleans,
finite numbers/integers, dense arrays, exact-key records, optional values,
exactly-one bounded unions, `Vector2`, `Vector3`, `CFrame`, and opt-in
server-only Instances. One shared validation-work budget contains nested union
attempts; depth, node, field, item, string, enum, and branch bounds fail closed.
The 22 focused boundary/adversarial cases and complete 128-case suite pass, as
does the four-project verifier. Exact architecture and evidence are in
`docs/NETWORK_PROTOCOL.md`. Packet 06.3 is next and has not begun.

- Add reusable validators for strings, enums, IDs, arrays, vectors, CFrames, and
  finite numeric values.
- Impose maximum sizes and depths.
- Reject NaN, infinity, oversized strings, and unexpected keys.

### Packet 06.3 — Server rate limiting

- Implement per-player token buckets or bounded cooldowns.
- Allow action-specific limits.
- Add cleanup on player removal.
- Log aggregate abuse signals without flooding output.

### Packet 06.4 — Request correlation and error contract

- Give mutating requests client-generated request IDs within strict limits.
- Return safe public error codes rather than raw server errors.
- Support pending/success/rejected UI states.
- Do not treat a request ID alone as proof of idempotency.

### Packet 06.5 — Security tests

- Test malformed payloads, spam, unauthorized context, stale IDs, and unexpected
  instances.
- Confirm rejected requests do not partially mutate state.
- Document the checklist future remotes must satisfy.

**Gate A exit:** Phases 00–06 are complete; both places build, definitions validate,
tests run, and all future remotes have an approved boundary.

# Milestone B — Graybox Match Vertical Slice

## Phase 07 — Map contract and graybox battlefield

**Objective:** Establish the Studio-authored map interface with one deliberately
simple test battlefield.

### Packet 07.1 — Map tag and attribute contract

- Define tags for enemy spawn, path nodes, defender base, placement zones,
  no-placement zones, camera anchors, and map bounds.
- Define required attributes such as lane ID and node order.
- Document naming and ownership rules for Studio authors.

### Packet 07.2 — Runtime map validator

- Detect missing, duplicate, disconnected, unordered, or invalid path markers.
- Validate base, spawn, bounds, and placement zones.
- Return a structured report before a match starts.

### Packet 07.3 — Graybox map loader

- Load or select one test map without production art.
- Build lane-distance data from authored markers.
- Expose safe read-only map queries to match services.
- Clean up a loaded map between test matches.

### Packet 07.4 — Studio graybox authoring gate

- Create one spawn-to-base path with at least one bend.
- Create land placement and no-placement regions.
- Add camera anchor and match spawn locations.
- Verify the map validator in Studio.

**Exit gate:** The graybox map loads, validates, unloads, and contains no lasting
Rojo-managed script edits in Studio.

## Phase 08 — Match lifecycle and initial ready check

**Objective:** Make the match an explicit server-owned state machine.

### Packet 08.1 — Match state machine

- Implement Loading, ReadyCheck, PreWave, WaveActive, Results, and Closing states.
- Define legal transitions and reject illegal ones.
- Add match-scoped cleanup.
- Replicate a minimal state snapshot.

### Packet 08.2 — Roster and participant state

- Track active, disconnected, returned, and spectator participants by UserId.
- Keep match identity separate from Player instances.
- Define current-player thresholds for votes and readiness.

### Packet 08.3 — Ready protocol

- Add a 45-second server timer.
- Validate one readiness state per active participant.
- Start early when all active players are ready.
- Return or remove unready players at timeout once teleport flow exists; use a
  safe local test outcome until then.

### Packet 08.4 — Minimal ready UI

- Show participant readiness and countdown.
- Disable duplicate Ready submissions.
- Handle server rejection and state changes.
- Provide keyboard, touch, and gamepad activation.

### Packet 08.5 — Multi-client ready test

- Test all ready, timeout, disconnect during ready, reconnect placeholder, and
  zero-ready cancellation with Server & Clients.

**Exit gate:** Four simulated clients cannot desynchronize or deadlock the ready
state.

## Phase 09 — Server enemy simulation and client rendering

**Objective:** Move placeholder ants along fixed lanes with server-owned progress
and smooth client visuals.

### Packet 09.1 — Enemy runtime model

- Define runtime enemy ID, definition ID, lane, path progress, health, status
  container, spawn time, and lifecycle state.
- Store authoritative state outside the visual model.

### Packet 09.2 — Fixed-path movement

- Advance enemies by distance and speed on the server.
- Convert path distance to world CFrame.
- Handle corners, large frame times, slows, and reaching the endpoint.
- Avoid PathfindingService for authored tower-defense lanes.

### Packet 09.3 — Spawn/despawn replication

- Replicate compact spawn, correction, state-change, and despawn messages.
- Define how late-joining clients receive a snapshot.
- Keep authoritative health and progress on the server.

### Packet 09.4 — Client enemy renderer

- Create placeholder enemy visuals.
- Interpolate movement locally and correct drift smoothly.
- Clean up visuals on despawn, match reset, and streaming changes.

### Packet 09.5 — Enemy simulation tests

- Test deterministic travel time, multiple speeds, multiple lanes, end-of-path,
  and mass cleanup.
- Run a Studio stress sample with increasing enemy counts.

**Exit gate:** Placeholder enemies reach the base consistently and render smoothly
without one permanent movement loop per model.

## Phase 10 — Defender base and leak damage

**Objective:** Add the loss condition and trustworthy base feedback.

### Packet 10.1 — Base runtime service

- Initialize max/current health from difficulty and map configuration.
- Apply fixed enemy leak damage on endpoint arrival.
- Clamp health and emit one defeat transition.
- Reject damage outside active match states.

### Packet 10.2 — Base replication and world display

- Replicate current and maximum health.
- Add a world-space bar anchored to the Studio-authored base marker.
- Add low-health and damage events without relying only on sound.

### Packet 10.3 — Defeat transition

- Stop future spawns.
- Resolve active enemies and tower inputs safely.
- Transition once to Results.
- Preserve enough match data for the future result screen.

### Packet 10.4 — Base edge-case tests

- Test simultaneous leaks, overkill, boss leak, zero health, late damage, and
  cleanup during defeat.

**Exit gate:** Leaks cause deterministic base damage and exactly one defeat.

## Phase 11 — Authored waves and difficulty scheduler

**Objective:** Run deterministic finite-mode waves with the approved timer rule.

### Packet 11.1 — Wave definition fixtures

- Create small test definitions for Easy-like and overlap scenarios.
- Support groups, counts, intervals, delays, lanes, and boss flags.
- Validate that all groups fit intentionally within or beyond the wave deadline.

### Packet 11.2 — Wave scheduler

- Spawn groups according to server time.
- Track scheduled, spawned, alive, and leaked enemies.
- Never infer completion only from a client or a visual folder.

### Packet 11.3 — Early-clear and deadline rules

- Start a five-second intermission after all scheduled enemies are gone.
- Start the next wave at deadline when old enemies remain.
- Preserve old enemies and correctly attribute their lifecycle.
- Prevent double-starts at the early-clear/deadline boundary.

### Packet 11.4 — Difficulty runtime

- Select test difficulty.
- Apply starting wave count, base health, starting cash placeholder, and enemy
  modifiers from configuration.
- Expose current/total wave and boss metadata.

### Packet 11.5 — Skip-vote system

- Make votes match-scoped and server-authoritative.
- Require a strict majority of active participants.
- Recompute threshold on disconnect.
- Prevent votes before the configured minimum time.

### Packet 11.6 — Wave scheduler tests

- Test empty waves, early clear, exact deadline, overlap, disconnect voting,
  final wave, defeat mid-spawn, and cleanup.

**Exit gate:** A test finite difficulty runs from wave one through its final wave
with correct overlaps and no duplicate transitions.

## Phase 12 — Tower definitions and temporary match loadout

**Objective:** Introduce tower runtime contracts before placement and combat.

### Packet 12.1 — Test tower definitions

- Define one single-target tower, one splash-capable fixture, and one support/economy
  fixture placeholder.
- Provide multiple upgrade levels without production balance promises.
- Validate costs, cooldowns, range, footprint, target filters, and placement cap.

### Packet 12.2 — Runtime tower model

- Define placed-tower ID, owner UserId, definition ID, unit reference placeholder,
  level, target mode, position, total investment, and cooldown state.
- Keep persistent unit data out of match mutation.

### Packet 12.3 — Temporary development loadout

- Give test players a server-created loadout while ProfileService does not exist.
- Clearly mark the hook as temporary and isolated.
- Prevent clients from inventing a tower definition ID.

### Packet 12.4 — Tower asset contract

- Define required model primary part/pivot, footprint, aiming joint or pivot,
  muzzle markers, animation hooks, and upgrade visual variants.
- Allow graybox parts while production assets do not exist.

**Exit gate:** Valid test towers and runtime instances can be created from a
server-approved temporary loadout.

## Phase 13 — Tower placement preview and server validation

**Objective:** Deliver accurate cross-platform placement without trusting the
client's chosen position.

### Packet 13.1 — Placement query API

- Query placement zones, exclusions, map bounds, and existing tower footprints.
- Use one authoritative footprint rule shared by preview and server validation.
- Define surface categories such as land, elevated, and future water.

### Packet 13.2 — Desktop placement preview

- Select a tower from the temporary hotbar.
- Raycast through an explicit filter.
- Render a translucent ghost and flat range indicator.
- Show valid, invalid, unaffordable, and capped states distinctly.
- Support cancel and deliberate rotation input.

### Packet 13.3 — Touch and gamepad placement

- Touch uses tap-to-position followed by a separate confirm button.
- Gamepad uses a reticle or virtual cursor with explicit confirm/cancel.
- Camera gestures cannot accidentally confirm placement.
- Input hints follow the current preferred device.

### Packet 13.4 — Authoritative placement request

- Validate loadout membership, definition ID, Battle Cash placeholder, phase,
  position, zone, map bounds, footprint, ownership, type cap, and total cap.
- Recompute validity from the server's world state.
- Create the placed tower only after every check passes.
- Return a safe reason for expected rejection.

### Packet 13.5 — Placement race and exploit tests

- Send simultaneous overlapping requests from multiple clients.
- Test NaN/infinite CFrames, outside-map positions, stale preview state, spam,
  nonexistent towers, and insufficient funds.
- Verify that only one overlapping placement succeeds.

**Exit gate:** All three input families can place valid towers, while malformed or
stale requests cannot create or charge for a tower.

## Phase 14 — Target acquisition and authoritative combat

**Objective:** Make towers select and damage enemies predictably at scale.

### Packet 14.1 — Target-query layer

- Query only alive, valid enemy runtime entities.
- Filter by range, lane/type permissions, and future stealth/flying rules.
- Define stable tie-breakers using progress, health, distance, and runtime ID.

### Packet 14.2 — Standard target modes

- Implement First, Last, Strongest, Weakest, and Closest.
- Specify whether Strongest compares current or maximum health and record it.
- Add deterministic tests for ties and target invalidation.

### Packet 14.3 — Central combat scheduler

- Schedule attacks centrally or in bounded buckets rather than one endless loop
  per tower.
- Use server time for cooldowns.
- Prevent attack-speed changes from creating free duplicate attacks.
- Stop attacks outside active wave states.

### Packet 14.4 — Damage pipeline

- Apply server-owned direct damage.
- Define damage event records with source owner, placed tower, enemy, amount,
  attack type, and flags.
- Clamp overkill and resolve death once.
- Add extension points for splash, slow, damage-over-time, and armor without
  implementing every behavior.

### Packet 14.5 — Attack replication and placeholder presentation

- Replicate target/attack events compactly.
- Rotate visual tower parts locally toward targets.
- Play placeholder hitscan/projectile effects locally.
- Never use a client hit report to apply damage.

### Packet 14.6 — Combat correctness tests

- Test range edges, cooldown boundaries, target death, overlapping waves,
  simultaneous damage, overkill, and match cleanup.

**Exit gate:** A placed test tower can kill enemies consistently, and server
outcomes do not depend on frame rate or client effects.

## Phase 15 — Upgrades, selling, targeting controls, and Battle Cash

**Objective:** Complete the strategic tower-management loop.

### Packet 15.1 — Battle Cash service

- Initialize individual balances from difficulty.
- Expose read-only balance snapshots/deltas to each client.
- Add atomic earn/spend checks.
- Record source and sink reasons for future analytics.

### Packet 15.2 — Damage income and wave stipends

- Credit the placed tower's owner from eligible damage.
- Cap credited damage at actual health removed.
- Award team wave stipends once.
- Define no-cash enemy and shield extension points.

### Packet 15.3 — Upgrade transaction

- Validate owner, placed-tower ID, active state, next level, and funds.
- Spend and upgrade as one server operation.
- Update stats without resetting cooldown unfairly.
- Notify clients of the precise changed fields.

### Packet 15.4 — Sell transaction

- Validate ownership and sellable state.
- Refund 70% of total investment using one documented rounding rule.
- Remove the tower and free placement capacity atomically.
- Prevent double-sell and sell-after-match races.

### Packet 15.5 — Target-mode transaction

- Validate the selected mode against the tower's supported modes.
- Cycle modes consistently across devices.
- Retarget promptly without granting an extra attack.

### Packet 15.6 — Tower selection panel

- Show owner, level, damage, cooldown, DPS, range, target mode, placement count,
  total investment, next-level deltas, upgrade cost, and sell value.
- Owners receive controls; other players receive inspection-only UI.
- Show selected tower range and clear selection safely.

### Packet 15.7 — Economy and transaction tests

- Test exact funds, insufficient funds, spam, simultaneous upgrade/sell, owner
  disconnect, non-owner actions, max level, rounding, and duplicate requests.

**Exit gate:** Players can earn, place, upgrade, retarget, and sell without
currency duplication or unauthorized actions.

## Phase 16 — Match HUD, camera, and core input experience

**Objective:** Make the graybox match understandable without using developer
output.

### Packet 16.1 — HUD information architecture

- Top: base health, current/total wave, deadline/intermission timer, difficulty,
  and enemies alive.
- Bottom: five-slot tower hotbar, costs, cooldown/availability, and Battle Cash.
- Context: ready panel, skip vote, tower panel, notifications, and boss banners.
- Ensure modal layers do not fight the Roblox top bar or chat.

### Packet 16.2 — Responsive HUD components

- Use safe insets, relative layouts, automatic sizing, and bounded text sizes.
- Define small-phone, tablet/desktop, and ten-foot layouts.
- Avoid permanent information in mobile thumbstick/jump zones.

### Packet 16.3 — Match camera

- Define default camera bounds and zoom appropriate for the graybox map.
- Preserve Roblox character movement where desired.
- Prevent camera from entering invalid geometry.
- Provide reset/focus-base actions and future spectate hooks.

### Packet 16.4 — Input action map

- Define semantic actions for hotbar select, cancel, rotate, upgrade, sell,
  retarget, skip, ready, focus, and menu back.
- Provide mouse/keyboard, touch, and gamepad bindings.
- Dynamically update input hints.

### Packet 16.5 — Enemy and base health presentation

- Add pooled or managed enemy health bars.
- Always show bosses; apply settings-ready culling rules to ordinary enemies.
- Include non-color health changes and shield placeholders.

### Packet 16.6 — Device smoke test

- Test supported aspect ratios, touch gestures, controller navigation, and
  keyboard-only use with Device and Controller Emulators.

**Exit gate:** A first-time tester can understand and operate the match on every
supported input family without reading source code.

## Phase 17 — Local victory, defeat, results, and replay

**Objective:** Close the graybox match loop before persistence and teleports.

### Packet 17.1 — Victory resolution

- Win when the final finite wave has finished spawning and every relevant enemy
  is resolved.
- Stop all further match mutations.
- Build a server-owned result summary once.

### Packet 17.2 — Result statistics

- Track waves completed, damage, placements, upgrades, Battle Cash earned/spent,
  base health remaining, elapsed time, and disconnect status.
- Treat statistics as informational; do not let clients award from them.

### Packet 17.3 — Result screen

- Show Victory/Defeat, difficulty, map, wave, provisional Gold preview, and
  player contribution.
- Provide Replay Local Test and Exit controls.
- Make clear that persistent rewards are not active yet.

### Packet 17.4 — Match reset

- Clean enemies, towers, UI state, votes, timers, effects, and connections.
- Reload the graybox map and restart ready state in Studio.
- Verify that the second run behaves like the first.

### Packet 17.5 — Repeated-session soak

- Play or simulate many consecutive short matches.
- Watch instance counts, connections, memory, and state transitions.

**Exit gate:** The graybox match can be won, lost, reset, and replayed repeatedly.

## Phase 18 — Graybox vertical-slice audit

**Objective:** Freeze and inspect the gameplay foundation before adding persistent
meta systems.

### Packet 18.1 — Architecture review

- Check that Map, Match, Wave, Enemy, Base, Placement, Tower, Combat, and Economy
  services own distinct responsibilities.
- Remove temporary cross-service access that bypasses interfaces.
- Record approved architecture decisions.

### Packet 18.2 — Security review

- Re-run malformed payload and unauthorized-action tests.
- Confirm all damage, funds, and state transitions remain server-owned.
- Review world-instance trust assumptions.

### Packet 18.3 — Gameplay usability test

- Give the graybox build to testers without instructions.
- Record placement confusion, HUD confusion, pacing problems, and input failures.
- Fix foundational interaction problems only; do not add production content.

### Packet 18.4 — Gate B regression suite

- Formalize a repeatable vertical-slice test checklist.
- Require solo, four-player, defeat, victory, overlap, and skip scenarios.

**Gate B exit:** The placeholder match is genuinely playable and structurally
stable enough to connect to persistent player data.

# Milestone C — Persistent Player Loop

## Phase 19 — Profile schema, persistence, and migrations

**Objective:** Safely store Gold, units, loadout, pity, settings, progression, and
transaction history.

### Packet 19.1 — Profile schema decision

- Finalize unique unit records versus compact copy counts.
- Define profile version, Gold, owned units, loadout, pity, settings, tutorial,
  statistics, first clears, and bounded transaction records.
- Estimate serialized size and growth.

### Packet 19.2 — Default profile and migration framework

- Create a valid starter profile with at least one usable tower and loadout.
- Apply sequential version migrations.
- Preserve unknown future-safe data only when explicitly intended.
- Test old, missing, malformed, and newest profiles.

### Packet 19.3 — Session-protected loading

- Load on the server with protected calls and retry/backoff.
- Prevent concurrent sessions from overwriting one another.
- Expose Loading, Ready, Failed, and Releasing states.
- Keep blocked players out of mutating systems.

### Packet 19.4 — Autosave and release

- Save periodically within Roblox budget constraints.
- Save on important persistent transactions.
- Release on player leave and bounded server shutdown.
- Do not retry indefinitely during shutdown.

### Packet 19.5 — Safe failure experience

- Display a clear retry/leave screen when profile load fails.
- Never fall back to a writable blank profile.
- Prevent queue, gacha, inventory mutation, or reward claims while unsafe.

### Packet 19.6 — Test-store strategy

- Use an isolated test scope or test universe.
- Document Studio API-access risks.
- Add wipe/migration tools only for explicitly named test users and test scopes.
- Never expose a broad production wipe command.

**Exit gate:** Profiles survive rejoin, version migration, simulated failures, and
concurrent-session tests without silent reset.

## Phase 20 — Shared UI shell, settings, and notifications

**Objective:** Establish reusable UI foundations before inventory and gacha
screens multiply.

### Packet 20.1 — UI theme tokens

- Define typography, spacing, colors, rarity styles, corners, strokes, shadows,
  selection visuals, and animation timings.
- Avoid encoding meaning through color alone.
- Separate design tokens from screen logic.

### Packet 20.2 — Screen and modal navigation

- Define one active primary screen and a managed modal stack.
- Support Back/Escape/ButtonB consistently.
- Restore gamepad selection when modals close.
- Prevent click-through and duplicate screen instances.

### Packet 20.3 — Notification system

- Support informational, success, warning, and error toasts.
- Deduplicate repeated network errors.
- Queue without covering critical match HUD.
- Respect reduced motion.

### Packet 20.4 — Settings model and persistence

- Implement master, music, SFX, UI volume, camera shake, damage numbers, enemy
  health bars, other-player effects, low detail, tower range, and UI scale.
- Save persistent preferences through SettingsService.
- Apply client-safe settings immediately and server-relevant preferences only
  through validated requests.

### Packet 20.5 — Roblox accessibility preferences

- Honor preferred text size, preferred transparency, and reduced motion.
- Reflow localized/expanded strings rather than shrinking them unreadably.
- Provide visual equivalents for important sounds.

### Packet 20.6 — UI shell device test

- Test smallest supported phone, common phone, tablet, 16:9 desktop, ultrawide,
  and console safe area.

**Exit gate:** Reusable navigation, modal, notification, theme, and settings
systems work without feature-specific hacks.

## Phase 21 — Persistent inventory and equipped loadout

**Objective:** Replace the temporary match loadout with a secure, usable collection
system.

### Packet 21.1 — InventoryService read model

- Convert profile unit records into a client-safe inventory snapshot.
- Never replicate private transaction history or raw profile tables.
- Send bounded deltas after mutation.

### Packet 21.2 — Equip/unequip transactions

- Validate unit ownership, five-slot limit, supported uniqueness rules, and
  profile readiness.
- Ensure the player can never save an unusable zero-tower loadout accidentally.
- Make repeated requests idempotent or harmless.

### Packet 21.3 — Inventory grid

- Implement responsive virtualized/managed cards if collection size warrants it.
- Show portrait, name, rarity, copy/merge data, favorite/lock, and equipped state.
- Add search, sort, and filters.

### Packet 21.4 — Tower detail panel

- Show combat statistics, role, costs, placement limit, target permissions,
  upgrade preview, description, and acquisition source where appropriate.
- Clearly distinguish persistent merge data from match upgrades.

### Packet 21.5 — Favorite and lock protection

- Save favorite/locked state.
- Require clear confirmation before any future destructive unit action.
- Ensure bulk operations can never consume locked units.

### Packet 21.6 — Match integration

- Snapshot the validated equipped loadout when a match begins.
- Replace the temporary development loadout.
- Refuse invalid or stale profile references safely.

### Packet 21.7 — Inventory tests

- Test duplicate towers, stale unit IDs, migration-created loadouts, rapid equip,
  full slots, disconnect during save, and multiple devices.

**Exit gate:** A saved five-tower loadout controls exactly which towers can be
placed in a match.

## Phase 22 — Chest/gacha and duplicate acquisition

**Objective:** Add a fair, auditable, server-owned tower acquisition loop.

### Packet 22.1 — Banner definitions and odds validator

- Define outcomes, weights, availability, cost, one/ten options, and pity rules.
- Display exact final outcome probabilities.
- Validate totals and impossible pity configurations.

### Packet 22.2 — Server RNG and roll planner

- Generate all outcomes on the server.
- Define pity increment/reset behavior precisely.
- Use deterministic injected RNG in tests and non-predictable server RNG in play.
- Never accept client-proposed outcomes.

### Packet 22.3 — Atomic gacha transaction

- Validate profile readiness, banner availability, policy eligibility, inventory
  capacity, Gold balance, and request ID.
- Deduct Gold, grant units, and update pity as one logical mutation.
- Store a bounded idempotency record so retries cannot double grant.

### Packet 22.4 — One-pull UI

- Show banner, cost, odds/details, pity, confirmation, animation, result, and
  duplicate/new status.
- Allow skipping presentation without skipping the server transaction.

### Packet 22.5 — Ten-pull UI

- Present all outcomes clearly.
- Handle near-capacity behavior deterministically.
- Do not send ten independent spend requests.

### Packet 22.6 — Regional and paid-random policy gate

- Query and cache player policy safely.
- If Gold is purchasable with Robux, block/replace paid random interactions for
  restricted users and disclose all required odds.
- Complete the experience compliance questionnaire before release.
- If Gold is earn-only, still disclose odds and record that policy assumption.

### Packet 22.7 — Gacha failure and exploit tests

- Test duplicate requests, disconnect after spend, server error during save,
  insufficient Gold, unavailable banner, restricted policy, malformed quantity,
  and pity boundaries.

**Exit gate:** One and ten pulls cannot lose currency without a recorded outcome
or duplicate an outcome through retries.

## Phase 23 — Lobby shell and player-facing navigation

**Objective:** Create a coherent lobby experience around the persistent systems.

### Packet 23.1 — Permanent lobby HUD

- Show Gold, player progression placeholder, Play, Inventory, Chests, Collection
  placeholder, Invite, Settings, and notifications.
- Keep future Shop/Quests additions structurally possible but hidden.

### Packet 23.2 — Lobby screen integration

- Integrate settings, inventory, loadout, and gacha into one navigation model.
- Preserve selection and scroll state when appropriate.
- Block mutation screens until profile readiness.

### Packet 23.3 — Lobby world interaction contract

- Define world markers for queue areas, chest station, inventory station, tutorial
  guide, and player spawn.
- UI buttons remain the accessible alternative to walking to stations.

### Packet 23.4 — Loading and first-join experience

- Show data loading before interactive UI.
- Handle first-time, returning, migration, and load-failure states.
- Avoid flashing default currency/inventory before the snapshot arrives.

### Packet 23.5 — Lobby device and respawn test

- Test menu state across character respawn, device switching, Roblox menu open,
  and invitation prompts.

**Gate C exit:** A player can safely load, change settings, manage a saved loadout,
and open chests from a coherent lobby UI.

# Milestone D — Parties, Queues, and Place Travel

## Phase 24 — Party and friend invitation model

**Objective:** Keep social grouping separate from physical queue membership.

### Packet 24.1 — Party state contract

- Define leader, members, invitations, privacy, capacity, pending queue, and
  disband rules.
- Decide how Roblox platform PartyId information supplements the custom party.

### Packet 24.2 — Same-server party service

- Implement create, invite, accept, decline, leave, kick, and leadership transfer.
- Validate friend/permission context and capacity.
- Keep party state ephemeral.

### Packet 24.3 — Invite Friends integration

- Use Roblox invite prompts where available.
- Include bounded launch data to identify the inviter or party intent.
- Validate launch data on the server and fall back safely.

### Packet 24.4 — Party UI

- Show leader, members, readiness/queue state, Invite, Leave, and permitted Kick.
- Avoid exposing private platform information.
- Handle member disconnect and server leave.

### Packet 24.5 — Party simulation test

- Use Studio Party Simulator and multi-client tests where available.
- Test invitation failure, full party, leadership transfer, and stale invite.

**Exit gate:** Same-server friends can form and manage a stable party before
approaching a queue.

## Phase 25 — Physical queue squares and captain configuration

**Objective:** Form a match squad through reliable world-space queue interactions.

### Packet 25.1 — Queue-zone detection

- Detect character presence on the server.
- Debounce character parts without relying on one Touched event.
- Handle respawn, death, teleport within lobby, and walking out.
- Enforce one queue per player.

### Packet 25.2 — Captain and roster rules

- First valid entrant becomes captain.
- Transfer captaincy to earliest remaining entrant.
- Reset empty queues.
- Reserve party spots only if an explicit design decision permits it.

### Packet 25.3 — Captain configuration service

- Allow captain-only map, difficulty, privacy, and maximum-player changes.
- Validate map/difficulty unlocks and compatibility.
- Broadcast an immutable queue snapshot.

### Packet 25.4 — Queue world display

- Show portraits, count, map, difficulty, privacy, and current state above the
  square.
- Do not use world UI as the only accessible control.

### Packet 25.5 — Queue configuration panel

- Give the captain controls and other members a read-only view.
- Include Leave and Start.
- Show loadout-invalid or profile-not-ready blockers per member.

### Packet 25.6 — Queue start and lock

- Revalidate every member and loadout.
- Lock membership/configuration while starting.
- Recover cleanly if ticket creation or teleport fails.

### Packet 25.7 — Queue grief and race tests

- Test two simultaneous first entrants, captain exit, full square, rapid in/out,
  privacy changes, invalid loadout, party split, and start spam.

**Exit gate:** The server can form, configure, lock, and recover a 1–4 player squad
without ambiguous captaincy.

## Phase 26 — Match tickets and safe group teleport

**Objective:** Move a locked squad to one reserved match server without trusting
the client.

### Packet 26.1 — Match ticket schema

- Store opaque match ID, expected UserIds, map, difficulty, created/expiry time,
  lobby origin, and one-time/claim state.
- Do not store access codes in client-readable state.

### Packet 26.2 — Ephemeral ticket storage

- Create and retrieve tickets through MemoryStore with protected calls.
- Set bounded expiry and cleanup.
- Prevent two match servers from independently claiming the same ticket when the
  design requires a single destination.

### Packet 26.3 — SafeTeleportService

- Reserve one match server and teleport the complete group.
- Wrap calls, classify retryable failures, and limit retries.
- Handle TeleportInitFailed per player.
- Restore queue state when the group remains in lobby.

### Packet 26.4 — Match admission

- Read opaque ticket ID from join data.
- Retrieve and validate server-owned ticket.
- Admit expected roster members and reject or safely return unexpected arrivals.
- Handle staggered group arrival within a grace window.

### Packet 26.5 — Teleport loading presentation

- Show selected map/difficulty and progress without secure details.
- Provide clear retry or return behavior after failure.
- Respect reduced motion and slow devices.

### Packet 26.6 — Published-client manual gate

- TeleportService cannot be fully tested in ordinary Studio play.
- With explicit publishing approval, test solo and 2–4 player teleports in a
  private test version.
- Record partial-group failure behavior.

**Exit gate:** A valid squad reaches one reserved match server and invalid/stale
tickets cannot start a reward-bearing match.

## Phase 27 — Persistent match rewards, retry, and return

**Objective:** Connect authoritative match results back to persistent Gold safely.

### Packet 27.1 — Reward formula contract

- Define win, loss/participation, difficulty, boss milestone, first-clear, and
  Endless milestone inputs.
- Cap or reject rewards for negligible participation and immediate leaving.
- Record formulas in `docs/CONTENT_BALANCE.md`.

### Packet 27.2 — Server result receipt

- Create one match-result ID with roster-specific reward entries.
- Persist or hand off claimable results safely.
- Never derive reward from a client result screen.

### Packet 27.3 — Idempotent profile claim

- Claim each player's result exactly once.
- Add Gold and progression in one profile mutation.
- Preserve unclaimed result when a transient save fails.
- Bound claimed-result history without allowing replay.

### Packet 27.4 — Production result screen

- Show granted versus pending rewards.
- Clearly distinguish Battle Cash statistics from persistent Gold.
- Disable duplicate claim interaction.

### Packet 27.5 — Return to lobby

- Teleport participants safely to the lobby.
- Refresh profile-visible Gold and unlocks after return.
- Handle failure without granting twice.

### Packet 27.6 — Retry/rematch

- Require an explicit rematch vote or captain decision.
- Create a new match ID and ticket even for the same roster/configuration.
- Snapshot loadouts according to the chosen rule.

### Packet 27.7 — Reward failure tests

- Test crash before claim, crash after claim, repeated ticket, duplicate callback,
  partial roster, leaver, defeat, first clear, and retry.

**Exit gate:** Match rewards are durable and exactly-once from the player's
perspective.

## Phase 28 — Disconnect, reconnect, late arrival, and spectating

**Objective:** Define fair behavior for unreliable networks and group travel.

### Packet 28.1 — Disconnect policy

- Keep disconnected player's towers active for a documented grace period or full
  match according to final design.
- Stop accepting actions immediately.
- Decide how their Battle Cash and rewards are handled.

### Packet 28.2 — Active-match routing record

- Store a short-lived UserId-to-match route without exposing reserved access code.
- Clear it on terminal match state.
- Prevent stale routes from trapping players.

### Packet 28.3 — Rejoin admission

- Route returning expected players to their active match when safe.
- Restore owner controls, Battle Cash, UI snapshot, placed tower references, and
  current match state.
- Avoid replaying rewards or ready actions.

### Packet 28.4 — Spectator mode

- Define when a player is a spectator rather than participant.
- Provide camera target cycling and return controls.
- Spectators cannot place, vote, earn participation, or affect combat.

### Packet 28.5 — Late/staggered teleport arrival

- Hold initial ready check for a bounded arrival grace period.
- Do not allow unexpected joins to expand the locked roster.
- Handle a party member who never arrives.

### Packet 28.6 — Network simulation test

- Test disconnects during ready, active wave, upgrade, reward, return, and rematch.
- Use latency, jitter, and packet-loss simulation.

**Gate D exit:** The complete lobby-to-match-to-lobby loop tolerates expected
disconnect and teleport failures without corrupting profiles or matches.

# Milestone E — First Production Content

## Phase 29 — First production map

**Objective:** Replace the graybox with one polished, validated, performant map
while preserving the proven map contract.

### Packet 29.1 — First-map design brief

- Decide theme, visual story, ant spawn structure, defender objective, path shape,
  lane count, buildable area, sight lines, and camera constraints.
- Define intended beginner placements and choke points.
- Avoid committing final wave balance in the map geometry.

### Packet 29.2 — Map gameplay blockout

- Build terrain and geometry in Studio.
- Preserve clear path readability from common camera angles.
- Test tower footprints at bends, straightaways, and base approach.
- Validate that players cannot stand in or obstruct critical systems.

### Packet 29.3 — Map art pass

- Add environment models, lighting, materials, landmarks, and themed base/nest.
- Keep enemy silhouettes and range discs readable against the ground.
- Disable unnecessary collision, shadows, and detail where appropriate.

### Packet 29.4 — Map markers and configuration

- Apply tags/attributes.
- Add map definition, thumbnail/icon references, display name, and supported
  difficulties.
- Run automated and runtime validators.

### Packet 29.5 — Map performance and device pass

- Measure join size, client memory, render cost, and camera occlusion.
- Test low graphics and smaller mobile devices.
- Fix geometry that causes placement ambiguity or touch mis-selection.

### Packet 29.6 — Map playtest gate

- Run solo and four-player tests using graybox combat content.
- Record dominant placement zones, dead zones, leaks caused by readability, and
  camera problems.

**Exit gate:** The first map is attractive, readable, valid, and does not require
special-case code in standard gameplay services.

## Phase 30 — First tower roster

**Objective:** Create a small roster that teaches distinct strategic roles and
exercises the general tower pipeline.

### Packet 30.1 — Roster role design

- Select a starter single-target tower.
- Select a fast/low-damage or short-range option.
- Select an area-damage option.
- Select a long-range or boss-focused option.
- Select a support, slow, or economy option only if its system is ready.
- Give every tower a clear niche and weakness.

### Packet 30.2 — Tower stat and upgrade sheets

- Define placement cost, levels, damage, cooldown, range, targeting, placement
  cap, sell behavior, and role description.
- Calculate DPS and total-investment curves.
- Avoid hidden behavior that the UI cannot explain.

### Packet 30.3 — Tower model integration

- Import or create models in Studio.
- Set pivots, footprint, aiming parts, muzzle markers, and upgrade visuals.
- Verify model ownership and asset permissions.

### Packet 30.4 — Tower attack behaviors

- Implement only the reusable attack behaviors required by the roster.
- Treat splash, slow, support aura, or economy production as general behavior
  modules, not tower-name checks.
- Add deterministic tests.

### Packet 30.5 — Animations, effects, and sounds

- Add aiming, attack, hit, upgrade, and placement feedback.
- Provide reduced-effects fallbacks.
- Keep server state independent of animation completion.

### Packet 30.6 — Inventory and gacha presentation

- Add portraits, rarity, descriptions, acquisition, cards, and banner membership.
- Verify stats agree across inventory, hotbar, tower panel, and definitions.

### Packet 30.7 — Tower roster playtest

- Test whether every tower is understandable, useful, and counterable.
- Record but do not immediately overreact to early balance opinions.

**Exit gate:** The first roster supports multiple viable beginner strategies and
contains no tower-name branching in core services.

## Phase 31 — First enemy roster, authored waves, and bosses

**Objective:** Create a readable learning curve that exercises tower roles without
using only health inflation.

### Packet 31.1 — Enemy role design

- Define basic, fast, tank, swarm, armored/resistant, support/special, miniboss,
  and boss roles as appropriate for the first release.
- Introduce mechanics one at a time before combining them.
- Give dangerous enemies recognizable silhouettes and warnings.

### Packet 31.2 — Enemy stat sheets

- Define health, speed, leak damage, cash eligibility, tags, resistances, and
  difficulty scaling.
- Calculate time-to-base and expected tower breakpoints.
- Ensure no enemy requires a tower unavailable to a valid beginner loadout.

### Packet 31.3 — Enemy models and health-bar offsets

- Import or create ant models and animations in Studio.
- Set pivots, scale, collision, rendering detail, and health-bar markers.
- Avoid full Humanoid overhead when a lighter visual rig suffices.

### Packet 31.4 — Special enemy behaviors

- Implement reusable status, armor, shield, spawn-on-death, aura, stealth, or
  flying behavior only when needed.
- Explain each mechanic through icons and first-appearance messaging.
- Add behavior and cash-credit tests.

### Packet 31.5 — Authored Easy waves

- Build 20 teaching-focused waves.
- Place a miniboss or escalation at meaningful milestones.
- Put a boss on wave 10 and a stronger final boss on wave 20, preserving the
  approved every-ten-waves cadence.
- Verify every spawn schedule and deadline.

### Packet 31.6 — Authored Normal waves

- Build 30 waves with earlier combinations and stronger final checks.
- Reuse enemies intentionally, not through copied Easy waves with only multipliers.

### Packet 31.7 — Authored Hard waves

- Build 40 waves with advanced compositions, meaningful boss cadence, and fair
  counterplay.
- Avoid assuming a specific rare gacha tower.

### Packet 31.8 — Boss presentation

- Add boss banner, health presentation, music transition, attacks/abilities if
  implemented, base leak consequence, and defeat feedback.
- Make warnings visual as well as audible.

### Packet 31.9 — Wave validation and simulation

- Run static validators and balance simulations.
- Check spawn totals, duration, income supply, boss timing, and impossible waves.

**Exit gate:** Easy, Normal, and Hard can be completed by intended loadouts and
teach mechanics before testing mastery.

## Phase 32 — Endless mode

**Objective:** Deliver genuinely unbounded, reproducible waves with controlled
scaling and milestone rewards.

### Packet 32.1 — Endless design contract

- Define the transition from authored opening waves to generated wave blocks.
- Define health, speed, count, composition, and ability scaling caps.
- Keep bosses every 10 waves.
- Define when new enemy tiers enter the pool.

### Packet 32.2 — Seeded wave generation

- Generate from a server seed and wave number.
- Make a wave reproducible for debugging.
- Validate budget and composition constraints.
- Prevent impossible combinations before their counters can reasonably exist.

### Packet 32.3 — Long-run economy

- Scale wave stipend and damage income without allowing infinite trivial farming.
- Define tower cap and placement-pressure behavior.
- Prevent numeric overflow and excessively tiny cooldowns.

### Packet 32.4 — Endless milestone rewards

- Award persistent rewards at documented checkpoints or final result.
- Bound claims with the match-result receipt system.
- Avoid encouraging players to remain connected indefinitely for disproportionate
  rewards.

### Packet 32.5 — Endless result and leaderboard-ready record

- Record highest resolved wave, elapsed time, map, difficulty version, roster
  size, and content version.
- Do not build a global leaderboard until its later phase.

### Packet 32.6 — Endless soak and overflow tests

- Simulate hundreds or thousands of waves without rendering.
- Test health/damage numeric stability, generator validity, memory growth, reward
  bounds, and long-session cleanup.

**Exit gate:** Endless is reproducible, unbounded by a fake final wave, numerically
stable, and reward-safe.

## Phase 33 — New-player onboarding and first-session funnel

**Objective:** Ensure a completely new player can understand both currencies,
equip a tower, form a solo queue, place/upgrade, and finish a first match.

### Packet 33.1 — Tutorial script and success criteria

- Define the minimum concepts taught.
- Avoid long text walls.
- Allow replay and a safe skip after essential profile initialization.

### Packet 33.2 — Starter inventory and guided loadout

- Grant starter tower records idempotently.
- Pre-equip a valid loadout.
- Prevent repeated first-join grants.

### Packet 33.3 — Lobby tutorial

- Guide Inventory, equipped slots, Gold, Chest odds, Settings, Invite, and Play.
- Provide a guaranteed/free first acquisition if retained by product design.
- Never force a random paid action.

### Packet 33.4 — Queue tutorial

- Guide a solo queue square, captain settings, selected Easy map, and Start.
- Recover if the player walks away or opens another menu.

### Packet 33.5 — Match tutorial

- Guide ready, select tower, valid placement, range, Battle Cash, upgrade, base
  health, wave timer, and targeting/sell when appropriate.
- Pause or soften only tutorial-safe solo timing, not shared public matches.

### Packet 33.6 — Tutorial persistence

- Save steps idempotently.
- Resume after disconnect.
- Keep completed players out of forced guidance.

### Packet 33.7 — Unassisted first-user test

- Observe new testers without explaining controls.
- Measure completion and confusion before adjusting presentation.

**Gate E exit:** The first map, roster, finite difficulties, Endless, and onboarding
form a complete production-content loop.

# Milestone F — Platform, Presentation, and Hardening

## Phase 34 — Accessibility, localization, and cross-platform audit

**Objective:** Verify that every critical flow is readable and operable across
supported users and devices.

### Packet 34.1 — Accessibility audit

- Test preferred text sizes, preferred transparency, and reduced motion.
- Check contrast and non-color indicators.
- Ensure all audio-critical events have visual feedback.
- Review flashing, camera shake, and rapid movement.

### Packet 34.2 — Localization readiness

- Remove concatenated user-facing sentences and hardcoded screen text.
- Add localization keys and mark names that should not auto-localize.
- Test pseudolocalization and 30–50% text expansion.
- Verify number/currency presentation.

### Packet 34.3 — Keyboard-only and screen-navigation audit

- Reach every interactive element without a mouse.
- Verify visible focus, sensible order, modal focus trapping, and restoration.

### Packet 34.4 — Touch audit

- Verify thumb zones, tap targets, scrolling, placement confirmation, camera
  gestures, and accidental-action protection.
- Test low-resolution landscape devices.

### Packet 34.5 — Console/gamepad audit

- Test ten-foot safe areas, text readability, all menus, placement, tower
  management, and Back behavior.
- Verify no flow requires chat or keyboard text entry.

### Packet 34.6 — Supported-platform decision

- Enable only platforms that pass their test matrix.
- Record deferred platform requirements rather than claiming unsupported parity.

**Exit gate:** Every advertised platform can complete the first-session and full
match loops accessibly.

## Phase 35 — Audio, animation, VFX, and game feel

**Objective:** Add polish without changing authoritative outcomes or overwhelming
lower-end devices.

### Packet 35.1 — Audio architecture

- Route music, SFX, and UI through separate controllable groups.
- Define lobby, match, boss, victory, and defeat music transitions.
- Handle asset load failure and permissions.

### Packet 35.2 — Combat feedback hierarchy

- Differentiate placement, attack, hit, kill, upgrade, sell, leak, boss, victory,
  and reward feedback.
- Prevent simultaneous effects from becoming unreadable.

### Packet 35.3 — Tower rotation and animation polish

- Smooth visual aim without delaying server attacks.
- Handle target loss, idle return, very fast cooldowns, and model variants.
- Respect reduced motion/low-effects settings.

### Packet 35.4 — Enemy and boss presentation

- Add spawn, damage, status, death, leak, and boss cues.
- Keep health and path readability above spectacle.

### Packet 35.5 — UI motion and sound polish

- Add restrained transitions and selection feedback.
- Remove positional motion when reduced motion is enabled.
- Do not make repeated button sounds fatiguing.

### Packet 35.6 — Effects-density test

- Test four players using high-fire-rate and splash towers on dense waves.
- Tune pooling, culling, sound concurrency, and per-frame effect budgets.

**Exit gate:** Presentation reinforces decisions, remains accessible, and can be
reduced without hiding gameplay-critical information.

## Phase 36 — Performance, memory, and network optimization

**Objective:** Validate performance through measurement rather than assumptions.

### Packet 36.1 — Performance budgets

- Set target server update time, client frame rate, join time, memory, enemy/tower
  counts, and network rates for supported devices.
- Record budgets in `docs/TEST_MATRIX.md`.

### Packet 36.2 — Server profiling

- Profile enemy simulation, target queries, combat scheduler, wave spawning,
  remotes, and cleanup.
- Replace hot full scans with lane/spatial buckets where measurement justifies it.
- Avoid premature micro-optimization outside hot paths.

### Packet 36.3 — Client profiling

- Profile enemy interpolation, health bars, range discs, UI, animation, effects,
  shadows, and streaming.
- Test low-end device emulation and actual representative hardware when possible.

### Packet 36.4 — Network audit

- Measure event frequency and payload size.
- Send deltas instead of whole profiles/inventories.
- Avoid per-frame reliable remotes.
- Use unreliable updates only for disposable presentation data and tolerate loss.

### Packet 36.5 — Instance and effect pooling

- Pool only high-churn visuals where profiling shows benefit.
- Reset every property and connection on reuse.
- Keep authoritative runtime entities independent of pooled visuals.

### Packet 36.6 — Map and asset optimization

- Review render fidelity, collision fidelity, shadows, lights, texture size, model
  LOD, animation metadata, and streaming behavior.

### Packet 36.7 — Long-session soak

- Run repeated finite matches and long Endless sessions.
- Track memory, connections, instances, DataStore/MemoryStore requests, and
  network traffic.

**Exit gate:** The build meets documented budgets on supported hardware and has
no known unbounded match-to-match growth.

## Phase 37 — Analytics, observability, and safe development tools

**Objective:** Make balance, funnel, and production failures measurable without
creating player-facing power or privacy risk.

### Packet 37.1 — Analytics event dictionary

- Define onboarding funnel events.
- Define queue, teleport, ready, match, difficulty, defeat-wave, and return events.
- Define Gold source/sink and gacha economy events.
- Define bounded custom fields and version identifiers.

### Packet 37.2 — Analytics implementation

- Log only after successful server outcomes.
- Respect service budgets.
- Avoid personal or sensitive data.
- Fail silently/safely when analytics is unavailable.

### Packet 37.3 — Operational logging

- Add rate-limited structured warnings for profile, ticket, teleport, config,
  match, reward, and security failures.
- Include correlation IDs without secrets.

### Packet 37.4 — Development command framework

- Restrict commands to Studio or an explicit UserId allowlist in private test
  environments.
- Add safe commands for starting test waves, granting test Battle Cash, inspecting
  state, and validating maps.
- Never expose broad production currency or inventory mutation by default.

### Packet 37.5 — Balance simulator/report

- Simulate tower DPS/investment curves and wave health/speed budgets.
- Export human-readable reports without modifying live configurations.

### Packet 37.6 — Dashboard verification

- In a private test release, confirm events arrive and dimensions are useful.
- Remove noisy or redundant events before player scale.

**Exit gate:** Core player and economy funnels can be measured, and production
failures can be correlated without logging sensitive state.

## Phase 38 — Security and resilience audit

**Objective:** Review the entire product as an adversarial system before broader
testing.

### Packet 38.1 — Remote authorization audit

- Inventory every client-to-server entry point.
- Verify payload validation, permission, rate limit, current phase, ownership,
  and effect bounds.
- Remove unused remotes.

### Packet 38.2 — Economy and profile audit

- Attempt Gold, unit, pity, reward, and loadout duplication through replay,
  disconnect, concurrent sessions, and stale state.
- Verify bounded idempotency records.

### Packet 38.3 — Match exploit audit

- Attempt free placement, remote upgrade/sell, invalid position, impossible
  target mode, fake damage, fake ready/skip, and match-state manipulation.

### Packet 38.4 — Queue, party, and teleport audit

- Attempt captain impersonation, roster injection, stale ticket reuse, unexpected
  match join, privacy bypass, and partial-teleport abuse.

### Packet 38.5 — Failure injection

- Simulate DataStore, MemoryStore, teleport, analytics, asset, and remote delays
  or failures.
- Verify safe state and understandable player feedback.

### Packet 38.6 — Dependency and asset review

- Inventory third-party packages and licenses.
- Remove unused dependencies.
- Verify model, audio, image, animation, and plugin provenance/permissions.

**Exit gate:** No known client action can directly create authority, persistent
value, or match outcomes outside validated server rules.

## Phase 39 — Balance, fairness, and comprehensive QA

**Objective:** Turn functional content into a fair and repeatable first release.

### Packet 39.1 — Test matrix completion

- Complete solo, 2-player, 3-player, and 4-player coverage.
- Cover every finite difficulty, major loadout role, victory, defeat, and return.
- Cover supported devices and simulated network conditions.

### Packet 39.2 — Economy balance

- Measure Battle Cash generation/spending curves by wave and player count.
- Measure persistent Gold sources, sinks, chest acquisition pace, pity value, and
  duplicate frustration.
- Prevent pay-to-progress assumptions from entering core difficulty.

### Packet 39.3 — Tower balance

- Compare cost efficiency, range utility, placement constraints, upgrade
  breakpoints, and team synergy.
- Preserve niches rather than forcing identical DPS.

### Packet 39.4 — Enemy and wave balance

- Inspect time-to-base, counter availability, boss checks, overlap pressure, and
  difficulty jumps.
- Fix unclear or unavoidable failure before reducing raw difficulty.

### Packet 39.5 — Map balance

- Identify dominant, unusable, and exploitative placements.
- Adjust geometry only when it improves readable decisions.
- Revalidate after every authored change.

### Packet 39.6 — Gacha fairness review

- Verify displayed odds exactly match server calculation.
- Verify pity text, duplicate handling, regional restriction, and starter access.
- Confirm no required gameplay role is locked behind unreasonable rarity.

### Packet 39.7 — Bug triage and regression

- Classify blockers, serious defects, normal defects, polish, and ideas.
- Fix by severity and add regression coverage.
- Do not expand scope during release stabilization.

**Exit gate:** No blocker or serious known defect remains, and the documented
first-release economy/difficulty targets are met.

## Phase 40 — Closed-alpha and release-readiness gate

**Objective:** Produce a controlled build ready for invited external testing, not
automatic public release.

### Packet 40.1 — Operations document

- Create `docs/OPERATIONS.md`.
- Document configuration versions, test/prod data separation, incident response,
  disabling banners/queues, rollback strategy, and support diagnostics.

### Packet 40.2 — Compliance checklist

- Complete content maturity, paid-random-item, platform, privacy, and asset
  permission reviews.
- Verify creator/group ownership and collaborator roles.

### Packet 40.3 — Release configuration

- Freeze content/config versions.
- Disable development commands and verbose logs.
- Verify PlaceIds, universe IDs, DataStore scopes, MemoryStore names, product IDs,
  and banner dates without storing secrets.

### Packet 40.4 — Clean-room build

- Install pinned tools from scratch.
- Run format check, lint, all tests, and all Rojo builds.
- Confirm generated artifacts are not accidentally committed.

### Packet 40.5 — Closed-alpha test

- With explicit approval, publish to a controlled audience.
- Test real invites, teleports, persistence, rewards, device performance, and
  analytics.
- Monitor errors and stop/rollback on data risk.

### Packet 40.6 — Alpha findings and go/no-go

- Summarize retention funnel, failures, balance, device issues, and player
  feedback.
- Decide whether to iterate, expand testing, or prepare a separate public-release
  plan.

**Gate G exit:** A stable closed-alpha candidate exists. Public publishing still
requires an explicit separate decision.

# Post-Core Expansion Roadmap

Post-core phases are intentionally defined now so early schemas remain compatible.
They do not belong in the initial closed-alpha scope.

## Phase 41 — Duplicate merging and ascension

**Objective:** Let duplicates strengthen an owned unit without corrupting the
first-release balance or inventory.

### Packet 41.1 — Merge design and caps

- Define copy costs, ranks, stat effects, visuals, maximum rank, reversibility,
  and treatment of extra copies.
- Avoid exponential power that makes base towers obsolete.

### Packet 41.2 — Profile migration

- Add merge fields or convert compact counts safely.
- Preserve equipped unit references and locks.

### Packet 41.3 — Atomic merge transaction

- Validate ownership, unlocked material copies, rank, and request ID.
- Consume and upgrade in one profile mutation.
- Never allow locked/favorite copies to be consumed implicitly.

### Packet 41.4 — Merge UI and preview

- Show exact consumed copies and resulting stats before confirmation.
- Provide bulk and auto-select only after safe individual flow exists.

### Packet 41.5 — Match stat integration and rebalance

- Apply merge modifiers from the loadout snapshot.
- Rebalance content around attainable rather than maximum merge ranks.

**Exit gate:** Merge transactions are reversible only if explicitly designed,
idempotent, and cannot consume protected units.

## Phase 42 — Second map and repeatable content pipeline

**Objective:** Prove that the architecture actually makes new content easy.

### Packet 42.1 — Authoring checklist and templates

- Turn first-map lessons into map, tower, enemy, and wave checklists.
- Provide validators and non-code templates, not copied production assets.

### Packet 42.2 — Second-map blockout

- Add a genuinely different path or lane arrangement using existing systems.
- Do not special-case MapService.

### Packet 42.3 — Map-specific waves/modifiers

- Add content through definitions.
- Allow map-specific composition only through approved configuration hooks.

### Packet 42.4 — Content regression

- Re-run every existing map/difficulty and ensure shared changes did not regress
  the first map.

**Exit gate:** A second map ships without duplicating match services or editing
ordinary tower/enemy logic.

## Phase 43 — Cross-server public matchmaking

**Objective:** Match eligible public players beyond one lobby server while
preserving parties and captain-selected private play.

### Packet 43.1 — Matchmaking rules

- Define queue keys by difficulty, map preference, region/latency, party size,
  and acceptable expansion over wait time.
- Keep solo/private queue squares unaffected.

### Packet 43.2 — MemoryStore queue implementation

- Add entries with expiration and ownership.
- Claim/remove safely with invisibility timeout behavior.
- Recover abandoned or duplicate processing.

### Packet 43.3 — Party-preserving match assembly

- Never split a party.
- Fill remaining slots according to privacy and wait-time rules.
- Select captain/configuration deterministically.

### Packet 43.4 — Cancellation and UI

- Show estimated/elapsed wait, cancel, found, and teleport states.
- Ensure cancel racing with match found has one outcome.

### Packet 43.5 — Matchmaking analytics and load test

- Measure time, success, abandonment, party composition, and failures.
- Test multiple lobby servers in a private published environment.

**Exit gate:** Cross-server matching cannot duplicate, split, or strand parties
and degrades safely when MemoryStore is unavailable.

## Phase 44 — Monetization and live banner operations

**Objective:** Add optional monetization only after the free core and data safety
are proven.

### Packet 44.1 — Monetization principles

- Define what can be sold without invalidating strategy or starter viability.
- Separate convenience/cosmetic value from required power.
- Record regional and age-related constraints.

### Packet 44.2 — Developer product receipt handling

- Process receipts on the server through the approved receipt callback.
- Store idempotent purchase grants.
- Never grant from a purchase-finished client event.

### Packet 44.3 — Paid Gold and gacha policy integration

- Re-evaluate every banner as paid random content if purchased Gold can fund it.
- Ensure exact odds, restriction handling, and questionnaire accuracy.

### Packet 44.4 — Banner scheduling and emergency disable

- Use server-authoritative availability windows.
- Support safe disable without profile mutation.
- Version pity behavior when banners rotate.

### Packet 44.5 — Purchase UX and test mode

- Show actual localized price and exact benefit.
- Handle pending, cancellation, delayed receipt, and duplicate delivery.
- Test only with explicit approval because test purchases can use real Robux.

**Exit gate:** Purchases are receipt-safe, policy-compliant, optional to core
success, and operationally disableable.

## Phase 45 — Long-term social and progression systems

**Objective:** Expand retention only after core engagement data identifies a real
need.

Potential separately planned subprojects:

- Collection/index rewards.
- Daily and weekly quests.
- Achievements and badges.
- Player level and unlock tracks.
- Map mastery and first-clear rewards.
- Global Endless leaderboards with anti-cheat eligibility.
- Tower skins and cosmetic loadouts.
- Events and battle passes.
- Clans.
- Trading, only after paid-item trading policy and duplication security reviews.
- Ranked or challenge modes.
- Activated tower abilities.
- Multiple tower upgrade branches.
- Consumable match items and revives.
- PvP, treated as a separate game-design and architecture project.

Each subproject requires its own design, abuse analysis, profile-size estimate,
economy impact review, work packets, and release gate. This list is not permission
to implement them opportunistically.

# Cross-phase quality requirements

## Definition of done for code packets

A code packet is done only when:

- Its bounded requirements are implemented.
- Public interfaces are typed and documented where their behavior is not obvious.
- Expected failures return safe, actionable outcomes.
- Relevant automated tests pass, and zero discovered tests is a failure.
- Changed Luau is formatted.
- `stylua --check --verify src tests` passes.
- `selene validate-config` and `selene src tests` pass.
- `lune run tests/run.luau` passes.
- `lune run tests/verify-builds.luau` proves all four projects build, tests do
  not ship in production, and Lobby/Match role isolation still holds.
- Exact generated outputs are removed and no unexpected residue remains.
- The diff contains no unrelated change.
- Required manual Studio steps are listed.
- No new warning/error is left unexplained.

## Definition of done for Studio-content packets

A Studio content packet is done only when:

- The asset is stored in the authoritative Studio/Team Create location.
- Rojo-managed scripts were not edited in Studio.
- Tags, attributes, pivots, collisions, and permissions follow the contract.
- Runtime validators pass.
- Supported camera and device views were checked.
- Performance implications were measured proportionally to risk.
- The repository records any required configuration/metadata.

## Required recurring test scenarios

The authoritative status, environments, procedures, prerequisites, and safety
boundaries for these scenarios are in `docs/TEST_MATRIX.md`. The following are
required recurring scenarios; most remain explicitly deferred until their
enabling packets exist:

- Solo, 2-player, 3-player, and 4-player.
- Captain leaves before start.
- Player disconnects during ready, wave, transaction, result, and return.
- Profile load/save/migration failure.
- Queue/ticket/teleport transient failure.
- Simultaneous placement, upgrade, sell, and reward requests.
- Old and new waves overlapping.
- Boss and multiple simultaneous leaks.
- Long Endless run.
- Small phone, touch tablet, desktop, ultrawide, and gamepad console.
- Preferred large text, opaque backgrounds, reduced motion, muted audio, and
  low-effects mode.
- High latency, jitter, and packet loss.
- Repeated matches in one server process.
- Malformed and spammed remote requests.
- Gacha retry and policy-restricted user.

## Architecture decision record triggers

Create a short decision record before:

- Replacing the profile/data library or persistence model.
- Changing unit copies from unique records to counts or vice versa.
- Allowing purchased currency to fund random chests.
- Adding a third Roblox place.
- Adding a general third-party framework.
- Moving combat authority toward clients.
- Adding dynamic pathfinding.
- Adding trading.
- Adding PvP.
- Changing match size or loadout size after saved profiles exist.

## Roadmap maintenance

After each completed packet:

- Mark only that packet complete with date and evidence.
- Record new blockers beside the dependent packet.
- Add newly discovered work to the correct future phase.
- Do not silently expand the active packet.
- If implementation invalidates this order, explain why and update dependencies
  before continuing.

At each gate:

- Run the gate regression suite.
- Review open bugs and technical debt.
- Confirm documentation matches behavior.
- Ask for explicit user approval before entering a gate that requires publishing,
  real purchases, production migration, or materially broader scope.

## Suggested wording for future prompts

Use a bounded prompt such as:

> Complete Packet 13.4 from `docs/DEVELOPMENT_PLAN.md`. Read the roadmap and
> `AGENTS.md` first, implement only that packet, run all required checks, and
> report the exact Studio tests I must perform.

For a phase gate:

> Audit and complete the exit gate for Phase 13. Do not begin Phase 14. Fix only
> issues required by the Phase 13 exit criteria, run the regression checks, and
> report any remaining Studio verification.

This keeps each prompt focused, reviewable, and recoverable while the complete
project advances over many sessions.
