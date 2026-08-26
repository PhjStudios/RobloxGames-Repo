# Map, Difficulty, and Wave Configuration Schemas

## Purpose

This document records the contracts, decisions, limits, and verification evidence
for Packet 04.3 of `docs/DEVELOPMENT_PLAN.md`. The packet defines immutable map,
difficulty, authored-wave, and generated-Endless input data before any runtime
map loader, wave scheduler, enemy spawner, reward service, or Endless generator
exists.

No production map, difficulty, enemy composition, wave list, boss roster, reward
amount, or balance value was authored. `Difficulties.luau`, `Maps.luau`, and
`Waves.luau` remain frozen empty arrays. All nonempty data used for verification
was synthetic, temporary, and destroyed afterward.

## Packet status

- Packet: 04.3
- Status: Complete
- Recorded: 2026-08-26
- Shared types: `src/shared/types/ConfigTypes.luau`
- Shared validation limits: `src/shared/util/Validation.luau`
- Schemas: `src/shared/config/DifficultySchema.luau`,
  `src/shared/config/MapSchema.luau`, and
  `src/shared/config/WaveSchema.luau`
- Empty authored catalogs: `src/shared/config/Difficulties.luau`,
  `src/shared/config/Maps.luau`, and `src/shared/config/Waves.luau`
- Supporting changes: `AssetSchema` recognizes symbolic `MapModel` entries,
  `SchemaPrimitives` recognizes grammar-only `EndlessWaveGenerator` references,
  and `EnemySchema` exposes its private validated-catalog identity check
- Source type mode: `--!strict`
- Gameplay, networking, persistence, UI, economy mutation, or services added: none
- Bootstrap integration added by Packet 04.3: none; Packet 04.5 now composes
  these schemas through whole-catalog boot validation
- Studio-authored content changed: no
- External services enabled: no
- Place saved or published: no

## Validation dependency graph

Raw authored arrays are validated in this deterministic order:

```text
Assets
  -> AssetSchema.validateManifest
       -> DifficultySchema.validateCatalog(Difficulties, manifest)
       -> EnemySchema.validateCatalog(Enemies, manifest)

validated manifest + validated difficulties
  -> MapSchema.validateCatalog(Maps, manifest, difficulties)

validated maps + validated difficulties + validated enemies
  -> WaveSchema.validateCatalog(Waves, maps, difficulties, enemies)
```

Every public validator returns
`Result.Result<CanonicalValue, Validation.Issue>`. Expected configuration
mistakes return frozen structured failures instead of throwing. These packet
validators deliberately return only the first deterministic issue. Packet 04.5
now composes them into the one whole-catalog report and bootstrap gate without
changing their individual contracts.

Each downstream schema requires the exact canonical dependency produced by the
corresponding validator in the same ModuleScript instance. Private weak-key
identity markers reject forged lookalike catalogs before indexed access. The
markers prove successful local validation, not origin, authorization, or a
cryptographic signature. Serialized data and cloned ModuleScript VMs must be
validated again.

## Map contract

A map definition contains:

| Field | Required | Contract |
| --- | --- | --- |
| `id` | Yes | Catalog-unique canonical `Ids.MapId` |
| `displayName` | Yes | Bounded authored text |
| `description` | No | Bounded authored text when present |
| `modelAssetKey` | Yes | Declared symbolic `MapModel` key |
| `iconAssetKey` | No | Declared symbolic `Icon` key |
| `lanes` | Yes | Nonempty dense list of map-local lane records |
| `supportedDifficultyIds` | Yes | Nonempty dense list of known difficulty IDs |
| `tags` | No | Nonempty unique symbolic-key list when present |

`MapModel` is a serialization-safe declaration only. It is not a Roblox asset
ID, Instance, DataModel path, uploaded model, or proof that Studio content
exists. Phase 07 owns physical map tags, marker attributes, model binding,
route geometry, bounds, spawn points, placement zones, and the defender-base
Instance.

Each lane currently contains only a symbolic `id`. Lane IDs are unique within
one map and may be reused by another map. Nodes, waypoints, path length, spawn
and base Instances, and runtime distance data are explicitly forbidden. A wave
group resolves its lane against the schedule's selected map.

Every supported difficulty must already exist in the validated difficulty
catalog, and the list cannot contain duplicates. Across a map catalog, no more
than 1,000 map/difficulty pairs may be declared because the wave catalog can
contain at most 1,000 schedules and must cover every pair exactly once.

## Difficulty contract

The discriminated union uses `kind`:

```luau
type DifficultyDefinition = FiniteDifficultyDefinition | EndlessDifficultyDefinition
```

Both variants contain:

