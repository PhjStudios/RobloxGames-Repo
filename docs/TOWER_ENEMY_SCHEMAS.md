# Tower and Enemy Configuration Schemas

## Purpose

This document records the implementation decisions and verification evidence for
Packet 04.2 of `docs/DEVELOPMENT_PLAN.md`. The packet establishes strict,
serialization-safe content contracts for towers, enemies, and their symbolic
asset manifest before gameplay code consumes those definitions.

The packet defines and validates immutable content. It does not place towers,
spawn or move enemies, resolve attacks or status effects, calculate merge ranks,
award currency, load Studio models, add networking, or change either bootstrap.

## Packet status

- Packet: 04.2
- Status: Complete
- Recorded: 2026-08-25
- Shared types: `src/shared/types/ConfigTypes.luau`
- Validation primitives: `src/shared/util/Validation.luau`
- Schema implementations: `src/shared/config/AssetSchema.luau`,
  `src/shared/config/SchemaPrimitives.luau`,
  `src/shared/config/TowerSchema.luau`, and
  `src/shared/config/EnemySchema.luau`
- Authored catalogs: `src/shared/config/Assets.luau`,
  `src/shared/config/Towers.luau`, and `src/shared/config/Enemies.luau`
- Source type mode: `--!strict`
- Lasting fixture definitions added: none; all three authored catalogs are empty
- Gameplay, runtime entities, networking, UI, or persistence added: none
- Aggregate configuration reporter or bootstrap integration added by Packet
  04.2: none; Packet 04.5 now composes this schema externally
- Studio-authored content changed: no
- External services enabled: no
- Place saved or published: no

## Validation flow

Consumers validate raw authored data in this order:

```text
Assets.luau (raw dense array)
  -> AssetSchema.validateManifest
  -> frozen, identity-marked AssetManifest
       -> TowerSchema.validateCatalog(Towers, manifest)
       -> EnemySchema.validateCatalog(Enemies, manifest)
```

Each call returns `Result.Result<CanonicalValue, Validation.Issue>`. Expected
configuration mistakes do not throw. The first deterministic issue is returned.
Packet 04.5 now composes that result into the all-catalog report and
development-boot gate without changing this schema's public result.

`TowerSchema` and `EnemySchema` accept only the exact canonical manifest produced
by the same `AssetSchema` module instance. The private weak identity marker
prevents an untyped caller from supplying a forged lookup table and causing an
exception, executing a hostile metatable, or authorizing an undeclared key.
`SchemaPrimitives.assetKey` repeats this check as an internal defense-in-depth
boundary.

Packet 04.4 additionally gives successful canonical Tower catalogs their own
private weak identity marker. `BannerSchema` requires that exact marker before
resolving outcome Tower IDs. A copied, frozen, serialized, or separately cloned
Tower catalog must be validated again.

The marker proves only that `AssetSchema` reconstructed and froze that exact
table after validating its shape, keys, and kinds. It is not provenance,
authorization, a signature, or proof that the raw input came from
`Assets.luau`. Serialization or a separate VM/module clone loses the marker and
requires validation again.

## Asset manifest contract

`Assets.luau` authors a dense array of records with exactly:

| Field | Required | Contract |
| --- | --- | --- |
| `key` | Yes | Globally unique symbolic key, at most 64 ASCII bytes |
| `kind` | Yes | `TowerModel`, `EnemyModel`, `MapModel`, or `Icon` |

Packet 04.3 added the `MapModel` family for symbolic map definitions. It does
not change Packet 04.2 tower/enemy behavior; current map contracts are recorded
in `docs/MAP_DIFFICULTY_WAVE_SCHEMAS.md`.

Symbolic keys use:

```text
[a-z0-9]+(?:[._-][a-z0-9]+)*
```

They are logical names, not Roblox asset IDs, URLs, filesystem paths, DataModel
paths, Instances, callbacks, or mutable model references. Validation proves only
that a key is declared with the expected kind. It cannot prove that a matching
Studio-authored instance exists, that a model has a valid pivot or attachment,
or that an asset has usable ownership and permissions. A later asset-binding
packet owns those live checks.

Successful validation produces:

```luau
type AssetManifest = {
    ordered: { AssetDefinition },
    byKey: { [AssetKey]: AssetDefinition },
}
```

The ordered and lookup views share canonical frozen records. Empty manifests are
valid so the repository can establish contracts before authored content exists.

## Tower definition

### Required fields

| Field | Contract |
| --- | --- |
| `id` | Unique canonical `Ids.TowerId` within the tower catalog |
| `displayName` | Bounded authored UTF-8 text; 1–80 code points |
| `modelAssetKey` | Declared `TowerModel` key |
| `placementCost` | Non-negative safe integer |
| `footprintRadiusStuds` | Finite number greater than zero |
| `placementCap` | Positive safe integer |
| `supportedTargetModes` | Dense, unique list of recognized target modes |
| `levels` | Non-empty dense list of at most 32 level definitions |

