# Automated test runner

## Decision record

- Status: Phase 05 and Packets 06.1–06.5 complete; fresh Phase 06/Gate A exit audit is next
- Research date: 2026-08-26
- Selected runtime: Lune 0.10.5
- Rokit tool identifier: `lune-org/lune@0.10.5`
- Release commit: `e173211a3b529eb53624137931fc11f0a02ff867`
- License: Mozilla Public License 2.0
- Canonical local command: `lune run tests/run.luau`

This decision was recorded before Lune or any test-runner code was added to the
repository. Lune is the only new third-party development dependency justified
for Phase 05. The assertion library, discovery logic, Roblox ModuleScript
adapter, fixtures, and structural build checks are small, project-owned Luau
modules rather than another package graph.

The runner's current coverage is only the automated-headless portion of
`docs/TEST_MATRIX.md`. Studio integration, multi-client, published-client,
device/accessibility, and destructive tests keep their separate status and must
not be inferred from a passing headless run.

## Selection criteria

The chosen approach must run strict Luau deterministically on headless Windows
and GitHub-hosted runners, return reliable process exit codes, exercise the
exact pure shared ModuleScript sources without Roblox credentials or
publication, fit the existing Rokit toolchain, and keep every test-only file out
of Default, Lobby, and Match builds.

Lune 0.10.5 meets those requirements with one pinned executable. Its official
release embeds Luau 0.709 and supplies filesystem, process, Luau compilation,
and Roblox DataModel libraries. The project-owned adapter builds
`test.project.json`, deserializes that exact Rojo output, and executes ModuleScript
`Source` with a restricted environment that provides Roblox-style `script` and
Instance-based `require`. The adapter will not attempt to run the full game or
pretend to reproduce Roblox engine behavior.

The principal compatibility risk is semantic drift between Lune's partial
Roblox environment and the live engine. The suite primarily targets pure shared
contracts. Packets 06.1, 06.3, and 06.4 additionally map only six common
networking ModuleScripts into test-only `ServerStorage`: the production policy
module, server registry owner, server limiter, server request dispatcher, client
lookup, and client request tracker. Injected connection, monotonic-clock,
Player-removal, response-sender, reporter, and request-ID-generator adapters
exercise deterministic ownership, lookup, token buckets, correlation,
origin-only routing, cleanup, and aggregate-reporting logic without claiming a
full engine simulation. The project still excludes client/server bootstraps,
shutdown hooks, live remote delivery, and other engine integration.
Genuine Roblox `Instance` cleanup can be exercised through Lune's DataModel
implementation; the `RBXScriptConnection` cleanup branch may use a narrowly
registered test double whose `typeof` adapter delegates every unregistered value
to the native function. Packet 06.2 also injects exactly the Lune-provided
`Vector2`, `Vector3`, and `CFrame` constructors so their real host datatypes and
non-finite components can exercise the production validators. No generalized
host-library access is exposed. Studio remains the authority for engine
integration regressions.

## Candidates considered

### Lune 0.10.5 — selected

- Maintenance: active; version 0.10.5 was released on 2026-07-02 and its tag
  resolves to the immutable commit recorded above.
- Compatibility: standalone Luau runtime with `@lune/luau` custom environments,
  `@lune/roblox` DataModel support, filesystem APIs, and explicit process exit.
- Headless use: native Windows binary suitable for local commands and GitHub
  Actions; official installation documentation recommends Rokit.
- Footprint: one Rokit-managed executable and no Wally package tree.
- Isolation: tests and their adapter can live outside every production Rojo
  mapping.
- Limitation: running a full Roblox game is an explicit non-goal. This project
  uses Lune only for pure contracts loaded from an isolated Rojo test build.

Primary sources:

