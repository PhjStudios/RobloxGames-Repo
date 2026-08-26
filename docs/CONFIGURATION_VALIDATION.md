# Whole-Configuration Validation and Bootstrap Gate

## Purpose

This document records the contracts, decisions, verification evidence, and
regression procedure for Packet 04.5 of `docs/DEVELOPMENT_PLAN.md`. The packet
composes every Phase 04 schema into one deterministic validation boundary and
gates both common bootstraps before any lifecycle service starts.

It adds no production tower, enemy, map, wave, difficulty, banner, or balance
content. Lasting catalogs remain empty, and all nonempty fixtures were
synthetic, temporary, and destroyed after validation.

## Packet status

- Packet: 04.5
- Status: Complete
- Recorded: 2026-08-26
- Whole-catalog implementation:
  `src/shared/config/ConfigurationValidator.luau`
- Shared aggregate types: `src/shared/types/ConfigTypes.luau`
- Bootstrap consumers: common client and common server only
- Loaded configuration families: 9
- Registered gameplay services: 0
- Test runner, test project, or CI added by Packet 04.5: none; Phase 05 later
  added them without changing this production bootstrap
- Studio-authored content changed: no
- External services enabled: no
- Place saved or published: no

## Public boundary

`ConfigTypes.AuthoredConfigurationSources` names all nine authored inputs, but
each field is `unknown` at the trust boundary. Static annotations on an authored
module do not replace runtime validation.

`ConfigurationValidator` exposes:

```luau
type ValidationResult = Result.Result<ConfigTypes.CoreConfiguration, Report>

validate(value: unknown): ValidationResult
validateLoaded(): ValidationResult
isValidatedConfiguration(value: unknown): boolean
```

`validate` is the pure fixture and future tool boundary. `validateLoaded` is the
single entry point used by Lobby and Match bootstraps. It loads the nine lasting
authored modules and passes their returned values through the same pure path.

A successful `CoreConfiguration` contains canonical values for:

1. assets;
2. towers;
3. enemies;
4. difficulties;
5. maps;
6. wave schedules;
7. economy;
8. banners; and
9. default settings.

Each component is the authentic canonical output of its owning schema. The
aggregate is a new frozen record marked in a private weak-key registry. Raw,
copied, serialized, or forged tables do not pass
`isValidatedConfiguration`; they must be validated again.

## Deterministic dependency order

Validation uses this fixed topological order:

```text
Assets
  -> Towers -------------------------------> Banners
  -> Enemies -----------+
  -> Difficulties ------+-> Maps ----------> WaveSchedules
                        +-------------------> Economy
DefaultSettings (independent)
```

The report order is always:

```text
Assets, Towers, Enemies, Difficulties, Maps, WaveSchedules,
Economy, Banners, DefaultSettings
```

No report ordering depends on dictionary traversal. Report arrays are copied
with numeric loops in their established order. Individual schemas already use
dense authored arrays and deterministic field/error precedence.

The composed schemas resolve every Phase 04 reference category:

- tower, enemy, difficulty, and map asset keys;
- map-to-difficulty support;
- schedule-to-map and schedule-to-difficulty pairs;
- wave-group enemy and map-local lane references;
- reverse schedule coverage for every supported map/difficulty pair;
- economy coverage for every difficulty;
- banner outcome and pity references to towers; and
- all catalog-local ID and value uniqueness rules.

Feature references such as future attack behaviors and Endless generators still
validate only their family and symbolic-key grammar because their registries
belong to later phases.

## Root causes and blocked families

Each Phase 04 schema returns its first deterministic issue. The whole validator
can report one root issue from every independent family that was safe to
evaluate in the same run. A failure report is deeply frozen and contains:

```luau
type Report = {
    firstIssue: Validation.Issue,
    issues: { Validation.Issue },
    blockedFamilies: { Family },
}
```

`firstIssue` is guaranteed to be the same object as `issues[1]`; an empty
failure report cannot be constructed. `blockedFamilies` lists families that
were deliberately not evaluated because an authentic dependency was
unavailable. This suppresses misleading cascades. For example:

- invalid Towers blocks Banners only;
- invalid Enemies blocks WaveSchedules only;
- invalid Difficulties blocks Maps, WaveSchedules, and Economy; and
- invalid Assets blocks Towers, Enemies, Difficulties, Maps, WaveSchedules,
  Economy, and Banners while independent DefaultSettings still validates.

A malformed outer source container prevents all nine families from being
evaluated, so all nine appear as blocked. A failure never returns a partial
`CoreConfiguration`.

## Safe source loading

`ConfigurationValidator` does not require authored data modules while its own
module is loading. `validateLoaded` loads them in the same fixed family order
under narrow `pcall` boundaries. If a source ModuleScript fails to load:

