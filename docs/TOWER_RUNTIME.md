# Phase 12 Tower Runtime and Temporary Loadout Contract

## Decision status and scope

This document is the authoritative decision, implemented contract, and Studio
evidence record for Phase 12, Packets 12.1–12.4. It defines authenticated
synthetic tower content, one match-scoped server runtime, the temporary
development loadout, and the exact version-1 tower-model contract. The focused
architecture, authority, lifecycle, and asset-contract review completed before
executable work; its material corrections are incorporated here. Executable
source, focused coverage, consolidated independent review, the exact unsaved
Match Studio gate, the `840`-case/`64`-suite complete local gate, and all four
structural builds pass. Phase 12 is complete; exact-final-SHA CI is recorded at
handoff, and Phase 13 is next but remains entirely unbegun.

Phase 12 creates trusted server contracts and inert presentation only. It does
not implement placement queries, previews, rotation input, collision or zone
validation, placement requests, Battle Cash, targeting, attack scheduling,
damage, splash execution, support auras, status execution, income, cooldown
advancement, upgrades, selling, target-mode transactions, hotbars, HUD, saved
inventory, or production tower content.

The boundaries are exact:

- Phase 13 owns every placement query, preview, input, rotation, overlap,
  map-zone, affordability, request, and placement-race behavior.
- Phase 14 owns target acquisition, attacks, damage, splash, status/support
  execution, and cooldown advancement.
- Phase 15 owns Battle Cash mutation, upgrades, selling, and target-mode
  transactions.
- Phase 21 owns the persistent five-equipped-tower loadout. The Phase 12
  partially occupied loadout is a temporary development exception only.
- Phase 30 owns real tower content, uploaded models, animation IDs, effects,
  sounds, and production balance.

Production `Assets.luau` and `Towers.luau` remain byte-identical frozen empty
arrays. The production Match service therefore starts and shuts down cleanly in
a dormant state. No tower client source, remote definition, rate policy, or
second network root is added. The production registry remains exactly ten
reliable Match-only endpoints and six inbound rate policies.

## Engine facts used by the decision

Only official Roblox primary documentation informed the engine-facing parts of
this contract:

- [`Model.PrimaryPart`](https://create.roblox.com/docs/reference/engine/classes/Model.md)
  is a descendant `BasePart` that anchors the model pivot. Phase 12 requires it
  even though graybox parts are anchored so the contract remains deterministic.
- [`PVInstance:GetPivot()` and `PivotTo()`](https://create.roblox.com/docs/reference/engine/classes/PVInstance.md)
  are the current APIs for reading and moving a Model pivot. `PivotTo()` moves
  the descendant PVInstances and does not perform placement collision policy.
- [`Instance:Clone()`](https://create.roblox.com/docs/reference/engine/classes/Instance.md)
  creates an initially unparented descendant copy and respects `Archivable`.
  [`Instance:Destroy()`](https://create.roblox.com/docs/reference/engine/classes/Instance.md)
  unparents recursively and disconnects owned connections.
- [`Attachment`](https://create.roblox.com/docs/reference/engine/classes/Attachment.md)
  provides a position and orientation relative to an ancestral PVInstance and
  is the inert aim/muzzle marker primitive.
- [`AnimationController`](https://create.roblox.com/docs/reference/engine/classes/AnimationController.md)
  plus a child [`Animator`](https://create.roblox.com/docs/reference/engine/classes/Animator.md)
  is the non-Humanoid animation seam. Phase 12 never loads an Animation or
  creates an AnimationTrack.
- [`BasePart.CanCollide`, `CanTouch`, and `CanQuery`](https://create.roblox.com/docs/reference/engine/classes/BasePart.md)
  separately control physical collision, touch events, and spatial-query
  participation. Every Phase 12 tower part is inert for all three.
- [`Players.PlayerRemoving`](https://create.roblox.com/docs/reference/engine/classes/Players.md)
  fires before the Player leaves. MatchLifecycle remains the sole authority
  that turns that connection event into a participant state; TowerRuntime sees
  only detached participant snapshots and never retains a Player.

These facts do not make Lune an engine-behavior test. Clone, pivot, parenting,
replication, client visibility, and destruction claims require the exact Match
Studio gate.

## Canonical synthetic definitions

Every Phase 12 fixture begins as one fresh, complete, mutable
`AuthoredConfigurationSources` root. The consumer calls only the complete real
`ConfigurationValidator.validate` transaction. That transaction internally
runs the production validators in dependency order and returns one root:

```text
ConfigurationValidator.validate
  -> Assets -> AssetSchema.validateManifest
  -> Towers -> TowerSchema.validateCatalog
  -> the remaining complete source families
  -> one frozen authenticated CoreConfiguration
```

Focused schema evidence may call `AssetSchema` or `TowerSchema` separately, but
those results are discarded. A separately validated manifest or catalog is
never fed into, composed with, or retained beside the complete transaction.

The fixture consumer requires all of the following identities, not merely equal
values:

- `ConfigurationValidator.isValidatedConfiguration(configuration)`;
- `AssetSchema.isValidatedManifest(configuration.assets)`;
- `TowerSchema.isValidatedCatalog(configuration.towers)`;
- `configuration.assets.byKey[definition.modelAssetKey]` is the exact canonical
  `TowerModel` declaration retained by the same root;
- `configuration.towers.byId[definition.id] == definition`; and
- every selected definition is also the exact object at its stable ordered
  catalog index.

Raw definitions, detached copies, serialized values, frozen lookalikes,
separately validated roots, mismatched manifests/catalogs, and definitions from
another ModuleScript VM cannot initialize a loadout, RuntimeTower, or template.
The weak-key schema markers authenticate validator identity inside one VM; they
are not cryptographic signatures or provenance claims.

Exactly three test/runtime-only TowerDefinitions exist in stable order:

1. `tower:phase12-single` — attacking single-target fixture, multiple levels,
   one muzzle per attacking level, and a single-target behavior reference.
2. `tower:phase12-splash` — attacking splash-capable fixture, multiple levels,
   two muzzles per attacking level, and a splash behavior reference that stays
   symbolic and inert.
3. `tower:phase12-support` — fully non-attacking support/economy placeholder,
   multiple levels, empty target-mode list, no default target mode, no aim or
   muzzle markers, and inert support/economy metadata represented only through
   already supported tags.

The fixtures deliberately cover zero and nonzero later upgrade costs, distinct
placement costs, ranges, cooldowns, damage metadata, footprints, placement
caps, supported/default target modes, icons, tags, attack-local status
references, and merge references. Every cumulative investment remains a safe
integer. The attacking fixtures use exact supported/default modes from the
current TowerSchema. The
support fixture has no attack at any level. Every runtime record uses the
Phase 12 constant `AllEligibleEnemies`; this runtime value does not expand the
authored target schema.

Attack behavior, splash, support, economy, status, merge, damage, range, and
cooldown values remain immutable metadata. Nothing interprets or executes them.

## Identity domains

The three tower identities are deliberately non-interchangeable:

| Identity | Representation | Meaning |
| --- | --- | --- |
| `TowerId` | existing canonical `tower:*` string | immutable content definition |
| temporary `UnitId` | existing canonical `unit:*` string | one occupied temporary loadout slot; no saved UnitRecord |
| `RuntimeTowerId` | positive safe integer | one accepted runtime allocation in one `(MatchId, towerEpoch)` |

`RuntimeTowerId` is not added to `Ids.luau` because it is a bounded numeric
runtime identity, like `RuntimeEnemyId`, rather than a public string-ID family.
It never aliases an Instance identity, transaction ID, Enemy ID, TowerId, or
UnitId.

One non-restartable TowerRuntime is bound before mutation to the exact current
validated `MatchId` and a positive monotonic `towerEpoch`. Phase 12 uses epoch
`1`; constructors and tests enforce the reviewed upper bound `4,096`. Runtime
IDs begin at `1`, increase monotonically for each accepted allocation, never
roll over, and are never reused after removal.

## Temporary development loadout

The loadout store is match-local and keyed only by `(MatchId, UserId)`. It never
retains a Player, persistent UnitRecord, profile, inventory, trait, skin,
favorite, lock, or merge state.

Every detached snapshot is deeply frozen and has exactly:

```luau
{
    matchId: MatchId,
    userId: number,
    revision: positive safe integer,
    slots: {
        { kind: "Occupied", slot: 1, towerId: TowerId, unitId: UnitId },
        { kind: "Occupied", slot: 2, towerId: TowerId, unitId: UnitId },
        { kind: "Occupied", slot: 3, towerId: TowerId, unitId: UnitId },
        { kind: "Empty", slot: 4 },
        { kind: "Empty", slot: 5 },
    },
}
```

No alternate field is allowed. The array is dense, stable, and exactly five
records. Empty records have no `towerId` or `unitId`. Occupied TowerIds are the
three unique canonical fixtures in catalog order. A user receives one loadout
only when a trusted detached MatchLifecycle snapshot first reports that UserId
as `Active` in this MatchId. Spectators and unknown users receive none.
Disconnect, return, or later spectator state does not replace an already issued
match-local loadout; reconnect during its allowed lifecycle returns the same
slot and UnitId values. A different MatchId creates a different store and makes
every old snapshot/capability inert.

Production `Dormant` and Studio `AwaitingFixture` startup install no participant
boundary. When the one authenticated Studio/test configuration activates
TowerRuntime, it uses one
synchronous MatchLifecycle registration operation that both reserves the sole
observer and returns the current detached snapshot with its revision. There is
no separate `getSnapshot` followed by subscribe gap. Tower prepares the initial
loadouts from that exact snapshot, then the no-fail commit enables the observer.
MatchLifecycle invokes it thereafter only after its own roster mutation and
passes its freshly composed detached snapshot. The callback count is one while
configured, does not vary by player, is removed before MatchLifecycle cleanup,
and cannot change roster truth. A throw, yield, malformed snapshot, wrong
MatchId, backwards revision, or re-entry faults TowerRuntime closed;
MatchLifecycle keeps its already committed roster truth. Tests cover activation
after service start, a mutation at the registration boundary, and captured late
callbacks.

Temporary UnitIds are deterministic server outputs using the existing grammar:

```text
unit:p12-e<towerEpoch>-p<positiveUserId>-s<slot>
unit:p12-e<towerEpoch>-n<absoluteNegativeStudioUserId>-s<slot>
```

The service validates the completed string through `Ids.validateUnitId`, checks
the nonzero safe-integer UserId and every arithmetic/string bound, and rejects a
collision rather than retrying indefinitely. UnitIds need only be unique within
the bound Match service lifetime. At most four admitted users and three
occupied slots create at most twelve temporary UnitIds.

Loadout revisions are positive safe integers allocated monotonically by this
store when a new user loadout commits. They do not change on disconnect/return.
Revision, UnitId, or store capacity exhaustion faults closed; no value clamps.

## Opaque creation capability

The only creation authorization is an opaque frozen table authenticated by a
private weak-key registry inside the loadout module. No capability is serialized,
replicated, logged, accepted from a client, or reconstructed from its fields.

One capability binds all of:

- owning loadout-store identity;
- exact `MatchId` and `towerEpoch`;
- exact UserId and loadout revision;
- occupied slot index;
- exact temporary UnitId and canonical TowerId;
- exact canonical TowerDefinition identity; and
- one unconsumed capability generation.

Only the narrow occupied-slot resolver can issue it. Empty, unknown,
spectator-only, removed, wrong-user, wrong-match, duplicate, or malformed slots
cannot. Preparation atomically changes an authentic capability from `Issued`
to `Reserved` and returns a second opaque weak-key-authenticated prepare token;
the original capability is unavailable from that point. Commit or abort makes
both objects permanently `Consumed`. Replay, copy, lookalike, cross-user,
wrong-slot, wrong-match, wrong-epoch, wrong-definition,
removed-loadout, fault, and post-clean attempts fail. An authentic capability
is revoked after any trusted create attempt that reaches template/runtime
preparation, including a later model failure, so retry requires a fresh
server-issued capability.

The resolver and trusted create seam are server-only ModuleScript methods used
by deterministic tests and the fixed Studio evidence trigger. No RemoteEvent,
RemoteFunction, UnreliableRemoteEvent, bindable exposed to clients, or generic
message bus accepts a tower operation.

## RuntimeTower record and store

The authoritative mutable store retains records with exactly these fields:

```luau
{
    matchId: MatchId,
    towerEpoch: positive safe integer,
    runtimeTowerId: positive safe integer,
    ownerUserId: nonzero safe integer,
    towerId: TowerId,
    unitId: UnitId,
    level: 1,
    targetMode: TargetMode?,
    targetEligibility: "AllEligibleEnemies",
    placementCFrame: CFrame,
    totalInvestment: nonnegative safe integer,
    cooldownEndsServerTime: 0,
    lifecycle: "Active",
}
```

`cooldownEndsServerTime == 0` is the documented available sentinel. Phase 14
may replace it only through its explicit cooldown state-machine decision.
Attacking level 1 copies the exact canonical `defaultTargetMode`;
non-attacking level 1 uses `nil`. `totalInvestment` copies only canonical
`placementCost`; there is no wallet or spend. `placementCFrame` is one detached
server-chosen CFrame whose twelve components are finite and whose position is
within the technical coordinate bound of `100,000` studs. The store never asks
whether that transform is on a map, inside a zone, affordable, non-overlapping,
or chosen by a client.

Phase 12 exposes only detached frozen snapshots, bounded metrics, trusted create,
trusted remove, visual remove/recreate, lifecycle methods, and cleanup. No
operation changes level, owner, TowerId, UnitId, transform, target mode,
investment, cooldown, or eligibility after creation.

Removing an Active record returns one detached frozen `Removed` tombstone,
deletes the active record, and releases its owner/TowerId active-cap count once.
It does not decrement lifetime allocation, reuse an ID, mutate the loadout, or
grant currency. Repeated removal is rejected and cannot release the cap twice.

The store retains no Player, Model, BasePart, Attachment, Animator, UI object,
client object, mutable definition, Workspace reference, task, timer, or
connection. Canonical definitions are retained only through the one exact
authenticated root and immutable identity references.

## Capacity, arithmetic, and fault closure

Phase 12 chooses technical bounds, not balance promises:

- service-wide active RuntimeTowers: `128`;
- service-wide lifetime accepted allocations: `4,096`;
- tower epoch: `1..4,096`;
- active participants/loadouts: `4`;
- occupied slots per loadout: `3` of exactly `5`;
- coordinate absolute value: `100,000` studs; and
- canonical TowerSchema bounds remain authoritative for definitions/levels.

The active bound matches the already reviewed EnemySimulation active bound,
keeps the Phase 12 Studio stress ladder comparable, and is comfortably above
the twelve records needed to exercise every occupied slot for four admitted
participants. It is a technical containment limit, not a content promise.

Before mutation, creation checks the active and lifetime limits, next ID,
owner/TowerId `placementCap`, owner and integer domains, canonical placement
cost, CFrame finiteness, capability identity, definition identity, and every
counter increment. It fails rather than clamping, wrapping, retrying an ID, or
accepting a partial result. `placementCap` counts only current Active records for
one owner and one TowerId. Different owners and TowerIds are isolated.

One synchronous operation guard covers prepare/commit/remove/recreate/cleanup.
Re-entry, a thrown or yielding dependency, impossible callback result, ID or
counter collision, safe-integer exhaustion, template/clone/pivot/parent failure,
or a post-commit invariant failure closes mutation and marks the coordinator
`Faulted`. After fault, record/loadout queries and every mutation are rejected;
only the bounded aggregate `getMetrics` result remains available for cleanup
evidence. Cleanup is always accepted and idempotent.

## Version 1 tower-model hierarchy

The exact contract version is positive integer `1`. A template root is an
unparented, Archivable `Model` named `Tower` with `PrimaryPart` equal to its
direct child `Part` named `Root`. It has exactly these direct children:

```text
Tower (Model; PrimaryPart = Root; ATDTowerModelContractVersion = 1)
├── Root (Part; invisible pivot)
├── Animation (Folder)
│   ├── Controller (AnimationController)
│   │   └── Animator (Animator)
│   └── Hooks (Folder)
│       ├── Idle (StringValue = "hook.idle")
│       ├── Upgrade (StringValue = "hook.upgrade")
│       └── Attack (StringValue = "hook.attack") [iff any level attacks]
└── UpgradeVariants (Folder)
    ├── Level01 (Model; PrimaryPart = Body)
    │   └── Body (Part)
    │       ├── Aim (Folder)
    │       │   └── AimPivot (Attachment) [iff this level attacks]
    │       └── Muzzles (Folder)
    │           └── Muzzle01..Muzzle04 (Attachment) [1..4 iff attacking]
    └── LevelNN ... one exact variant per canonical level
```

There are no optional or unexpected descendants. Variant names use two digits
for levels `1..32`. Each variant maps by index to exactly one canonical level.
An attacking level has exactly one `AimPivot` and between one and four densely
numbered muzzles. A non-attacking level has empty `Aim` and `Muzzles` folders.
The Attack hook exists exactly when at least one canonical level attacks. The
controller, Animator, and symbolic StringValues are inert hooks; there are no
Animation objects, asset/content IDs, tracks, or playback.

Hard bounds are:

| Item | Maximum |
| --- | ---: |
| descendants below `Tower` | 297 |
| BaseParts including `Root` | 33 |
| upgrade variants | 32 |
| Attachments total | 160 |
| muzzles per attacking variant | 4 |
| animation hook StringValues | 3 |

The descendant bound is derived from the exact worst case rather than guessed:
one Root, seven Animation descendants with all three hooks, one
`UpgradeVariants` Folder, and 32 attacking variant subtrees of nine descendants
each totals `297`. The attachment total permits one aim plus four muzzles for
each of 32 levels. The exact hierarchy constrains the real total more tightly
for any given definition.

Every Part is `Anchored = true`, `Massless = true`, `CastShadow = false`,
`CanCollide = false`, `CanTouch = false`, and `CanQuery = false`. Root has
`Transparency = 1`; every template variant Body has `Transparency = 0`. A live
clone sets the selected level's Body to `0` and every other Body to `1`, then
rechecks that exact selection. Size components are finite, positive, and no
greater than `64`; all part and attachment transforms are finite and within the
coordinate bound. The template pivot is identity. The validator never calls
`GetBoundingBox` or `GetExtentsSize` and never compares visual dimensions to
placement rules.

The root's sole allowed attribute is numeric
`ATDTowerModelContractVersion = 1`. Descendants have no attributes. The root
and every descendant have zero CollectionService tags. Unknown attributes or
tags are rejected; neither is copied into runtime metadata.

Only the exact classes shown above are allowed. Scripts, LocalScripts,
ModuleScripts, remotes, bindables, Constraints, joints, Welds, Motor6Ds,
Humanoids, prompts, detectors, TouchTransmitters, effects, sounds, UI, Values
other than the three exact StringValues, and every other unexpected descendant
are rejected. A later art phase must introduce a reviewed contract version
before MeshParts, bones, Motor6Ds, animations, effects, or other primitives can
be admitted.

The canonical `TowerDefinition.footprintRadiusStuds` is the only footprint
authority. Model bounds, Root/Body sizes, attachments, Workspace state,
replicated visuals, and client caches never produce or modify a footprint.

## Template ownership, cloning, pivot, and tampering

Template registration requires the exact canonical definition and its exact
`TowerModel` manifest key. The validator checks a fresh caller-owned template,
then the model owner clones it while unparented and validates that private clone
again. The owner retains only the private clone. Later caller mutation,
reparenting, or destruction cannot alter the registered template.

Creation is one non-yielding prepare/commit transaction:

1. atomically reserve the current loadout capability and obtain its opaque
   prepare token;
2. preflight every store counter, RuntimeTowerId, cap, field, and CFrame;
3. clone the owner-held template while unparented, revalidate its exact
   hierarchy, select the level-1 variant deterministically, make only that
   variant visible, and `PivotTo` the planned runtime CFrame;
4. inspect Workspace for a foreign same-named root, create and authenticate a
   private root while unparented if none is already owned, then parent the root
   and prepared Model and verify their exact identities and final pivot;
5. commit the capability token, RuntimeTower record, counters, and owner index
   through pre-reserved no-fail tokens whose remaining work is table assignment;
   and
6. publish no network message and invoke no gameplay callback.

A failure through step 4 immediately best-effort unparents and destroys the
prepared clone and any newly created empty root, drops all references, then
aborts the prepare tokens. It mutates no authoritative record or counter state
and permanently revokes the authentic capability. Prepared-clone count is zero
whenever the guarded operation is not active. Step 5 has no caller callback,
allocation, lookup, validation, yield, or engine operation remaining. An
impossible failure there destroys the exact prepared/parented Model, faults the
coordinator, and leaves no queryable accepted record. Cleanup removes any
intermediate prepared clone or privately owned empty root.

The model owner creates at most one Folder named `ATDTowerRuntime` under
Workspace and marks it only in a private weak-key ownership registry. Only that
exact privately owned root may be reused. A pre-existing same-named Workspace
Folder or Model is foreign and causes failure without adoption, mutation, or
destruction. The owner indexes its live Models by RuntimeTowerId. Runtime records
never reference that folder or any Model. A visual removal or external tamper
does not remove or mutate authoritative state. There is no per-model listener;
explicit `removeVisual` and `recreateVisual` operations inspect the owner index.
Recreation re-clones the private template and uses only the detached
authoritative RuntimeTower snapshot. It cannot change level, transform,
identity, investment, cap accounting, or cooldown. Foreign same-named roots or
models fail closed rather than being adopted or destroyed.

Trusted RuntimeTower removal first closes that record to further visual work,
removes the owned visual idempotently, then releases the active record/cap once.
If visual destruction throws, authoritative removal still completes and the
owner faults for cleanup; no visual ever vetoes or recreates server truth. The
owner immediately attempts one bounded unparent fallback and cleanup retries
Destroy/unparent only for the exact privately owned Instance. A persistent
failure is surfaced as lifecycle cleanup failure. Zero residue is claimed only
after the owned Instance is actually absent.

## Service graph and constant ownership

The server graph becomes:

```text
NetworkRegistry -> MatchLifecycle -> BaseRuntime -> EnemySimulation -> WaveRuntime -> TowerRuntime
```

TowerRuntime depends on the exact Match identity and participant boundary from
MatchLifecycle and starts after WaveRuntime so shutdown closes all tower
capabilities, records, templates, and Models before Wave/Enemy/Base/Match/map
truth is released. It does not read or mutate Wave gameplay/runtime truth; the
Wave dependency is limited to lifecycle ordering and the single Studio fixture
boundary described below.
Reverse shutdown is:

```text
TowerRuntime -> WaveRuntime -> EnemySimulation -> BaseRuntime -> MatchLifecycle/MapLoader -> NetworkRegistry
```

Its exact `ServiceDefinition.dependencies` array is
`{ "NetworkRegistry", "MatchLifecycle", "WaveRuntime" }`. The Wave dependency
is intentionally lifetime/order-only; Tower does not read or mutate Wave state.
Match bootstrap registers TowerRuntime immediately after WaveRuntime.

The ownership states are explicit. Non-Studio production `Dormant` owns zero
MatchLifecycle observers, zero Wave boundaries, and zero runtime state. Studio
`AwaitingFixture` still has the production-empty catalog and owns exactly one
opaque boundary registered with WaveRuntime's existing fixed fixture trigger,
but zero MatchLifecycle observers, loadouts, templates, runtime roots, or tower
records. `Configured` retains that same one Wave boundary and owns one constant
MatchLifecycle participant observer plus its authenticated Tower state. A
failed, consumed, or cleaned installation is permanently closed and revokes
both handles in Tower-before-Wave order. TowerRuntime owns no BindableFunction,
loop, Heartbeat, RenderStepped, timer, delayed task, per-user callback,
per-tower connection,
per-level connection, per-model connection, or per-slot connection. The model
owner owns zero connections. Production-empty dormancy owns no runtime root,
template, loadout, capability, model, or participant callback.

## Studio-only fixture and evidence boundary

Phase 12 does not create a second trigger or validate a second runtime
configuration. In Studio only, TowerRuntime registers one narrow opaque
boundary with the existing WaveRuntime-owned server BindableFunction
`_ATDPhase11WaveEvidence`. TowerRuntime depends on WaveRuntime; Wave retains
only that one bounded callback/handle, and TowerRuntime revokes it before Wave
shutdown. Outside Studio, no boundary is registered. The BindableFunction
remains under ServerStorage, cannot be reached by clients, accepts only a closed
set of fixed operation tokens, and never accepts a TowerId, UnitId,
RuntimeTowerId, CFrame, UserId, owner, level, target mode, investment, cooldown,
Model, callback, or arbitrary configuration.

The existing Phase 11 fresh raw Studio sources are extended with the three
Phase 12 towers and their `TowerModel` declarations. Existing map, enemy,
difficulty, wave, economy, Base, and lifecycle fixture data remains unchanged.
The same Wave-owned one-shot transaction calls `ConfigurationValidator` once,
then passes the exact resulting canonical root to its already reviewed
Base/Enemy/Wave preparation and to the registered Tower boundary. No separately
validated tower manifest, catalog, definition, or root can be composed with it.

The combined one-shot install operation:

- builds one fresh complete raw configuration containing the established Wave
  evidence plus the exact three tower fixtures and declarations;
- calls the real `ConfigurationValidator` exactly once;
- creates fresh version-1 graybox templates for those definitions;
- preflights every Tower, loadout, model, and participant-observer allocation
  before entering the established Base/Enemy/Wave activation sequence;
- installs only that same resulting canonical root and private cloned templates;
- synchronizes the current detached MatchLifecycle participant snapshot; and
- closes installation forever after any runtime mutation or failed commit.

Wave calls Tower's narrow `prepareStudioConfiguration` boundary with the exact
canonical root and exact current Match identity. That prepare authenticates the
root, validates and privately clones every graybox template while unparented,
preallocates every catalog, loadout, UnitId, snapshot, index, metric, and
capacity table, and starts one atomic
MatchLifecycle participant-observer reservation. The reservation returns its
current detached snapshot without a `get`/subscribe gap; Tower fully prepares
the initial loadouts from that snapshot. It enables no callback and publishes
no Tower configuration, loadout, template, root, or record. Failure aborts the
observer reservation and destroys every private clone before returning.

The read-only foreign-`ATDTowerRuntime` root check occurs during the first
visual `prepareCreate`, immediately before any root or Model is parented. A
foreign same-named object therefore cannot affect configuration installation,
but it still fails the first trusted allocation closed before any runtime
record or counter commits.

The existing Wave activation is sequential rather than one assignment-only
Base/Enemy/Wave batch. Tower integrates without changing that reviewed Phase
08–11 ordering. Wave retains the opaque Tower prepare token, then
`WaveRuntime` begins its existing lifecycle activation transaction. Inside the
Wave service's `beginWaveActivation` dependency wrapper, it first obtains the
reversible MatchLifecycle wave token, refreshes Tower's reserved participant
snapshot, and synchronizes it only if its revision advanced. It then activates
the participant observer at that exact revision. These cross-service handle and
revision checks are the last fallible Tower configuration work and occur before
Base or Enemy can commit.

After observer activation succeeds, Tower's local commit retains the already
validated private templates and publishes only its preallocated configuration
and loadout tables. That local commit performs no validation, lookup,
allocation, cloning, parenting, Workspace mutation, callback invocation, or
other engine operation. The wrapper then returns the lifecycle wave token and
the established Wave path performs Base initialization, Enemy difficulty
binding, clock validation, the `PreWave -> WaveActive` lifecycle commit, and
first-wave scheduling in its existing order. No Tower configuration or
admission callback runs after Base/Enemy truth starts committing. A downstream
Wave initialization failure invokes Tower's bounded Wave-originated
`closeFromWave` path before Wave releases its own state. That path never calls
back into Wave: it closes Tower admission and releases Tower-owned observer,
loadout, runtime, model, template, and root state, then Wave itself invalidates
and releases the fixture boundary before its remaining cleanup. Normal service
shutdown uses Tower's distinct lifecycle `shutdown` path, which detaches its
Wave boundary before releasing the same Tower-owned state, so reverse service
order remains Tower before Wave. There is no second configuration or partial
Tower retry. This decision does not mischaracterize existing Base, Enemy, or
Wave operations as new two-phase assignment-only commits.

Subsequent fixed Phase 12 evidence tokens are routed through that same existing
trigger and narrow Tower boundary. They may issue capabilities for the three
occupied slots, use only predeclared server CFrames, create/remove/recreate visuals,
attempt one fixed invalid template, query detached diagnostics, and clean the
fixture. They do not create placement, attack, damage, income, upgrade, sell,
targeting, HUD, or client behavior.

Grayboxes use only Parts, Attachments, folders, the inert animation seam, and
colors/materials available at runtime. They are transient and never saved,
published, uploaded, or copied into production catalogs.

Studio acceptance uses only the connected Match place with PlaceId
`136401514513678`, GameId `10757629094`, CreatorType `Group`, CreatorId
`35420107`, PHJGAMES ownership, `ATDPlaceRole = Match`, and Edit mode before and
after. Before synchronization it records the bounded persistent root inventory
and mapped Script.Source hashes. Only branch-owned `match.project.json` source
may synchronize. No map, placement zone, marker, terrain, setting, model,
unmapped instance, Team Create content, save, publish, or upload is allowed.

The gate records actual MatchId, tower epoch, UserIds, loadout revisions and
slot shapes, TowerIds, UnitIds, RuntimeTowerIds, variants, descendant counts,
clone/pivot/visibility/removal/recreation/cleanup timings, service callback and
connection counts, endpoint/rate counts, assertions, errors/warnings, and final
residue. Two clients must see the same server-created Models. Lune evidence is
not substituted for those engine observations.

## Cleanup and residue

Both cleanup entries first close participant, create, remove, recreate,
diagnostic-mutation, and Phase 12 evidence admission, then revoke the exact
MatchLifecycle boundary. Normal Tower lifecycle `shutdown` also detaches its
exact WaveRuntime fixture boundary before releasing Tower-owned state.
Wave-originated `closeFromWave`, used only while Wave is already inside its
initialization/trigger operation, must not call Wave; Wave invalidates and
releases that boundary itself immediately after the close returns. WaveRuntime
remains the owner that destroys the single Studio trigger during its later
cleanup. Tower then invalidates all prepared/issued capabilities, destroys
prepared and live Models, destroys the exact owned runtime root, destroys
private templates, clears model indexes, clears active records and cap counters,
clears loadout snapshots/slots/UnitIds, clears canonical references and
identities, and enters `Cleaned`.

Cleanup is idempotent and remains available after fault or partial
initialization. Captured late participant callbacks, capabilities, prepare
tokens, visual operations, and trigger handlers cannot mutate, parent, clone,
or recreate anything after cleanup. The final residue requirement is zero tower
records, loadouts, UnitIds, capabilities, templates, Models, runtime roots,
callbacks, connections, caches, triggers, and service references.

After TowerRuntime cleanup, the established reverse order cleans WaveRuntime,
EnemySimulation, BaseRuntime, MatchLifecycle/MapLoader, and Network. Phase 12
does not change their authority, defeat behavior, or residue contracts.

## Deterministic and Studio verification boundary

Focused headless suites cover the fresh canonical fixtures; schema failures and
hostile inputs; loadout shape, isolation, negative Studio UserIds,
disconnect/return, capability replay/forgery/staleness, UnitId/counter faults;
RuntimeTower identity, transform, initial values, caps, bounds, removal, fault,
and cleanup; exact model hierarchy validation, private clone isolation,
prepare/commit adapters, tamper/recreation authority; integrated creation from
all three slots for multiple users; production dormancy; and explicit absence
of network, placement, combat, economy, persistence, and Phase 13 behavior.

Headless model tests use deterministic adapters for clone, pivot, parenting,
and destruction where Lune cannot prove engine semantics. Exact engine
Instances, replication, visibility, PrimaryPart/pivot behavior, and cleanup are
accepted only through Match Studio.

`TEST_MATRIX` M-02 remains Deferred because placement/combat/transactions remain
unimplemented. Phase 12 receives new dedicated headless and Studio rows.

After executable source and Studio evidence stabilize, one consolidated
independent review covers architecture, canonical authentication, authority,
identity separation, capability security, participant lifecycle, caps and
arithmetic, hierarchy safety, transaction ordering, fault closure, cleanup,
tests, Studio safety, documentation, and Phase 13 exclusion. Every material
finding is resolved before the one complete local gate and final push.

## Executed focused and structural evidence — 2026-08-28

The eight dedicated Phase 12 suites pass `90` focused cases: authenticated
fixtures `14`, RuntimeStore `14`, TemporaryLoadoutStore `11`, model contract
`12`, graybox factory `9`, model owner `13`, service `9`, and integration `8`.
The directly affected MatchLifecycle suite passes `43` cases after adding the
base-defeat observer-detach regression. The complete repository gate passes all
`840` cases across `64` suites.

The structural verifier accepts the completed Phase 12 tree with
Default/Lobby/Match/Test ModuleScript counts `83/46/83/159`, exact
Script/LocalScript counts `1/1`, `1/1`, `1/1`, and `0/0`, and `79` explicitly
allowlisted Test-owned modules. It authenticates the six server-Match Tower
modules and every Test/shared mirror by DataModel path, class, authoritative
file, and exact source bytes. It also proves ten reliable Match-only endpoint
definitions, six request-rate policies, no tower endpoint, empty production
`Assets`, `Towers`, `Enemies`, `Maps`, `Difficulties`, `Waves`, and
difficulty-specific `Economy`, no generated Roblox artifact, and no Phase 13
path or TowerRuntime public operation.

## Executed Match Studio evidence — 2026-08-28

Every accepted run used only PlaceId `136401514513678`, GameId `10757629094`,
Group CreatorId `35420107`, owner `PHJGAMES`, and `ATDPlaceRole = Match`, with
one local server and exactly two fresh simulated clients. Only branch-owned
`match.project.json` source was synchronized. The place began and ended in Edit
mode; the task-owned Rojo connection was stopped; no place, model, map, terrain,
setting, Team Create object, or asset was saved or published.

Before synchronization, the bounded persistent inventory was six Workspace
descendants, five Lighting descendants, and zero descendants in SoundService,
Teams, StarterGui, and StarterPack. The final inventory retained those exact
counts and objects. The mapped source inventory moved only from the Phase 11
branch's `77` ModuleScripts to the reviewed Phase 12 branch's `83`, while the
single Script and LocalScript remained one each. Final Play cleanup found no
`ATDTowerRuntime`, runtime map, enemy visual root, network root, Studio trigger,
or other runtime residue. The final Edit-mode audit measured `1,843,901` mapped
source bytes; `TowerRuntimeService` was `83,729` bytes and contained both final
consolidated-review fixes.

The final-source accepted primary run used MatchId
`match:52847c36-92d9-47c8-912a-52e2a7a8ca3e`, tower epoch `1`, and participant
UserIds `-2` and `-1`. Their loadout revisions were `1` and `2`. Each exact
five-slot snapshot contained, in order:

1. `tower:phase12-single` with `unit:p12-e1-n2-s1` or
   `unit:p12-e1-n1-s1`;
2. `tower:phase12-splash` with the corresponding `...-s2` UnitId;
3. `tower:phase12-support` with the corresponding `...-s3` UnitId; and
4. two explicit `Empty` slots with no TowerId or UnitId.

The server safely returned `NOT_FOUND` for unknown UserId
`9007199254740991`. No tower RemoteEvent, RemoteFunction, or client mutation
operation existed. The production network remained ten endpoint folders,
sixteen reliable RemoteEvent instances, zero RemoteFunctions, zero
UnreliableRemoteEvents, and six exact request policies.

The first six trusted allocations produced RuntimeTowerIds `1..6`, one record
per occupied slot for each user, at server-selected X coordinates
`0, 6, 12, 18, 24, 30`. Every record retained the exact owner, slot, canonical
TowerId, temporary UnitId, level `1`, canonical default target mode or nil,
`AllEligibleEnemies`, placement-cost total investment, cooldown sentinel `0`,
trusted pivot, and `Active` state. Server activation plus loadout creation took
`0.0046535` seconds; the first six record/model transactions took
`0.0006274`–`0.0011286` seconds.

Both clients observed the same first-six hierarchy and pivots. Per Model, the
single fixture had `27` descendants, `4` BaseParts, `6` Attachments, `3`
muzzles, `3` hooks, and `3` variants; splash had `30/4/9/6/3/3`; support had
`20/4/0/0/2/3`. No attack, target, support, economy, status, animation, or
cooldown behavior executed. Removing a visual took `0.0001617` seconds and left
its RuntimeTower record unchanged. Explicit recreation took `0.0010771`
seconds. Changing the replicated contract-version attribute to `999` likewise
left the authoritative record unchanged; the reviewed repair path recreated
only the owned support visual in `0.0006388` seconds. A deliberately invalid
template failed with `INVALID_ATTRIBUTE` in `0.0000267` seconds, accepting no
record and changing no count.

The cap ladder ended with active RuntimeTowerIds `1..11,13`: each owner had
exactly two single, three splash, and one support record, matching every
per-owner/per-TowerId `placementCap`. RuntimeTowerId `12` was removed and was
not reused; the next accepted allocation received `13`. Final metrics were
`12` active, `13` lifetime, next ID `14`, `13` issued RuntimeTowerIds,
capability generation `23`, zero outstanding issued/reserved capabilities or
service expectations, `28` evidence operations, and `10` expected cap
rejections.
Both clients agreed on the final twelve Models: four single, six splash, two
support, `328` descendants, `48` BaseParts, `78` Attachments, `36` variants,
and `34` hooks, with zero unexpected descendants or pivot mismatch.

The ordinary Phase 11 schedule simultaneously reached Wave `FiniteComplete`
revision `22`, Base `Active` revision `11`, and Match `WaveActive` revision `8`
with ten exact spawns, zero active enemies, no early spawn, and no Tower count,
identity, model, or connection change. TowerRuntime retained one participant
observer and one Wave evidence boundary; WaveController, BaseController/view,
and EnemyController retained their established constant ownership. Explicit
Tower cleanup then succeeded in `0.0019925` seconds, removed all twelve records,
loadouts, UnitIds, capabilities, templates, Models, roots, observers, and
boundaries, made late creation return `UNAVAILABLE`, and left one completed
assertion set with zero failures.

The separate final-source accepted defeat run used MatchId
`match:762fcd89-2459-4c68-b85c-bce0624682d9`. UserId `-2` received the same
three occupied slots and RuntimeTowerIds `1..3`; both clients observed their
exact single/splash/support Models. One lethal scheduled enemy produced Match
`Results` revision `9`, Wave `DefeatClosed` revision `3`, Base `Defeated`
revision `3`, Base health `0/10`, exactly one defeat/Results commit, no later
spawn, and no change to any Tower record or Model. This run exposed a cleanup
seam: committed base defeat closes ordinary MatchLifecycle callbacks before
Tower shutdown, so the former common observer gate incorrectly rejected the
authentic detach operation. MatchLifecycle now treats only
`detachParticipantObserver` as cleanup-only after callback closure while still
requiring service/handle/re-entry authenticity; reserve, refresh, activate, and
post-shutdown detach remain unavailable. The focused regression passes. The
final-source rerun activated in `0.0048356` seconds, created all three role
Models in `0.0031535` seconds, and cleaned Tower state in `0.0015069` seconds
with no residue.

Both accepted scenarios recorded zero console errors. The server emitted only
the expected bounded early `GetBaseSnapshot` `UNAVAILABLE` bootstrap warning;
clients emitted no warning. A separate discarded diagnostic session measured
first client visual replication in roughly `46.0`–`57.0` milliseconds for
creation/recreation/cleanup, but acceptance correctness comes only from the
fresh zero-error runs above.

## Consolidated review and final gate

The independent consolidated review approved the completed Phase 12 tree
with no remaining material findings. It covered requirements, architecture,
canonical authentication, authority/security, runtime identity separation,
loadout/capability behavior, participant lifecycle, cap arithmetic, model and
Instance ownership, transaction/fault closure, cleanup, tests, exact Studio
safety/evidence, structural scope, documentation, and Phase 13 exclusion.

The review's material findings are resolved. `TowerRuntimeService` now adopts a
fatal or cleaned child-store state immediately, closes admission, and revokes
service capability expectations; a failed rollback abort now faults with
`CAPABILITY_ABORT_FAILED` instead of discarding the abort result. The committed
Defeat observer-detach correction remains cleanup-only and authentic. Focused
regressions cover those seams, and the fresh final-source primary and Defeat
Studio sessions above pass with zero errors and residue. The final local gate
passes formatting, lint, all `840` tests across `64` suites, all four exact
structural builds, diff/scope/exclusion checks, and an inspected Rojo build with
the generated artifact removed. Exact-final-SHA CI is recorded at handoff.