### Optional fields

| Field | Contract |
| --- | --- |
| `description` | Bounded authored UTF-8 text; 1–500 code points when present |
| `iconAssetKey` | Declared `Icon` key |
| `defaultTargetMode` | Required for an attacking tower; otherwise absent |
| `tags` | Non-empty unique symbolic-key list when present |
| `mergeProgression` | Unresolved `MergeProgression` feature reference |

Supported target modes are `First`, `Last`, `Strongest`, `Weakest`, and
`Closest`. An attacking tower must declare at least one mode and a default that
belongs to its supported list. A fully non-attacking tower must use an empty
supported list and omit the default.

### Levels and upgrade cost

A level has `upgradeCost`, `rangeStuds`, and an optional `attack` record.
`rangeStuds` is finite and non-negative. Level 1 represents the tower immediately
after placement, so its `upgradeCost` must be zero; `placementCost` buys that
level. For level `n > 1`, `levels[n].upgradeCost` is the cost to enter level `n`
from `n - 1`. Zero-cost later upgrades are intentionally representable.

Packet 04.4 additionally checks the cumulative placement cost plus every level's
upgrade cost. It rejects the first upgrade that would exceed the exact
safe-integer range. The computed total is not stored in the immutable
definition; match-owned `totalInvestment` remains runtime state.

The schema does not impose balance policy: range, damage, or other values may
decrease between levels. Attack presence may also change. A tower may gain,
lose, or regain an attack as it upgrades. The tower-wide supported/default mode
set is retained in the definition, while future controls must consider whether
the current level has an attack. This representation supports damage, support,
and economy-oriented towers without inventing fake combat numbers.

An attack record has:

| Field | Required | Contract |
| --- | --- | --- |
| `behavior` | Yes | Unresolved `AttackBehavior` reference |
| `damage` | Yes | Finite non-negative number; zero is representable |
| `cooldownSeconds` | Yes | Finite number greater than zero |
| `statusEffects` | No | Non-empty unique list of unresolved `StatusEffect` references |

No attack target, cooldown timestamp, placed-instance identity, current level,
owner, merge rank, or accumulated investment is content data.

## Enemy definition

### Required fields

| Field | Contract |
| --- | --- |
| `id` | Unique canonical `Ids.EnemyId` within the enemy catalog |
| `displayName` | Bounded authored UTF-8 text; 1–80 code points |
| `modelAssetKey` | Declared `EnemyModel` key |
| `maxHealth` | Finite number greater than zero |
| `moveSpeedStudsPerSecond` | Finite number greater than zero |
| `leakDamage` | Non-negative safe integer |
| `damageIncomeClass` | `EligibleHealthRemoved` or `None` |

### Optional fields

| Field | Contract |
| --- | --- |
| `description` | Bounded authored UTF-8 text; 1–500 code points when present |
| `iconAssetKey` | Declared `Icon` key |
| `tags` | Non-empty unique symbolic-key list when present |
| `resistanceProfile` | Unresolved `ResistanceProfile` reference |
| `behaviors` | Non-empty unique list of unresolved `EnemyBehavior` references |

Current health, path position, lane identity, world transform, spawn time,
active effects, runtime model, and cleanup ownership are explicitly excluded.
Packet 04.4 added only immutable damage-income eligibility. It never stores
credited damage or Battle Cash. `EligibleHealthRemoved` permits future income
from actual server-calculated health removed; `None` is the no-cash extension
point. Economy amounts and rules are recorded in
`docs/ECONOMY_BANNER_SETTINGS_SCHEMAS.md`, while Packet 04.3 owns wave-level
reward classes.

## Future feature references

The Packet 04.2 public types use distinct literal-kind records instead of one
broad assignable reference:

- `AttackBehaviorReference`
- `StatusEffectReference`
- `MergeProgressionReference`
- `ResistanceProfileReference`
- `EnemyBehaviorReference`

Packet 04.3 subsequently added `EndlessWaveGeneratorReference`; its grammar-only
extension seam and deferred registry behavior are documented in
`docs/MAP_DIFFICULTY_WAVE_SCHEMAS.md`.

Every reference has only `kind` and a symbolic `key`. Validation distinguishes
an unknown kind (`INVALID_ENUM`) from a recognized but contextually wrong kind
(`INVALID_REFERENCE`). Lists are dense, non-empty when present, and unique by
key.

These references validate grammar and family only. No registry, behavior
implementation, merge-rank calculation, status application, resistance
calculation, or enemy special behavior exists yet. A syntactically valid key is
not proof that later content exists.

