# Test Matrix

## Purpose and status

This document is the authoritative test-environment and test-status index for
Ant Tower Defense. Packet 05.4 created it on 2026-08-26. It separates checks
that are automated today from Studio, published-client, device, and destructive
checks that require later systems or explicit authorization.

The Playable Local Match, Persistent Lobby Loop, and Squad Travel Loop outcomes
through historical Phase 28 are complete. Their historical baseline at commit
`fe48b9fe2a9b597d6d169530877465654c8c4e96` passed `1,419` headless tests, all
four structural builds, isolated Studio verification, and the authorized
private-staging Lobby/Match loop. The staging observations covered real solo
and three-player reserved travel, admission, rematch, reconnect, reward/Gold
refresh, and return; deterministic tests—not published clients—covered the
documented adversarial edges. Production was not tested or changed.

Content and Onboarding combines historical Phases 29–33 and is complete on
`codex/content-onboarding` at verified clean baseline commit
`ddd01c9c0d459d91639c122c5ae784c1e59608c3`. That outcome contains validated
release map and difficulty selection, four strategic towers, six enemy roles, exact
20/30/40-wave finite campaigns, bounded seeded Endless generation in the
existing runtime, version-2 results/rewards, and the profile-v6 authoritative
tutorial. Focused and full-gate checks cover content compatibility, authored
campaigns and balance, Endless determinism/bounds, reward idempotency, tutorial
transitions, travel continuity, protocols, and client projections. The
historical consolidated review was clean, cumulative headless coverage was
`1,486/1,486`, all four builds passed, and the Garden solo/mobile and
four-client Studio gates passed. Reduced-effects behavior is deterministic
client projection/view evidence, not a claimed live Studio toggle. No newly
published staging-client validation or uninstructed first-time-player
observation is claimed.

Platform, Presentation, Performance, and Analytics combines historical Phases
34–37 on `codex/platform-hardening`. Repository implementation and scoped local
verification are complete, the consolidated review is clean, cumulative headless
coverage is `1,601/1,601`, and all four builds passed. Delivery branch:
`codex/platform-hardening`. The
baseline full gate was not rerun merely to establish the starting point. H-17
and S-08 index the new contracts and local evidence. Phase 38 has not begun.

The message/pseudolocalization boundary, shared accessibility preferences,
cross-input navigation, client presentation/audio architecture, measured local
budgets, bounded analytics/logging, isolated commands and read-only balance
report have focused deterministic coverage. Studio observations include bounded
solo and four-client sessions; they do not establish physical-phone/tablet,
genuine console, published-client or external-service acceptance. No new version
was published, no analytics destination was configured and no experience platform
settings changed. Exact limitations are recorded in
[the design lock](PLATFORM_HARDENING_DESIGN_LOCK.md),
[presentation](PRESENTATION.md), [performance budgets](PERFORMANCE_BUDGETS.md)
and [analytics](ANALYTICS.md).

Rows for earlier packets preserve their original evidence and may describe the
repository as it existed then. H-16, S-07 and M-11 retain the completed Content
and Onboarding evidence; H-17 and S-08 are the current platform-hardening overlay.
Current status rows distinguish that historical baseline from new deterministic,
Studio, published, physical-device, destructive and external-service gates.

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
- `Pending` means a required check is available but its exact current external
  evidence has not run or has not yet been recorded.
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
- Repository-owned `tests/studio` tools are mapped by no Rojo project. Runtime
  harnesses are discarded with their local sessions; guarded Edit-mode
  authoring/repair commands default deny and may run only under exact identity,
  inventory, scope, and persistence authorization.
- Production universe `10757629094` is not a routine persistence-test target.
  Keep Studio API access disabled there. The complete environment policy is in
  [Place and test-environment inventory](PLACE_INVENTORY.md).
- Current Studio work is restricted to private staging GameId
  `10764687717`, Lobby PlaceId `140661668701496`, and Match PlaceId
  `104415140644510`, after confirming `PHJGAMES` group `35420107` ownership and
  the configured Lobby/Match role. No staging publication is implied.
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
- **Current status:** `Passed` for the complete Phase 12 exit run on Windows x64
  on 2026-08-28: `840` cases across `64` suites. The eight dedicated Phase 12
  Tower suites contain `90` focused cases; the directly affected
  MatchLifecycle suite passes `43/43`, including the consolidated-review
  regression.
- **Environment:** repository checkout with the versions pinned by `rokit.toml`;
  no Roblox Studio, network, publication, or external Roblox service.
