# Test Matrix

## Purpose and status

This document is the authoritative test-environment and test-status index for
Ant Tower Defense. Packet 05.4 created it on 2026-08-26. It separates checks
that are automated today from Studio, published-client, device, and destructive
checks that require later systems or explicit authorization.

Packet 05.4 is complete. The fresh combined Phase 05 exit audit is the next
checkpoint; Phase 06 has not begun.

The current repository has no gameplay, networking, persistence, UI, or
external-service implementation. A separate private test universe has not been
created or configured. Future tests are therefore marked `Deferred`,
`Unavailable`, or `Prohibited`; they are never presented as passing evidence.

## Status vocabulary

- `Passed` means the exact current check has recorded evidence from the stated
  environment and date.
- `Available; ...` means a safe current procedure exists, but its suffix states
  whether the latest evidence is historical or the procedure has not yet been
  rerun. Phase 05 did not rerun safe Studio procedures because no production
  source or Studio integration behavior changed.
- `Historical evidence only` means the named packet recorded a passing temporary
  harness, but its exact executable harness was not committed and cannot be
  rerun as a current repository test.
- `Deferred` means the planned system or test implementation does not exist yet.
- `Unavailable` means an external environment, device, publication, or service
  prerequisite is also missing.
- `Prohibited` means the procedure must not be run in the named environment.

An older evidence document remains truthful for its own packet even when a
later packet has automated the same area. Follow the current status here and
the current commands in [Automated test runner](TEST_RUNNER.md), while using the
linked historical document for the original Studio evidence.

## Global safety boundaries

- Repository tests use deterministic fixtures under `tests/`; they do not use a
  network, wall clock, uncontrolled randomness, uploaded asset, DataStore,
  MemoryStore, TeleportService, purchase, or Studio-authored instance.
- Default, Lobby, and Match never map `tests/` or a test-only dependency.
  `lune run tests/verify-builds.luau` enforces exact source identity, role
  isolation, runnable-entrypoint counts, and test exclusion.
- Production universe `10757629094` is not a routine persistence-test target.
  Keep Studio API access disabled there. The complete environment policy is in
  [Place and test-environment inventory](PLACE_INVENTORY.md).
- Do not save or publish a Roblox place merely to run a Studio regression.
- Publishing, external-service enablement, production-sensitive mutation, real
  purchase testing, and test-data reset each require separate explicit approval.
- Never retain generated `.rbxl`, `.rbxlx`, test-place, package, or CI artifact
  output. Remove only the exact output created by the procedure.

## Automated headless tests

### H-01 — Runner discovery, execution, and failure contract

- **System or contract:** repository-owned deterministic runner, discovery,
  stable ordering, module loading, assertion reporting, privacy, and exit codes.
- **Test category:** automated headless unit/runner test.
- **Current status:** `Passed` on Windows x64 on 2026-08-26.
- **Environment:** repository checkout with the versions pinned by `rokit.toml`;
  no Roblox Studio, network, publication, or external Roblox service.