- [Lune repository and MPL-2.0 license](https://github.com/lune-org/lune)
- [Lune 0.10.5 release](https://github.com/lune-org/lune/releases/tag/v0.10.5)
- [Official Rokit installation guidance](https://lune-org.github.io/docs/getting-started/1-installation/)
- [`@lune/luau` compilation environments](https://lune-org.github.io/docs/api-reference/luau/)
- [`@lune/roblox` DataModel APIs](https://lune-org.github.io/docs/api-reference/roblox/)
- [`@lune/process` execution and exit APIs](https://lune-org.github.io/docs/api-reference/process/)
- [`@lune/task` scheduler API](https://lune-org.github.io/docs/api-reference/task/)

### Roblox Jest — rejected

Roblox Jest is maintained, MIT-licensed, and appropriate for tests executing
inside Roblox. Its documented package setup brings Jest, JestGlobals, and a
large transitive Wally module graph. Its documented automated Roblox execution
path relies on Roblox/Open Cloud infrastructure, credentials, and uploaded
place execution. Those requirements conflict with Phase 05's minimal footprint
and prohibition on secrets, publishing, and external Roblox services. Adding
Jest would not remove the need for a headless ModuleScript adapter here.

Primary sources:

- [Roblox Jest repository and package instructions](https://github.com/Roblox/jest-roblox)
- [Roblox Jest release history](https://github.com/Roblox/jest-roblox/blob/master/CHANGELOG.md)
- [Roblox place CI/CD example](https://github.com/Roblox/place-ci-cd-demo)

### TestEZ — rejected

TestEZ is Apache-2.0 licensed and familiar in Roblox projects, but Roblox
archived the official repository on 2024-09-14. Its documented CI route uses
the legacy Lemur environment. An archived framework and obsolete CI adapter are
not an acceptable new foundation for this repository.

Primary source:

- [Roblox TestEZ repository and archive notice](https://github.com/Roblox/testez)

### run-in-roblox — rejected as the canonical runner

`run-in-roblox` 0.3.0 is MIT-licensed and can execute a place or script through
an installed Roblox Studio process. It is useful for optional local engine
checks, but it is not a lightweight headless GitHub-hosted runner: it requires a
Studio installation and launches the engine. Phase 05's pure suite does not
need that dependency.

Primary source:

- [run-in-roblox repository](https://github.com/rojo-rbx/run-in-roblox)

### Standalone Luau CLI — rejected

The official Luau CLI was active at version 0.735 when researched. It supplies
the language runtime but no Roblox DataModel or
ModuleScript tree. Most current shared modules intentionally use
`require(script.Parent...)`, and `ConfigurationValidator.validateLoaded()` uses
`FindFirstChild` and `IsA`. Rewriting production imports or maintaining
transformed copies would make tests exercise a different program. Lune's
included DataModel support permits a smaller and more faithful adapter.

Primary source:

- [Luau repository](https://github.com/luau-lang/luau)

### Lute 1.0.0 — rejected

Lute is an actively maintained, MIT-licensed general-purpose Luau runtime from
the Luau organization. Its stable 1.0.0 release and later nightly activity make
it a credible alternative, but it does not include Lune's Roblox DataModel
library. Supporting this source tree would therefore require more Roblox
emulation while still requiring the project-owned assertion and discovery
layers. Lune is the smaller adaptation for the current contracts.

Primary sources:

- [Lute repository](https://github.com/luau-lang/lute)
- [Lute 1.0.0 release](https://github.com/luau-lang/lute/releases/tag/v1.0.0)

## Installation and update policy

Lune will be pinned in `rokit.toml` by exact version. `rokit install` is the
only supported installation command, and no downloaded executable, package
cache, or installation directory is tracked. A future update requires a
separate dependency review of the release, embedded Luau version, license,
ModuleScript adapter behavior, negative controls, and all production-exclusion
checks. Phase 05 does not upgrade Rojo, StyLua, Selene, Rokit, or unrelated
tools.

## Isolated execution design

`test.project.json` is build-only and has no `servePlaceIds`. It maps the
authoritative `src/shared` tree plus explicit `tests/` roots into an isolated
DataModel. Packet 06.1 added
`src/server/common/networking/ServerRemoteRegistry.luau` and
`src/client/common/networking/ClientRemoteLookup.luau`; Packet 06.3 added
`src/server/common/networking/ProductionRateLimits.luau` and
`src/server/common/networking/ServerRateLimiter.luau`; and Packet 06.4 added
`src/server/common/networking/ServerRequestDispatcher.luau` and
`src/client/common/networking/ClientRequestTracker.luau`. These six exact
modules sit beneath explicit `ServerStorage.AutomatedTests` roots. The project
maps no bootstrap, shutdown hook, place-specific source, or other server/client
path and contains no runnable `Script` or `LocalScript`.

Packet 06.2 requires no new project mapping: shared
`network/PayloadValidation.luau` enters all four projects through the existing
authoritative `src/shared` mapping, while `PayloadValidation.spec.luau` remains
under the Test-only spec root.

The production client API accepts only endpoint name and total timeout; it
internally selects `ProductionRemotes`, actual `ReplicatedStorage`, centralized
place role, `os.clock()`, and bounded `WaitForChild()`. The dependency-injected
resolver used by the runtime spec is attached only when the module's exact
identity is
`ServerStorage.AutomatedTests.ProductionClientNetworking.ClientRemoteLookup`.
The production `StarterPlayerScripts` location fails this structural gate and
exposes no injection seam.

The coordinator:

1. confirm it is running from the repository root;
2. invoke the pinned Rojo build for the isolated test project;
3. deserialize the exact generated DataModel;
4. load ModuleScripts by Instance identity with cycle detection and caching;
5. inject only the standard Luau globals, `script`, the isolated `game`,
   Instance-aware `require`, Roblox `Instance`, `Vector2`, `Vector3`, `CFrame`,
   and the Lune task scheduler;
6. discover normal specs in canonical bytewise path order;
7. execute cases in their declared order with stable suite and case names;
8. emit privacy-safe classifications and paths; and
9. remove only its exact generated test build before returning an exit code.

The ModuleScript environment will not expose filesystem, network, process,
authentication, or secret APIs. A production or test ModuleScript cannot use a
filesystem string with the injected `require`; only a ModuleScript Instance is
accepted.

## Discovery and result contract

- Normal discovery is restricted to the documented automated-spec root.
- Every selected discovery root must be a `Folder`. A wrong-class root fails
  before descendant discovery with `ROOT_WRONG_CLASS`, even when it contains an
  otherwise valid spec.
- Spec ModuleScript names in the isolated DataModel must end in `.spec`; normal
  repository files use the corresponding `.spec.luau` convention. The enforced
  boundary is the Rojo-built ModuleScript name. Any other ModuleScript under a
  selected discovery root fails with `MISNAMED_SPEC`. Valid specs are sorted by
  canonical full path before load.
- Cases retain explicit declaration order. Dictionary iteration order never
  determines discovery or execution.
- Duplicate suite names, duplicate case names, malformed suites, sparse case
  arrays, zero-case suites, compile failures, module-load failures, and zero
  discovered tests are failures.
- Normal discovery never traverses fixtures or negative controls.
- Success output records deterministic suite, case, and summary context.
- Failure output records a stable category, safe code, suite/case when known,
  and canonical repository or DataModel path. It does not reproduce arbitrary
  caught errors, rejected private values, secrets, or catalog contents.

Exit-code classes are:

- `0`: every discovered test passed and runner cleanup succeeded;
- `1`: one or more assertions or test cases failed;
- `2`: discovery, malformed-suite, compile, or ModuleScript-load failure,
  including zero discovered tests; and
- `3`: runner, build, deserialization, structural, or cleanup failure.

Any nonzero class fails local automation and CI. The exact canonical command
must itself preserve these codes.

The permanent negative controls are reproduced with:

| Command | Exit | Category | Stable code |
| --- | ---: | --- | --- |
| `lune run tests/run.luau --control assertion` | 1 | `assertion` | `ASSERT_EQUAL_FAILED` |
| `lune run tests/run.luau --control zero` | 2 | `discovery` | `ZERO_TESTS` |
| `lune run tests/run.luau --control module-load` | 2 | `module-load` | `MODULE_EXECUTION_FAILED` |
| `lune run tests/run.luau --control malformed` | 2 | `discovery` | `MISNAMED_SPEC` |
| `lune run tests/run.luau --control malformed-root` | 2 | `discovery` | `ROOT_WRONG_CLASS` |
| `lune run tests/run.luau --control runner-crash` | 3 | `runner` | `RUNNER_CRASH` |

## Generated-output and shipping policy

The runner may create one exact `.rbxlx` under the ignored `build/` directory
while executing. It removes that file on success and on protected failure. Rojo
verification may create other explicitly named files under `build/`; they are
never tracked or retained as CI artifacts and are removed only by exact path.
`sourcemap.json` remains ignored under the existing policy.

Default, Lobby, and Match project definitions do not map `tests/`, the runner,
fixtures, negative controls, or a third-party test package. Packet verification
builds all projects independently and requires every production
`LuaSourceContainer` to match a fixed positive map of its exact DataModel path,
class, authoritative `src/` file, and byte-for-byte source. Missing, unexpected,
renamed, replaced, or altered source containers fail. Exact class counts, role
isolation, test path/name checks, and test-only source markers remain additional
defenses. Tests cannot ship merely because they exist in the repository.

The two Packet 06.1 production runtime modules mapped into the Test build are
explicit source-under-test, not test dependencies. The verifier requires each at
one exact test-only `ServerStorage` path with source identical to its
authoritative `src/` file. It also requires all three production builds to
contain those modules only at their normal common client/server paths and to
remain completely free of test modules and fixtures.

## Packet 05.1 verification evidence

Verification completed on Windows x64 on 2026-08-26 without modifying
production source, Studio content, or either Roblox place.

- `rokit install` completed and `lune --version` reported `0.10.5`; Rojo,
  StyLua, and Selene retained their existing pins and reported versions.
- `stylua src tests`, `stylua --check src tests`, and
  `stylua --check --verify src tests` passed.
- `selene validate-config` and `selene src tests` passed with zero errors,
  warnings, or parse errors.
- The canonical command discovered one suite and two ordered cases. It loaded
  the exact production `Result` ModuleScript from the Rojo-built DataModel and
  verified the identity-scoped connection adapter delegates ordinary `typeof`
  calls unchanged.
- Isolated controls returned exit `1` for an assertion failure, `2` for zero
  discovery, nested ModuleScript-load failure, and malformed discovery, and `3`
  for a runner crash. Private sentinel values in the intentional failures did
  not appear in output.
- The nested-load control identified
  `ServerStorage.NegativeControls.Dependencies.BrokenDependency` with the stable
  `MODULE_EXECUTION_FAILED` code rather than collapsing the failure into its
  importing spec.
- `lune run tests/verify-builds.luau` independently built Default, Lobby, Match,
  and Test. Every production build retained exactly 30 ModuleScripts, one
  Script, and one LocalScript. Lobby contained no Match layer; Match contained
  no Lobby layer. The Test build contained all 29 shared ModuleScripts and zero
  runnable scripts.
- The verifier scanned each complete production DataModel and found no test
  path, `.spec` module, runner/support marker, fixture, negative control, or
  test-only dependency. Packet 05.2 subsequently hardened this proof with the
  exact positive source map described above.
- All exact generated outputs were removed. The only pre-existing ignored file
  remained `sourcemap.json`.
- A final independent adversarial review found no unresolved P0, P1, or P2
  runner, dependency, deterministic-discovery, privacy, isolation, or
  production-shipping issue.

The intentional controls remain permanently isolated under `tests/negative` so
their failing state cannot enter normal discovery. Selecting a control is a
temporary command mode; the canonical command always returns to the normal
`tests/specs` root without modifying source.

## Packet 05.2 deterministic contract-suite evidence

Verification completed on Windows x64 on 2026-08-26 without changing
production source, Studio-authored content, or either Roblox place.

- Normal discovery found eight suites and 76 stable, descriptive cases in
  canonical path and declaration order.
- Cleanup cases cover LIFO order, duplicate ownership, all supported task
  forms, idempotence, post-clean behavior, nested containers and cycles,
  reentry, cached results, and failure isolation.
- Core-contract cases cover all ten ID families, exact byte boundaries, every
  cross-family pairing, Result branches and immutable envelopes, and every
  declared Validation issue form, code, path, related path, cause, and freeze
  boundary.
- Test-only fixtures represent Assets, Towers, Enemies, Maps, Finite and
  Endless Difficulties, finite and generated Endless Waves, Economy, Banners,
  and Settings. Lasting authored catalogs remain empty and lasting Economy and
  Settings remain policy-only.
- Schema cases cover valid canonical outputs, public single-definition APIs,
  authentication, deep freezing, input detachment, duplicate IDs and
  references, symbolic assets, every cross-catalog reference family,
  non-finite and boundary numbers, discriminants, order rules, probability
  tolerance, version failures, exact issue paths, full issue and blocked-family
  order, malformed roots, and source-load containment.
- Whole-record privacy checks enforce exact public error/report fields and
  recursively prove rejected values, catalog identities, caught errors,
  metatables, and private sentinels do not survive in observable failures.
- Three consecutive canonical runs returned exit 0 with byte-identical 15,469
  byte output and SHA-256
  `52bf494c37f3c47822b5a7c6ce372d8c8ea76ee807ebf28f3ea767cef8c93616`.
  This is reproducibility evidence, not a source or compatibility guarantee.
- Assertion, zero-discovery, module-load, malformed-discovery,
  wrong-class-root, and runner-crash controls returned the documented nonzero
  exit classes and stable codes without printing private markers.
- The four-project verifier passed. Default, Lobby, and Match each retained 30
  ModuleScripts, one Script, and one LocalScript; Test retained 29 shared
  ModuleScripts and no runnable scripts. All 32 production Lua containers
  matched the fixed expected path, class, authoritative file, and exact source.
- Formatting, Selene, all four builds, production exclusion, role isolation,
  generated-output cleanup, lasting-policy checks, and `git diff --check`
  passed. No real coverage percentage is claimed because no coverage tool was
  introduced.
- Fresh independent coverage, quality, privacy, runner, and isolation reviews
  found no unresolved P0, P1, or P2 issue.

## Packet 06.1 completion verification

Packet 06.1 extends normal discovery without
changing the canonical command or its exit-code contract:

- Ten suites and all 106 cases passed in canonical path and declaration order.
- `RemoteRegistry.spec.luau` contributes 18 cases for exact definition shape,
  the 128-definition and 48-byte-name boundaries, canonical ordering and role
  views, deep freezing and provenance, duplicate/conflicting identity,
  unsupported combinations, hostile metatables, and privacy-safe failures.
- `RemoteRuntime.spec.luau` contributes 12 cases for exact parent-last server
  publication, role isolation, complete and unique handler binding, conflict
  preservation, partial-bind rollback, duplicate-owner/re-entry rejection,
  listener-before-root cleanup, every request/response/event leaf shape,
  production dependency-seam exclusion, and bounded exact client lookup with no
  creation.
- Deterministic remote definitions come from `tests/fixtures/NetworkFixtures.luau`;
  the lasting production registry remains empty and no gameplay catalog was
  added.
- `lune run tests/verify-builds.luau` passed with 34 ModuleScripts, one Script,
  and one LocalScript in Default, Lobby, and Match. Test contained 31 shared
  ModuleScripts, exactly the two explicitly mapped networking runtime modules,
  20 test-owned ModuleScripts, and zero runnable scripts.
- The verifier retained exact source identity, production test exclusion,
  Lobby/Match source isolation, intended bootstrap counts, and exact generated
  output removal.

This is focused source/test evidence only. Live Roblox remote delivery and
shutdown remain subject to the authorized unsaved Studio regression. Packet
06.1 is complete; Phase 06 and Gate A remain open.

## Packet 06.2 completion verification

Packet 06.2 extends the same normal discovery and restricted loader without
changing the canonical command or exit-code contract:

- Eleven suites and all 128 cases pass in canonical path and declaration order.
- `PayloadValidation.spec.luau` contributes 22 cases for authenticated/frozen
  schema composition; strict string, enumeration, every typed ID family,
  boolean, finite number/integer, dense array, exact-key record, optional,
  exactly-one bounded union, `Vector2`, `Vector3`, `CFrame`, and explicit
  Instance policies.
- Adversarial cases cover cap and cap-plus-one boundaries, narrower schema
  limits, one shared validation-work budget including nested speculative union
  attempts, sparse and unexpected keys, excessive depth/nodes/fields/items,
  cycles and repeated references, hostile/protected metatables, coercion,
  NaN/infinity, exact component paths, Instance class/ancestry/running-server
  boundary checks, output detachment/freezing, and privacy-safe issues.
- The loader exposes exactly the `@lune/roblox` `Vector2`, `Vector3`, and
  `CFrame` constructor tables in addition to its existing restricted surface.
  Production/test ModuleScripts still receive no filesystem, process, network,
  authentication, or secret API.
- `lune run tests/verify-builds.luau` passes with 35 ModuleScripts, one Script,
  and one LocalScript in Default, Lobby, and Match. Test contains 32 shared
  ModuleScripts, the same two explicitly mapped networking runtime modules, 21
  test-owned ModuleScripts, and zero runnable scripts, for 55 ModuleScripts
  total.
- The verifier retains exact identity for all 37 production Lua containers,
  production test exclusion, Lobby/Match isolation, intended bootstrap counts,
  and exact generated-output cleanup. Lasting production remotes remain empty,
  and no gameplay definition or Phase 07 source was added.

Packet 06.2 completed with this evidence; Packet 06.3 has since completed.

## Packet 06.3 completion verification

Packet 06.3 extends the same normal discovery and restricted loader without
changing the canonical command or its exit-code contract:

- Twelve suites and all 145 cases pass in canonical path and declaration order.
- `ServerRateLimiter.spec.luau` contributes 17 cases for authenticated/frozen
  policy construction and complete inbound coverage, exact burst/refill
  boundaries, independent Player/endpoint state, non-finite/backwards/throwing
  clock containment and recovery, Player-removal and shutdown cleanup, bounded
  state, global aggregate cadence/count saturation, reporter failure isolation,
  and privacy-safe results and diagnostics.
- `RemoteRuntime.spec.luau` retains 12 cases while proving the limiter child is
  initialized and started under the one `NetworkRegistry` lifecycle service and
  participates in exact parent LIFO cleanup.
- `lune run tests/verify-builds.luau` passes with 37 ModuleScripts, one Script,
  and one LocalScript in Default, Lobby, and Match. Test contains 32 shared
  ModuleScripts, exactly four mapped networking modules, 22 test-owned
  ModuleScripts, and zero runnable scripts, for 58 ModuleScripts total.
- The verifier retains exact identity for all 39 production Lua containers,
  production test exclusion, Lobby/Match isolation, intended bootstrap counts,
  and exact generated-output cleanup. The lasting production registry and
  frozen production rate-policy list remain empty.

Packet 06.3 completed with this evidence; Packet 06.4 has since completed.

## Packet 06.4 completion verification

Packet 06.4 extends the same normal discovery and restricted loader without
changing the canonical command or its exit-code contract:

- Fifteen suites and all 189 cases pass in canonical path and declaration
  order.
- `RequestProtocol.spec.luau` contributes 13 cases for exact hostile-safe
  request, event, success, and rejection envelopes; bounded authentic request
  IDs; the fixed public-error allowlist and optional validation-path metadata;
  immutable Pending/Success/Rejected state; and rejected-value privacy.
- `ClientRequestTracker.spec.luau` contributes 12 cases for fixed canonical
  endpoint registration, pre-send payload validation, bounded generation and
  collision retries, the 32-Pending cap, the 128-terminal ring, endpoint and
  response-schema matching, cancellation, stale classification, and explicit
  cleanup.
- `ServerRequestDispatcher.spec.luau` contributes 19 cases for the documented
  check order, one global per-Player request-ID ledger, rate limiting before
  authorization, server-derived context, strict payload and response
  validation, protected handler translation, origin-only sending, duplicate and
  stale behavior, lifecycle/removal/cleanup re-entry, no-response contracts,
  bounded privacy-safe abuse aggregates, and zero handler mutation after an
  authorization-time removal or shutdown.
- `RemoteRuntime.spec.luau` retains 12 cases while proving the registry owns the
  limiter and dispatcher, requires a typed contract for every active inbound
  definition, captures each fixed response leaf, dispatches only the originating
  Player, and disconnects listeners before child and root teardown.
- `lune run tests/verify-builds.luau` passes with 40 ModuleScripts, one Script,
  and one LocalScript in Default, Lobby, and Match. Test contains 33 shared
  ModuleScripts, exactly six mapped networking modules, 25 test-owned
  ModuleScripts, and zero runnable scripts, for 64 ModuleScripts total.
- The verifier retains exact identity for all 42 production Lua containers,
  production test exclusion, Lobby/Match isolation, intended bootstrap counts,
  and exact generated-output cleanup. The lasting production registry and
  rate-policy list remain empty.

Packet 06.4 is complete. Its counts above are historical Packet 06.4 evidence.

## Packet 06.5 completion verification

Packet 06.5 extends the same deterministic discovery and restricted loader
without changing the canonical command or its exit-code contract:

- Sixteen suites and all 200 cases pass in canonical path and declaration
  order. `NetworkSecurity.spec.luau` contributes nine integrated adversarial
  cases while the focused registry, validation, limiter, protocol, dispatcher,
  lookup, and tracker suites remain in normal discovery.
- `ServerRequestDispatcher.spec.luau` now contributes 21 focused cases. The two
  review-driven additions prove that feature callbacks cannot yield and retain
  suspended work, and that only dispatcher-owned payload validation may attach
  public validation-path metadata.
- The integrated cases compose the real foundation modules through test-only
  adapters and cover fixed endpoint use, malformed envelopes and hostile
  payloads, forged authority fields, duplicate/stale correlation, independent
  Player/endpoint bursts, bounded privacy-safe aggregates, contained handler
  failures, and removal/shutdown ownership. They add no gameplay definition.
- `lune run tests/verify-builds.luau` passes with the unchanged 40
  ModuleScripts, one Script, and one LocalScript in Default, Lobby, and Match.
  Test contains 33 shared ModuleScripts, exactly six mapped common networking
  modules, 26 test-owned ModuleScripts, and zero runnable scripts, for 65
  ModuleScripts total.
- `tests/studio/Phase06NetworkServer.server.luau` and
  `tests/studio/Phase06NetworkClient.client.luau` are tracked manual harness
  sources. They are mapped by no Rojo project and therefore are absent from
  Default, Lobby, Match, and Test builds.
- On the observed Roblox Studio installation directory
  `version-dcbeee682ce74ee0`, three unsaved Lobby cycles and three unsaved Match
  cycles passed, followed by the final two-client networking regression. Both
  places were left in Edit mode; neither place was saved or published.
- The production file/build inventory remains unchanged from Packet 06.4. The
  existing dispatcher alone gained non-yielding callback and validation-metadata
  hardening; lasting remote definitions and policies remain empty, and Phase 07
  has not begun.

Packet 06.5 is complete with this packet-level evidence. Phase 06 and Gate A
remain open pending the fresh exit audit and its genuine CI evidence.
