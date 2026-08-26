# Automated test runner

## Decision record

- Status: Packets 05.1 and 05.2 complete; Packet 05.3 locally in progress with
  genuine GitHub evidence pending
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

## Selection criteria

The chosen approach must run strict Luau deterministically on headless Windows
and GitHub-hosted runners, return reliable process exit codes, exercise the
exact pure shared ModuleScript sources without Roblox credentials or
publication, fit the existing Rokit toolchain, and keep every test-only file out
of Default, Lobby, and Match builds.

Lune 0.10.5 meets those requirements with one pinned executable. Its official
release embeds Luau 0.709 and supplies filesystem, process, Luau compilation,
and Roblox DataModel libraries. The project-owned adapter builds
`test.project.json`, deserialize that exact Rojo output, and execute ModuleScript
`Source` with a restricted environment that provides Roblox-style `script` and
Instance-based `require`. The adapter will not attempt to run the full game or
pretend to reproduce Roblox engine behavior.

The principal compatibility risk is semantic drift between Lune's partial
Roblox environment and the live engine. The suite therefore targets existing
pure shared contracts. It excludes client/server bootstraps, shutdown hooks,
services, signals, and other engine integration. Genuine Roblox `Instance`
cleanup can be exercised through Lune's DataModel implementation; the
`RBXScriptConnection` cleanup branch may use a narrowly registered test double
whose `typeof` adapter delegates every unregistered value to the native
function. Studio remains the authority for engine integration regressions.

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
DataModel. It maps no `src/server` or `src/client` path and contains no runnable
`Script` or `LocalScript`.

The coordinator:

1. confirm it is running from the repository root;
2. invoke the pinned Rojo build for the isolated test project;
3. deserialize the exact generated DataModel;
4. load ModuleScripts by Instance identity with cycle detection and caching;
5. inject only the standard Luau globals, `script`, the isolated `game`,
   Instance-aware `require`, Roblox `Instance`, and the Lune task scheduler;
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