- the caught value is discarded;
- the report uses stable code `SOURCE_LOAD_FAILED`;
- the path is only the affected family, such as `Assets`;
- the message is the static `Authored configuration source failed to load`;
- no exception object, source text, catalog value, or arbitrary callback error
  enters the report or log; and
- no schema or dependent system starts with a partial loaded set.

Loaded sources are atomic: if any authored module fails to load, schemas do not
run for the otherwise successful modules. Those successful families appear in
`blockedFamilies`, while every failed source receives its own fixed-order
`SOURCE_LOAD_FAILED` issue.

This is a fail-closed authoring safeguard, not a recovery or fallback content
system.

## Error paths and privacy

Existing `Validation.Issue` records retain stable codes, frozen path segments,
safe static messages, optional safe `causeCode`, and optional earlier
`relatedPath`. Representative composed paths are:

```text
Towers[2].id
Enemies[1].maxHealth
Maps[1].supportedDifficultyIds[1]
WaveSchedules[1].waves[1].groups[1].enemyId
Economy.difficultyRules[1].damageIncome.healthRemovedDenominator
Banners[1].outcomes
DefaultSettings.version
```

Rejected values are never interpolated into these records. The bootstrap logs
only the first stable code, total issue count, and first path. It does not log
issue messages, `relatedPath`, catalogs, reports, caught errors, IDs stored as
values, or arbitrary table contents.

The logging allowlist adds only:

- public subsystem `configuration`;
- `configurationFamilyCount`;
- `issueCount`; and
- `validationPath`.

`validationPath` has a dedicated maximum length of 512 bytes and accepts only
the canonical grammar:

```text
Identifier(.Identifier|[positive-integer])*
```

This permits actionable paths without permitting whitespace, control
characters, equals signs, zero/negative indexes, unmatched brackets, or
unrelated punctuation inside the logger's bracket-delimited record format.

## Bootstrap gate

Both common bootstraps now use the same sequence:

1. snapshot PlaceId and Studio state;
2. create the provisional unresolved context and logger;
3. validate centralized PlaceId configuration;
4. resolve the declared Lobby, Match, or Development role;
5. create the resolved context and logger;
6. call `ConfigurationValidator.validateLoaded()`;
7. fail through structured `Log.error` when invalid; and only on success
8. create the lifecycle runner; the client starts it empty, while the server
   constructs the fixed network owner from the empty production registry and
   empty rate-policy list, registers one `NetworkRegistry` service, and then
   initializes and starts it;
9. create cleanup ownership;
10. register the server close hook; and
11. emit the existing ready record.

Successful Studio boot adds one record per execution context before the ready
record:

```text
[subsystem=configuration][event=validated][configurationFamilyCount=9]
```

An invalid configuration uses static event `validation_failed`. `Log.error`
raises in both Studio and production, so the script stops before lifecycle,
cleanup, or server shutdown resources are created. The error remains observable
with resolved execution context, role, PlaceId, environment, code, count, and
path. Production `DEBUG`/`INFO` suppression is unchanged.

Valid configuration follows the exact Phase 03 lifecycle, cleanup, and graceful
shutdown path. Rejected boot has nothing to clean because it creates no owned
resource and installs no `BindToClose` hook.

## Focused Studio validation

Both synchronized places used fresh temporary clones of
`ReplicatedStorage.Shared`, preventing old Edit-mode `require` caches from
mixing schema authenticity registries. All clones, strict consumers, and
temporary source-failure modules were destroyed. No place was saved.

| Place | Whole-validator evidence | Source-load evidence | Result |
| --- | ---: | ---: | --- |
| Lobby (`100561454756026`) | 330 assertions | 26 assertions | Pass |
| Match (`136401514513678`) | 58 parity assertions | 26 assertions | Pass |

A temporary `--!strict` consumer imported `Family`, `Report`, and
`ValidationResult`, narrowed both Result branches, accessed the authenticated
aggregate, and compiled/executed in both places.

The evidence covered:

- lasting empty configuration and a representative nonempty synthetic graph;
- aggregate and component authenticity, deep freezing, and detachment from raw
  input;
- malformed/missing/unknown outer source fields;
- duplicate Tower and Enemy IDs;
- invalid and missing asset references;
- broken map/difficulty, wave/enemy, wave/lane, economy/difficulty,
  banner/tower, and pity references;
- NaN rejection, invalid probability totals, and unsupported settings versions;
- fixed multi-root issue order across ten repeated validations;
- precise blocked-family order without dependency-noise issues;
- frozen reports, nonempty `firstIssue`, and absence of partial success values;
- static privacy-safe messages with synthetic secret sentinels;
- canonical log formatting and valid actionable paths;
- rejection of unmatched/zero-index brackets, equals signs, whitespace,
  controls, and overlength log paths;
- production-context fail-closed behavior before a dependent-start sentinel;
  and
- missing, wrong-class, single-throwing, and multiple-throwing source
  ModuleScripts without reflecting caught errors.