## Canonical output and runtime-state exclusion

Validators do not freeze or retain caller-owned definition tables. They copy
accepted fields into new canonical records, then recursively freeze:

- asset records, ordered arrays, lookup maps, and manifests;
- tower/enemy definitions and catalog views;
- levels, attacks, tags, target modes, feature references, and reference lists;
- `Validation.Issue` records and their path-segment arrays; and
- enclosing `Result` envelopes through the Packet 04.1 Result contract.

Mutating raw authored input after validation cannot change canonical output.
Unknown fields are rejected, and named runtime fields produce the more specific
`RUNTIME_FIELD_FORBIDDEN` issue. Metatable-bearing objects and arrays are
rejected before field access. Validation uses `rawget`/`next` rather than
`__index`, `__pairs`, or `__tostring`, and rejected values are never copied into
messages.

## Text, numeric, and collection limits

Display fields must be valid UTF-8, fit both the byte and code-point bounds,
contain authored content, and have no leading/trailing recognized Unicode
whitespace. C0/C1 controls, line separators, bidi controls, zero-width spaces,
and selected unsafe format controls are rejected. Unicode 17.0 default-ignorable
code points are allowed where they participate in valid text, such as emoji ZWJ
sequences and variation selectors, but they do not count as content alone.
Selected Unicode layout-format ranges and common combining-mark ranges likewise
do not count as content alone.

This is an authored-configuration guard, not Unicode normalization, confusable
detection, moderation, filtering, or a general user-name security algorithm.
Roblox text filtering remains mandatory for future user-authored text.

Continuous statistics have no arbitrary balance maximum in this foundational
schema. They must be finite and meet their sign rule, so very large or very small
finite values remain representable. Later balance and simulation packets must
choose stable gameplay caps before using untrusted or production content.
Integer currency/damage fields use exact safe integers no greater than
`9,007,199,254,740,991` in magnitude.

Technical collection limits are:

| Collection | Maximum |
| --- | ---: |
| Definition object fields | 64 |
| Tower or enemy catalog entries | 1,000 |
| Asset entries | 2,000 |
| Tower levels | 32 |
| Tags or feature references | 32 |
| Target modes | 5 |

Object scans stop at field 65 and array scans at their limit plus one. This
bounds work for hostile oversized tables.

## Deterministic issue contract

An issue has a code, a rendered actionable path, frozen path segments, a static
message, and optional `causeCode`, `relatedPath`, or `actualType`. Example paths
include:

```text
Towers[2].id
Tower.levels[1].attack.statusEffects[2].key
Enemies[1].modelAssetKey
Assets[3].kind
```

When a table contains several structural problems, selection is deterministic:

1. exceeding the technical field/entry limit is a bounded terminal result;
2. within the limit, object keys use non-string, forbidden runtime, unsafe
   unknown, then lexically first unknown-field precedence;
3. within the limit, arrays use invalid-key, oversized-index, then sparse-shape
   precedence; and
4. valid dense arrays are processed in increasing numeric order, so the first
   invalid authored entry wins.

Duplicate IDs, asset keys, modes, tags, and feature references report both the
duplicate path and the first declaration through `relatedPath`. Invalid tower
or enemy IDs preserve the underlying Packet 04.1 ID error in `causeCode`.

## Focused Studio Edit-mode validation

The synchronized `ReplicatedStorage.Shared` tree was cloned into a temporary
`ServerStorage` harness so every run used fresh ModuleScript caches. No lasting
test fixture was added.

| Place | Primary validation | Supplemental hardening | Result |
| --- | ---: | ---: | --- |
| Lobby (`100561454756026`) | 390 assertions | 30 assertions | Pass |
| Match (`136401514513678`) | 94 parity assertions | 30 assertions | Pass |

The matrix covered:

- empty, minimal, full, mixed-attack, Unicode, and numeric-boundary definitions;
- all five feature-reference families and recognized-wrong versus unknown kinds;
- asset declaration, lookup, duplicate, kind, JSON round-trip, identity marker,
  forged manifest, and hostile metatable cases;
- canonical ID families, duplicate IDs, related paths, and same body text across
  tower and enemy families;
- required, optional, unknown, and explicitly forbidden runtime fields;
- finite/non-finite, integer/fractional, sign, zero, safe-integer, and technical
  collection boundaries;
- target-mode, level-order, tag, status-list, and feature-list cross-rules;
- bounded UTF-8, whitespace, invalid encoding, ZWJ emoji, combining text, and
  default-ignorable-only strings;
- sparse arrays, invalid keys, field-limit bounds, fixed first-error precedence,
  and exact actionable paths;
- deep freezing, failed caller mutation, privacy-safe static issues, and hostile
  `__index`, `__pairs`, and `__tostring` sentinels; and
