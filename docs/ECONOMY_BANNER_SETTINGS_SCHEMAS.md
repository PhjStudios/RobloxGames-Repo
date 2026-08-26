# Economy, Banner, and Settings Configuration Schemas

## Purpose

This document records the contracts, implementation decisions, limits, and
verification evidence for Packet 04.4 of `docs/DEVELOPMENT_PLAN.md`. The packet
defines immutable economy metadata, banner metadata, and default player
settings before any currency service, reward grant, profile, DataStore, gacha
roll, transaction, settings service, or settings UI exists.

No production starting Battle Cash, damage-income rate, wave stipend, Gold
reward, banner, chest cost, probability table, or pity threshold was authored.
All nonempty balance and banner data used for verification was synthetic,
temporary, and destroyed afterward.

## Packet status

- Packet: 04.4
- Status: Complete
- Recorded: 2026-08-26
- Shared types: `src/shared/types/ConfigTypes.luau`
- Common validation: `src/shared/util/Validation.luau` and
  `src/shared/config/SchemaPrimitives.luau`
- Economy source: `src/shared/config/Economy.luau` and
  `src/shared/config/EconomySchema.luau`
- Banner source: `src/shared/config/Banners.luau` and
  `src/shared/config/BannerSchema.luau`
- Settings source: `src/shared/config/DefaultSettings.luau` and
  `src/shared/config/SettingsSchema.luau`
- Supporting changes: `EnemyDefinition` requires an explicit damage-income
  class; `TowerSchema` checks cumulative investment and authenticates validated
  catalogs for banner references
- Source type mode: `--!strict`
- Gameplay, networking, persistence, UI, RNG, transactions, or services added:
  none
- Bootstrap integration added by Packet 04.4: none; Packet 04.5 now owns the
  centralized validation gate
- Studio-authored content changed: no
- External services enabled: no
- Place saved or published: no

## Validation dependency graph

Packet 04.4 extends the established canonical-validation graph:

```text
Assets -> AssetSchema.validateManifest
  -> TowerSchema.validateCatalog
       -> BannerSchema.validateCatalog
  -> DifficultySchema.validateCatalog
       -> EconomySchema.validateConfiguration

DefaultSettings -> SettingsSchema.validateDefaults
```

Every public validator returns a frozen
`Result.Result<CanonicalValue, Validation.Issue>`. Downstream validators accept
only canonical dependencies produced by the expected schema module in the same
ModuleScript VM. Private weak-key identity markers reject forged, copied,
deserialized, or differently cloned lookalikes before lookup-table access.

These markers prove that the local validator produced the value. They are not
authorization, origin attestation, or cryptographic signatures. Serialized
content and values crossing a ModuleScript graph must be validated again.

## Currency terminology and authority

The following meanings are invariant:

- **Gold** is persistent lobby currency used for persistent progression and
  future banner pulls.
- **Battle Cash** is individual, match-scoped placement and upgrade currency.
  It resets for every match.
- Gold never becomes match spending money.
- Battle Cash never converts into persistent Gold.
- Future clients may request actions, but only the server may calculate,
  mutate, spend, refund, grant, settle, or persist either currency.

Strict field allowlists reject conversion fields, current balances, owners,
claims, receipts, transactions, and other mutable state from immutable
configuration.

## Enemy damage-income class

Every enemy definition now requires `damageIncomeClass`:

| Value | Meaning |
| --- | --- |
| `EligibleHealthRemoved` | Actual server-calculated health removed may feed the future damage-income calculation |
| `None` | Damage to this enemy does not award Battle Cash |

The name deliberately says **health removed**. Overkill, an attack's requested
damage, a client-reported number, and shield damage are not implicitly eligible.
Shield eligibility would require a later explicit contract change. Runtime
credited damage, earnings, health, owners, and placed-tower state remain
forbidden in `EnemyDefinition`.

## Economy contract

### Authored root