| Field | Contract |
| --- | --- |
| `id` | Catalog-unique canonical `Ids.DifficultyId` |
| `displayName` / optional `description` | Bounded authored text |
| optional `iconAssetKey` | Declared symbolic `Icon` key |
| `base.maxHealth` | Positive safe integer |
| `modifiers.enemyHealthMultiplier` | Finite number from `0.001` through `1,000` |
| `modifiers.enemyMoveSpeedMultiplier` | Finite number from `0.001` through `1,000` |
| `timing.earlyClearIntermissionSeconds` | Finite number from `0` through `3,600` |
| `timing.bossCadenceWaves` | Integer from `1` through `1,000` |
| `timing.skipVoteMinimumDelaySeconds` | Finite number from `0` through `3,600` |
| optional `tags` | Nonempty unique symbolic-key list |

A finite difficulty also requires an integer `waveCount` from 1 through 1,000.
An Endless difficulty forbids `waveCount`; it is not represented by a sentinel,
large number, or concealed finite list.

`base.maxHealth` is difficulty-owned configuration in this contract. This
allows difficulty runtime to choose the maximum without storing current health
or an Instance in content data. Phase 07 binds the physical map base marker, and
Phases 10 and 11 own runtime initialization and any later approved composition
between map and difficulty metadata.

The schemas are generic enough for synthetic and future content. They do not
hardcode names such as Easy or Hard. The accepted product defaults remain:

- Easy: 20 authored waves.
- Normal: 30 authored waves.
- Hard: 40 authored waves.
- Endless: unbounded generated continuation.
- Boss cadence: every 10 waves.
- Early-clear intermission: 5 seconds.

A temporary exact-default fixture proved all of these values are representable.
Production definitions and balance remain later content work.

## Wave schedules and indexes

`Waves.luau` authors one dense array of schedules. A schedule is keyed by the
pair `(mapId, difficultyId)` rather than by a separate runtime schedule ID.
Successful validation produces:

```luau
type WaveCatalog = {
    ordered: { WaveScheduleDefinition },
    byId: { [Ids.WaveId]: AuthoredWaveDefinition },
    byMapId: { [Ids.MapId]: { [Ids.DifficultyId]: WaveScheduleDefinition } },
}
```

`ordered` preserves authored schedule order. `byMapId` provides exact pair
lookup. `byId` contains every authored finite wave and authored Endless opening
wave; it cannot contain future generated runtime waves.

For every map-supported difficulty there must be exactly one schedule. A known
but unsupported difficulty, an unknown map or difficulty, a duplicate pair, and
a missing reverse-coverage pair all fail with the precise authored path.
Wave IDs are globally unique across all finite schedules and Endless prefixes.

### Authored finite schedules

`AuthoredFinite` requires a finite difficulty and a dense `waves` array whose
length equals `difficulty.waveCount`. Array position is the wave's sequence
number. No duplicate ordinal field is stored, so authored order cannot disagree
with a separate number.

Finite schedules forbid `authoredOpeningWaves` and `generator`.

### Generated Endless inputs

`GeneratedEndless` requires an Endless difficulty and contains:

- `authoredOpeningWaves`, a bounded dense prefix which may be empty; and
- `generator`, an `EndlessWaveGenerator` feature reference with a canonical
  symbolic key.

The generator reference validates only its kind and key grammar because no
generator registry exists. Phase 32 owns registry resolution, the authored-to-
generated transition, seeds, deterministic RNG, pools, formulas, scaling,
runtime caps, and actual wave production. Packet 04.3 does not make Endless
finite and does not implement any generator behavior.

## Authored wave and group contract

An authored wave contains:

| Field | Contract |
| --- | --- |
| `id` | Globally unique canonical `Ids.WaveId` |
| `deadlineSeconds` | Finite number from `0.01` through `3,600` |
| `deadlinePolicy` | `AllSpawnsByDeadline` or `AllowScheduledOverlap` |
| `bossKind` | `None`, `MiniBoss`, or `Boss` |
| `rewardClass` | `Standard`, `Milestone`, or `Final` |
| `groups` | Dense list of at most 128 spawn groups |

An ordinary `None` wave may have no groups. A `Boss` or `MiniBoss` wave must
have at least one group. The marker describes the wave; it does not yet prove
that one referenced enemy is semantically a boss because no production boss
roster or behavior registry exists.

A group contains an enemy ID, map-local lane ID, positive integer count,
non-negative start delay, and non-negative spawn interval. Enemy and lane
references must resolve. Groups must appear in nondecreasing
`startDelaySeconds` order; equal start times are allowed. Mutable counts,
timestamps, active enemies, scheduler state, Instances, and RNG are forbidden.

For zero-based spawn index `n` from `0` through `count - 1`, the authored time is:

```text
startDelaySeconds + n * spawnIntervalSeconds
```