## Initial Phase 03 regression

After bootstrap integration, one isolated Play/Stop cycle passed in each place.
Each server and client emitted configuration success before its ready record.
Lobby resolved PlaceId `100561454756026`; Match resolved PlaceId
`136401514513678`. Both contexts reached lifecycle `Started`, cleanup `Active`
with one task, and zero services. On Stop, each server reached lifecycle
`Shutdown` and cleanup `Cleaned` within the existing ten-second budget. No Ant
Tower Defense warning or error appeared, and both sessions returned to Edit
mode without saving or publishing.

The fresh Phase 04 exit audit then completed three additional consecutive
cycles per place from the final combined source state. All six cycles preserved
the same ordering and terminal states with zero ATD warning or error, and both
places ended in Edit mode. The audit also reran 376 combined assertions in each
place and recorded its complete evidence in `docs/PHASE_04_EXIT_AUDIT.md`.

Packet 06.5 subsequently passed a fresh unsaved networking regression against
the network-enabled bootstrap. Three plain Lobby and three plain Match
Play/Stop cycles each reported server `serviceCount=1`, client
`serviceCount=0`, successful configuration before ready, clean shutdown, and
final Edit mode. The final runtime-only two-client Match harness passed real
`PlayerRemoving`, a remaining-peer request, server and remaining-client
`caseCount=10` terminals, fixture cleanup `Cleaned`, preservation of the empty
production `ATDNetwork/v1` tree, and bounded Output audits with
`forbiddenMatches=0` and `errorCount=0`. See
`docs/NETWORK_SECURITY_STUDIO_REGRESSION.md`.

## Formatting, lint, and build verification

| Check | Result |
| --- | --- |
| Focused StyLua formatting | Pass |
| `stylua --check src` | Pass |
| `stylua --check --verify src` | Pass |
| `selene src` | Pass; 0 errors, 0 warnings, 0 parse errors |
| `rojo build default.project.json` | Pass |
| `rojo build lobby.project.json` | Pass |
| `rojo build match.project.json` | Pass |
| Independent validator/bootstrap adversarial review | Pass after hardening |
| Fresh Phase 04 source and documentation audits | Pass after documentation reconciliation |

Each build contains 29 shared ModuleScripts plus the server-only `Shutdown`
module, for 30 ModuleScripts total, alongside one Script and one LocalScript.
`ConfigurationValidator` appears in every build. Default retains both empty role
folders, Lobby contains no Match source, and Match contains no Lobby source.
The exact ignored build artifacts were removed after inspection.

## Scope boundary

Packet 04.5 adds no gameplay service, controller, remote, network protocol,
DataStore, MemoryStore, TeleportService, profile, currency mutation, reward
grant, gacha roll, purchase, settings application, UI, Studio tag, map loader,
enemy movement, wave scheduler, tower behavior, external dependency, CI,
publishing action, or production content.

The source loader's `pcall` exists only to convert authored ModuleScript loading
failure into a safe typed report. It does not catch or expose arbitrary gameplay
callbacks.

## Regression procedure

1. Run `stylua src tests`, then `stylua --check --verify src tests`,
   `selene validate-config`, and `selene src tests`.
2. Run `lune run tests/run.luau`. Confirm all 200 ordered cases across 16 suites
   pass, including
   lasting-empty and policy-only configuration, representative graphs, invalid
   references/boundaries, exact code/path/order, privacy, malformed roots, and
   source-load containment.
3. Run `lune run tests/verify-builds.luau`. Confirm all four builds; 40
   ModuleScripts plus one Script and one LocalScript in each production build;
   65 ModuleScripts and zero runnable scripts in Test; role isolation; exact
   source identity; and no test code in production.
4. If production bootstrap or engine-integration behavior changed, connect
   `lobby.project.json` only to Lobby and `match.project.json` only to Match.
5. In each affected place, complete three consecutive Play/Stop cycles. Confirm
   configuration success precedes ready on server and client; lifecycle reaches
   `Started`; cleanup is `Active`; server Stop reaches `Shutdown`/`Cleaned`; and
   there are no unexplained warnings or errors.
6. Use a temporary reviewed Studio harness only for an engine-parity case that
   the headless suite cannot represent. Never break lasting authored source to
   force a source-load failure.
7. Leave both sessions in Edit mode. Remove only exact temporary harnesses and
   builds. Do not save or publish merely to test.

Automated evidence is in `docs/TEST_RUNNER.md` and CI evidence is in
`docs/CONTINUOUS_INTEGRATION.md`. `docs/TEST_MATRIX.md` distinguishes headless
coverage from historical, current, and deferred environment-specific gates.
The fresh local Phase 06/Gate A configuration, build, and Studio checks pass in
`docs/PHASE_06_EXIT_AUDIT.md`; current audit-content CI evidence and its
completion record remain open.