`AuthoredEconomyConfiguration` contains:

| Field | Contract |
| --- | --- |
| `version` | Positive safe-integer economy content/configuration revision |
| `sellRefund` | Basis-point rate and one fixed rounding vocabulary |
| `difficultyRules` | Dense array with exactly one rule for every validated difficulty |

The canonical result replaces `difficultyRules` with frozen `ordered` and
`byDifficultyId` views. Both views reference the same canonical rule objects.
Rule order preserves authored order; missing reverse coverage is checked in
canonical difficulty order.

The lasting `Economy.luau` contains only approved structural policy:

- version `1`;
- `7,000` basis points, representing the provisional 70% refund;
- rounding mode `Floor`; and
- an empty difficulty-rule array while the lasting difficulty catalog is empty.

The schema accepts technically valid basis-point values from `0` through
`10,000` so a later approved balance review remains data-driven. Packet 04.4
separately verifies that the lasting authored value is exactly `7,000`.

### Difficulty economy rule

Each rule contains:

| Field | Contract |
| --- | --- |
| `difficultyId` | Valid, known, unique `Ids.DifficultyId` |
| `startingBattleCash` | Nonnegative safe integer |
| `damageIncome` | Reduced rational rate plus fixed rounding and accumulation semantics |
| `waveRewards` | Exact `standard`, `milestone`, and `final` metadata records |

The lowercase reward fields correspond to the `Standard`, `Milestone`, and
`Final` `WaveRewardClass` literals. Each record contains a nonnegative safe
integer `battleCashStipendPerActivePlayer` and nested persistent-Gold formula
input named `baseAmountPerEligiblePlayer`.

These are metadata, not grants. Phase 15 owns Battle Cash mutation and active
participant stipends. Phase 27 owns victory, loss, participation, first-clear,
receipt, claim, and final persistent-Gold formulas. Phase 32 owns bounded
Endless milestone settlement.

### Damage-income rational

`DamageIncomeConfiguration` contains:

- `battleCashNumerator`, integer `1..1,000,000`;
- `healthRemovedDenominator`, integer `1..1,000,000`;
- `rounding = "Floor"`; and
- `accrualScope = "PerPlayerMatch"`.

The numerator and denominator must be in lowest terms. This gives equivalent
rates one authored representation. The future intended interpretation is to
accumulate eligible health-removed fractions for each player across the match
and award the increase in the floor of that cumulative value. That avoids
per-hit rounding bias and attack-splitting exploits. The placed tower's owner
receives eligible damage income; no mutation is implemented here.

### Sell policy and safe arithmetic

The approved provisional interpretation is:

```text
floor((placement cost + every purchased upgrade cost) * 7,000 / 10,000)
```

`TowerSchema` now rejects the first upgrade whose cumulative
placement-plus-upgrade investment would exceed the exact safe-integer range.
It does not add `totalInvestment` to the immutable definition; that remains
runtime state.

A future sell implementation must use checked quotient/remainder arithmetic so
an intermediate multiplication cannot lose integer precision. Runtime wallet
addition, finite reward totals, and unbounded Endless accumulation must also use
checked arithmetic rather than clamping or silently losing precision.

### Economy version

`Economy.version` is a positive safe-integer content/configuration revision.
It is not a semantic-version string and is not an authentication token. A future
result receipt should preserve both the already computed amount and the economy
revision used for diagnostics; delayed claims must not recompute an old reward
using current configuration.

Unlike the settings reader version, a positive future economy revision is
structurally valid when it still uses this schema. Interpretation changes that
require a new reader must be introduced deliberately.

## Banner contract

### Definition fields