- **Command or procedure:** run `lune run tests/run.luau`. For isolated failure
  semantics, run the six documented controls in
  [Automated test runner](TEST_RUNNER.md#packet-051-verification-evidence).
- **Required players or devices:** zero players; one Windows x64 development or
  CI host.
- **Authorization requirement:** none for local non-publishing execution.
- **External service or publication requirement:** none.
- **Destructive-data risk:** none; the runner uses only deterministic fixtures
  and an exact ignored build path that it removes.
- **Expected evidence:** eight suites and 76 tests pass in stable path and
  declaration order; zero discovery, module-load, malformed-root/discovery, and
  runner-crash controls return their documented nonzero exit classes; output
  contains stable suite, case, assertion, code, and path context without private
  sentinels.
- **Cleanup procedure:** confirm the runner removed its exact temporary test
  place and that `git status --short --ignored` shows no new residue.
- **Phase or prerequisite:** available now; Packet 05.1 established the runner
  and Packet 05.2 established the current suite.

### H-02 — Cleanup contract

- **System or contract:** `Cleanup` ordering, ownership, supported task forms,
  idempotence, nesting/cycles, post-clean guards, cached failures, and sibling
  failure isolation.
- **Test category:** automated headless unit test.
- **Current status:** `Passed` as part of the 76-test suite on 2026-08-26.
- **Environment:** isolated Rojo test DataModel under Lune.
- **Command or procedure:** run `lune run tests/run.luau`; inspect the ordered
  `cleanup contract` suite in the result.
- **Required players or devices:** zero.
- **Authorization requirement:** none.
- **External service or publication requirement:** none.
- **Destructive-data risk:** none; created Instances, connections, threads, and
  nested containers are test-owned.
- **Expected evidence:** every Cleanup case passes with stable names and no
  leaked callback error or private sentinel.
- **Cleanup procedure:** automatic test-owned cleanup, followed by the H-01
  residue check.
- **Phase or prerequisite:** available now; original Studio evidence remains in
  [Typed Cleanup Utility](CLEANUP.md#focused-studio-edit-mode-validation).

### H-03 — IDs, Result, and Validation contracts

- **System or contract:** all ten typed ID families, byte boundaries,
  cross-family rejection, immutable Result envelopes, validation issue paths,
  related paths, codes, causes, path formatting, and freezing.
- **Test category:** automated headless unit test.
- **Current status:** `Passed` as part of the 76-test suite on 2026-08-26.
- **Environment:** isolated Rojo test DataModel under Lune.
- **Command or procedure:** run `lune run tests/run.luau`; inspect the ordered ID,
  Result, and Validation suites.
- **Required players or devices:** zero.
- **Authorization requirement:** none.
- **External service or publication requirement:** none.
- **Destructive-data risk:** none.
- **Expected evidence:** constructors and validators accept canonical values,
  reject malformed and cross-family values at exact boundaries, preserve stable
  public codes/paths, freeze public outputs, and expose no rejected value or
  caught error.
- **Cleanup procedure:** H-01 residue check.
- **Phase or prerequisite:** available now; contract reference is
  [IDs and Results](IDS_AND_RESULTS.md).

### H-04 — Configuration schemas and aggregate validator

- **System or contract:** Assets, Towers, Enemies, Maps, Difficulties, finite and
  Endless Waves, Economy, Banners, Settings, `ConfigurationValidator`, and
  lasting empty/policy configuration.
- **Test category:** automated headless unit/integration test with test-only
  deterministic fixtures.
- **Current status:** `Passed` as part of the 76-test suite on 2026-08-26.
- **Environment:** isolated Rojo test DataModel under Lune; fixtures under
  `tests/fixtures` only.
- **Command or procedure:** run `lune run tests/run.luau`; inspect schema and
  aggregate configuration suites.
- **Required players or devices:** zero.
- **Authorization requirement:** none.
- **External service or publication requirement:** none.
- **Destructive-data risk:** none; lasting catalogs remain empty and Economy and
  Settings remain policy-only.
- **Expected evidence:** deterministic canonical outputs; exact duplicate and
  cross-reference failures; non-finite/boundary rejection; probability and
  settings-version enforcement; stable issue and blocked-family order;
  authenticated, deeply frozen outputs; malformed-root/source-load containment;
  privacy-safe failures.
- **Cleanup procedure:** run the H-01 residue check. Lasting-empty and policy-only
  configuration is enforced by this H-04 canonical test coverage, not by the
  structural build verifier.
- **Phase or prerequisite:** available now; schema references are
  [Tower and enemy schemas](TOWER_ENEMY_SCHEMAS.md),
  [Map, difficulty, and wave schemas](MAP_DIFFICULTY_WAVE_SCHEMAS.md), and
  [Economy, banner, and settings schemas](ECONOMY_BANNER_SETTINGS_SCHEMAS.md).

### H-05 — Four-project structure and production test exclusion

- **System or contract:** Default/Lobby/Match/Test builds, exact authoritative
  Lua source map, production runnable-entrypoint counts, place-role isolation,
  and absence of tests/test-only dependencies from production.
- **Test category:** automated headless build and structural integration test.
- **Current status:** `Passed` on 2026-08-26.
- **Environment:** local Windows x64 and GitHub Actions Windows runner using
  pinned Rojo and Lune.
- **Command or procedure:** run `lune run tests/verify-builds.luau`.
- **Required players or devices:** zero.
- **Authorization requirement:** none.
- **External service or publication requirement:** none.
- **Destructive-data risk:** none; generated builds are ignored and exact-path
  temporary outputs are removed.
- **Expected evidence:** Default, Lobby, and Match each contain exactly 30
  ModuleScripts, one Script, and one LocalScript; Test contains 29 shared
  ModuleScripts and no runnable script; Lobby contains no Match source, Match
  contains no Lobby source, and production contains no test source or marker.
- **Cleanup procedure:** the verifier removes its exact four outputs; confirm no
  generated place remains.
- **Phase or prerequisite:** available now; mapping details are in
  [Rojo Project Definitions](ROJO_PROJECTS.md).

### H-06 — Formatting, linting, and genuine CI enforcement

- **System or contract:** StyLua, Selene, canonical tests, structural builds,
  generated-output residue, least-privilege workflow, and unambiguous negative
  controls.
- **Test category:** automated local quality gate and GitHub Actions CI.
- **Current status:** `Passed` locally and in genuine GitHub Actions runs on
  2026-08-26. Formatting, Selene-lint, broken-expectation, and broken-definition
  controls each failed their intended step before ordinary restoration commits;
  final clean runs passed and retained no artifacts.
- **Environment:** local Windows x64 or GitHub-hosted `windows-2025`; tools and
  action pins are repository-controlled.
- **Command or procedure:** locally run, in order, `stylua --check --verify src
  tests`, `selene validate-config`, `selene src tests`, `lune run
  tests/run.luau`, and `lune run tests/verify-builds.luau`. GitHub runs the same
  required gates through `.github/workflows/ci.yml`.
- **Required players or devices:** zero.
- **Authorization requirement:** none locally; pushing a branch or changing a
  workflow requires repository authorization.
- **External service or publication requirement:** GitHub Actions only for
  genuine CI evidence; no Roblox service or publication.
- **Destructive-data risk:** none. Required checks do not deploy, publish,
  release, upload artifacts, or use secrets.
- **Expected evidence:** every clean step exits zero; each deliberate local/CI
  control exits nonzero at its intended gate; workflow permissions are only
  `contents: read`; no artifact is retained.
- **Cleanup procedure:** restore a local temporary control before exiting. If a
  control was pushed for genuine CI evidence, follow it with an ordinary
  restoring commit; never rewrite history. Remove exact generated outputs and
  leave no broken working-tree state.
- **Phase or prerequisite:** available now; exact commits, runs, jobs, and
  security policy are in [Continuous integration](CONTINUOUS_INTEGRATION.md).

### H-07 — Lifecycle, logging, and shutdown headless regression

- **System or contract:** `ServiceLifecycle`, structured `Log` and
  `EnvironmentContext`, `Shutdown`, and bootstrap composition beyond the Cleanup
  unit coverage in H-02.
- **Test category:** future automated headless regression test.
- **Current status:** `Deferred`; no repository-owned headless specs currently
  exercise these Roblox-runtime contracts.
- **Environment:** future isolated test project with explicit Roblox-runtime
  adapters or a separately justified Studio runner.
- **Command or procedure:** none yet. Do not describe the historical temporary
  Studio harnesses as current repository tests.
- **Required players or devices:** expected zero for pure adapters; Studio
  runtime cases may require one local player.
- **Authorization requirement:** none for a future local non-publishing harness.
- **External service or publication requirement:** none for the planned local
  non-publishing harness.
- **Destructive-data risk:** none expected.
- **Expected evidence:** deterministic lifecycle order/state/error tests,
  privacy-safe logging tests, and bounded shutdown composition tests with stable
  failure context.
- **Cleanup procedure:** test-owned runtime objects only; exact generated output
  removal.
- **Phase or prerequisite:** a dedicated maintenance/regression packet must
  design these tests before or alongside any behavioral change to the Phase 03
  contracts. Historical evidence is linked in the Studio sections below.

## Local Studio solo tests

### S-00 — Place-role resolver and incorrect-pairing rejection

- **System or contract:** deterministic Development/Lobby/Match role resolution,
  configured PlaceIds, unknown-place rejection, invalid ID rejection, role/place
  mismatch rejection, and safe unset-placeholder behavior.
- **Test category:** historical Studio Edit-mode resolver harness plus current
  build/boot integration boundary.
- **Current status:** `Historical evidence only`; all ten Packet 02.3 resolver
  cases passed on 2026-08-25, but the exact temporary harness was destroyed and
  has not been converted into a repository-owned headless spec.
- **Environment:** historical connected Studio Luau runtime against a temporary
  clone of the synchronized `PlaceRoles` module.
- **Command or procedure:** no exact current executable harness exists. Preserve
  the case inventory in [Place roles](PLACE_ROLES.md#focused-packet-023-runtime-validation);
  use H-05 plus S-02/S-03 for current positive build/boot integration. A new
  resolver harness must be reviewed before claiming a rerun.
- **Required players or devices:** no player; one Studio operator for the
  historical Edit-mode harness.
- **Authorization requirement:** none for a future temporary unsaved harness.
- **External service or publication requirement:** none.
- **Destructive-data risk:** low if only test-owned clones are used; never change
  centralized production PlaceIds to force a negative case.
- **Expected evidence:** all declared role/place pairs resolve deterministically,
  while development-outside-Studio, unknown, invalid, mismatched, and unset
  production-role cases fail with their stable codes and no raw ID scattering.
- **Cleanup procedure:** destroy the exact test clone/harness, leave Edit mode,
  and do not save/publish.
- **Phase or prerequisite:** a future focused regression packet is required for
  reusable automated resolver coverage.

### S-01 — Combined Development bootstrap smoke test

- **System or contract:** combined Default project, Development role,
  configuration-before-lifecycle bootstrap order, structured server/client ready
  records, and clean Play-Stop shutdown.
- **Test category:** local Studio solo regression.
- **Current status:** `Available; current role-aware procedure not yet rerun`.
  Its historical precursor passed during Packet 01.3; isolated Lobby/Match
  integration later passed, but that does not prove the combined Development
  procedure as written.
- **Environment:** Roblox Studio, local Play, development/Lobby place
  `100561454756026`, `default.project.json` connected through Rojo.
- **Command or procedure:** follow
  [Current Roblox Studio smoke-test procedure](BOOTSTRAP_SMOKE_TEST.md#current-roblox-studio-smoke-test-procedure).
- **Required players or devices:** one local desktop player and the Studio server.
- **Authorization requirement:** none for Edit/Play without save or publish.
- **External service or publication requirement:** none; keep external services
  disabled.
- **Destructive-data risk:** none when the procedure is followed.
- **Expected evidence:** exact configuration and ready records for server/client,
  zero bootstrap warning/error, no old demo content, then one server shutdown
  start/completion pair and prompt return to Edit mode.
- **Cleanup procedure:** stop Play, leave Studio in Edit mode, disconnect Rojo if
  desired, and do not save or publish.
- **Phase or prerequisite:** available now.

### S-02 — Isolated Lobby bootstrap and shutdown regression

- **System or contract:** Lobby place identity, common-plus-lobby source
  isolation, configuration validation, zero-service lifecycle, Cleanup ownership,
  logging, and bounded server shutdown.
- **Test category:** local Studio solo regression.
- **Current status:** `Available; last passed after Packet 04.5`, with the Phase
  03 three-cycle Play-Stop evidence still applicable. Not rerun in Phase 05.
- **Environment:** Roblox Studio Lobby place `100561454756026` with only
  `lobby.project.json` connected.
- **Command or procedure:** follow the Lobby half of
  [Graceful shutdown manual regression](GRACEFUL_SHUTDOWN.md#manual-regression-procedure)
  and the current configuration expectations in
  [Configuration validation](CONFIGURATION_VALIDATION.md).
- **Required players or devices:** one local desktop player and the Studio server.
- **Authorization requirement:** none for Edit/Play without save or publish.
- **External service or publication requirement:** none.
- **Destructive-data risk:** none.
- **Expected evidence:** role `Lobby`, correct PlaceId, nine validated families,
  one common Script and LocalScript, no Match source, ready state, and clean
  bounded shutdown for three consecutive cycles when running the full regression.
- **Cleanup procedure:** stop Play, return to Edit mode, do not save/publish, and
  stop the Lobby Rojo server before connecting another project.
- **Phase or prerequisite:** available now.

### S-03 — Isolated Match bootstrap and shutdown regression

- **System or contract:** Match place identity, common-plus-match source
  isolation, configuration validation, zero-service lifecycle, Cleanup ownership,
  logging, and bounded server shutdown.
- **Test category:** local Studio solo regression.
- **Current status:** `Available; last passed after Packet 04.5`, with the Phase
  03 three-cycle Play-Stop evidence still applicable. Not rerun in Phase 05.
- **Environment:** Roblox Studio Match place `136401514513678` with only
  `match.project.json` connected.
- **Command or procedure:** follow the Match half of
  [Graceful shutdown manual regression](GRACEFUL_SHUTDOWN.md#manual-regression-procedure)
  and [Configuration validation](CONFIGURATION_VALIDATION.md).
- **Required players or devices:** one local desktop player and the Studio server.
- **Authorization requirement:** none for Edit/Play without save or publish.
- **External service or publication requirement:** none.
- **Destructive-data risk:** none.
- **Expected evidence:** role `Match`, correct PlaceId, nine validated families,
  one common Script and LocalScript, no Lobby source, ready state, and clean
  bounded shutdown for three consecutive cycles when running the full regression.
- **Cleanup procedure:** stop Play, return to Edit mode, do not save/publish, and
  stop the Match Rojo server when finished.
- **Phase or prerequisite:** available now.

### S-04 — Phase 03 focused module harnesses

- **System or contract:** lifecycle invalid states/dependencies, Cleanup runtime
  task forms, structured logging/privacy, and shutdown timeout/failure isolation.
- **Test category:** historical local Studio Edit-mode harness validation.
- **Current status:** `Historical evidence only`; the Phase 03 temporary
  harnesses passed on 2026-08-25 but were intentionally not committed as a
  reusable suite.
- **Environment:** Roblox Studio Edit mode against current Rojo-synchronized
  ModuleScripts.
- **Command or procedure:** use the case inventories and safety boundaries in
  [Service lifecycle](SERVICE_LIFECYCLE.md#focused-studio-edit-mode-validation),
  [Cleanup](CLEANUP.md#focused-studio-edit-mode-validation),
  [Logging](LOGGING.md#focused-studio-validation), and
  [Graceful shutdown](GRACEFUL_SHUTDOWN.md#focused-studio-edit-mode-validation).
  A new executable harness must be reviewed before use; do not reconstruct one
  from memory and claim it is the original test.
- **Required players or devices:** no player for Edit-mode cases; one Studio
  desktop host.
- **Authorization requirement:** none if temporary objects remain unparented or
  test-owned and no place is saved.
- **External service or publication requirement:** none.
- **Destructive-data risk:** low; a careless ad hoc harness could touch mapped or
  Studio-authored instances, so it must be scoped and reviewed.
- **Expected evidence:** stable structured fields, deterministic state/order,
  privacy-safe failures, cleanup of temporary objects, and no saved place change.
- **Cleanup procedure:** destroy all test-owned Instances/connections/tasks,
  remove the temporary harness, leave Edit mode, and do not save/publish.
- **Phase or prerequisite:** H-07 requires a future dedicated packet before these
  become reusable repository-owned tests.

### S-05 — Phase 04 engine-parity schema and bootstrap harnesses

- **System or contract:** all Phase 04 schemas, hostile Luau-table boundaries,
  engine serialization/freezing behavior, source loading, aggregate validation,
  and configuration-before-lifecycle bootstrap order.
- **Test category:** historical Studio Edit-mode harness and Studio solo
  integration evidence.
- **Current status:** `Historical evidence only`; the Phase 04 exit-audit
  harnesses passed on 2026-08-26 but are not tracked. The current headless suite
  covers the pure schema/configuration contract separately.
- **Environment:** correctly paired Lobby and Match Studio places, fresh clones
  of the synchronized shared tree, followed by local Play/Stop.
- **Command or procedure:** use the historical assertion inventory and safety
  procedure in [Phase 04 exit audit](PHASE_04_EXIT_AUDIT.md) and the current
  conditional Studio steps in
  [Configuration validation](CONFIGURATION_VALIDATION.md#regression-procedure).
- **Required players or devices:** one Studio operator; one local player per
  place for bootstrap integration.
- **Authorization requirement:** none for temporary Edit/Play validation without
  save or publish.
- **External service or publication requirement:** none.
- **Destructive-data risk:** low if all clones remain test-owned and lasting
  mapped source/content is not edited to force a failure.
- **Expected evidence:** the historical gate recorded 376 assertions in each
  correctly paired place, identical issue ordering, lasting empty/policy success,
  and three clean Play/Stop cycles per place.
- **Cleanup procedure:** destroy exact temporary clones/harnesses, stop Play,
  leave both places in Edit mode, and do not save/publish.
- **Phase or prerequisite:** available for targeted engine parity now; H-04 is
  the current reusable pure-contract coverage.

### S-06 — Graybox map contract and loader

- **System or contract:** map tags/attributes, lanes, path geometry, spawn/goal,
  placement zones, loader diagnostics, and Match-place integration.
- **Test category:** future local Studio solo/editor test.
- **Current status:** `Deferred`; no runtime map contract, loader, or graybox map
  has been implemented.
- **Environment:** future Match Studio place with reviewed Studio-authored
  graybox content and `match.project.json`.
- **Command or procedure:** none yet.
- **Required players or devices:** one Studio editor; later one local player.
- **Authorization requirement:** explicit approval is required before saving or
  publishing Studio-authored map changes.
- **External service or publication requirement:** no publication for local
  validation; Studio-authored content is required.
- **Destructive-data risk:** moderate if mapped/unknown Studio instances are
  edited carelessly; preserve unmapped content.
- **Expected evidence:** deterministic validator diagnostics and successful
  graybox loader smoke test without modifying unrelated instances.
- **Cleanup procedure:** remove only test-owned temporary instances; leave Edit
  mode and save only when separately authorized.
- **Phase or prerequisite:** Packets 07.1–07.4.

## Studio Server & Clients and other multi-client tests

### M-01 — Ready protocol and initial match state

- **System or contract:** server roster, per-player ready state, timeout policy,
  disconnect handling, and first-wave start gate.
- **Test category:** Studio Server & Clients multi-client test.
- **Current status:** `Deferred`; the match state machine, networking, ready
  protocol, and ready UI do not exist.
- **Environment:** future Match place in Studio Server & Clients mode.
- **Command or procedure:** none yet; the exact procedure belongs to Packet 08.5.
- **Required players or devices:** four simulated clients, exercising the
  established maximum roster.
- **Authorization requirement:** none for local unsaved Studio simulation.
- **External service or publication requirement:** none for the local Studio
  gate.
- **Destructive-data risk:** none with in-memory participant state.
- **Expected evidence:** no premature start, deterministic all-ready/timeout
  transition, safe disconnect behavior, and consistent UI/server state.
- **Cleanup procedure:** stop all clients/server and leave the place in Edit mode
  without save/publish.
- **Phase or prerequisite:** Phases 06 and 08; specifically Packet 08.5.

### M-02 — Placement, combat, and transaction races

- **System or contract:** authoritative placement, placement collision/races,
  target/combat correctness, Battle Cash, upgrades, selling, and targeting
  transactions.
- **Test category:** Studio multi-client correctness and exploit test.
- **Current status:** `Deferred`; these gameplay systems do not exist.
- **Environment:** future Match place with two or more Studio clients.
- **Command or procedure:** none yet; use packet-specific procedures when added.
- **Required players or devices:** at least two clients; include concurrent
  placement and transaction attempts.
- **Authorization requirement:** none for local in-memory Studio tests.
- **External service or publication requirement:** none for the local Studio
  gate.
- **Destructive-data risk:** none if Battle Cash and loadouts remain match-local.
- **Expected evidence:** server rejects invalid/replayed/racing requests,
  preserves authoritative balances and tower ownership, and produces consistent
  simulation outcomes.
- **Cleanup procedure:** stop simulation; no save/publish.
- **Phase or prerequisite:** Packets 13.5, 14.6, and 15.7 after Phase 06.

### M-03 — Party, queue, and captain concurrency

- **System or contract:** party membership, invitations, physical queue zones,
  captain authority, difficulty/map selection, roster lock, grief/race handling,
  and multi-lobby-server behavior.
- **Test category:** Studio multi-client test, followed later by private
  published multi-server testing.
- **Current status:** `Deferred`; party and queue systems do not exist.
- **Environment:** future Lobby place with multiple Studio clients; published
  private environment for cross-server cases.
- **Command or procedure:** none yet.
- **Required players or devices:** two to four clients locally; multiple real
  clients and lobby servers for the final cross-server gate.
- **Authorization requirement:** local Studio requires none; publication and
  private-client testing require explicit approval.
- **External service or publication requirement:** none for same-server Studio;
  publication is required for cross-server behavior.
- **Destructive-data risk:** low; use in-memory state until reviewed ephemeral
  storage exists.
- **Expected evidence:** deterministic captain/roster ownership, no duplicate or
  stranded queue state, safe leave/rejoin, and resistance to concurrent grief
  attempts.
- **Cleanup procedure:** stop clients/servers; later clear only exact test-universe
  ephemeral keys through reviewed tooling.
- **Phase or prerequisite:** Packets 24.5 and 25.7 for same-server party/queue
  behavior. Published travel/rejoin also requires Phases 26 and 28; true
  cross-server matchmaking/load evidence requires Phase 43, specifically Packet
  43.5, plus the private test universe.

### M-04 — Disconnect, reconnect, late arrival, and network simulation

- **System or contract:** disconnect policy, active-match routing, rejoin
  admission, spectator state, staggered teleport arrival, and adverse network
  conditions.
- **Test category:** Studio multi-client/network simulation plus published
  private-client testing.
- **Current status:** `Deferred`; no match admission, reconnect, spectator, or
  teleport system exists.
- **Environment:** future Studio Server & Clients for local cases and a private
  published test universe for real teleport/reconnect cases.
- **Command or procedure:** none yet.
- **Required players or devices:** at least two clients; multiple real sessions
  or accounts for published cases.
- **Authorization requirement:** explicit approval for publishing and any
  external-service enablement.
- **External service or publication requirement:** required for genuine
  teleport, reserved-server, and staggered-arrival evidence.
- **Destructive-data risk:** low to moderate; test-only routing/ticket records
  require exact cleanup and expiry.
- **Expected evidence:** valid players rejoin the correct match, invalid/replayed
  tickets fail closed, late arrivals converge safely, and disconnects do not
  corrupt authoritative state.
- **Cleanup procedure:** stop all sessions and clear only exact test-universe
  ephemeral records with reviewed tooling.
- **Phase or prerequisite:** Phases 26 and 28; specifically Packet 28.6 for the
  network simulation gate.

### M-05 — Full match player-count and repeated-session regression

- **System or contract:** solo/two/three/four-player scaling, finite difficulties,
  early/overlapping waves, boss plus simultaneous leaks, victory/defeat/result,
  return/retry, repeated matches, and long Endless behavior.
- **Test category:** Studio multi-client gameplay regression and soak test.
- **Current status:** `Deferred`; the match loop and content do not exist.
- **Environment:** future Match Studio Server & Clients plus private published
  servers for long/end-to-end cases.
- **Command or procedure:** none yet; the Phase 39 matrix completion packet must
  bind each scenario to deterministic content versions and acceptance criteria.
- **Required players or devices:** repeat with one, two, three, and four players;
  long-duration host for Endless/repeated-session cases.
- **Authorization requirement:** none for local in-memory Studio; explicit
  approval for private publication or persistent rewards.
- **External service or publication requirement:** none for initial local match
  simulation; later end-to-end return/reward paths require private publication.
- **Destructive-data risk:** low locally; moderate once test profiles/rewards are
  included, so use designated test accounts only.
- **Expected evidence:** deterministic scaling and outcomes, no old/new wave
  corruption, simultaneous leaks resolve once, terminal states are exclusive,
  and repeated sessions leak no state.
- **Cleanup procedure:** stop every client/server; later reset only exact
  designated test profiles through reviewed tooling.
- **Phase or prerequisite:** Phases 11, 17, 27, 31, and 32, with comprehensive
  execution in Packet 39.1.

### M-06 — Malformed, replayed, and spammed remote requests

- **System or contract:** remote registry, payload validation, rate limiting,
  authorization, correlation/error envelopes, replay resistance, and abuse
  containment.
- **Test category:** automated protocol tests plus Studio multi-client security
  regression.
- **Current status:** `Deferred`; Phase 06 networking has not begun and no remotes
  exist.
- **Environment:** future headless pure validator tests and Studio Server &
  Clients with an adversarial client harness.
- **Command or procedure:** none yet; Packet 06.5 must define stable attack cases
  before any feature remote is accepted.
- **Required players or devices:** zero for pure validators; at least two Studio
  clients for cross-player authorization and throttling isolation.
- **Authorization requirement:** none for local contained tests; do not attack a
  public or production server.
- **External service or publication requirement:** none for the initial gate.
- **Destructive-data risk:** none locally if all authoritative state is fixture or
  match-local; never log raw private payloads.
- **Expected evidence:** invalid, oversized, cross-player, replayed, and throttled
  requests fail closed with bounded stable errors while valid peers remain usable.
- **Cleanup procedure:** stop adversarial clients, destroy test-owned remotes, and
  retain no raw payload logs.
- **Phase or prerequisite:** Packet 06.5 initially, expanded by Phase 38.

## Published-client and private-version tests

### P-01 — Real party travel and match admission

- **System or contract:** queue launch, reserved-server teleport, signed/opaque
  match ticket, arrival admission, party preservation, and failure recovery.
- **Test category:** published private-client integration test.
- **Current status:** `Unavailable`; the systems and separate private test
  universe do not exist, and nothing is authorized for publication now.
- **Environment:** future private Test Lobby and Test Match places in a separate
  PHJGAMES-owned test universe.
- **Command or procedure:** none yet; Packet 26.6 must define the exact manual
  gate before execution.
- **Required players or devices:** up to four designated real clients/accounts;
  test solo and 2-4-player parties.
- **Authorization requirement:** explicit approval to create/configure the test
  universe, publish both places, and run the gate.
- **External service or publication requirement:** publication, TeleportService,
  reserved servers, and reviewed test-only ephemeral storage.
- **Destructive-data risk:** moderate if environment IDs are misconfigured; all
  production IDs must be rejected by test tooling.
- **Expected evidence:** complete group arrival, correct admission, replay and
  mismatch rejection, safe teleport failure handling, and no production data or
  credential use.
- **Cleanup procedure:** allow ephemeral keys/reserved servers to expire and use
  only exact reviewed test-universe cleanup operations.
- **Phase or prerequisite:** Phases 24–26, a separate private test universe, and
  explicit publication authorization.

### P-02 — Persistence lifecycle and migration

- **System or contract:** default profile, migrations, session locking,
  autosave/release, load failure, test-store separation, and safe recovery.
- **Test category:** Studio-in-test-universe and published private-client
  persistence test.
- **Current status:** `Unavailable`; persistence is not implemented, the private
  test universe is absent, and Studio API access must remain disabled in
  production.
- **Environment:** future separate test universe with explicit test store names,
  designated test UserIds, and API access enabled only there.
- **Command or procedure:** none yet; Packet 19.6 must define commands and exact
  target guards before execution.
- **Required players or devices:** designated test account(s), including two
  sessions for lock contention.
- **Authorization requirement:** explicit approval for test-universe setup, API
  access, published testing, and any destructive migration/reset case.
- **External service or publication requirement:** DataStore access; some cases
  require a published private version.
- **Destructive-data risk:** high if IDs/store names are wrong; production wipes
  and copied production profiles are prohibited.
- **Expected evidence:** correct migration/version behavior, session exclusion,
  idempotent release/retry, privacy-safe failures, and proof that only exact
  test-universe/test-store/test-user targets changed.
- **Cleanup procedure:** reviewed exact-user reset in the test store only; record
  resolved environment/store/UserId before mutation.
- **Phase or prerequisite:** Phase 19, separate private test universe, reviewed
  reset tooling, designated accounts, and explicit authorization.

### P-03 — Production rewards, retry, and return travel

- **System or contract:** result receipt, idempotent reward claim, retry/rematch,
  return to Lobby, and failure recovery across places.
- **Test category:** published private-client integration test.
- **Current status:** `Unavailable`; profile, match result, reward, and teleport
  systems do not exist.
- **Environment:** future separate private test universe.
- **Command or procedure:** none yet.
- **Required players or devices:** one to four real clients/accounts.
- **Authorization requirement:** explicit test-universe publication and
  persistence-test approval.
- **External service or publication requirement:** DataStore, TeleportService,
  and published private places.
- **Destructive-data risk:** moderate/high; duplicate claims or wrong environment
  configuration could mutate balances.
- **Expected evidence:** exactly-once reward, safe retry/return, no duplicate
  claim after reconnect, and test-only balance effects.
- **Cleanup procedure:** exact designated-test-user cleanup using Phase 19 tools.
- **Phase or prerequisite:** Phase 27 after Phases 19 and 26.

### P-04 — Closed-alpha candidate

- **System or contract:** complete first-session, Lobby, queue, travel, Match,
  result, persistence, compliance, operations, and rollback readiness.
- **Test category:** private published closed-alpha and release gate.
- **Current status:** `Unavailable`; the game and release configuration are not
  implemented.
- **Environment:** clean private alpha version, followed only later by a reviewed
  production candidate.
- **Command or procedure:** none yet; Phase 40 must supply the exact operations
  document, clean-room build, checklist, and go/no-go procedure.
- **Required players or devices:** representative alpha cohort across every
  supported platform and region requirement.
- **Authorization requirement:** explicit release, publication, tester-access,
  and go/no-go authorization.
- **External service or publication requirement:** yes; all intended production
  integrations in a controlled release configuration.
- **Destructive-data risk:** high; real accounts and persistent state are in
  scope, so rollback and support procedures are mandatory.
- **Expected evidence:** completed traceable matrix, no unresolved release
  blocker, verified rollback/support path, and explicit recorded go/no-go.
- **Cleanup procedure:** follow the future operations/rollback document; never
  improvise a production-data reset.
- **Phase or prerequisite:** Phase 40 after every preceding exit gate.

### P-05 — Analytics delivery and dashboard verification

- **System or contract:** privacy-safe event delivery, bounded dimensions,
  funnel/error usefulness, and dashboard interpretation.
- **Test category:** private published-client/external-service integration test.
- **Current status:** `Unavailable`; analytics contracts, sinks, dashboard, and a
  private published test release do not exist.
- **Environment:** future private test release with a reviewed analytics
  destination and non-sensitive designated accounts.
- **Command or procedure:** none yet; Packet 37.6 must define event-by-event
  evidence and retention/privacy boundaries before execution.
- **Required players or devices:** representative private clients for the flows
  that emit each event.
- **Authorization requirement:** explicit analytics-service, publication, and
  tester authorization.
- **External service or publication requirement:** yes; private publication and
  the approved analytics destination.
- **Destructive-data risk:** low for gameplay data but material privacy risk if
  payloads are not bounded; raw profiles/private player payloads are prohibited.
- **Expected evidence:** expected bounded events arrive once with useful safe
  dimensions, missing/duplicate events are diagnosable, and no secret or raw
  private value appears.
- **Cleanup procedure:** remove only test dashboard data when the provider and
  future policy support an exact safe operation; otherwise document retention.
- **Phase or prerequisite:** Phase 37, specifically Packet 37.6.

### P-06 — Cross-server public matchmaking load test

- **System or contract:** MemoryStore queue ownership/expiry, party-preserving
  assembly, cancellation races, cross-server handoff, degradation, and load.
- **Test category:** multi-server private published-client load test.
- **Current status:** `Unavailable`; this post-core system and private test
  environment do not exist.
- **Environment:** future private published Test Lobby fleet in a separate test
  universe with isolated MemoryStore namespaces.
- **Command or procedure:** none yet; Packet 43.5 must define the load profile,
  safety limits, observations, and abort/cleanup procedure.
- **Required players or devices:** multiple Lobby server processes and enough
  designated clients/bots to exercise party sizes and cancellation races.
- **Authorization requirement:** explicit private publication, MemoryStore, load,
  and test-account authorization.
- **External service or publication requirement:** MemoryStore and multiple
  private published servers.
- **Destructive-data risk:** moderate; wrong namespaces or unbounded load could
  strand test parties or consume service budget.
- **Expected evidence:** no duplicate/split/stranded party, bounded time and
  service usage, correct expiry/cancel race, and safe unavailable-store behavior.
- **Cleanup procedure:** stop load, close sessions, and expire or remove only the
  exact isolated test namespace through reviewed tooling.
- **Phase or prerequisite:** Phase 43, specifically Packet 43.5, after the core
  closed-alpha gate and separate test universe.

## Device, controller, touch, accessibility, and layout tests

### D-01 — Match HUD, camera, and core input

- **System or contract:** responsive HUD, camera, desktop input, touch placement,
  gamepad placement/navigation, enemy/base health presentation, and safe areas.
- **Test category:** device and input smoke test.
- **Current status:** `Deferred`; no gameplay HUD, camera, placement, or input
  action map exists.
- **Environment:** future Studio device emulation plus representative physical
  desktop, phone, tablet, and controller/console-style hardware.
- **Command or procedure:** none yet; Packet 16.6 must define the device smoke
  procedure after Packet 13.3 and Phase 16 implementation.
- **Required players or devices:** one player on each supported input family;
  include representative phone/tablet aspect ratios and a gamepad.
- **Authorization requirement:** none for local Studio/hardware tests; console or
  published-client access may require separate setup/approval.
- **External service or publication requirement:** not for initial Studio tests;
  later real-device client testing may require a private publication.
- **Destructive-data risk:** none.
- **Expected evidence:** every action is reachable and reversible, prompts match
  the active input, placement/camera remain controllable, and critical HUD data
  is readable within safe areas.
- **Cleanup procedure:** stop sessions; no save/publish solely for the test.
- **Phase or prerequisite:** Packets 13.3 and 16.1–16.6.

### D-02 — Shared UI shell and settings

- **System or contract:** navigation stack, modals, notifications, audio/settings
  model, Roblox accessibility preferences, focus, text scaling, and responsive
  layout.
- **Test category:** device, controller, touch, accessibility, and layout test.
- **Current status:** `Deferred`; the shared UI shell and settings UI do not exist.
- **Environment:** future Lobby and Match Studio device emulation, then physical
  supported devices.
- **Command or procedure:** none yet; Packet 20.6 must define exact viewport,
  input, and accessibility cases.
- **Required players or devices:** one player per supported input family and
  representative desktop/mobile/tablet viewports.
- **Authorization requirement:** none locally; private publication may be needed
  for final physical-device evidence.
- **External service or publication requirement:** none for initial local tests.
- **Destructive-data risk:** none; settings persistence must use a test profile
  once Phase 19 exists.
- **Expected evidence:** deterministic navigation/focus, no trapped modal, saved
  settings in the test environment, readable/scalable text, safe-area compliance,
  and equivalent function across mouse, keyboard, touch, and gamepad.
- **Cleanup procedure:** reset only the designated test profile/settings through
  reviewed test tooling; otherwise stop the local session.
- **Phase or prerequisite:** Phases 19 and 20; specifically Packet 20.6.

### D-03 — Lobby, inventory, gacha, and queue presentation

- **System or contract:** permanent Lobby HUD, inventory/loadout, gacha screens,
  party/queue configuration, respawn recovery, first-join loading, and input
  parity.
- **Test category:** device, layout, controller, and touch integration test.
- **Current status:** `Deferred`; these UI and gameplay systems do not exist.
- **Environment:** future Lobby Studio device emulation and private physical
  clients.
- **Command or procedure:** none yet; use packet-specific device gates when
  implemented.
- **Required players or devices:** representative desktop, phone, tablet, and
  gamepad/controller; multiple players for party/queue presentation.
- **Authorization requirement:** local tests require none; real private clients
  and publication require explicit approval.
- **External service or publication requirement:** none for early UI-only tests;
  private publication for final party/queue flow.
- **Destructive-data risk:** low to moderate once profiles and gacha exist; use
  designated test accounts/currency only.
- **Expected evidence:** no clipped/hidden critical control, stable respawn and
  first-join state, equivalent navigation, readable odds/currency information,
  and correct captain/non-captain affordances.
- **Cleanup procedure:** stop sessions and reset only exact test profiles when
  explicitly authorized.
- **Phase or prerequisite:** Phases 21–25; Packet 23.5 is the Lobby device and
  respawn gate.

### D-04 — Accessibility, localization, and supported-platform decision

- **System or contract:** keyboard-only operation, screen navigation, touch,
  console/gamepad, localization expansion, color/readability, reduced-motion or
  other supported preferences, and final supported-platform claims.
- **Test category:** accessibility, localization, and cross-platform audit.
- **Current status:** `Deferred`; complete user flows and localized/accessibility
  surfaces do not exist.
- **Environment:** representative physical hardware, Studio emulation, and
  private published clients where platform behavior requires it.
- **Command or procedure:** none yet; Phase 34 must define audited scenarios and
  acceptance criteria.
- **Required players or devices:** keyboard-only desktop, mouse/keyboard desktop,
  phone, tablet, controller/console-style device, and representative assistive
  settings; language pseudo-localization and target locales.
- **Authorization requirement:** none for Studio emulation; explicit private
  publication and device-access approval for final real-client evidence.
- **External service or publication requirement:** none for Studio emulation;
  private publication is required for final console and other real-client
  evidence.
- **Destructive-data risk:** none.
- **Expected evidence:** every critical flow is operable, focus and labels are
  meaningful, text expansion does not obscure controls, color is not the sole
  signal, and platform support is claimed only for passing targets.
- **Cleanup procedure:** stop private sessions and retain only privacy-safe issue
  records/screenshots approved for repository use.
- **Phase or prerequisite:** Phase 34 after feature-complete flows; earlier
  device gates in Phases 16, 20, 23, and 29 must also pass.

### D-05 — Performance, effects density, and long-session device behavior

- **System or contract:** frame time, memory, network traffic, instance/effect
  density, map/assets, lower-end device behavior, and long-session stability.
- **Test category:** device performance profile and soak test.
- **Current status:** `Deferred`; gameplay content and formal budgets do not exist.
- **Environment:** representative supported physical hardware and controlled
  private clients, with Roblox profiling tools.
- **Command or procedure:** none yet.
- **Required players or devices:** lower/mid/high representative desktop and
  mobile targets, controller target, multi-client server, and long-duration host.
- **Authorization requirement:** explicit private publication if real-client or
  multi-server behavior is required.
- **External service or publication requirement:** none for initial Studio
  profiling; private publication and Roblox-hosted servers are required for
  representative network/server soak evidence.
- **Destructive-data risk:** none, but logs/profiles must not expose player or
  credential data.
- **Expected evidence:** measured budgets and representative traces, stable
  memory/network behavior, acceptable effects density, and no long-session leak.
- **Cleanup procedure:** remove local profiler captures unless intentionally
  reviewed and tracked; stop all sessions and exact test servers.
- **Phase or prerequisite:** Packets 29.5, 32.6, and 35.6, plus Phase 36.

### D-06 — VR support decision

- **System or contract:** any future VR camera, input, comfort, world-space UI,
  placement, and accessibility contract.
- **Test category:** deferred platform decision and device audit.
- **Current status:** `Deferred`; VR is explicitly outside the current supported
  platform target and has no implementation or acceptance criteria.
- **Environment:** none selected; future representative Roblox-supported VR
  hardware and a private client would be required.
- **Command or procedure:** none. Do not infer VR support from desktop/gamepad
  behavior.
- **Required players or devices:** future representative VR headset/controller.
- **Authorization requirement:** an explicit product/platform scope decision is
  required before implementation or testing.
- **External service or publication requirement:** private publication is
  required for genuine device evidence if VR enters scope.
- **Destructive-data risk:** none.
- **Expected evidence:** to be defined only if VR enters scope.
- **Cleanup procedure:** stop the private session and retain only approved,
  privacy-safe evidence.
- **Phase or prerequisite:** a future roadmap amendment and explicit
  supported-platform decision after Phase 34; not part of the current core.

## Destructive or production-sensitive tests

### X-01 — Production DataStore mutation or profile wipe

- **System or contract:** production profile storage and player balances.
- **Test category:** destructive production-sensitive operation.
- **Current status:** `Prohibited` as a test strategy.
- **Environment:** production universe `10757629094` and its DataStores.
- **Command or procedure:** none; do not create a broad wipe command or enable
  Studio API access on production for testing.
- **Required players or devices:** not applicable.
- **Authorization requirement:** ordinary development authorization is
  insufficient. A future narrowly scoped operational repair would require a
  separately reviewed incident procedure and exact user/record authorization.
- **External service or publication requirement:** production DataStore.
- **Destructive-data risk:** critical and potentially irreversible.
- **Expected evidence:** no test should produce evidence from this operation.
- **Cleanup procedure:** not applicable; prevention is the control.
- **Phase or prerequisite:** never becomes an ordinary test. Use P-02 in the
  separate test universe after Phase 19.

### X-02 — Test-universe migration, reset, and failure injection

- **System or contract:** test profiles, migrations, corrupt/load-failure paths,
  session locks, and recovery tooling.
- **Test category:** destructive but isolated persistence test.
- **Current status:** `Unavailable`; the private test universe, persistence, and
  guarded reset tooling do not exist.
- **Environment:** future separate private test universe only.
- **Command or procedure:** none until the tool requires exact environment,
  DataStore name, and designated test UserId and fails closed on production IDs.
- **Required players or devices:** designated test account(s).
- **Authorization requirement:** explicit approval for each destructive test
  scope and external-service enablement.
- **External service or publication requirement:** test-universe DataStore; some
  cases may require private publication.
- **Destructive-data risk:** high but containable if all guards pass.
- **Expected evidence:** preflight shows exact test target, mutation affects only
  the authorized test record, recovery behavior is deterministic, and production
  identifiers are rejected.
- **Cleanup procedure:** exact-user/test-store cleanup through the same reviewed
  tool, with before/after evidence that contains no raw private profile.
- **Phase or prerequisite:** Packet 19.6 and the separate private test universe.

### X-03 — Ephemeral ticket/routing-store failure injection

- **System or contract:** MemoryStore-backed match tickets, active-match routing,
  expiration, replay, stale data, and cross-server recovery.
- **Test category:** destructive/production-sensitive ephemeral-service test.
- **Current status:** `Unavailable`; no MemoryStore/ticket/routing implementation
  or private test universe exists.
- **Environment:** future separate private test universe.
- **Command or procedure:** none yet; exact-key and namespace guards are required.
- **Required players or devices:** multiple clients/servers for integration cases.
- **Authorization requirement:** explicit external-service and publication
  approval.
- **External service or publication requirement:** MemoryStore, TeleportService,
  and private published servers.
- **Destructive-data risk:** moderate; broad deletion could disrupt active test
  sessions, and production namespaces must fail closed.
- **Expected evidence:** expiry/replay/stale-route behavior is safe and only exact
  test keys are touched.
- **Cleanup procedure:** exact key/namespace cleanup or documented expiry; never
  enumerate-delete a production namespace.
- **Phase or prerequisite:** Phases 26 and 28 plus guarded test tooling.

### X-04 — Gacha, purchases, and paid-random policy gates

- **System or contract:** banner odds, pity, atomic grants, purchase receipts,
  regional restrictions, disclosure, and duplicate acquisition.
- **Test category:** production-sensitive economy/compliance test.
- **Current status:** `Deferred`; no gacha, persistent economy, product, or
  purchase flow exists.
- **Environment:** deterministic headless fixtures first, then designated private
  test accounts/environment under reviewed Roblox policy settings.
- **Command or procedure:** none yet; real-money production transactions are not
  an acceptable routine test mechanism.
- **Required players or devices:** zero for odds simulation; designated real
  clients for later private receipt/UI gates.
- **Authorization requirement:** explicit product/configuration/publication and
  test-transaction approval.
- **External service or publication requirement:** none for pure probability
  tests; Roblox purchase services/private publication for receipt integration.
- **Destructive-data risk:** high if real currency or production inventory is
  involved.
- **Expected evidence:** deterministic odds/pity proofs, exactly-once receipt and
  inventory grant, correct regional/disclosure behavior, and no production-spend
  dependency.
- **Cleanup procedure:** use only designated test products/accounts and exact
  test-profile cleanup; never reverse or alter arbitrary production purchases.
- **Phase or prerequisite:** Phases 19, 21, and 22 for profile/inventory/free
  gacha, followed by Phase 44 for developer products and paid-Gold integration;
  real purchase test mode is Packet 44.5.

### X-05 — Broad production failure injection

- **System or contract:** dependency outages, remote abuse, persistence failure,
  teleport failure, queue failure, and operational recovery.
- **Test category:** production-sensitive resilience/security test.
- **Current status:** `Prohibited` in production during ordinary development and
  `Unavailable` in the intended private environment.
- **Environment:** future controlled private test universe with reviewed failure
  switches and rollback.
- **Command or procedure:** none yet.
- **Required players or devices:** depends on scenario; use designated accounts
  and controlled clients only.
- **Authorization requirement:** explicit per-scenario failure-injection,
  publication, and external-service approval.
- **External service or publication requirement:** Packet 38.5 must determine the
  exact boundary per scenario before execution; an end-to-end case that exercises
  hosted services requires private publication and those external services.
- **Destructive-data risk:** high; uncontrolled injection could strand players or
  corrupt state.
- **Expected evidence:** bounded failure, privacy-safe operational signal, no
  permanent inconsistent state, and verified recovery/rollback.
- **Cleanup procedure:** execute the future scenario-specific rollback and prove
  the injected condition is disabled.
- **Phase or prerequisite:** Packet 38.5 after the affected systems and private
  test environment exist.

## Current execution order

For every source/test change, use this local order from the repository root:

1. `stylua src tests`
2. `stylua --check --verify src tests`
3. `selene validate-config`
4. `selene src tests`
5. `lune run tests/run.luau`
6. `lune run tests/verify-builds.luau`
7. `git diff --check`
8. inspect `git status --short --ignored` and remove only exact generated outputs.

Run the applicable Studio, multi-client, published-client, device, or destructive
row only when its prerequisites exist and its authorization line is satisfied.
Do not replace a deferred environment-specific test with a headless test and call
the environment gate passed.