All times are relative to wave start. `AllSpawnsByDeadline` is inclusive: the
last authored spawn may occur at the deadline. Floating comparison uses the
deterministic tolerance:

```text
max(1, abs(deadlineSeconds), abs(lastSpawnSeconds)) * 1e-9
```

`AllowScheduledOverlap` allows later authored spawns to remain attributed to an
older wave after that wave's deadline, into a later wave window. It does not lift
the technical 3,600-second last-spawn horizon. The horizon comparison uses
`3,600 * 1e-9` tolerance.
Runtime completion, cancellation, old-wave ownership, and next-wave scheduling
remain Phase 11 behavior.

## Boss and reward metadata

The difficulty's cadence is applied to the wave's dense sequence index:

- a cadence wave must use `Boss`;
- `Boss` is forbidden off cadence;
- `MiniBoss` is representable off cadence;
- a final finite wave must use `Final`, including when it is a cadence boss;
- a nonfinal `None` wave must use `Standard`; and
- a nonfinal `Boss` or `MiniBoss` wave must use `Milestone`.

Endless opening waves are never final, so they cannot use `Final`. Reward
classes contain no numeric amount and grant nothing. Packet 04.4 now maps those
classes to typed Battle Cash and pending Gold metadata as recorded in
`docs/ECONOMY_BANNER_SETTINGS_SCHEMAS.md`; later authoritative services still own
mutation and granting.

## Numeric composition and technical work limits

Enemy health and speed remain finite positive content values from Packet 04.2.
Whenever a wave references an enemy, `WaveSchema` also verifies that multiplying
those values by the selected difficulty modifiers remains finite and greater
than zero. This rejects both overflow to infinity and subnormal underflow to
zero before runtime consumes the pair.

Technical ceilings are safety bounds, not approved production balance. The
shared limits documented in `docs/TOWER_ENEMY_SCHEMAS.md` also apply: 64 object
fields, 80 display-name code points, 500 description code points, and 32 tags.
The 04.3-specific ceilings are:

| Scope | Maximum |
| --- | ---: |
| Difficulty, map, or schedule catalog entries | 1,000 |
| Supported difficulties per map | 32 |
| Lanes per map | 32 |
| Map/difficulty pairs across all maps | 1,000 |
| Authored waves in one schedule | 1,000 |
| Authored waves across the catalog | 1,000 |
| Groups in one wave | 128 |
| Enemies in one group | 10,000 |
| Scheduled enemies in one wave | 100,000 |
| Authored groups across the catalog | 10,000 |
| Authored scheduled enemies across the catalog | 1,000,000 |
| Zero-interval enemies in one group | 100 |
| Enemies at one exact authored numeric time in one wave | 1,000 |
| Authored time field and derived last-spawn horizon | 3,600 seconds |

The simultaneous limit counts every computed spawn event, including events from
positive intervals and values whose floating additions round to the same Luau
number. Buckets use exact IEEE-number identity. This is an authored-data work
bound, not a future frame scheduler or performance guarantee.

## Canonical output and deterministic failures

Validators reconstruct accepted fields into new canonical records and deeply
freeze definitions, nested arrays, lookup tables, pair indexes, issues, path
segments, and Result envelopes. Mutating raw input cannot change canonical
output. Lookup values are the same canonical objects present in ordered views.
Canonical ordered data is JSON-safe and may be serialized, but deserialized
data must pass validation again.

Metatable-bearing objects and arrays are rejected before access. Validation
uses raw access and does not execute `__index`, `__pairs`, or `__tostring`.
Runtime fields receive `RUNTIME_FIELD_FORBIDDEN`, multiple safe unknown fields
choose the lexical first path, and dense arrays are processed in increasing
index order. Duplicate values report the current path plus the first declaration
through `relatedPath`.

Representative paths include:

```text
Maps[1].lanes[2].id
Maps[1].supportedDifficultyIds[1]
WaveSchedules[2].difficultyId
WaveSchedules[1].waves[10].bossKind
WaveSchedules[1].waves[1].groups[2].startDelaySeconds
```

## Focused Studio validation

Both synchronized places used temporary clones of `ReplicatedStorage.Shared` so
each harness received fresh ModuleScript caches. Every clone was destroyed and
no place was saved.

| Place | Current Packet 04.3 assertions | Result |
| --- | ---: | --- |
| Lobby (`100561454756026`) | 397 explicit assertions plus empty-catalog smoke | Pass |
| Match (`136401514513678`) | 59 explicit assertions plus empty-catalog smoke | Pass |

The evidence included:

- an exact Easy 20, Normal 30, Hard 40, and generated-Endless fixture in both
  places, with cadence 10 and five-second intermission;
- inclusive deadline equality, genuine late-first and late-repeated spawns,
  explicit overlap, technical horizon, and floating tolerance cases;