- JSON encode/decode followed by revalidation of ordered canonical data.

Every cloned folder was destroyed. The authored `Assets`, `Towers`, and
`Enemies` modules remained empty. Neither place was saved.

## Phase 03 regression evidence

At Packet 04.2 completion, the pure modules were not required by a bootstrap and
therefore did not change startup. One isolated Play-Stop regression still
passed in each place: the correct Lobby/Match role reached lifecycle `Started`,
cleanup `Active`, lifecycle `Shutdown`, and cleanup `Cleaned`; structured
shutdown used the established 10-second budget; and no application warning or
error appeared. Both places were returned to Edit mode without saving.

## Formatting, lint, build, and structure verification

| Check | Result |
| --- | --- |
| Focused StyLua formatting | Pass |
| `stylua --check src` | Pass |
| `stylua --check --verify src` | Pass |
| `selene src` | Pass; 0 errors, 0 warnings, 0 parse errors |
| `rojo build default.project.json` | Pass |
| `rojo build lobby.project.json` | Pass |
| `rojo build match.project.json` | Pass |

At Packet 04.2 completion, each independent build contained 17 ModuleScripts,
one server Script, and one client LocalScript. The new shared modules appeared under
`ReplicatedStorage.Shared` in every build. Lobby contains no match source, Match
contains no lobby source, and Default retains the documented combined empty
role layers. Generated outputs remained ignored and were removed after
inspection. Current combined-state counts are recorded in
`docs/PHASE_04_EXIT_AUDIT.md`.

## Regression procedure

After changing these contracts:

1. Run `stylua src tests`, then `stylua --check --verify src tests`.
2. Run `selene validate-config`, then `selene src tests`.
3. Run `lune run tests/run.luau`. Confirm all 76 ordered cases pass, including
   Tower, Enemy, and Asset valid/invalid, boundary, hostile-input, exact-path,
   immutability, and cross-reference coverage.
4. Run `lune run tests/verify-builds.luau`. Confirm all four builds pass, the
   schema/type/catalog modules retain their exact production paths, Lobby/Match
   remain isolated, and no test code ships in Default, Lobby, or Match.
5. Use a temporary reviewed Studio harness only for an engine-parity case that
   the headless suite cannot represent; remove the exact harness afterward.
6. If bootstrap or engine-integration behavior changed, run isolated Play-Stop
   checks in each affected place and verify the established lifecycle and cleanup
   terminal states.
7. Leave both places in Edit mode. Remove exact generated builds and temporary
   harnesses only. Do not save or publish merely to test.

## Phase 12 authenticated TowerSchema consumption — 2026-08-28

Phase 12 consumes this unchanged Packet 04.2 schema; it does not add a field,
ID family, target taxonomy, behavior implementation, or production definition.
One fresh complete raw configuration supplies exactly three test/runtime-only
Tower definitions and their six `TowerModel`/`Icon` manifest entries. The real
`ConfigurationValidator` validates the whole root once in dependency order, and
TowerRuntime accepts only the exact canonical frozen root, manifest, catalog,
ordered records, by-ID records, definitions, and model-asset identities from
that transaction. Raw tables, copied/frozen lookalikes, separately validated
catalogs, mismatched manifests, and wrong ordered identities remain rejected.

The consumed fixtures prove the existing cross-rules without expanding them:

- `tower:phase12-single` and `tower:phase12-splash` have three levels, exact
  supported/default target modes, placement/upgrade costs, finite range/damage/
  cooldown metadata, positive authored footprints, per-owner placement caps,
  and inert attack/status/merge references;
- `tower:phase12-support` has three fully non-attacking levels, an empty target
  mode list, no default target mode, and inert support/economy tags; and
- runtime eligibility is the separate immutable value `AllEligibleEnemies`.
  It is not authored into TowerSchema and creates no air/water/tag filter.

The canonical `footprintRadiusStuds` remains the only runtime footprint
authority. Phase 12 never derives it from a Model, bounding box, part, client
visual, or Workspace state. `placementCost` seeds detached
`totalInvestment`; no wallet is created or mutated. Attack, splash, support,
economy, status, merge, range, damage, and cooldown values remain inert
metadata. Lasting production `Assets.luau` and `Towers.luau` remain
byte-identical empty, so normal production TowerRuntime is dormant.

Phase 05 subsequently added deterministic test-only fixtures and headless schema
coverage without populating lasting catalogs. Current commands and evidence are
in `docs/TEST_RUNNER.md`, and environment-specific status is in
`docs/TEST_MATRIX.md`. Packet 04.5 remains the original whole-catalog/bootstrap
gate documented in `docs/CONFIGURATION_VALIDATION.md`; the historical Phase 04
audit remains in `docs/PHASE_04_EXIT_AUDIT.md`.