| Field | Required | Contract |
| --- | --- | --- |
| `id` | Yes | Catalog-unique canonical `Ids.BannerId` |
| `version` | Yes | Positive safe-integer content/pity revision |
| `displayName` | Yes | Bounded authored text; raw IDs are not presentation copy |
| `pullOptions.onePull.goldCost` | Yes | Positive safe-integer Gold cost for one logical outcome |
| `pullOptions.tenPull.goldCost` | Yes | Positive safe-integer Gold cost for ten logical outcomes in one future transaction |
| `outcomes` | Yes | Nonempty dense list of unique Tower references and percentages |
| `pityRule` | No | Minimal discriminated hard-pity guarantee when present |

One- and ten-pull quantities are fixed by their field names and cannot be
reconfigured accidentally. The schema does not require a ten-pull discount;
that relationship is a later balance decision. Costs are explicitly named
`goldCost`, so Battle Cash cannot be substituted by ambiguous configuration.

No banner artwork, rarity, availability window, region rule, enable switch,
soft pity, RNG seed, profile state, transaction, or rolled unit record exists in
this packet. Availability belongs to Phases 22 and 44.

### Outcomes and probability tolerance

Each outcome contains one valid Tower ID and `probabilityPercent`. Authored
percentage points are literal: `30` means 30%, not 0.30% and not a relative
weight.

The deterministic policy is:

- every probability must be finite;
- every probability is between `0.000000001` and `100`, inclusive;
- Tower IDs are unique within one banner;
- the same tower may appear in different banners;
- at most 1,000 outcomes may be authored in one banner;
- values are summed in dense authored order using compensated summation;
- the absolute total error from 100 must be at most `1e-9` percentage points;
- the boundary is inclusive;
- invalid totals return `INVALID_TOTAL` at the complete `outcomes` path; and
- validation never silently normalizes or rewrites authored probabilities.

The technical probability floor matches the total tolerance so authored entries
cannot be positive subnormal values that disappear when accumulated near 100.
Phase 22 must define one server-side interval/final-bin rule for the tiny
accepted discrepancy and use that same rule for actual rolls and displayed
odds.

### Pity rule

The optional current variant is:

```luau
{
    kind = "GuaranteedTower",
    hardPityPullCount = positive integer up to 1,000,000,
    guaranteedTowerId = known outcome TowerId,
}
```

The target must exist in the authentic Tower catalog and in the same banner's
outcomes. This proves the configured guarantee is possible. Counter
initialization, increment, reset, natural-hit behavior, ten-pull ordering,
carry-over, and version migration remain Phase 22 work.

### Banner version

Banner version is a per-banner content/pity revision, not the settings schema
reader version. Future persistent pity state should identify both `BannerId`
and banner `version`. Changing outcome probabilities, pity meaning, or pull
terms should increment the banner version. Packet 04.4 does not decide whether
pity resets, carries, or migrates across that change.

Banner configuration is client-readable metadata for future odds presentation,
but only the server's validated configuration may drive future outcomes. This
schema never rolls, seeds, normalizes, deducts Gold, changes pity, creates units,
or trusts a client-provided cost, version, probability, or result.

## Default player settings contract

`DefaultSettings.luau` contains a flat, frozen, device-independent default
record:

| Field | Default | Accepted range or type |
| --- | ---: | --- |
| `version` | `1` | Exactly supported reader version `1` |
| `masterVolume` | `1` | Finite `0..1` multiplier |
| `musicVolume` | `1` | Finite `0..1` multiplier |
| `sfxVolume` | `1` | Finite `0..1` multiplier |
| `uiVolume` | `1` | Finite `0..1` multiplier |
| `cameraShakeIntensity` | `1` | Finite `0..1` multiplier |
| `damageNumbersEnabled` | `true` | Boolean |
| `enemyHealthBarsEnabled` | `true` | Boolean |
| `otherPlayerEffectsEnabled` | `true` | Boolean |
| `lowDetailEnabled` | `false` | Boolean |
| `towerRangeEnabled` | `true` | Boolean |
| `uiScale` | `1` | Finite `0.75..1.25` multiplier |