- **Command or procedure:** run `lune run tests/run.luau`. For isolated failure
  semantics, run the six documented controls in
  [Automated test runner](TEST_RUNNER.md#packet-051-verification-evidence).
- **Required players or devices:** zero players; one Windows x64 development or
  CI host.
- **Authorization requirement:** none for local non-publishing execution.
- **External service or publication requirement:** none for the local check;
  H-06 separately records the required current GitHub Actions exit evidence.
- **Destructive-data risk:** none; the runner uses only deterministic fixtures
  and an exact ignored build path that it removes.
- **Expected Phase 09 evidence:** 39 suites and 467 tests pass in stable path and
  declaration order; zero discovery, module-load, malformed-root/discovery, and
  runner-crash controls return their documented nonzero exit classes; output
  contains stable suite, case, assertion, code, and path context without private
  sentinels.
- **Cleanup procedure:** confirm the runner removed its exact temporary test
  place and that `git status --short --ignored` shows no new residue.
- **Phase or prerequisite:** available now; Packet 05.1 established the runner,
  Packet 05.2 established the initial contract suite, Packets 06.1–06.5 added
  the networking foundation, and Phases 07–09 added the current map, Match, and
  enemy suites. Phase 10 adds the focused base suites indexed in H-12, and Phase
  11 adds the authored-wave suites indexed in H-13.

### H-02 — Cleanup contract

- **System or contract:** `Cleanup` ordering, ownership, supported task forms,
  idempotence, nesting/cycles, post-clean guards, cached failures, and sibling
  failure isolation.
- **Test category:** automated headless unit test.
- **Current status:** `Passed` as part of the 200-test suite on 2026-08-26.
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
- **Current status:** `Passed` as part of the 200-test suite on 2026-08-26.
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
- **Current status:** `Passed` as part of the 200-test suite on 2026-08-26.
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
- **Current status:** `Passed` for the completed Phase 12 inventory on
  2026-08-28. The current Default/Lobby/Match/Test builds contain
  `83/46/83/159` ModuleScripts;
  each production build has one Script and one LocalScript, Test has no runnable
  source and exactly `79` test-owned modules, and the verifier authenticates ten
  Match endpoints and six request policies. The Phase 11 `77/46/77/144` and
  `70` Test-owned inventory, Phase 06 audit-content run, and earlier inventories
  remain historical evidence.
- **Environment:** current local Windows x64 plus the GitHub Actions
  `windows-2025` runner using pinned Rojo and Lune.
- **Command or procedure:** run `lune run tests/verify-builds.luau`.
- **Required players or devices:** zero.
- **Authorization requirement:** none.
- **External service or publication requirement:** GitHub Actions is required
  for the current exit evidence; no Roblox service or publication is required.
- **Destructive-data risk:** none; generated builds are ignored and exact-path
  temporary outputs are removed.
- **Expected Phase 09 evidence:** Default and Match each contain exactly 63
  ModuleScripts, Lobby contains 44, and each has one Script and one LocalScript;
  Test contains 35 authoritative shared ModuleScripts, 25 exact production
  mirrors, and 51 test-owned ModuleScripts, with no runnable Script or
  LocalScript, for 111 ModuleScripts total;
  Lobby contains no Match
  source, Match contains no Lobby source, and production contains no test source
  or marker. All four manual `tests/studio` harness sources are mapped nowhere
  and occur in none of the four builds. Every Test-owned
  ModuleScript is independently matched to an exact DataModel path, class,
  authoritative file, and byte-for-byte source; unlisted Test-owned source
  fails the verifier.
- **Cleanup procedure:** the verifier removes its exact four outputs; confirm no
  generated place remains.
- **Phase or prerequisite:** available now; mapping details are in
  [Rojo Project Definitions](ROJO_PROJECTS.md). The Phase 06/Gate A exit audit
  and its exact current Actions evidence pass.

### H-06 — Formatting, linting, and genuine CI enforcement

- **System or contract:** StyLua, Selene, canonical tests, structural builds,
  generated-output residue, least-privilege workflow, and unambiguous negative
  controls.
- **Test category:** automated local quality gate and GitHub Actions CI.
- **Current status:** `Passed` for the complete Phase 12 local gate on
  2026-08-28: formatting, lint, `840` tests across `64` suites, all four
  structural builds, diff/scope/generated-output/test-exclusion/catalog/remote/
  rate/role-isolation checks. Exact-final-SHA Repository Verification is cited
  at handoff.
- **Environment:** local Windows x64 or GitHub-hosted `windows-2025`; tools and
  action pins are repository-controlled.
- **Command or procedure:** locally run, in order, `stylua src tests`, `stylua
  --check --verify src tests`, `selene validate-config`, `selene src tests`,
  `lune run tests/run.luau`, `lune run tests/verify-builds.luau`, and `git diff
  --check`, followed by the exact scope/generated-output/catalog/role-isolation
  checks. GitHub runs every non-writing verification gate through
  `.github/workflows/ci.yml`.
- **Required players or devices:** zero.
- **Authorization requirement:** none locally; pushing a branch or changing a
  workflow requires repository authorization.
- **External service or publication requirement:** GitHub Actions only for
  genuine CI evidence; no Roblox service or publication.
- **Destructive-data risk:** none. Required checks do not deploy, publish,
  release, upload artifacts, or use secrets.
- **Expected evidence:** every current clean step exits zero; the existing
  Phase 05 deliberate controls remain linked to their intended failing gates;
  workflow permissions are only `contents: read`; no artifact is retained.
- **Cleanup procedure:** restore a local temporary control before exiting. If a
  control was pushed for genuine CI evidence, follow it with an ordinary
  restoring commit; never rewrite history. Remove exact generated outputs and
  leave no broken working-tree state.
- **Phase or prerequisite:** the Phase 09 complete local sequence passed once
  after executable stabilization. Its genuine zero-artifact Repository
  Verification run for the exact final SHA is cited at handoff. Historical
  commits, runs, jobs, and security policy are in
  [Continuous integration](CONTINUOUS_INTEGRATION.md).

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

### H-08 — Network registry, payload validation, and server rate limiting

- **System or contract:** fixed authenticated remote registry, server-owned
  parent-last runtime, bounded fixed client lookup, authenticated composable
  payload schemas, explicit authenticated rate policies, and deterministic
  server-authoritative token buckets.
- **Test category:** automated headless protocol/security unit and integration
  test with deterministic test-only remote definitions and payloads.
- **Current status:** `Passed` for the current Packet 06.5 headless boundary on
  Windows x64 on 2026-08-26. M-06 records the completed initial Phase 06
  adversarial and Studio evidence.
- **Environment:** isolated Rojo Test DataModel under Lune; production runtime
  modules are copied to exact test-only `ServerStorage` paths, while shared
  validators use the normal `ReplicatedStorage.Shared` mapping.
- **Command or procedure:** run `lune run tests/run.luau`; inspect
  `RemoteRegistry.spec`, `RemoteRuntime.spec`, `PayloadValidation.spec`, and
  `ServerRateLimiter.spec`, plus the integrated `NetworkSecurity.spec` suite.
- **Required players or devices:** zero.
- **Authorization requirement:** none for local non-publishing execution.
- **External service or publication requirement:** none.
- **Destructive-data risk:** none; definitions, payloads, and Instances are
  test-owned. The current production catalog contains exactly the three Phase 08
  Match endpoints and two Phase 09 enemy endpoints, with one exact policy for
  each of the three inbound requests.
- **Expected evidence:** all 18 registry, 12 runtime/lookup, 22 payload, and 17
  limiter cases pass. Strict payload evidence includes exact/cap-plus-one
  limits, one shared speculative-union work budget, exact deterministic paths, finite
  numbers/vectors/CFrames, cycles, repeated aliases, hostile metatables/keys,
  every typed ID family, explicit server-only Instance class/ancestry policy,
  detached frozen table containers with approved Instance identity retained,
  and privacy-safe failures. Limiter evidence includes
  exact policy coverage and bounds, burst/refill math, independent Player/endpoint
  state, clock anomaly recovery, removal/shutdown cleanup, aggregate warning
  cadence, reporter failure isolation, and payload/identity-free diagnostics.
  Nine integrated adversarial cases additionally compose the fixed registry,
  lookup, validators, limiter, dispatcher, protocol, and tracker across hostile
  payload, forged-authority, spam, replay, failure, privacy, and cleanup paths.
- **Cleanup procedure:** destroy test-owned Instances and rely on the runner's
  exact generated-place cleanup; confirm no new residue.
- **Phase or prerequisite:** Packets 06.1–06.5 and the initial M-06 record are
  complete. Phase 08 and Phase 09 feature endpoints add their exact authenticated
  schemas, policies, ownership, convergence, and cleanup coverage without
  changing the foundational transport. Every future feature remote must still satisfy the
  [remote-security checklist](REMOTE_SECURITY_CHECKLIST.md) before it can ship.
  The Phase 06/Gate A audit and current Actions evidence pass. Phase 06 is
  complete and Gate A passed.

### H-09 — Request correlation, dispatch, and public errors

- **System or contract:** bounded asynchronous request/event/response envelopes,
  client correlation state, server-derived authorization context, fixed dispatch
  order, replay classification, safe error translation, and origin-only response
  routing.
- **Test category:** automated headless protocol/security unit and integration
  test with deterministic test-only contracts and mutation sentinels.
- **Current status:** `Passed` for the current Packet 06.5 headless boundary on
  Windows x64 on 2026-08-26. M-06 records the completed initial Phase 06
  adversarial and Studio evidence.
- **Environment:** isolated Rojo Test DataModel under Lune; the exact production
  protocol, client tracker, dispatcher, registry, limiter, and validator modules
  are exercised with fixed test-only registry definitions.
- **Command or procedure:** run `lune run tests/run.luau`; inspect
  `RequestProtocol.spec`, `ClientRequestTracker.spec`,
  `ServerRequestDispatcher.spec`, `RemoteRuntime.spec`, and the integrated
  `NetworkSecurity.spec` suite.
- **Required players or devices:** zero.
- **Authorization requirement:** none for local non-publishing execution.
- **External service or publication requirement:** none.
- **Destructive-data risk:** none; Players, remotes, payloads, senders, clocks,
  reporters, and mutation sentinels are test-owned.
- **Expected evidence:** all 13 protocol, 12 client-tracker, 21 dispatcher, and
  12 integrated runtime cases pass. The set covers malformed and oversized IDs,
  exact envelope keys, hostile tables, fixed endpoint/schema matching,
  Pending/Success/Rejected states, the 32-Pending and 128-terminal bounds,
  duplicate/stale/cross-endpoint behavior, rate-before-authorization ordering,
  protected handlers and response validation, non-yielding callback enforcement,
  rejection of handler-supplied validation metadata, origin-only sending,
  Player-removal and shutdown re-entry, public-error privacy, aggregate log
  bounds, and zero handler mutation after authorization-time removal or cleanup.
  The nine integrated adversarial cases add fixed client lookup/tracking,
  forged-authority rejection, cross-endpoint replay, independent peer/endpoint
  bursts, contained Request/Event handler failure, privacy-safe aggregation, and
  removal/shutdown mutation sentinels.
- **Cleanup procedure:** destroy test-owned Players and remotes, clear owned
  correlation/ledger state, and confirm the runner removed its exact generated
  place.
- **Phase or prerequisite:** Packets 06.1–06.5 and the initial M-06 record are
  complete. Every future feature remote still requires its approved boundary
  checklist. The Phase 06/Gate A audit and current Actions evidence pass. Phase
  06 is complete and Gate A passed.

### H-10 — Phase 07 map contract, validator, and loader

- **System or contract:** fixed map metadata, root-scoped deterministic
  validation, trusted catalog selection, parent-last loader transactions,
  detached lane queries, rollback, unload/reload, and cleanup.
- **Test category:** automated headless unit/integration tests with synthetic
  `MapFixtures` only.
- **Current status:** `Passed`. All 41 focused cases across `MapContract.spec`,
  `MapValidator.spec`, and `MapLoader.spec` pass, and the complete local suite
  passes 241 cases across 19 suites.
- **Environment:** isolated Rojo Test DataModel under Lune; exact production map
  modules are mapped under Test-only `ServerStorage` paths.
- **Command or procedure:** run `lune run tests/run.luau`; use `--spec
  MapContract`, `--spec MapValidator`, or `--spec MapLoader` while iterating.
- **Authorization/external/destructive risk:** none; fixtures are test-only and
  no production catalog or external service is used.
- **Expected evidence:** stable frozen diagnostics and snapshots, bounded
  adversarial rejection, zero partial runtime state, mutation isolation, and
  clean repeated load/unload/cleanup.
- **Cleanup procedure:** fixture/loader cleanup plus the H-01 residue check.
- **Phase or prerequisite:** Packets 07.1–07.3; authoritative contract is
  [Map Runtime Contract](MAP_RUNTIME_CONTRACT.md).

### H-11 — Phase 09 enemy simulation, replication, and renderer

- **System or contract:** match-scoped runtime identity and storage, detached
  fixed-lane sampling, one bounded server simulation loop, exact-once endpoint
  resolution, reliable bounded replication and late recovery, client convergence,
  interpolation/correction, one render loop, and mass cleanup.
- **Test category:** deterministic headless unit, integration, protocol, and
  controller tests with injected clocks and synthetic lanes.
- **Current status:** `Passed` for all `120` focused cases across `11` suites on
  2026-08-27; the combined exit run passes `467` cases across `39` suites.
- **Environment:** isolated Rojo Test DataModel under Lune. Production modules
  are mapped at exact test-only mirror paths; definitions, lanes, clocks,
  remotes, players, visuals, and senders are test-owned.
- **Command or procedure:** run `lune run tests/run.luau`; while iterating use
  `--spec` for `EnemyRuntimeStore`, `EnemyPath`, `EnemyMovement`,
  `EnemySimulationService`, `EnemyReplicationPublisher`, `EnemyProtocol`,
  `EnemyReplicationState`, `EnemyController`, `EnemyPresentation`,
  `EnemyRenderer`, or `EnemySimulationIntegration`.
- **Required players or devices:** zero.
- **Authorization/external/destructive risk:** none; no wall-clock wait, Roblox
  service, publication, production content, or Studio asset is used.
- **Expected evidence:** deterministic IDs and ordering, multi-lane/corner/large
  update travel, slows, exact-once endpoint/despawn, bounded publications,
  snapshot/delta convergence, stale/gap rejection, renderer correction and
  recreation, constant service-level connection counts, and idempotent cleanup.
- **Cleanup procedure:** test-owned Instances and state are cleaned by each case;
  the runner removes its exact generated Test build.
- **Phase or prerequisite:** Packets 09.1–09.5; authoritative contract is
  [Enemy Simulation and Replication](ENEMY_SIMULATION.md). Headless evidence does
  not claim engine rendering smoothness; M-07 records that separate Studio gate.

### H-12 — Phase 10 base runtime, replication, presentation adapters, and defeat

- **System or contract:** authenticated match-scoped base initialization,
  exact-once endpoint outcomes and safe-integer arithmetic, independent revision
  ordering, bounded reliable recovery/coalescing, world-view adapter behavior,
  one safe-boundary defeat, Results commit, result seed, and cleanup.
- **Test category:** deterministic headless unit, integration, protocol,
  controller, and fault-injection tests with injected clocks/schedulers/senders.
- **Current status:** `Passed` on 2026-08-28: `97` focused cases across the `9`
  dedicated Phase 10 base suites, with `593` cases across `48` suites in the
  complete repository run.
- **Environment:** isolated Rojo Test DataModel under Lune. Production base,
  enemy, lifecycle, and client modules are mapped at exact Test-only mirror
  paths; definitions, outcomes, clocks, remotes, players, marker/view adapters,
  and senders are test-owned.
- **Command or procedure:** run `lune run tests/run.luau`; while iterating use
  `--spec` for `BaseRuntime`, `BaseRuntimeService`, `BaseProtocol`,
  `BaseReplicationPublisher`, `BaseStateReducer`, `BaseViewModel`,
  `BaseWorldView`, `BaseController`, or `BaseDefeatIntegration`, plus directly
  affected enemy/lifecycle/network suites.
- **Required players or devices:** zero.
- **Authorization/external/destructive risk:** none; no wall-clock wait, Roblox
  service, publication, production content, or Studio asset is used.
- **Expected evidence:** authentic configuration/provenance and mutation
  isolation; every lifecycle state; zero/exact/overkill/high/simultaneous leaks;
  duplicate/stale/foreign/revoked rejection; low crossing; replication races,
  gaps, recovery, and sender faults; UI calculation/recreation adapters; one
  defeat/Results transition; spawn closure; ordered active-enemy cleanup;
  transition/publication/callback/shutdown faults; and residue-free idempotent
  cleanup.
- **Cleanup procedure:** each case clears test-owned state/Instances and the
  runner removes its exact generated Test build.
- **Phase or prerequisite:** Packets 10.1–10.4; authoritative contract is
  [Defender Base Runtime and Replication](BASE_RUNTIME.md). Headless evidence
  does not claim engine BillboardGui, Adornee, streaming, tween, or visual
  behavior; M-08 records that separate Studio gate.

### H-13 — Phase 11 authenticated authored-wave runtime and scheduler

- **System or contract:** authenticated finite configuration selection, bounded
  authored schedule compilation, stable due-spawn/deadline/intermission/skip
  ordering, exact Wave ownership/counters, Base/Enemy/MatchLifecycle composition,
  full-state replication and client recovery, finite completion, defeat
  preemption, fail-closed dependencies, and idempotent cleanup.
- **Test category:** deterministic headless unit, integration, protocol,
  controller, timing, bounds, and fault-injection tests with injected clocks,
  schedulers, senders, rosters, and canonical fixtures.
- **Current status:** `Passed` on 2026-08-28: `123` focused cases across the eight
  dedicated Phase 11 suites, with `742` cases across `56` suites in the complete
  repository run.
- **Environment:** isolated Rojo Test DataModel under Lune. Production Wave,
  Enemy, Base, MatchLifecycle, network, and client modules are mapped at exact
  Test-only mirror paths; fixtures and adapters are test-owned.
- **Command or procedure:** run `lune run tests/run.luau`; while iterating use
  `--spec` for `AuthenticatedWaveFixtures`, `WaveProtocol`, `WaveRuntime`,
  `WaveRuntimeService`, `WaveReplicationPublisher`, `WaveRuntimeIntegration`,
  `WaveStateReducer`, or `WaveController`, plus every directly affected Enemy,
  Base, MatchLifecycle, registry, and limiter suite.
- **Required players or devices:** zero.
- **Authorization/external/destructive risk:** none; no wall-clock wait, Roblox
  service, publication, production catalog, Studio asset, or persistent data is
  used.
- **Expected evidence:** authentic canonical roots and rejected forgeries;
  exact-time stable spawn ordering including deadline ties and deliberate
  overlap; empty waves and five-second intermissions; at-or-below-128 bounded
  passes; strict-majority skip and disconnect recomputation; originating-wave
  accounting; Store-commit reconciliation; one finite completion without
  Results; one defeat/Results preemption; one coalesced publication per semantic
  pass; stale/duplicate/gap/wrong-Match recovery without rollback or wedged
  recovery budget; privacy-safe terminal fault truth; and residue-free cleanup.
- **Cleanup procedure:** each case clears test-owned state/Instances and the
  runner removes its exact generated Test build.
- **Phase or prerequisite:** Packets 11.1–11.6; authoritative contract is
  [Authored Wave Runtime and Difficulty Scheduler](WAVE_RUNTIME.md). Headless
  evidence does not claim real engine transport, multi-client timing, or use of
  the authored Match lane; M-09 records that separate Studio gate.

### H-14 — Phase 12 authenticated TowerRuntime, temporary loadout, and model contract

- **System or contract:** one complete canonical Tower/Asset fixture
  transaction; three inert fixture roles; exact MatchId/towerEpoch and identity
  domains; five-slot Active-participant loadouts; opaque single-use occupied-
  slot capabilities; RuntimeTower creation/removal/caps/bounds; version-1
  template/live-model validation and ownership; service composition, fatal
  child/rollback adoption, and residue-free cleanup.
- **Test category:** deterministic headless unit, integration, hostile-input,
  identity, authority/security, hierarchy, transaction-ordering, capacity,
  arithmetic, callback, re-entry, fault-injection, and cleanup tests.
- **Current status:** `Passed` on 2026-08-28 for `90` focused cases across the
  eight dedicated Phase 12 suites. The directly affected MatchLifecycle suite
  passes `43/43`, including authentic observer detach after committed defeat.
  The complete repository gate passes `840/840` cases across `64` suites.
- **Environment:** isolated Rojo Test DataModel under Lune. The six production
  server-Match Tower modules are mapped at exact
  `ProductionServerTowers` paths; shared configuration and affected
  MatchLifecycle/Wave modules are exact production mirrors; `TowerFixtures` and
  all eight specs are Test-owned. Test contains no Script or LocalScript.
- **Command or procedure:** run `lune run tests/run.luau`; while iterating use
  `--spec` for `AuthenticatedTowerFixtures`, `TemporaryLoadoutStore`,
  `TowerRuntimeStore`, `TowerModelContract`, `TowerGrayboxFactory`,
  `TowerModelOwner`, `TowerRuntimeService`, or `TowerRuntimeIntegration`, plus
  directly affected `MatchLifecycleService` coverage.
- **Required players or devices:** zero.
- **Authorization/external/destructive risk:** none; no wall-clock wait,
  Roblox service, production content, persistent data, saved Model, upload, or
  publication is used.
- **Expected evidence:** exact canonical root/catalog/manifest/definition
  identities and rejected forgeries; single/splash/support cross-rules; stable
  occupied/empty slot order and temporary UnitId isolation; forged/replayed/
  stale/wrong-owner/wrong-match capability rejection; numeric RuntimeTowerId
  separation and no reuse; per-owner placement caps and 128/4,096 technical
  bounds; exact initial record values; nonfinite/arithmetic/counter closure;
  strict attacking/non-attacking hierarchy and variant selection; clone/pivot/
  parent/tamper/recreation adapters; coordinator adoption of child throw/yield/
  fault and rollback failure; dormant empty production; no endpoint, Tower
  client, placement, combat, economy, persistence, or Phase 13 behavior; and
  idempotent cleanup with inert late work.
- **Cleanup procedure:** every case closes all capabilities/records/models/
  callbacks and the runner removes only its exact generated Test build.
- **Phase or prerequisite:** Packets 12.1–12.4; authoritative contract is
  [Tower Runtime and Temporary Loadout](TOWER_RUNTIME.md). Headless adapters do
  not claim engine Model cloning, PrimaryPart/pivot, replication, visibility,
  or Instance-destruction behavior; M-10 records that exact Studio gate. M-02
  now records the completed Phase 13 placement-race portion; combat and Phase
  15 transactions remain deferred.

### H-15 — Phase 13 placement preview, geometry, protocol, and atomic admission

- **System or contract:** shared authored-footprint geometry and surface rules;
  caller-private placement snapshots/revisions; exact reliable protocol/rate
  policy; desktop/touch/gamepad input-reducer-view-controller state machines;
  authoritative validation, reservation, affordability placeholder,
  TowerRuntime capability/create/rollback integration, races, and cleanup.
- **Test category:** deterministic headless unit, integration, hostile-input,
  network, concurrency, re-entry, fault-injection, and cleanup tests.
- **Current status:** `Passed` on 2026-08-30 for `100` focused cases across the
  nine dedicated Phase 13 suites. The complete gate passes `941` cases across
  `73` suites and all four structural builds at `91/48/91/176` ModuleScripts.
- **Environment:** isolated Rojo Test DataModel under Lune. Shared, server, and
  client placement modules are exact production mirrors; all fixtures/specs are
  Test-owned, and Test contains no Script or LocalScript.
- **Command or procedure:** run `lune run tests/run.luau`; while iterating use
  `--spec` for `PlacementGeometry`, `PlacementProtocol`,
  `PlacementInputAdapter`, `PlacementPreviewReducer`, `PlacementPreviewView`,
  `TowerPlacementController`, `TowerPlacementQuery`,
  `TowerPlacementService`, or `TowerPlacementNetwork`.
- **Required players/devices/external/destructive risk:** zero; no Roblox
  service, wall-clock wait, persistence, production content, saved Model,
  upload, publication, wallet, or external dependency is used.
- **Expected evidence:** exact graph/numeric bounds; tangency/containment/
  exclusion/surface/height rules; private five-slot snapshots; bootstrap and
  revision coalescing; one raycast per frame; gesture-safe touch; bounded
  gamepad reticle; exact intent only; server-derived identity/definition/map/
  transform/caps; replay/rate/privacy closure; overlapping and independent
  races; every reservation/create/rollback fault seam; zero double placeholder
  commit; and inert late callbacks/work after idempotent cleanup.
- **Cleanup procedure:** every case closes trackers, callbacks, reservations,
  placeholder tokens, capabilities, records, models, roots, and test state; the
  runner removes only its exact generated Test build.
- **Phase or prerequisite:** Packets 13.1–13.5; authoritative contract is
  [Tower Placement](TOWER_PLACEMENT.md). Headless evidence does not claim live
  input, engine raycasts/replication, or device layout; M-02 records those exact
  Studio scenarios.

### H-16 — Content selection, campaigns, Endless, rewards, and onboarding

- **System or contract:** additive content identity and compatibility;
  server-owned map/difficulty selection; four tower and six enemy roles;
  20/30/40 authored campaigns; legal Garden placement/range balance; generic
  splash combat; stateless seeded Endless generation and runtime bounds;
  version-1/result-version-2 reward compatibility and exactly-once claims;
  profile-v6 tutorial migration/state transitions; authenticated travel
  continuity; and bounded client projections.
- **Test category:** deterministic headless unit, schema, simulation,
  compatibility, hostile-input, idempotency, soak, client reducer/view, and
  server integration tests.
- **Current status:** `Passed` on 2026-09-04 after a clean consolidated review.
  The milestone gate ran once: StyLua check/verify passed, Selene configuration
  and `src`/`tests` lint passed, and Default, Lobby, Match, and Test all built.
  The initial complete headless run passed `1,484/1,486`; the two failures were
  stale expectations in `AuthenticatedTowerFixtures` and
  `PersistentMatchLoadoutIntegration`. After correcting only those
  expectations, the affected specs passed `15/15` and the affected Test build
  passed, giving the resulting tree cumulative `1,486/1,486` coverage.
  Development checkpoints also included a `383/383` changed-spec bundle and a
  final `52/52` `MatchTravelHost` run.
- **Environment:** isolated Rojo Test DataModel under Lune. The balance model is
  test-only and uses authored legal Garden pockets and two-dimensional path
  range; it does not replace engine placement, rendering, camera, or device
  observations.
- **Command or procedure:** the completed iteration ran the relevant specs
  together, including `ContentCatalog`, `EndlessWaveGenerator`,
  `PlayableMatchRuntime`,
  `PlayableMatchProtocol`, `MatchResultContract`, `RewardPolicy`,
  `ProfileRewardClaimService`, `TutorialProtocol`, `TutorialService`,
  `LobbyQueueService`, `LobbyController`, `LobbyUiModel`, `LobbyView`,
  `PlayableMatchController`, and `PlayableMatchView`, followed by exactly one
  full milestone gate using the commands in the current execution order.
- **Required players/devices/external/destructive risk:** zero for headless
  coverage; no wall-clock campaign wait, Roblox service, DataStore,
  MemoryStore, teleport, purchase, publication, or production mutation occurs.
- **Expected evidence:** legacy IDs remain first and unchanged; hidden content
  cannot be queued; authenticated tickets select only compatible content; all
  finite wave counts and ten-wave bosses are exact; starter and alternate
  two-role loadouts complete deterministic Easy; 10,000 generated Endless waves
  repeat within all bounds; terminal rewards and receipts cannot duplicate;
  only server-observed tutorial events advance; malformed, stale, replayed,
  public, squad, spectator, and foreign-match inputs fail closed; clients show
  display names, boss information, Endless state, and contextual guidance.
- **Cleanup procedure:** every test releases service/profile/runtime state and
  the runner removes only its exact generated Test build.
- **Phase or prerequisite:** historical Phases 29–33 as one Content and
  Onboarding outcome. S-07 and M-11 retain the engine/device/multi-client
  boundaries that headless tests cannot satisfy.

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
  isolation, configuration validation, one foundation-only server network
  service with zero gameplay services, zero client services, Cleanup ownership,
  logging, and bounded server shutdown.
- **Test category:** local Studio solo regression.
- **Current status:** `Passed` on 2026-08-26 for the current Phase 06 build; all
  three Lobby Play/Stop cycles passed with server service count 1, client service
  count 0, a production root with zero endpoints, and clean shutdown.
- **Environment:** Roblox Studio Lobby place `100561454756026` with only
  `lobby.project.json` connected.
- **Command or procedure:** follow the Lobby half of the
  [Phase 06 plain-place lifecycle procedure][phase-06-plain-lifecycle].
  The general shutdown and configuration references remain
  [Graceful shutdown](GRACEFUL_SHUTDOWN.md#manual-regression-procedure) and
  [Configuration validation](CONFIGURATION_VALIDATION.md).
- **Required players or devices:** one local desktop player and the Studio server.
- **Authorization requirement:** none for Edit/Play without save or publish.
- **External service or publication requirement:** none.
- **Destructive-data risk:** none.
- **Expected evidence:** role `Lobby`, correct PlaceId, nine validated families,
  one common Script and LocalScript, no Match source, server ready with one
  `NetworkRegistry` service and zero gameplay services, client ready with zero
  services, and clean bounded shutdown for three consecutive cycles when running
  the full regression.
- **Cleanup procedure:** stop Play, return to Edit mode, do not save/publish, and
  stop the Lobby Rojo server before connecting another project.
- **Phase or prerequisite:** current Packet 06.5 evidence passed 3/3; rerun after
  a relevant bootstrap, lifecycle, network-owner, or project-mapping change.

### S-03 — Isolated Match bootstrap and shutdown regression

- **System or contract:** Match place identity, common-plus-match source
  isolation, configuration validation, one foundation-only server network
  service with zero gameplay services, zero client services, Cleanup ownership,
  logging, and bounded server shutdown.
- **Test category:** local Studio solo regression.
- **Current status:** `Historical evidence only` for the Phase 06 composition;
  all three then-current Match Play/Stop cycles passed with server service count
  1, client service count 0, an empty production root, and clean shutdown. M-01
  and M-07 supersede that runtime inventory for Phases 08 and 09.
- **Environment:** Roblox Studio Match place `136401514513678` with only
  `match.project.json` connected.
- **Command or procedure:** follow the Match half of the
  [Phase 06 plain-place lifecycle procedure][phase-06-plain-lifecycle].
  The general shutdown and configuration references remain
  [Graceful shutdown](GRACEFUL_SHUTDOWN.md#manual-regression-procedure) and
  [Configuration validation](CONFIGURATION_VALIDATION.md).
- **Required players or devices:** one local desktop player and the Studio server.
- **Authorization requirement:** none for Edit/Play without save or publish.
- **External service or publication requirement:** none.
- **Destructive-data risk:** none.
- **Expected evidence:** role `Match`, correct PlaceId, nine validated families,
  one common Script and LocalScript, no Lobby source, server ready with one
  `NetworkRegistry` service and zero gameplay services, client ready with zero
  services, and clean bounded shutdown for three consecutive cycles when running
  the full regression.
- **Cleanup procedure:** stop Play, return to Edit mode, do not save/publish, and
  stop the Match Rojo server when finished.
- **Phase or prerequisite:** Packet 06.5 evidence passed 3/3 historically;
  current Match lifecycle, network, and cleanup evidence is in M-01 and M-07.

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
- **Test category:** local Studio Play regression plus controlled Edit-mode
  authoring/persistence gate.
- **Current status:** `Passed` on 2026-08-27 for implementation, Studio content,
  consolidated review, and the complete local exit gate.
- **Environment:** exact Match PlaceId `136401514513678`, GameId `10757629094`,
  PHJGAMES Group `35420107`, role `Match`, with only `match.project.json`.
- **Command or procedure:** follow the gate and evidence in
  [Map Runtime Contract](MAP_RUNTIME_CONTRACT.md#studio-persistence-gate).
- **Required players or devices:** one Studio editor and one local Play server.
- **Authorization requirement:** the one reviewed graybox Save To Cloud was
  explicitly authorized and succeeded at `2026-08-27T02:11:31Z`; no broader
  publication/settings authorization exists.
- **External service or publication requirement:** none beyond that completed
  controlled save.
- **Destructive-data risk:** moderate if mapped/unknown Studio instances are
  edited carelessly; preserve unmapped content.
- **Expected evidence:** the prior unsaved Play regression passed 169 checks.
  The lasting transaction recorded `98 -> 123` inventory records, exactly 25
  additions, zero removals/unrelated changes, one template, one five-point bent
  lane, and zero retained runtime roots.
- **Cleanup procedure:** loader cleanup removes the runtime clone. Studio remains
  in Edit with only the exact 25-record trusted catalog lasting.
- **Phase or prerequisite:** Packets 07.1–07.4 and the Phase 07 gate are
  complete. Phase 08 subsequently completed without changing the saved
  Phase 07 map catalog.

### S-07 — Content and Onboarding Garden authoring and solo acceptance

- **System or contract:** release Garden map contract, fixed path and ordered
  waypoints, four spawns, camera bounds/framing, placement/exclusion pockets,
  playable tower/enemy templates, content selection, boss/Endless presentation,
  reduced effects, and the singleton Easy onboarding path.
- **Test category:** guarded private Team Create inventory/authoring audit,
  followed by one consolidated connected Match Studio solo/device regression.
- **Current status:** `Passed` on 2026-09-04. Before the first persistent edit,
  live identity, role, and ownership matched the configured private staging
  experience. The guarded additive authoring transaction created the Garden,
  Bombardier, Broodling, and Royal Guard templates in authorized roots. A
  default-deny placement repair produced four legal build pockets and one
  visible exclusion; the resulting 212-descendant map passed the live validator
  and direct legal/blocked placement probes, introduced no script, preserved
  every legacy template, and left no runtime/preview residue. An iPhone 17 Pro
  landscape session then verified readable Garden framing, authored camera
  bounds, touch placement, selection, upgrade, and the safe defeat path.
  Reduced-effects communication passed deterministic projection/view coverage;
  no live Studio toggle is claimed.
- **Environment:** private staging GameId `10764687717`, Match PlaceId
  `104415140644510`, owner `PHJGAMES` Roblox Group `35420107`, role `Match`,
  synchronized only from `match.project.json`. Lobby PlaceId
  `140661668701496` is inspected only for the bounded onboarding/queue boundary.
- **Command or procedure:** live GameId, PlaceId, group ownership, role, and
  authorized-root inventory were reverified; one managed background Match Rojo
  session was connected and reused. The session batched map-contract,
  legal/blocked placement, camera, solo Easy, and representative phone-layout
  observations, then stopped Play and Rojo deliberately. Reduced-effects
  behavior was checked in the deterministic client projection/view gate.
- **Required players or devices:** one solo desktop client plus representative
  phone emulation. M-11 covers four-client concurrency.
- **Authorization requirement:** the milestone authorizes narrow persistent
  Team Create changes only under `ServerStorage.ATDMapTemplates`,
  `ReplicatedStorage.ATDPlayableTemplates`, existing ATD-owned Lobby queue/world
  content, and one bounded `ATDTutorial...` root if needed. Identity mismatch is
  a hard stop.
- **External service or publication requirement:** none for this Studio gate.
  No new private staging version may be published without a separate specific
  approval.
- **Destructive-data risk:** moderate if the wrong Team Create identity or root
  is touched. Guarded commands use exact expected identities/inventories and
  transactional rollback; Rojo-managed scripts, unrelated instances, and
  production are out of scope.
- **Expected evidence:** Garden loads without a content-specific runtime branch;
  lane, choke points, nest, goal, and build pockets remain readable; intended
  starter placements are legal while lane/props/spawns/goal are blocked; camera
  limits and phone HUD remain usable; low-detail/reduced-motion preserves
  warnings and silhouettes; solo Easy can place and upgrade; no error or owned
  runtime residue remains.
- **Cleanup procedure:** exact audit previews/runtime clones were destroyed,
  Play and the managed Rojo process stopped, simulator settings were restored,
  and the authorized roots were inventoried. Match ended with two map
  children/237 descendants, Garden at 212 descendants, ten playable-template
  children/83 descendants, zero scripts, and no runtime/direct attributes. The
  Lobby queue root remained one child/one descendant with zero scripts. The
  persistent Garden/templates remain the authorized Team Create result; no new
  place version was published.
- **Phase or prerequisite:** Content and Onboarding Phases 29–33. The identity
  and initial authoring portion is recorded in
  [the design lock](CONTENT_ONBOARDING_DESIGN_LOCK.md).

## Studio Server & Clients and other multi-client tests

### M-01 — Ready protocol and initial match state

- **System or contract:** server roster, per-player ready state, timeout policy,
  disconnect/reconnect-placeholder handling, revisioned snapshot protocol,
  minimal Ready UI/input, and the `PreWave` start gate. No wave or combat
  behavior is included.
- **Test category:** Studio Server & Clients multi-client test.
- **Current status:** `Passed` on 2026-08-27 for the exact Packet 08.5 Studio
  gate. The consolidated final review and complete Phase 08 local exit gate also
  pass.
- **Environment:** connected Match Studio PlaceId `136401514513678`, GameId
  `10757629094`, CreatorType `Group`, CreatorId `35420107`, official group API
  name `PHJGAMES`, resolved `ATDPlaceRole = Match`, with only
  `match.project.json` synchronized. Every sub-session began and ended in Edit
  mode.
- **Command or procedure:** follow
  [Packet 08.5 four-client procedure](MATCH_LIFECYCLE_READY.md#packet-085-four-client-procedure).
  Capture the bounded persistent inventory and mapped source first; then use
  fresh four-client Server & Clients sub-sessions for zero-ready, one-ready
  mixed timeout, all-ready input, stale/duplicate protocol, and early-disconnect
  cases. Use direct MCP Luau for setup/assertions and the authorized Studio
  controls only where MCP lacks Server & Clients or device/input control. Run
  the isolated production-roster reconnect-placeholder harness through direct
  MCP while a fresh four-client session remains live, end every sub-session,
  reset emulation, and repeat the residue probe.
- **Required players or devices:** four simulated clients. The all-ready run used
  keyboard `R` on Players 1 and 4, virtual `ButtonA` on Player 2, and the
  touch-translated Ready button on Player 3 under iPhone 17 Pro emulation
  (`TouchEnabled`, viewport `750x361`).
- **Authorization requirement:** the user authorized active Team Create Rojo
  synchronization of only current-branch mapped Match source and unsaved local
  simulation. Manual Script.Source edits, Script Sync, save, publish, settings,
  Lobby content, and unrelated instances remained unauthorized.
- **External service or publication requirement:** none for the local Studio
  gate.
- **Destructive-data risk:** low because Team Create synchronization touches
  mapped source; the pre/post inventory and exact source capture guard unmapped
  content. Match/roster state itself is in-memory.
- **Expected evidence:** zero ready reached identical `Closing` revision `7` on
  all four clients; mixed timeout reached identical `PreWave` revision `9` with
  one `Active` ready and three `Returned`; all ready reached identical
  `PreWave` revision `11` with four `Active` ready; initial recovery succeeded
  at revision `7`, followed by `STALE_REQUEST` and `DUPLICATE_REQUEST` without
  an extra transition; early disconnect left Player 2/UserId `-2`
  `Disconnected` and caused immediate consistent `PreWave` revision `11` after
  three Ready actions. In a fresh live session, four registered client
  DataModels each reported four players in the exact Match place while the
  isolated same-UserId reconnect/returned-placeholder production-module harness
  passed `43` assertions without touching the production match.
- **Cleanup procedure:** stop every server/client sub-session and leave Studio
  in Edit mode without save/publish. The final probe counted `54` ModuleScripts,
  one Script, one LocalScript, the exact server/client common bootstrap paths,
  and `24` map-catalog descendants; it found no runtime map, `ATDNetwork`, Ready
  GUI, `AutomatedTests`, or `TestRunner`. Device emulation was reset and no
  simulated window remained.
- **Phase or prerequisite:** Phases 06 and 08. M-01 and the Phase 08 exit gate
  passed. Phase 09 subsequently reused this Ready contract without changing its
  roster or state-transition rules; see M-07.

### M-02 — Placement, combat, and transaction races

- **System or contract:** authoritative placement, placement collision/races,
  target/combat correctness, Battle Cash, upgrades, selling, and targeting
  transactions.
- **Test category:** Studio multi-client correctness and exploit test.
- **Current status:** `Passed` for the current Content and Onboarding scope. The
  historical Phase 13 placement-race evidence remains valid, while combat,
  Battle Cash, upgrade, sell, target-mode authority, and generic splash have
  deterministic coverage. M-11 added current private-staging engine evidence:
  four clients each placed one independently owned Dart, every client received
  owner controls, and one authoritative level-two upgrade converged without
  residue. It did not repeat every historical malformed/race case in Studio.
- **Environment:** historical evidence used Match place `136401514513678` in
  production GameId `10757629094`. Current content verification must use only
  private staging Match PlaceId `104415140644510`, GameId `10764687717`, with
  two to four local Studio clients and representative device emulation.
- **Command or procedure:** follow
  [Executed Phase 13 Studio evidence](TOWER_PLACEMENT.md#executed-studio-evidence--2026-08-30).
- **Required players or devices:** at least two clients; include concurrent
  placement and transaction attempts.
- **Authorization requirement:** none for local in-memory Studio tests.
- **External service or publication requirement:** none for the local Studio
  gate.
- **Destructive-data risk:** none if Battle Cash and loadouts remain match-local.
- **Expected evidence:** the historical placement portion passed exactly one
  overlapping success, both independent successes, no double placeholder
  commit, safe malformed/forged/stale/replay/rate rejection, identical
  replicated Models, eight constant client connections, natural recovery from
  two pre-activation query rejections without a Studio refresh, safe-area phone
  layout, and zero residue. The current M-11 addition records independent
  ownership, one upgrade, and live combat progression; broader economy/splash
  outcomes remain deterministic evidence rather than new Studio claims.
- **Cleanup procedure:** every simulated client/server stopped, Xbox/iPad
  emulation reset, final Edit probe found no runtime/evidence residue, and no
  save/publish occurred.
- **Phase or prerequisite:** Packets 13.5, 14.6, and 15.7 after Phase 06.

### M-03 — Party, queue, and captain concurrency

- **System or contract:** party membership, invitations, physical queue zones,
  captain authority, difficulty/map selection, roster lock, grief/race handling,
  and multi-lobby-server behavior.
- **Test category:** Studio multi-client test, followed later by private
  published multi-server testing.
- **Current status:** `Passed` for the completed Squad Travel baseline's
  server-authority coverage and authorized private-staging same-squad travel.
  The current branch additionally validates release map/difficulty choices and
  rejects hidden/development selections. Current Garden Match presentation
  passed S-07/M-11; Lobby labels and onboarding presentation passed deterministic
  client coverage, while a newly published newcomer journey is not claimed.
- **Environment:** Lobby Studio multi-client checks plus the dedicated private
  staging Lobby/Match experience. Cross-server public matchmaking remains a
  separate Phase 43 concern.
- **Command or procedure:** use focused party/queue/ticket specs for authority;
  use the already configured private staging environment only under the exact
  authorization for any real travel rerun.
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
- **Current status:** `Passed` for the completed Squad Travel baseline. Private
  staging exercised authenticated admission, in-match reconnect with retained
  ownership/state, and return. Deterministic authority tests cover invalid,
  replayed, late, spectator, stale-route, and never-arrived boundaries. Content
  version 1 preserves that graph; the tutorial's matching ticket/result/return
  transitions have headless coverage, while a newly published newcomer journey
  is not claimed.
- **Environment:** local Studio Server & Clients for deterministic engine cases
  and the dedicated private staging experience for the completed real travel/
  reconnect baseline.
- **Command or procedure:** run the focused admission/routing/travel/tutorial
  specs. Any new real-client run requires the exact staging version and
  authorization then in force.
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
- **Current status:** `Partially complete; current Content and Onboarding gate
  passed`. Deterministic simulation validates exact authored campaigns,
  beginner Easy viability, terminal-state exclusivity, and 10,000 generated
  Endless waves without real-time waits. S-07 and M-11 supplied the bounded
  solo and four-client Garden engine, presentation, and cleanup evidence. The
  broader one/two/three/four-player repetition and hosted long-session matrix
  remains later Phase 39 work rather than a Phase 29–33 blocker.
- **Environment:** private staging Match Studio Server & Clients for the current
  local gate. Any later long hosted/end-to-end run requires a separately
  authorized private publication.
- **Command or procedure:** use H-16 for deterministic content/soak coverage and
  M-11 for the bounded current Studio session. Phase 39 will broaden the matrix
  rather than redefine the Phase 32 generator bounds.
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
- **Current status:** `Passed` for the fresh Phase 06/Gate A local record on
  2026-08-26. Three byte-identical complete 200-case runs and nine integrated
  headless adversarial cases passed together with the
  [exact current-source unsaved two-client Studio evidence][phase-06-two-client-evidence].
- **Environment:** isolated Lune Test DataModel for deterministic protocol logic;
  correctly paired Match Studio `Server & Clients` with exactly two clients for
  engine transport, origin, routing, datatype, and disconnect behavior. The two
  tracked `tests/studio` harness sources are mapped nowhere and are injected only
  into runtime DataModels that are discarded at session end.
- **Command or procedure:** run `lune run tests/run.luau` and inspect the
  nine-case `NetworkSecurity.spec` suite, then follow the exact
  [runtime-only two-client procedure][phase-06-two-client-procedure].
- **Required players or devices:** zero for the headless attack set; exactly two
  Studio clients and one local server for the engine regression.
- **Authorization requirement:** none for local contained tests; do not attack a
  public or production server.
- **External service or publication requirement:** none for the initial gate.
- **Destructive-data risk:** none locally if all authoritative state is fixture or
  match-local; never log raw private payloads.
- **Expected evidence:** the completed initial record proves malformed, oversized, deeply
  nested, cyclic, hostile-metatable, non-finite, and unexpected-Instance payloads
  fail closed with stable privacy-safe paths. It also proves deterministic
  bursts/refills, independent Player/endpoint buckets, invalid-clock recovery,
  bounded cleanup, fixed-envelope/correlation behavior, protected dispatch and
  safe public translation, origin-only responses, and interval-limited
  privacy-safe abuse aggregates. The nine integrated cases consolidate
  cross-player authorization, forged identity/ownership, arbitrary-path and
  wrong-direction attempts, zero-partial-mutation behavior, disconnect cleanup,
  lifecycle re-entry, and remaining-peer isolation. The linked Studio pass
  records real `PlayerRemoving`, exact departing-player limiter/ledger cleanup,
  continued remaining-peer service, zero forbidden log-history matches and zero
  error records, exact fixture cleanup, and preservation of the empty production
  root.
- **Cleanup procedure:** the headless runner destroys test-owned state and its
  exact generated place. The Studio fixture owns and destroys its exact root;
  ending the session discards all runtime-only harness scripts. Both places
  return to Edit mode without save or publication.
- **Phase or prerequisite:** Packets 06.1–06.5 complete the initial foundation
  record and the fresh exit audit passes. Phase 06 is complete and Gate A
  passed. This pass
  does not cover or approve gameplay remotes, published-client behavior,
  adverse-network simulation, reconnect/teleport behavior, devices,
  persistence, or external services. Those rows remain deferred or unavailable,
  and later Phase 38 expands M-06 only after its affected systems exist.

### M-07 — Phase 09 enemy simulation, late recovery, and stress

- **System or contract:** server-owned enemy spawn/state/progression, traversal
  of the real detached bent lane, reliable spawn/correction/state/snapshot/despawn
  convergence, placeholder rendering, exact-once endpoint cleanup, constant
  update/render connection ownership, and increasing-count stress.
- **Test category:** unsaved Match Studio Server & Clients correctness,
  late-bootstrap, rendering, profiling, stress, and cleanup gate.
- **Current status:** `Passed` on 2026-08-27 for Packet 09.5. The executable
  Studio gate, consolidated final review with both material findings resolved,
  complete 467-case local gate, and all four structural builds pass. Phase 09
  is complete; exact-final-SHA CI is cited at handoff.
- **Environment:** the exact connected Match place, PlaceId `136401514513678`,
  GameId `10757629094`, CreatorType `Group`, CreatorId `35420107`, owner
  `PHJGAMES`, role `Match`; normally two simulated clients with only
  `match.project.json` synchronized. Every session began and ended in Edit mode.
- **Command or procedure:** follow the predeclared and executed procedure in
  [Enemy Simulation and Replication](ENEMY_SIMULATION.md#executed-studio-evidence--2026-08-27).
  Direct MCP Luau performed setup, assertions, and inspection. Studio exposed an
  `AddPlayers` action, but invoking it terminated rather than extending the live
  session, so the recorded active-session delayed-bootstrap fallback suspended
  one existing client before spawn and resumed it for authenticated snapshot
  recovery.
- **Required players or devices:** one local server and two simulated desktop
  clients; the real authored map remains the single Phase 07 bent lane.
- **Authorization requirement:** the user authorized current-branch Match Rojo
  synchronization and unsaved runtime-only triggers. No manual Script.Source,
  Script Sync, map/asset mutation, save, publish, setting, Lobby, or unrelated
  content change was authorized or performed.
- **External service or publication requirement:** none.
- **Destructive-data risk:** low and bounded to synchronized repository-owned
  source; pre/post persistent inventories and exact source values guarded
  unmapped Team Create content.
- **Expected evidence:** the delayed client recovered 16 active enemies in
  `0.167` seconds and converged at sequence `56`; stale/duplicate messages were
  ignored and a sequence gap recovered. A destroyed visual recreated as exactly
  three safe Parts without changing server state. A speed-12 enemy reached the
  real endpoint in `9.565` seconds and resolved/despawned once, with no base
  health, damage, Results, or wave transition. The `1/32/64/128` ladder held one
  server update connection and one client render connection; at 128 enemies the
  server p95/max sample was `7.782/10.623 ms`, client p95/max samples were
  `4.473/5.442 ms` and `4.915/5.945 ms`, maximum correction error was below the
  `8`-stud snap threshold, and captured client frame p95 values were
  `17.669/17.466 ms`.
- **Cleanup procedure:** clear the runtime trigger, publisher, store, controller
  state, buffers, visual roots, and map; end all clients/server; stop the
  task-owned Rojo server; reset emulation/profiling; verify no runtime enemy,
  network, map, UI, test, timer, queue, or cache residue; leave Studio in Edit
  mode without save or publish.
- **Phase or prerequisite:** Packets 09.1–09.5. At that dated checkpoint this
  evidence did not implement or approve Phase 10 base health/damage/Results or
  Phase 11 waves/cadence; the later Phase 10 gate is M-08.

### M-08 — Phase 10 defender base, recovery, world presentation, and defeat

- **System or contract:** authenticated base identity/health, exact-once endpoint
  leak damage through the real Phase 09 seam, coalesced reliable full-state
  convergence, late recovery, marker-bound BillboardGui feedback, one defeat and
  Results transition, spawn closure, ordered enemy cleanup, and residue-free
  shutdown.
- **Test category:** unsaved Match Studio Server & Clients correctness,
  delayed-bootstrap, world-UI, profiling/statistics, fault, and cleanup gate.
- **Current status:** `Passed` on 2026-08-28 for the exact Phase 10 Studio gate.
  The consolidated final review and complete local/structural gate also pass;
  exact-final-SHA CI is cited at handoff.
- **Environment:** exact connected Match place, PlaceId `136401514513678`, GameId
  `10757629094`, CreatorType `Group`, CreatorId `35420107`, owner `PHJGAMES`,
  `ATDPlaceRole = Match`; one local server and exactly two simulated desktop
  clients with only `match.project.json` synchronized. Every session began and
  ended in Edit mode.
- **Command or procedure:** use the fixed Studio-only server trigger and bounded
  client diagnostics described in
  [Defender Base Runtime and Replication](BASE_RUNTIME.md#executed-studio-evidence--2026-08-28).
  Direct Studio MCP Luau performs assertions/inspection. Because adding a true
  late client terminates the local server in this Studio build, use the already
  established active-session delayed-bootstrap fallback: suspend one existing
  client before initialization, then resume its one-shot bounded recovery.
- **Authorization requirement:** current-branch Match Rojo synchronization and
  runtime-only triggers were authorized. No manual Script.Source edit, Script
  Sync, map/marker/asset mutation, save, publish, setting, Lobby, or unrelated
  content change is permitted.
- **External service or publication requirement:** none.
- **Destructive-data risk:** low and bounded to synchronized repository-owned
  source; pre/post persistent inventory protects Studio/Team Create content.
- **Expected evidence:** measurement health began at `1,000,000`. The
  `1/32/64/128` ladder reached revision/health `2/999999`, `34/999967`,
  `98/999903`, and `226/999775`; zero damage held revision `226` and publication
  count `5`; ordinary and low fixtures reached revisions `227` and `228`, with
  low current health `249750` and publication count `7`. Measurement convergence
  maxed at `0.030816` seconds and delayed recovery at `0.049293` seconds. The
  final protocol/recovery checkpoint was revision `231`, health `249675`, and
  publication count `9`. BaseController/BaseWorldView connections stayed
  constant at `2/38` per client; lifetime tween creation totals were `8/7`,
  active owned tweens stayed bounded at `0` idle and `1` during feedback, and
  cleanup returned them to `0`. One temporary evidence probe was cleaned. The
  server pass max was `0.007418` seconds, p50 approximately `0.0000271`, and p95
  approximately `0.0000360` seconds. The bar remained attached to the real
  DefenderBase marker and survived marker/UI removal and recreation without
  server-state change. Replay of the immutable accepted MCP responses executed
  `804` explicit evidence assertions with `0` failures; the discarded fault
  probe was excluded.
- **Defeat evidence:** separate exact, overkill, and high-damage runs each
  reached base revision `3` and Results revision `9`, with one defeat, one
  Results commit, exactly `2` base publications, closed spawns, and both clients
  converged. The exact survivor
  produced two terminal enemies but only the endpoint enemy leaked; corrected
  maximum client convergence was `0.033782` seconds. A Studio-discovered
  terminal MatchSnapshot recipient-capture seam was fixed by freezing recipients
  during defeat preflight; the corrected reruns passed. The discarded diagnostic
  warning is not counted as an accepted-run console error.
- **Cleanup procedure:** end every client/server, remove trigger/base/enemy/map/
  network/UI/request/tween/cache state, disconnect the task-owned Rojo process,
  reset emulation/profiling, and leave Studio in Edit mode without save or
  publish. Accepted runs had zero console errors and zero runtime residue.
- **Phase or prerequisite:** Packets 10.1–10.4. This evidence starts no Phase 11
  wave definition, scheduler, cadence, or production difficulty selection.

### M-09 — Phase 11 authored waves, skip/recovery, stress, completion, and defeat

- **System or contract:** authenticated finite authored scheduling over the real
  saved lane; exact spawn/deadline/overlap/intermission ordering; originating-wave
  ownership; strict-majority skip and disconnect recomputation; bounded reliable
  Wave convergence; finite completion without Results; lethal Base defeat
  preemption; constant ownership; profiling; and residue-free shutdown.
- **Test category:** unsaved Match Studio Server & Clients correctness,
  recovery/order injection, timing, stress, lifecycle, and cleanup gate.
- **Current status:** `Passed` on 2026-08-28 for the exact Phase 11 Studio gate.
  Twelve accepted scenario records, the one consolidated final review, and the
  complete local/structural gate pass; exact-final-SHA CI is cited at handoff.
- **Environment:** exact connected Match place, PlaceId `136401514513678`, GameId
  `10757629094`, CreatorType `Group`, CreatorId `35420107`, owner `PHJGAMES`,
  `ATDPlaceRole = Match`; one local server and exactly two fresh simulated desktop
  clients with only `match.project.json` synchronized. Every session began and
  ended in Edit mode.
- **Command or procedure:** use the single fixed Studio-only authenticated fixture
  transaction and bounded server/client diagnostics described in
  [Authored Wave Runtime and Difficulty Scheduler](WAVE_RUNTIME.md#executed-studio-evidence--2026-08-28).
  Ordering/recovery injection travels through the real production `FireClient`
  path; no reducer or client signal is invoked directly.
- **Required players or devices:** one local server and two simulated desktop
  clients; the unchanged Phase 07 five-point bent lane is consumed read-only.
- **Authorization requirement:** current-branch Match Rojo synchronization and
  runtime-only evidence triggers were authorized. No manual Script.Source edit,
  Script Sync, map/marker/asset/catalog mutation, save, publish, setting, Lobby,
  or unrelated content change is permitted.
- **External service or publication requirement:** none.
- **Destructive-data risk:** low and bounded to synchronized repository-owned
  source and runtime-only objects; pre/post persistent inventory protects
  Studio/Team Create content.
- **Expected evidence:** primary, empty-wave, exact-deadline, overlap, skip,
  disconnect, `1/32/64/128` due-spawn ladder, real-transport recovery injection,
  and lethal-defeat records all passed. Spawns were never early, work remained
  bounded, publication coalesced to at most one Wave state per semantic pass, and
  each client retained three WaveController listeners and one diagnostics bridge.
  Healthy content completed exactly once while MatchLifecycle stayed
  `WaveActive`, with no victory, reward, or Results transition.
- **Defeat evidence:** `match:0c0771bc-82b5-40bb-a13a-9ef04026f874` admitted one
  lethal spawn and no later scheduled spawn; Wave/Base/Match ended at revision
  `3/3/9` in `DefeatClosed`/`Defeated`/`Results`, with one defeat, one Results
  transition, and zero finite completions. The last/max scheduler passes were
  `0.0000119000033`/`0.0002893999990` seconds, maximum lateness was
  `0.0140790939331` seconds with zero early spawns, and client convergence was
  `0.0344388485`/`0.0335118771` seconds.
- **Cleanup procedure:** accepted runs had zero console errors, only the expected
  bootstrap/network warning, one completed assertion set with zero failures, and
  no retained Wave/Base/Enemy/Match/network/map/client/trigger state. End every
  client/server, reset profiling/emulation, stop the task-owned Rojo process, and
  leave Studio in Edit mode without save or publish.
- **Phase or prerequisite:** Packets 11.1–11.6. Production catalogs remain empty;
  this fixture-backed gate does not start tower combat or authorize production
  content, save, or publication.

### M-10 — Phase 12 temporary loadouts, RuntimeTowers, graybox Models, and cleanup

- **System or contract:** exact Active-participant five-slot loadouts; distinct
  TowerId/UnitId/RuntimeTowerId domains; server-capability creation and
  per-owner caps; strict attacking/non-attacking version-1 Models; server/client
  pivot and replication agreement; visual tamper/removal/recreation authority;
  unchanged finite Wave and lethal-defeat paths; constant ownership; and exact
  Tower cleanup.
- **Test category:** unsaved Match Studio Server & Clients authority,
  engine-Instance, replication, timing, cap, lifecycle, defeat, and residue
  gate.
- **Current status:** `Passed` on 2026-08-28 in fresh zero-error primary and
  defeat sessions. A separate diagnostic session was discarded from acceptance
  after an AssistantCommand error; only its bounded client-replication timing
  observations are retained.
- **Environment:** exact connected Match place, PlaceId `136401514513678`,
  GameId `10757629094`, CreatorType `Group`, CreatorId `35420107`, owner
  `PHJGAMES`, `ATDPlaceRole = Match`; one local server and exactly two fresh
  simulated desktop clients with only reviewed `match.project.json` source
  synchronized. Every accepted scenario began and ended in Edit mode.
- **Command or procedure:** use the existing Wave-owned one-shot Studio trigger
  and its fixed Tower boundary described in
  [Tower Runtime and Temporary Loadout](TOWER_RUNTIME.md#executed-match-studio-evidence--2026-08-28).
  Validate one fresh complete raw configuration once, create only predeclared
  server CFrames, inspect server/client Models and bounded diagnostics, run the
  fixed cap/tamper/recreation/invalid-template operations, then invoke exact
  Tower cleanup. No client Tower operation exists.
- **Required players or devices:** one local server and two simulated desktop
  clients. UserIds were `-2` and `-1`; an unknown safe-integer UserId was probed
  only through the server boundary.
- **Authorization requirement:** current-branch Match Rojo synchronization and
  runtime-only fixtures/grayboxes were authorized. No manual Studio
  Script.Source edit, Script Sync, map/marker/asset/catalog mutation, save,
  publish, upload, setting, Lobby, or unrelated place action is permitted.
- **External service or publication requirement:** none.
- **Destructive-data risk:** low and bounded to task-owned synchronized source
  and runtime objects; exact pre/post persistent-root and mapped-source
  inventories protect Studio/Team Create content.
- **Primary evidence:** final-source MatchId
  `match:52847c36-92d9-47c8-912a-52e2a7a8ca3e`, epoch `1`, loadout revisions
  `1/2`, five exact slots per user, and unique `unit:p12-e1-n2-s1..s3` /
  `unit:p12-e1-n1-s1..s3`. First allocations `1..6` matched every owner, slot,
  canonical role, level/default mode-or-nil, eligibility, placement-cost
  investment, cooldown sentinel, and X pivot `0..30` by six. Activation took
  `0.0046535` seconds and the first six create transactions
  `0.0006274`–`0.0011286` seconds. Both clients agreed on role hierarchies,
  variants, and pivots. Removal/recreation/tamper repair took
  `0.0001617`/`0.0010771`/`0.0006388` seconds without record mutation; an invalid
  template rejected in `0.0000267` seconds with no count change.
- **Cap/model evidence:** final active RuntimeTowerIds were `1..11,13`, with
  exactly two single, three splash, and one support tower per owner. ID `12` was
  removed and not reused; metrics were active/lifetime/next/issued-ID
  `12/13/14/13`, capability generation `23`, zero outstanding capabilities,
  and ten expected cap rejections. Both clients agreed on twelve Models, four
  single/six splash/two support, `328` descendants, `48` BaseParts, `78`
  Attachments, `36` variants, and `34` hooks. The ordinary schedule completed
  once with Match still `WaveActive` and no Tower count/identity change.
- **Defeat evidence:** final-source MatchId
  `match:762fcd89-2459-4c68-b85c-bce0624682d9` created exact IDs `1..3` and
  both clients saw all three role Models. One lethal spawn reached Match
  `Results` revision `9`, Wave `DefeatClosed` revision `3`, and Base `Defeated`
  revision `3`, with one defeat/Results commit, no later spawn, and all Tower
  truth unchanged. The first run exposed the observer-detach cleanup gate;
  after its cleanup-only fix and focused regression, the final-source rerun
  activated in `0.0048356` seconds, created the three Models in `0.0031535`
  seconds, and cleaned Tower state in `0.0015069` seconds.
- **Cleanup procedure:** primary Tower cleanup took `0.0019925` seconds; both
  accepted runs produced exact all-zero Tower receipts, no server/client
  runtime root, late creation `UNAVAILABLE`, one completed assertion set with
  zero failures, zero console errors, and only the expected early base-snapshot
  server warning. Stop both clients/server, reset profiling/emulation, disconnect
  and stop the task-owned Rojo process, confirm port `34872` has zero listener,
  and leave the exact unchanged place in Edit mode without save or publish.
- **Phase or prerequisite:** Packets 12.1–12.4 only. Production `Assets` and
  `Towers` remain empty; networking remains ten endpoints/six policies; M-02
  stays Deferred; no placement, combat, Battle Cash mutation, hotbar,
  persistence, production content, or Phase 13 behavior began.

### M-11 — Content and Onboarding Garden four-client integration

- **System or contract:** current Garden loading and camera framing; four-player
  roster/Ready/runtime convergence; fixed path, legal placement, generic direct
  and splash combat, enemy/boss presentation, finite and Endless projection;
  bounded active work/network collections; public/squad isolation from tutorial
  assistance; and exact cleanup.
- **Test category:** one consolidated private-staging Match Studio Server &
  Clients integration and residue gate.
- **Current status:** `Passed` on 2026-09-04. All four clients reached Ready on
  the same Garden/Easy snapshot, each placed one independently owned Dart, all
  received owner controls, and one player upgraded to level two. The clients
  converged at wave 12 with four towers, 20 enemies, base health `93/100`, and
  the surviving Garden Queen panel still visible at `573/585` health, covering
  boss overlap beyond its spawn wave.
- **Environment:** private staging GameId `10764687717`, Match PlaceId
  `104415140644510`, role `Match`, owner `PHJGAMES` group `35420107`, one local
  Studio server and exactly four simulated clients, with the current
  `match.project.json` synchronized through one managed Rojo process.
- **Command or procedure:** after S-07's exact identity/inventory check and map
  repair verification, one four-client session verified shared authoritative
  state, Ready, four independent legal placements, owner controls, one upgrade,
  direct combat, wave/base/boss projection, bounds, and cleanup. Generic splash,
  tutorial public/squad isolation, and Endless display remained deterministic
  server/client coverage; this Studio session used the direct non-rewarding
  local fallback.
- **Required players or devices:** exactly four simulated clients for the
  acceptance session; representative mobile layout remains in S-07.
- **Authorization requirement:** local private-staging Studio execution and the
  already bounded Team Create content edits are authorized. This does not
  authorize production, publication, a new place version, or persistent player
  data mutation.
- **External service or publication requirement:** none. Do not turn this into a
  published-client test merely to exercise four clients.
- **Destructive-data risk:** low after exact identity and root checks; all runtime
  objects and test state are session-owned. Persistent authorized Garden assets
  must remain untouched by cleanup.
- **Expected evidence:** every client sees the same selected map/difficulty,
  wave/boss/base/enemy/tower truth; server-only placement and upgrade authority
  holds under concurrency; collections remain within bounds; warnings are
  readable; public/squad behavior is unchanged by onboarding; shutdown leaves
  no runtime, test, network, or preview residue.
- **Cleanup procedure:** the multiplayer test ended, all server/client child
  DataModels closed, the exact Studio instance returned to Edit mode, direct
  attributes were removed, authorized roots were inventoried, and the managed
  Rojo process was deliberately stopped. No new place version was published;
  final inventory found zero scripts or runtime/presentation residue.
- **Phase or prerequisite:** Content and Onboarding Phases 29–33 after S-07.

## Published-client and private-version tests

### P-01 — Real party travel and match admission

- **System or contract:** queue launch, reserved-server teleport, signed/opaque
  match ticket, arrival admission, party preservation, and failure recovery.
- **Test category:** published private-client integration test.
- **Current status:** `Passed` for the Squad Travel baseline at commit
  `fe48b9fe2a9b597d6d169530877465654c8c4e96`. Authorized private staging
  clients completed real solo and three-player reserved-server travel,
  expected-roster admission, unanimous rematch into a fresh Match, reconnect,
  and return. Content version 1 has not been newly published or rerun through
  this gate.
- **Environment:** private staging GameId `10764687717`, Lobby PlaceId
  `140661668701496`, Match PlaceId `104415140644510`, PHJGAMES group
  `35420107`. Production GameId `10757629094` is excluded.
- **Command or procedure:** retain the completed baseline evidence. A content-v1
  rerun requires a newly published private staging version and one specific
  approval; the local S-07/M-11 checks do not require publication.
- **Required players or devices:** the completed gate used designated solo and
  three-player clients; a future rerun may cover up to four.
- **Authorization requirement:** authorization applied to the completed staging
  gate only. Publishing current content or rerunning real clients requires new
  specific approval.
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
- **Current status:** `Partially complete`. Profile persistence, migration,
  session ownership, result receipts, and the private staging environment now
  exist; prior outcomes exercised ordinary save/reconnect/reward continuity.
  Profile-v6 tutorial migration and duplicate/replayed transition behavior have
  deterministic coverage. A fresh destructive migration/reset/failure-injection
  gate is not authorized or claimed.
- **Environment:** dedicated private staging experience and deterministic local
  profile adapters. Studio API access and destructive profile work remain
  prohibited in production.
- **Command or procedure:** run profile schema/migration/owner/tutorial/result
  specs locally. Any real migration/reset test must first identify the exact
  staging store and designated UserIds and obtain specific destructive approval.
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
- **Current status:** `Passed` for the Squad Travel baseline's version-1
  exactly-once reward/Gold refresh, rematch, reconnect, and Lobby return path.
  Content version 1 adds compatible result version 2, per-difficulty finite
  rewards, bounded Endless terminal rewards, and tutorial result/return
  continuity with deterministic idempotency coverage. A newly published
  end-to-end content/onboarding client gate remains `Pending` approval and is
  not claimed.
- **Environment:** dedicated private staging Lobby and Match for completed
  version-1 evidence; isolated headless adapters for current version-2 and
  tutorial coverage.
- **Command or procedure:** use H-16 for current result/reward/tutorial authority.
  Publish and exercise the exact private staging version only after one specific
  approval identifies what will be published and tested.
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
- **Current status:** `Unavailable`; Phases 34–37 repository implementation and
  scoped local verification are complete, with external platform/assets/analytics
  gates pending. Release configuration and closed-alpha acceptance in Phases 38–40
  have not begun and are outside the current outcome.
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
- **Current status:** `Unavailable externally`; the versioned dictionary,
  authoritative observers, bounded delivery abstraction and mock-sink coverage
  exist. A reviewed destination/dashboard and current private published test
  release are not configured. Packet 37.6 remains pending.
- **Environment:** future private test release with a reviewed analytics
  destination and non-sensitive designated accounts.
- **Command or procedure:** H-17 and scoped local verification are complete; use the
  bounded approval contract in [analytics](ANALYTICS.md). Approval must name
  experience/version, provider, event subset, accounts, expected writes,
  retention/privacy, abort conditions and cleanup before external execution.
- **Required players or devices:** representative private clients for the flows
  that emit each event.
- **Authorization requirement:** explicit analytics-service, publication, and
  tester authorization.
- **External service or publication requirement:** yes; private publication and
  the approved analytics destination.
- **Destructive-data risk:** low for gameplay data but material privacy risk if
  payloads are not bounded; raw profiles/private player payloads are prohibited.
- **Expected evidence:** bounded events arrive with useful safe dimensions;
  duplicates, drops and failures are diagnosable within the documented
  best-effort delivery contract; retention is verified; no secret or raw
  private value appears. Mock records establish none of this provider evidence.
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
- **Current status:** `Partially complete; historical Content and Onboarding device
  gate passed`. The gameplay HUD, bounded camera, desktop/touch/gamepad
  placement, and input actions retain their earlier evidence. S-07 additionally
  verified Garden framing and bounds plus touch placement, selection, upgrade,
  and defeat at an iPhone 17 Pro landscape viewport. Content version 1 finite/
  Endless labels, boss warning/health, contextual tutorial, and reduced-effects
  behavior passed deterministic view coverage. Current Phases 34–37 input,
  localization and preference work has completed the scoped local S-08 checks;
  its full-flow, physical-device and published-client acceptance remains pending.
- **Environment:** current private staging Match Studio device emulation plus
  representative physical devices later in the roadmap.
- **Command or procedure:** run H-17's client reducer/view/controller specs and
  S-08's current bounded input/layout procedures. Preserve S-07 as its earlier
  desktop/phone evidence, not a pass for the new current-tree matrix.
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
- **Current status:** `Partially complete; historical Content and Onboarding phone
  gate passed`. The shared Lobby shell, persistent settings, responsive layouts,
  and Match presentation exist. Tutorial, content-selection, boss, Endless, and
  reduced-effects projections have deterministic layout/reducer coverage; S-07
  verified current Match phone layout and touch gameplay in Studio. That local
  milestone evidence is not the broader current Phases 34–37 acceptance.
  Shared preference precedence, localization expansion and focus improvements
  are implemented; H-17 and the scoped S-08 local checks are complete.
- **Environment:** Lobby and Match Studio device emulation now; representative
  physical supported devices remain later acceptance work.
- **Command or procedure:** run the focused Lobby/Match UI specs in H-17 and the
  S-08 preference/input/expansion matrix. S-07 remains historical evidence.
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
- **Current status:** `Partially complete`. Persistent profile, inventory,
  loadout, earn-only Garden chest disclosure, party/queue configuration, and
  responsive Lobby UI exist. Content version 1 projects player-facing map and
  difficulty names plus concise tutorial guidance. Those projections passed the
  historical Content and Onboarding headless gate. The private-staging Lobby
  queue root was verified
  unchanged and script-free, but no newly published physical-client newcomer
  journey or uninstructed first-time-player observation is claimed.
- **Environment:** private staging Lobby Studio device emulation; a newly
  published private physical-client newcomer gate would require separate
  approval.
- **Command or procedure:** use H-17 for current projections and S-08 for the
  authorized local staging boundary. Record a first-time-player test only when
  another person actually performs it against an approved version.
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
- **Current status:** `Scoped local verification complete; external acceptance pending`;
  the bounded audit/design lock, localization/formatting/pseudolocalization,
  preference precedence and cross-input implementation exist. H-17/S-08 record
  the verified current surfaces and full-flow limits; no physical-device, console, screen-reader,
  assistive-device or production-language support is inferred from emulation.
- **Environment:** representative physical hardware, Studio emulation, and
  private published clients where platform behavior requires it.
- **Command or procedure:** follow S-08 and the acceptance criteria/evidence
  levels in [the design lock](PLATFORM_HARDENING_DESIGN_LOCK.md). English source
  plus 30–50% pseudolocalization is the current scope; human translation and
  review are required before any additional language-support claim.
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
- **Current status:** `Partially complete; historical content-density check
  passed`. Gameplay content and explicit generator/runtime bounds include a
  deterministic 10,000-wave soak with saturated-growth and distant-wave probes.
  Private-staging scene analysis measured 76,971 client triangles/79 draws with
  shadows, or 52,386 creator-adjusted triangles/44 draws; the server contained
  1,290 instances, with no unparented ATD instance. S-07/M-11 also exercised
  solo mobile and four-client wave-12 load. Current S-08 adds bounded solo and
  four-client frame/Stats/network-count and named CPU captures plus actual
  replay cleanup. Final-source Garden Hard reached twelve towers/twenty enemies
  with boss-bracketed client/server CPU captures, and SceneAnalysis recorded
  181,255 triangles/143 draws including shadows at wave 21. Two active 30-second
  Endless windows and an unchanged-source three-cycle repeat are recorded in
  [performance budgets](PERFORMANCE_BUDGETS.md). Representative low-end hardware,
  published transport, hosted/all-composition capacity and long-duration traces
  remain pending. Historical scene counts and deterministic generation do not
  substitute for those gates.
- **Environment:** representative supported physical hardware and controlled
  private clients, with Roblox profiling tools.
- **Command or procedure:** S-08 with the test-only PlatformProfile harness,
  MicroProfiler scopes and PerformanceScenarios accounting in H-17; use the
  matching-environment thresholds in [performance budgets](PERFORMANCE_BUDGETS.md).
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

## Platform hardening procedures — 2026-09-04

These procedures were recorded before execution. Status: implementation and
scoped local verification are complete, the consolidated review is clean and
the milestone gate has cumulative `1,601/1,601` coverage with all four builds
passed. Delivery branch: `codex/platform-hardening`; external acceptance remains
pending. Historical
S-07/M-11 evidence remains historical.
The [design lock](PLATFORM_HARDENING_DESIGN_LOCK.md) defines evidence labels and
platform claims; no whole-outcome acceptance is asserted from partial checks.

### S-08 — Unsaved platform and performance sessions

Read-only geometry companion: inject the returned function from
`tests/studio/UiLayoutAudit.luau` through the direct Studio Client tool after
identity verification, then invoke with `{}` for the role's exact ATD GUI.
Run after a fresh layout/frame update at each selected device/input/preference
checkpoint. The probe inspects at most 4,096 instances and reports at most 512
visible interactive controls, stable relative names, focus, safe-root bounds,
text fit, scroll clipping and overlapping active objects. It retains no raw UI
text, creates no instances or connections, and mutates nothing. Abort on an
identity/root mismatch or truncation. Record scrolling candidates separately
from fixed-container clipping, and verify reachability with actual input and
screenshots; zero geometry flags alone do not establish human acceptance.
The final probe also checks up to 512 ancestry-visible text labels for engine
TextFits failures and marks interactive controls below 44 physical pixels.
These are review candidates: a label inside a scrollable reading panel may be
outside the current viewport, and disabled modal-background controls are not
actionable. Check the actual text fit and foreground control geometry separately.
The touch-size check uses a 0.01 px tolerance; geometry uses 1 px. Nonempty
TextBox placeholders expose bounded counts and an explicit unmeasured flag.
Inspect their rendering visually at the tested preferences and UI scale.


- Current status: `Recorded local scenarios; external acceptance pending`.
  Confirmed staging evidence includes solo Garden/Endless, four-client Easy
  wave-20 Victory/replay, two three-cycle finite replays, and final-source Hard
  with twelve towers/twenty enemies. The unchanged-source repeat left zero owned
  entities/effects and probe connections, with no monotonic process-memory rise.
  Hard client/server CPU captures were bracketed by visible boss-health summaries;
  the later Endless MicroProfiler was already Results and remains labeled that
  way. Active Endless has two 30-second Playing traces, not a long-duration soak.
  Exact input/layout evidence and final restoration are recorded separately;
  [performance budgets](PERFORMANCE_BUDGETS.md) preserves source JSON, settings,
  focus and measurement limits. No physical or published acceptance follows.
- Final Match follow-up: the additional 12.150-second trace was still active
  boss/dense combat, not cleanup. The natural terminal observation later reached
  Results at wave 34 with base health zero; an accepted ordinary replay returned
  to Ready with zero towers/enemies/effects and three presentation descendants.
  The terminal result enum was not captured reliably and is not inferred from
  the probe's discarded default. All four temporary clients closed; Match Edit
  emulator/camera were restored, test attributes removed and owned-template
  inventory unchanged, with zero ATD runtime residue. The
  [final cleanup record](evidence/platform-final-cleanup.json) additionally
  confirms Lobby preference/emulator/camera restoration, unchanged queue-root
  inventory and zero remaining managed Rojo processes. Profiler capture/display
  are off and the documented 256 frame-limit default restored; its initial
  value and exact original dock-pane arrangement were not captured. The
  [fresh-source chest modal check](evidence/platform-lobby-final-modal.json)
  records readable Confirm/Cancel at Largest text and pseudo50, with only
  intentional overlap over disabled modal-background controls.
- Environment: confirmed PHJGAMES staging GameId `10764687717`, Lobby
  `140661668701496`/`lobby.project.json`, Match
  `104415140644510`/`match.project.json`, group `35420107`. Reverify live identity
  and role before runtime actions. Use one managed Rojo process per project.
- Authorization: source synchronization and unsaved/runtime testing only; no
  publication, stored-profile mutation, persistent Team Create edits, external
  analytics, API-access changes or experience settings.
- Record before/after ATD root inventory, camera, emulator and profiler state.
  Start with direct non-rewarding Studio Match; Lobby persistent-service behavior
  that cannot be tested without stores uses a test-only injected in-memory service
  or remains a published-client gate. Never infer travel from a direct Match.
- Players/devices: one solo and four local clients; desktop 16:9, ultrawide,
  minimum landscape 667×375, common phone, tablet, keyboard-only and controller
  TenFoot. Emulation has no claim to phone/tablet/console hardware performance.
- Run first-join/loading/failure/retry, tutorial/help/skip/replay, currencies and
  odds/acquisition/rewards, inventory/loadout/settings, party/queue/captain/travel,
  Ready/HUD/camera/placement/cancel/select/target/upgrade/sell, boss/wave/Endless,
  victory/defeat/rematch/return/reconnect/spectating and modal/error/recovery paths.
  Exercise keyboard traversal and Back at every depth, controller without required
  typing, touch confirm/cancel, safe areas and scroll reachability.
- Compare English and pseudo30/40/50 with largest preferred text, opaque panels,
  reduced motion, low detail, saved scale/shake/audio controls including live
  changes. Capture text extents, visible control bounds, selection/focus and
  screenshots; programmatic visibility alone does not prove visual readability.
- Profile idle/normal/boss/dense/results/cleanup. Use test-only
  `tests/studio/PlatformProfile.luau` with `tests/support/PerformanceWindow.luau`
  injected locally, 10–30-second bounded captures, engine Stats and LibMP snapshots
  plus SceneAnalysisService. Payload counts are JSON-like estimates, explicitly
  separate from engine aggregate Kbps counters. Do not retain raw remote payloads.
- Dense scenario: four independent players, all current legal tower slots,
  rapid-fire and splash roles, overlapping regular/boss enemies within authority
  caps. Repeated-session scenario: at least three finite rematch cycles and one
  bounded real-time Endless session, sampling equal idle/combat/cleanup points.
  Thousands of generated waves are deterministic coverage, not a real-time soak.
- Abort on identity mismatch, persistent-service mutation requirement, unexpected
  runtime authority, unbounded growth, UI-critical obstruction or tool failure.
  Record partial measurements honestly; do not average missing results into passes.
- Cleanup: disconnect all probe listeners; dispose LibMP sessions/arrays/iterators;
  stop Play/clients; restore emulator, profiler capture/UI/frame limit and camera;
  remove only runtime test fixtures; stop the exact managed Rojo PID; verify no
  test attributes, preview/runtime roots, generated places or profiler residue.
  Reinventory ATD roots and record any difference. Persistent assets stay unchanged.

#### S-08 repeated finite-session measurement

This procedure was recorded before execution. Status: `Passed for the bounded
local repeated-session procedure; long-duration memory acceptance remains open`.
`docs/evidence/platform-repeated-stable-source.json` records three ordinary solo
Garden Easy no-tower wave-10 defeats and replays in 504.379 seconds, seven accepted
requests/checkpoints and zero remaining probe connections. Its 191-file source
fingerprint was unchanged throughout. All checkpoints had zero tower/enemy/effect
roots and three empty presentation folders. Instances changed 2,692 → 2,694 once
and then stayed flat; Ready memory changed 2356.21875 → 2348.421875 MB
(-7.796875 MB). A separate 12.199-second warmed Ready probe retained 732 frames,
p95 17.9634 ms and maximum 23.9034 ms, with 6,513 instances flat, zero additions/
removals/connections and memory 2348.484375 → 2348.496094 MB.

The earlier `docs/evidence/platform-repeated-sessions.json` trace completed three
cycles in 504.41 seconds with owned-object cleanup, but process memory rose
64.324 MB while source synchronization occurred. That increase was not reproduced
in the unchanged-source follow-up and remains unexplained. The two runs used
different viewport/preferences; neither explains away the other. See
[performance evidence](PERFORMANCE_BUDGETS.md). No full-session frame,
long-Endless, absolute hardware-memory or published-client acceptance follows.

Use `tests/studio/RepeatedSessionProfile.luau` as a returned runner inside one
temporary runtime-only LocalScript, with the local PerformanceWindow dependency:
`runner(Window, 600)`. The wrapper runs asynchronously, stores only the returned
sanitized report for inspection, and is destroyed after the runner finishes.
Neither harness is mapped into a Rojo project or synchronized as persistent code.

- Environment/authorization: confirmed unsaved private staging Match, GameId
  `10764687717`, PlaceId `104415140644510`, PHJGAMES Group `35420107`, Match role
  and `match.project.json`; one local Studio participant, a non-rewarding finite
  Garden Easy runtime initially Ready with no towers. Verify identity and
  before-inventory, source freshness, emulator and profiler state. Existing
  permission covers ordinary local gameplay requests, not service/data mutation.
- Actions: one validated GetPlayableMatchSnapshot read, then three ordinary
  SubmitPlayableReady requests and three ordinary SubmitPlayableReplay requests.
  Each uses production RequestProtocol envelopes and current authenticated Match
  identity. No tower placement, test cash, wave/entity injection, forced outcome,
  profile/store access or changes to authoritative behavior occur. Let actual
  enemies leak to produce finite defeats; do not call these campaign victories.
- Evidence: at most 600 seconds total requested duration, including two-second
  settlement at each Ready/terminal checkpoint. Seven bounded checkpoint records
  contain map/difficulty names, content version, terminal wave/outcome, numeric
  memory/instance/world counts, settled frame samples and cumulative request/event
  counts with JSON-like size estimates. Final replay remains Ready without starting
  a fourth match; its three owned presentation folders must be empty. This is a
  local repeated-session trace, not published rematch/return, wire bandwidth or a
  long-Endless/device-memory acceptance result.
- Abort: identity/role mismatch, rewarding/spectator/multi-participant/Endless
  state, any tower placement, unexpected map/difficulty/match change, rejected or
  malformed response, missing endpoints, failure to reach the expected state,
  cleanup mismatch or timeout. No automatic retries of rejected gameplay actions.
  Retain partial sanitized evidence and report its failure code; do not turn it
  into a pass. Do not destroy the wrapper while the runner is active.
- Cleanup: runner disconnects every owned listener after success/error/timeout,
  checks actual connection state and clears transient current/request/retired IDs.
  The wrapper retains no raw snapshot, UserId, profile or receipt. Read the report,
  destroy only the exact runtime wrapper, stop Play, restore emulator/camera/
  profiler/settings, and verify no runtime roots/test attributes remain. Reinventory
  the unchanged ATD-owned templates. No save, publication or persistent edit.

#### S-08 final UI observations and remaining flow acceptance

The source boundary review covers all critical Lobby and Match messages,
including failure/recovery, tutorial, economy/acquisition, inventory/settings,
party/queue/travel, placement/owner actions, results, reconnect and spectating.
That review and deterministic reducers do not establish a rendered full-flow pass.
The recorded engine evidence is deliberately narrower:

| Flow family | Current local evidence | Remaining acceptance |
| --- | --- | --- |
| Lobby Help/tutorial, inventory/details, settings, chest confirmation/result | Actual navigation and pseudo50 geometry; saved scale/focus changes; final header follow-up closes three earlier candidates | Independent newcomer and complete first-session matrix on published clients |
| Party/queue and navigation Back | Local party/privacy/captain controls and keyboard/controller discrete actions; deterministic failures and travel projections | Real designated accounts, invitation, authenticated queue/travel and recovery |
| Match Ready, HUD, touch placement | Smallest landscape Ready and tower selection generated Touch; map tap enabled Confirm with zero authoritative towers; explicit confirmation placed one tower | Physical phone/tablet gestures, thumb reach and complete match interaction |
| Match tower owner controls and replay | Keyboard selection/target/upgrade/sell exercised; actual R Results→Ready; earlier four-client campaign reached Victory and replay cleaned owned entities | Full controller owner-action and sustained analog matrix, published rematch/return |
| Match expanded Results | Six final device-layout samples had zero text-overflow, undersized-touch or fixed-clipping candidates | All other critical surfaces across complete per-device first-session/full-match runs |
| Virtual controller | Actual A Ready and A placement confirmation; stick pulse probe observed 20 axis events but zero held-axis samples over 600 Placement/Gamepad1 frames | Sustained analog input and complete controller path on a named physical controller; no console inference |
| Failure, reconnect, spectating, persistent rewards | Deterministic contracts and whole-message review | Current private published version and designated-account recovery/reward checks |

Sources are `docs/evidence/platform-lobby-final-ui.json`,
`platform-lobby-header-followup.json`, and `platform-match-final-ui.json` in the
same evidence directory. Each is Studio-emulated evidence on the development
desktop. Scrollable controls outside the viewport require scrolling; geometry
alone is not interaction evidence. A later controller owner-action attempt had
inconsistent observations and is not recorded as a pass. No physical-device,
assistive-device, console or complete advertised-platform exit is claimed.

### H-17 — Platform/observability deterministic contracts

Current status: `Passed`, with a clean consolidated review and cumulative
`1,601/1,601` headless coverage. The full milestone sequence ran once: StyLua
check/verify, Selene configuration and all-source lint, and Default/Lobby/Match/
Test builds passed. The complete headless run initially passed `1,599/1,601`;
two ReadyController cases still expected old English copy. A diagnostic rerun
reproduced those same failures. Four assertions were corrected in test sources
only, formatted and linted; the affected ReadyController/ReadyView/ReadyViewModel
bundle then passed `30/30`, closing cumulative coverage at `1,601/1,601` without
another full gate or any production-source change. Overlapping focused counts
are not added together. The historical H-16 `1,486/1,486` remains baseline evidence.

Run selected Localization, Accessibility, Focus, Presentation, Audio, Performance,
Analytics, Operational, DevelopmentCommands and balance-report specs in a combined
selector invocation after their files stabilize. Validate bounded hostile inputs,
whole-message completeness, expansion ratios, preference precedence, focus graph
containment/restoration, reducer reordering and cleanup, asset failure/concurrency,
payload/measurement limits, private schema/delivery failure, command fail-closed
identity and production exclusion, read-only report reproducibility and repeated
finite/Endless runtime cleanup. Headless results do not establish device rendering,
sound quality, engine memory/frame/network behavior or dashboard delivery.

Generate the reproducible read-only artifact with
`lune run tests/balance-report.luau`; output is
`build/content-balance-report.md`. Inputs, content version, production runtime
reuse and evidence limits are documented in [content balance](CONTENT_BALANCE.md).
The command changes no configuration, profile, live state or external service.

## Current execution order

Platform hardening followed the risk-based ladder in `AGENTS.md`: format/lint
changed Luau, batch nearby specs and build affected projects at meaningful
checkpoints. The full milestone gate below ran once after implementation and
review stabilized. H-17 records the two test-only expectation corrections and
affected rerun. Git hygiene and branch delivery follow without repeating the gate:

1. `stylua --check --verify src tests`
2. `selene validate-config`
3. `selene src tests`
4. `lune run tests/verify-builds.luau`
5. `git diff --check`
6. inspect `git status --short --ignored` and remove only exact generated outputs.

H-16 records the initial `1,484/1,486` full-suite result, the two stale
expectation corrections, the affected `15/15` rerun and Test build, and the
resulting historical cumulative `1,486/1,486` baseline coverage. That gate was
not rerun merely to establish the baseline. After the current gate, rerun only
checks affected by subsequent fixes. The verifier runs the complete
headless suite and builds Default, Lobby, Match, and Test once each.

Run the applicable Studio, multi-client, published-client, device, or destructive
row only when its prerequisites exist and its authorization line is satisfied.
Do not replace a deferred environment-specific test with a headless test and call
the environment gate passed.

[phase-06-plain-lifecycle]: NETWORK_SECURITY_STUDIO_REGRESSION.md#plain-lobby-and-match-lifecycle-checks
[phase-06-two-client-evidence]: NETWORK_SECURITY_STUDIO_REGRESSION.md#final-two-client-run
[phase-06-two-client-procedure]: NETWORK_SECURITY_STUDIO_REGRESSION.md#runtime-only-two-client-injection