- group chronological order, exact 1,000-event concurrency, mixed zero/positive
  intervals, positive subnormal interval rounding, and first-excess failures;
- finite and non-finite fields, derived enemy-stat overflow and underflow, safe
  integer, array, per-wave, per-schedule, and catalog-wide bounds;
- valid, malformed, duplicate, unsupported, and unresolved map, difficulty,
  lane, enemy, wave, schedule-pair, asset, and generator references;
- finite/Endless field discrimination, reverse schedule coverage, global wave
  ID uniqueness, cadence markers, empty boss waves, and reward-class rules;
- forged dependencies, hostile metatables, runtime-field precedence, lexical
  first unknown fields, ten-run deterministic issue reproduction, frozen
  results, deep canonical freezing, raw-input detachment, and JSON encoding;
- explicit successful boundaries at 1,000 supported pairs, 1,000 authored
  waves, 10,000 authored groups, and 1,000,000 authored scheduled enemies,
  followed by exact first-excess failures for each aggregate; and
- a temporary `--!strict` consumer in both places covering the new unions,
  narrowing, IDs, literals, Results, public validator APIs, and authenticity
  checks. It compiled, executed nine runtime assertions, and was destroyed.

The lasting `Assets`, `Towers`, `Enemies`, `Difficulties`, `Maps`, and `Waves`
catalogs remained empty.

## Phase 03 regression evidence

One isolated Play/Stop regression passed in each place. Lobby resolved role
`Lobby` at PlaceId `100561454756026`; Match resolved role `Match` at PlaceId
`136401514513678`. Each server and client emitted exactly one ready record with
lifecycle `Started`, cleanup `Active`, one cleanup task, and zero services. Each
server then emitted one shutdown `started` record with the established
10-second budget and one `completed` record with cleanup `Cleaned` and lifecycle
`Shutdown`.

Both server and client runtime trees contained one common executable and zero
opposite-role executables. The Lobby place preserved an empty unknown
opposite-role folder from earlier Studio state, which is allowed by the Rojo
unknown-instance policy. An initial test-only assertion incorrectly required
that preserved folder to be absent and produced two `AssistantCommand` lines;
the corrected executable-count assertion passed. These were diagnosed harness
errors, not Ant Tower Defense warnings. No application warning, failure,
timeout, duplicate bootstrap, or hang appeared. Both sessions returned to Edit
mode without saving.

## Formatting, lint, build, and structural verification

| Check | Result |
| --- | --- |
| Focused StyLua formatting | Pass |
| `stylua --check src` | Pass |
| `stylua --check --verify src` | Pass |
| `selene src` | Pass; 0 errors, 0 warnings, 0 parse errors |
| `rojo build default.project.json` | Pass |
| `rojo build lobby.project.json` | Pass |
| `rojo build match.project.json` | Pass |
| Independent source audit | Pass; no remaining Packet 04.3 blocker |

Each build contained 23 ModuleScripts, one server Script, and one client
LocalScript. Twenty-two modules are shared; server-only `Shutdown` is the
twenty-third. All six Packet 04.3 modules appeared under
`ReplicatedStorage.Shared`. Default retained both empty role layers, Lobby had
no Match layer, Match had no Lobby layer, and no role-specific executable
existed. Exact ignored audit builds were removed after inspection; the
pre-existing ignored `sourcemap.json` was not touched.

Current combined-state build counts are recorded in
`docs/PHASE_04_EXIT_AUDIT.md`; this historical Packet 04.3 evidence remains
unchanged.

## Regression procedure

1. Format changed Luau, run both whole-source StyLua checks, and run Selene.
2. Build Default, Lobby, and Match independently into exact ignored outputs.
3. Recheck the current 30/1/1 instance counts, shared schema presence, and role
   isolation, then remove only those outputs.
4. In each correctly connected Studio place, clone `ReplicatedStorage.Shared`
   into a temporary Edit-mode harness to avoid stale `require` caches.
5. Validate the dependency graph in order and rerun empty, exact-default, valid,
   invalid, hostile, boundary, immutability, serialization, and strict-consumer
   cases.
6. Destroy the harness and confirm lasting catalogs are still empty.
7. Run an isolated Play/Stop cycle in Lobby and Match and verify the established
   role, startup, cleanup, and shutdown terminal records.
8. Leave both places in Edit mode. Do not save or publish merely to test.

A persistent runner, test project, CI workflow, and `docs/TEST_MATRIX.md` remain
Phase 05 work. Packet 04.5 composes these schemas through the whole-catalog
report and bootstrap gate documented in `docs/CONFIGURATION_VALIDATION.md`;
Phase 04 passed its fresh exit audit in `docs/PHASE_04_EXIT_AUDIT.md`. Packet
05.1 is next and has not begun.