Every field is required and unknown fields are rejected. Numeric and Boolean
lookalikes are not coerced. Well-formed version values other than `1` return
`UNSUPPORTED_VERSION`; Phase 19 must migrate older serialized settings before
the current reader validates them.

### Accessibility and device composition

Roblox exposes preferred text size, preferred transparency, and reduced motion
as read-only, non-replicated `GuiService` properties. They may change while a
player is running the game. They are dynamic client inputs, not saved game
settings, so `preferredTextSize`, `preferredTransparency`,
`reducedMotionEnabled`, current input mode, device class, screen dimensions,
safe area, and Roblox `EnumItem` values are rejected from this serialized
record.

Phase 20 must compose these inputs as follows:

- game `uiScale` supplements and must not cancel the player's preferred text
  size;
- preferred transparency remains honored;
- reduced motion overrides effective shake and positional UI motion even when
  the saved shake intensity is nonzero;
- important sounds receive visual equivalents;
- `enemyHealthBarsEnabled` may hide ordinary bars, but boss health remains
  mandatory;
- `towerRangeEnabled` may hide selected-tower inspection overlays, but not the
  placement preview's required range feedback; and
- low detail and effect suppression remove cosmetic work only, never
  authoritative or gameplay-critical cues.

References: [Roblox GuiService API](https://create.roblox.com/docs/reference/engine/classes/GuiService)
and [PreferredTextSize enum](https://create.roblox.com/docs/reference/engine/enums/PreferredTextSize).

## Validation, errors, and canonical values

All three schemas:

- accept only plain tables without metatables;
- use dense one-based arrays with technical entry limits;
- reject non-string object keys and excessive field counts;
- check recognized mutable runtime fields before ordinary unknown fields;
- sort unknown field names before reporting the first one;
- validate authored arrays in index order;
- validate dependencies before lookup;
- use static privacy-safe messages that never interpolate rejected values or
  arbitrary tables;
- return stable codes, paths, optional causes, and duplicate `relatedPath`
  values;
- reconstruct every accepted nested table instead of retaining caller-owned
  input;
- deeply freeze canonical nested records, arrays, indexes, and Result envelopes;
  and
- mark only successful canonical roots with VM-local weak identity sets.

`SchemaPrimitives.requiredNumber` canonicalizes accepted negative zero to
ordinary zero. Currency values are nonnegative safe integers. Display text,
IDs, references, and numeric fields retain the earlier Phase 04 grammar and
error precedence.

Representative paths include:

```text
Enemies[1].damageIncomeClass
Towers[1].levels[3].upgradeCost
Economy.difficultyRules[1].damageIncome.healthRemovedDenominator
Economy.difficultyRules[1].waveRewards.final.persistentGold.baseAmountPerEligiblePlayer
Banners[2].outcomes[3].towerId
Banners[2].pityRule.guaranteedTowerId
DefaultSettings.cameraShakeIntensity
```

## Focused Studio validation

Both synchronized places used fresh temporary clones of
`ReplicatedStorage.Shared` so every harness had one internally consistent set of
ModuleScript identity markers. All clones, temporary strict consumers, and
Instances were destroyed afterward. No place was saved.

| Place | Validation evidence | Result |
| --- | --- | --- |
| Lobby (`100561454756026`) | 157 Economy/Enemy/Tower assertions; 191 Banner assertions; 363 Settings assertions; 6 exact probability-boundary assertions; strict-consumer execution; empty/policy smoke | Pass |
| Match (`136401514513678`) | 42 focused parity assertions; empty/policy smoke | Pass |

The matrix covered:

- authentic versus forged and cross-ModuleScript dependency catalogs;
- empty lasting catalogs and the policy-only lasting economy/default settings;
- exact difficulty economy coverage, duplicates, wrong-family IDs, missing
  references, and deterministic reverse coverage;
- individual safe-integer currency boundaries, non-finite values, fractions,
  strings, rational reduction, denominator zero, basis-point limits, and
  cumulative tower-investment overflow;
- both enemy damage-income classes plus missing, mistyped, and unknown values;
- exact, within-tolerance, inclusive-boundary, above-tolerance, and
  below-tolerance banner totals;
- maximum 1,000 outcomes and 1,000 banners followed by first-excess failures;
- duplicate outcomes, unresolved Towers, optional/invalid pity, one and maximum
  pity thresholds, one/ten Gold costs, and per-banner versions;
- every settings numeric boundary, Boolean literal and impostor, missing field,
  malformed/current/future version, device/accessibility snapshot field, and
  exact `UNSUPPORTED_VERSION` path;
- sparse arrays, non-string keys, field caps, hostile metatables with unexecuted
  metamethod sentinels, lexical first-error selection, and recognized runtime
  fields;
- ten-run deterministic complete issue records and absence of secret sentinel
  values from errors;
- deep freezing, failed canonical mutation, lookup identity, raw-input
  detachment, JSON encode/decode/revalidation, and authenticity loss after
  serialization; and
- a temporary `--!strict` consumer covering every new public type family,
  Result narrowing, optional pity narrowing, literal fields, lookup views, and
  authenticity APIs.

Three independent read-only adversarial reviews separately audited economy,
banner, and settings contracts. All passed without a blocking or actionable
source finding.

## Phase 03 regression evidence

One isolated Play/Stop regression passed in each place. Lobby resolved role
`Lobby` at PlaceId `100561454756026`; Match resolved role `Match` at PlaceId
`136401514513678`.

Each server and client emitted exactly one ready record with lifecycle
`Started`, cleanup `Active`, one cleanup task, and zero services. Each server
then emitted one shutdown `started` record with the established ten-second
budget and one `completed` record with cleanup `Cleaned` and lifecycle
`Shutdown`. No Ant Tower Defense warning, failure, timeout, duplicate bootstrap,
or hang appeared. Both sessions returned to Edit mode without saving.

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
| Three independent schema audits | Pass; no remaining Packet 04.4 source finding |

Each build contained 29 ModuleScripts, one server Script, and one client
LocalScript. Twenty-eight modules are shared; server-only `Shutdown` is the
twenty-ninth. All six new Packet 04.4 modules appeared under
`ReplicatedStorage.Shared.config`.

Default retained both empty role layers, Lobby had no Match layer, and Match had
no Lobby layer. No role-specific executable was introduced. Exact ignored audit
builds were removed after inspection; the pre-existing ignored
`sourcemap.json` was not touched.

## Regression procedure

1. Format changed Luau, run both whole-source StyLua checks, and run Selene.
2. Build Default, Lobby, and Match independently into exact ignored outputs.
3. Recheck the current 30/1/1 instance counts, all six Packet 04.4 modules, and
   role isolation, then remove only those outputs.
4. In each correctly connected Studio place, clone `ReplicatedStorage.Shared`
   into a temporary Edit-mode harness so all dependencies share fresh identity
   markers.
5. Validate Assets, Towers, Enemies, Difficulties, Economy, Banners, and default
   settings in dependency order.
6. Rerun lasting-empty, lasting-policy, valid, invalid, tolerance, boundary,
   hostile, privacy, immutability, serialization, and strict-consumer cases.
7. Destroy every temporary clone and confirm lasting balance/content catalogs
   remain empty.
8. Run an isolated Play/Stop cycle in Lobby and Match and verify the established
   role, startup, cleanup, and shutdown records.
9. Leave both places in Edit mode. Do not save or publish merely to test.

A persistent test runner, test project, CI workflow, and
`docs/TEST_MATRIX.md` remain Phase 05 work. Packet 04.5 owns the completed
deterministic whole-catalog report and minimum shared bootstrap gate documented
in `docs/CONFIGURATION_VALIDATION.md`; Phase 04 passed its fresh exit audit in
`docs/PHASE_04_EXIT_AUDIT.md`. Packet 05.1 is next and has not begun.
