# Phase 10 Defender Base Runtime and Replication Contract

## Decision status and scope

This is the authoritative Phase 10 decision for Packets 10.1–10.4. It was
recorded before executable Phase 10 implementation. The single focused
architecture, authority, networking, and lifecycle review completed on
2026-08-28 with no P0 finding, six P1 findings, and four P2 findings. The
safe-boundary API, fault/snapshot semantics, state-tagged cleanup record, client
identity lock, irreversible-defeat preflight, one Studio trigger, exact marker
watchers, provenance lifetime, recipient policy, logging boundary, and map
authentication resolutions are incorporated below. The same reviewer confirmed
all ten resolutions in the same review round; no blocking finding remains and
the pre-implementation architecture gate is cleared.

Packets 10.1–10.4 implement this decision. Their focused deterministic checks,
exact unsaved two-client Match Studio gate, consolidated final review,
`593`-case/`48`-suite local gate, and all four structural builds passed on
2026-08-28. The final review found one P1 terminal-publication classification
defect and one P2 Studio-count documentation gap; both were fixed and covered by
the focused regression/evidence replay. Exact-final-SHA CI is cited at handoff
rather than through a self-referential evidence commit. Phase 10 is complete;
Phase 11 remains unbegun.

Phase 10 adds one match-scoped server-owned defender-base runtime, its bounded
reliable replication, a minimal client-owned world bar, and the narrow defeat
coordination required to move an already active match to Results. Production
configuration remains dormant because the validated production difficulty and
enemy catalogs remain empty. A future server-owned Phase 11 caller may select an
already authenticated `DifficultyDefinition` and initialize this service; Phase
10 does not select a difficulty, schedule a wave, or progress into WaveActive in
production.

Phase 10 does not add authored content, balance composition, map health,
player-count scaling, wave scheduling, spawn cadence, wave tracking, towers,
combat, healing, repair, armor, rewards, persistence, a results screen, a global
base HUD, audio, assets, or a client-to-server gameplay mutation. Phase 11
remains unbegun.

## Engine constraints

The design retains the existing reliable `RemoteEvent` foundation. A
`RemoteEvent` is asynchronous, one-way, and non-yielding, but a send has no
application acknowledgement and a listener that is not connected cannot recover
an earlier event. Cross-endpoint event/response order is not an authority or
causal guarantee. Consequently the client connects first, requests a full
snapshot second, and accepts only a newer full state by `(MatchId,
baseRevision)`. Phase 10 does not add `RemoteFunction`, `InvokeClient`,
`UnreliableRemoteEvent`, a generic bus, or another network root.

Remote payloads contain only bounded string-keyed records, arrays, strings,
booleans, and finite numbers. They contain no Instance, callback, metatable,
mixed-key table, definition, marker, UI, Player, recipient, error, or private
state.

A `BillboardGui` can live under `PlayerGui` while adorning a Workspace
`BasePart`. The client therefore owns its GUI in `PlayerGui`; the exact
`Workspace.ATDRuntimeMap.Markers.DefenderBase` Part is used only as `Adornee`.
Streaming can temporarily remove a Workspace Instance from ancestry. Marker loss
is presentation loss only: authoritative state remains cached, the GUI hides,
and bounded ancestry/descendant signals rebind a newly available exact marker.
No permanent render loop is required.

Cancelling a tween leaves its properties at their current interpolated values,
and cancellation can signal completion. The base view therefore owns at most
one damage-label/pulse tween, uses no completion connection, cancels and destroys
the old tween before replacement, and explicitly restores steady-state
properties before creating the next pulse or cleaning up.

Primary references:

- [RemoteEvent](https://create.roblox.com/docs/reference/engine/classes/RemoteEvent)
- [Remote events and callbacks](https://create.roblox.com/docs/scripting/events/remote)
- [BillboardGui](https://create.roblox.com/docs/reference/engine/classes/BillboardGui)
- [PlayerGui](https://create.roblox.com/docs/reference/engine/classes/PlayerGui)
- [Instance streaming](https://create.roblox.com/docs/workspace/streaming)
- [TweenBase](https://create.roblox.com/docs/reference/engine/classes/TweenBase)
- [TweenService](https://create.roblox.com/docs/reference/engine/classes/TweenService)
- [Performance diagnostics](https://create.roblox.com/docs/performance-optimization/identify)

## Server ownership and service graph

The resolved Match server graph becomes:

```text
initialize/start: NetworkRegistry -> MatchLifecycle -> BaseRuntime -> EnemySimulation
shutdown:         EnemySimulation -> BaseRuntime -> MatchLifecycle -> NetworkRegistry
```

`MatchLifecycle` remains the only MapLoader owner. `BaseRuntime` reads its
MatchId and the already-loaded detached frozen `RuntimeMapSnapshot`; it neither
loads a second map nor retains a marker Instance. `EnemySimulation` depends on
`BaseRuntime` and installs the base's synchronous endpoint sink into its sole
runtime store. Network remains the first owner and last cleanup target.

The client graph becomes:

```text
initialize/start: MatchReadyController -> BaseController -> EnemyController
shutdown:         EnemyController -> BaseController -> MatchReadyController
```

The base controller cleans its listener, request state, marker listeners, GUI,
tween, and cached state before Ready/map shutdown. It
does not own or destroy the server-created runtime map.

## Base runtime identity, state, and initialization

There is exactly one non-restartable BaseRuntime per Match service lifetime. Its
strict internal state union is:

```text
Uninitialized -> Active -> DefeatPending -> Defeated
       |           |            |
       +-----------+------------+-> Faulted
Uninitialized/Active/DefeatPending/Defeated/Faulted -> Cleaned
```

`Cleaned` is terminal. Cleanup is idempotent. No state can return to
`Uninitialized` or `Active`, and no second difficulty can be bound. Only an
uninitialized construction/dependency failure, an Active mutation/dependency
failure, or a pre-Results DefeatPending coordination failure may enter Faulted.
Defeated is an already committed terminal truth and never transitions to
Faulted, including after a per-recipient or logical publication failure.

Faulted closes initialization, damage, feedback, defeat coordination, tower
input, and every other mutation. If initialization had committed, Faulted keeps
one immutable read-only full snapshot available to `GetBaseSnapshot` and
attempts at most one State publication only when the publisher itself remains
healthy. A pre-initialization fault has no base snapshot. If a test-injected
revision exhaustion prevents a distinct Faulted revision, the service retains
only the last committed snapshot and returns a fixed unavailable error rather
than publishing contradictory equal-revision state.

The private record contains only:

```luau
type BasePayload = {
    matchId: Ids.MatchId,
    enemyEpoch: number,
    mapId: Ids.MapId,
    baseCFrame: CFrame,
    basePosition: Vector3,
    difficultyCatalog: ConfigTypes.DifficultyCatalog?,
    difficultyId: Ids.DifficultyId?,
    maximumHealth: number?,
    currentHealth: number?,
    baseRevision: number,
    initializedServerTime: number?,
    updatedServerTime: number?,
    lastObservedOutcomeServerTime: number?,
    lowHealth: boolean,
    lowHealthCrossingIssued: boolean,
    processedByRuntimeEnemyId: { [number]: ProcessedLeakIdentity },
    processedOutcomeCount: number,
    pendingFeedback: PendingFeedback?,
    terminalResultSeed: BaseResultSeed?,
    towerInputAdmissionClosed: boolean,
    lastFinishedEnemyPassOrdinal: number,
    lastBoundaryOutcome: EnemyPassBoundaryOutcome?,
}

type BaseRuntimeRecord = {
    state: "Uninitialized" | "Active" | "DefeatPending" | "Defeated" | "Faulted" | "Cleaned",
    payload: BasePayload?,
}
```

Every non-Cleaned state has the one private payload. Cleanup releases it and
leaves only `{ state = "Cleaned", payload = nil }`, so an idempotent method
receiver remains without retaining match/base state. The ledger stores only a
copied frozen `ProcessedLeakIdentity` tuple of IDs, damage, and time; it never
retains the provenance-bearing outcome object.

The record retains no Player, enemy Instance, map marker Instance, runtime map
Instance, UI, tween, connection, client object, coroutine, mutable definition,
or caller-owned table. Queries allocate and freeze detached records. Cleanup
clears the ledger, pending feedback, terminal seed, timestamps, identifiers,
health, definition/catalog references, callbacks, and detached map values.

During lifecycle initialization, BaseRuntime directly calls the current
`MatchLifecycle` instance for MatchId and `getRuntimeMapSnapshot()`. No caller
can supply or replace a map snapshot. It requires the exact deeply frozen map
and base records, a canonical MapId, finite CFrame and Vector3 components, and
exact `base.cframe.Position == base.position` before copying only map identity,
base CFrame, and base position. It also authenticates one enemy epoch in
`1..4,096`. Initialization is a separate one-shot server operation so production
can remain dormant.

Initialization accepts only a definition whose identity is present in the
captured `DifficultySchema`-authenticated catalog: the catalog must pass
`DifficultySchema.isValidatedCatalog`, the canonical `byId` value must be the
same frozen definition object, and its ID and `base.maxHealth` are rechecked.
Raw, merely frozen, cloned, mutated, foreign-catalog, client-provided, or
metatable-bearing definitions are rejected without mutation. The sole balance
source is `DifficultyDefinition.base.maxHealth`; the map contributes only its
authenticated identity and world base CFrame/position.

Successful initialization samples the injected non-yielding monotonic server
clock once, sets maximum and current health to that positive safe integer, sets
`baseRevision = 1`, sets `lowHealth = false`, and enters `Active`. A bad clock,
invalid map, invalid definition, duplicate initialization, or unavailable match
fails without partial state. Production's empty difficulty catalog leaves the
runtime `Uninitialized` until Phase 11.

Initialization is allowed only while the authenticated lifecycle is ReadyCheck
or PreWave. WaveActive, Results, Closing, unavailable, Faulted, Defeated, and
Cleaned reject it, preventing a mid-wave health reset. In Studio only, a one-shot
catalog install may replace the captured authenticated empty production catalog
with one freshly schema-validated runtime-only catalog. It is allowed only while
Uninitialized, only when the captured catalog is empty, only before any outcome
identity is processed, and only through the single closed trigger described
below. A nonempty production catalog can never be replaced.

## Authenticated endpoint leak outcome

The Phase 09 endpoint callback changes from a general endpoint snapshot to this
detached frozen server-only outcome:

```luau
type AuthenticatedLeakOutcome = {
    matchId: Ids.MatchId,
    enemyEpoch: number,
    runtimeEnemyId: number,
    enemyId: Ids.EnemyId,
    leakDamage: number,
    serverTime: number,
}
```

`EnemyRuntimeStore` creates the outcome only after an authenticated immutable
EnemyDefinition reaches its endpoint. `leakDamage` is copied directly from that
definition; it is never accepted from a client, spawn caller, runtime fixture
request, enemy replication message, marker, Attribute, or mutable snapshot.
`EnemyRuntimeStore` owns the provenance lifetime. Its module-private weak-key
set recognizes outcomes created by a live store, while each store retains a
bounded outcome-by-ID set solely so cleanup can explicitly revoke every issued
object before clearing its terminal records. The module exposes only the
predicate that BaseRuntime captures during construction, not a production
creator. BaseRuntime severs that predicate on cleanup. Wrong-store objects still
have to match the bound MatchId and epoch, and a cleaned store's retained object
is no longer authentic. Tests obtain genuine outcomes through a real test store
or an exact test-only constructor unavailable in production mappings.

The outcome is created and authenticated before the callback. The store marks
the endpoint issued, invokes the sink synchronously in a fresh coroutine,
resumes it exactly once, rejects throw/yield/re-entry, and then always completes
that enemy's `EndpointResolved -> Despawned` transaction before the outer enemy
service reacts. The callback may call only BaseRuntime's non-yielding
`recordLeak`; BaseRuntime owns no EnemySimulation/store mutation reference. An
endpoint callback cannot spawn, slow, despawn, step, clean, or otherwise re-enter
EnemyRuntimeStore inline.

No `leakDamage` field is added to client enemy replication. BaseRuntime copies
only the validated outcome fields into its ledger and retains no strong
reference to the provenance object.

## Exact-once ledger and damage arithmetic

One enemy epoch can issue at most 4,096 RuntimeEnemyIds, so BaseRuntime owns one
fixed lifetime ledger with the same 4,096-entry ceiling. The ledger is keyed by
RuntimeEnemyId and belongs only to the base runtime. It is cleared on cleanup and
never copied to clients. An accepted zero-damage outcome is ledgered too, which
prevents a later conflicting replay without creating a health revision or
publication.

`recordLeak` is synchronous and non-yielding. It returns a strict Result whose
success is either `{ kind = "Applied", appliedDamage, baseRevision,
defeatPending }` or `{ kind = "Ignored", reason, outcomeConsumed }`. The fixed
Ignored reasons cover Duplicate, ConflictingReplay, Uninitialized,
WrongLifecycle, PostDefeat, and ZeroDamage. Wrong identity/provenance, malformed
authenticated data, clock/order/cap/revision failure, re-entry, and dependency
failure use fixed typed errors. The endpoint wrapper treats every success as a
completed callback and converts only an impossible error to one static throw
after retaining no payload/error value. It never parses an error string and
ordinary post-defeat/same-pass rejection never faults EnemySimulation.

`recordLeak` validates and commits in this order:

1. runtime is not Cleaned or Faulted;
2. outcome provenance is authentic and its exact fields are structurally valid;
3. MatchId and enemy epoch equal the bound identity;
4. RuntimeEnemyId is in `1..4,096`, EnemyId is valid, damage is a non-negative
   safe integer, and time is finite and non-negative;
5. an existing ledger identity is an exact duplicate or conflicting stale
   replay and cannot apply again;
6. outcome time is no earlier than the last observed authentic outcome time;
   equal timestamps are valid within one pass;
7. ledger capacity is available, then the copied identity is consumed exactly
   once even while Uninitialized, outside WaveActive, at zero damage, or after
   defeat;
8. the lifecycle snapshot read synchronously from MatchLifecycle has the same
   MatchId and exact `WaveActive` state, and runtime state is Active;
9. a positive nonlethal commit has one revision slot, while a lethal commit has
   two slots reserved atomically—one for zero/DefeatPending and one for the final
   Defeated state.

Wrong-match, wrong-epoch, malformed, unauthenticated, stale-time, duplicate,
conflicting-replay, capacity-exhausted, faulted, and cleaned outcomes cannot
apply health. A first authentic current-identity outcome is ledgered even when
Uninitialized, non-WaveActive, zero-damage, or post-defeat, then returns a benign
Ignored success without changing health, revision, low-health state, feedback,
or result seed. This prevents a retained genuine outcome from becoming damaging
after a later state change. A positive revision-exhausted outcome is consumed,
does not change health, and fails closed. An impossible malformed authenticated
outcome or dependency failure faults the integration only after the current
enemy terminalizes.

Arithmetic never evaluates an overflowing subtraction:

```text
appliedDamage = min(leakDamage, currentHealth)
if leakDamage >= currentHealth then nextHealth = 0
else nextHealth = currentHealth - leakDamage
```

All inputs and retained health values are safe integers. Current health is
always clamped to `[0, maximumHealth]`. Zero damage changes no health, base
revision, low-health state, or publication. Overkill applies exactly the
remaining health. Multiple outcomes are observed in the deterministic order in
which EnemyRuntimeStore terminalizes the ascending start-of-pass RuntimeEnemyId
snapshot; direct endpoint operations use their server call order. Luau
operations are synchronous and BaseRuntime has a mutation re-entry guard.

Every health-changing outcome increments `baseRevision` exactly once after
preflighting safe-integer space. Base revision is independent from
`MatchStateMachine.revision`, enemy epoch, enemy per-record revisions, and enemy
replication sequence because those counters describe different mutation
domains, can legitimately skip each other, and have different recovery owners.
No counter is inferred from another or silently rolled over.

Low health is presentation policy computed with the overflow-free comparison
`currentHealth <= maximumHealth / 4`; division by four is exact enough for this
integer threshold and never multiplies a safe integer. The persistent state
becomes true on the first transition to
at most 25% and never returns false because Phase 10 has no healing. Its crossing
flag is issued at most once. Initialization at full positive health is never
low.

The first health-changing outcome that reaches zero sets `currentHealth = 0`,
increments the revision once, enters `DefeatPending`, closes future damage, and
records exactly one pending defeat. Later outcomes in the same enemy pass or any
later pass cannot change health, revision, or defeat count.

## Narrow API and enemy-pass boundary

The production surface is limited to authenticated one-shot initialization,
`recordLeak`, detached snapshot/query/result/defeat-state reads,
`finishEnemyPass`, prepared-defeat completion/failure, the read-only future
tower-input admission query, and idempotent cleanup. No method accepts a Player,
recipient, raw health/damage, map Instance, transition target, callback, or
client value.

Every successfully committed EnemyRuntimeStore `step` and direct
`resolveEndpoint` is one enemy pass. EnemySimulation owns one monotonic positive
safe-integer pass ordinal across both paths. After the store returns and all of
that pass's endpoint/despawn records have committed to the enemy publisher, a
common non-yielding finalizer invokes `finishEnemyPass(passOrdinal)` exactly
once. Normal passes with pending damage flush one coalesced Damage message;
passes with no health change are no-ops. A pass that reached zero reserves one
logical terminal publication and returns one opaque prepared-defeat token
without flushing an intermediate state.

The boundary method caches only the latest ordinal and detached outcome. A
repeat with that exact ordinal returns the cached outcome without transition,
publication, clock sample, or feedback replay. A lower ordinal is stale; a gap,
overlap, re-entry, wrong token, or exhausted ordinal is an invariant failure.
The next pass cannot begin while a prepared defeat is unresolved. A shutdown
requested during store/callback work remains deferred until this finalizer has
either completed the normal flush or closed/finalized the prepared defeat; then
the existing reverse lifecycle cleanup runs. Thus pending feedback can never
silently spill into a later simulation pass.

## Defeat boundary and MatchLifecycle integration

The defeat sequence is synchronous and occurs at the first safe
EnemySimulation boundary after the endpoint transaction that depleted health.
Before any irreversible enemy or match mutation, the boundary performs all
possible preflight work:

- BaseRuntime proves the reserved terminal revision, samples the non-yielding
  completion clock, constructs and validates the candidate final snapshot and
  result seed, and reserves one logical base-publication slot;
- MatchLifecycle's narrow `beginBaseDefeat(matchId)` validates exact identity,
  Started/available WaveActive state and revision space, obtains the existing
  opaque state-machine transition token, and reserves the one transition claim;
- the enemy publisher preflights every ascending remaining active ID against its
  already reserved terminal capacity; and
- BaseRuntime/EnemySimulation validate their operation tokens and closed-set
  dependencies without yielding.

The prepared data is detached and fixed, so after Results commits no clock,
revision, result-construction, or logical-capacity decision remains.

1. BaseRuntime has already committed zero health and DefeatPending once and
   `finishEnemyPass` has returned the one prepared-defeat token.
2. EnemyRuntimeStore has finished that enemy's endpoint state and despawn, and the
   enemy publisher commits its terminal records.
3. EnemySimulation closes spawn, slow, manual-despawn, and endpoint admission.
4. It snapshots remaining active IDs in ascending order, preflights their
   reserved terminal publication capacity, and calls one bounded store operation
   that samples time once and terminalizes them in that order with reason
   `Defeat`. These removals never invoke the endpoint sink or leak damage.
5. BaseRuntime's future tower-input query is sealed. It is only a boolean
   server-owned admission seam; no tower service or input endpoint is created.
6. EnemySimulation commits MatchLifecycle's already prepared opaque transition
   token. It commits `WaveActive -> Results` once and then attempts the resulting
   MatchSnapshot publication. A repeated committed token is a no-op duplicate
   and never touches the match revision or republishes.
7. If Results committed, BaseRuntime atomically installs the already validated
   Defeated snapshot/result seed and the base publisher attempts the one reserved
   coalesced terminal full-state message for that simulation pass.

`beginBaseDefeat` and its opaque commit/rollback operations are one narrow
server-only transactional API. They have no remote definition and accept no
Player, recipient, client payload, arbitrary target state, or caller token.
Rollback is allowed only before commit and releases the claim without changing
state. No general transition API is exposed. Studio-only evidence may use a
separately gated exact operation to move PreWave to WaveActive while Phase 11 is
absent; it is unavailable outside `RunService:IsStudio()` and is not production
progression.

The future tower admission query returns true only for an initialized Active
base while MatchLifecycle is WaveActive. It returns false before initialization,
outside WaveActive, once DefeatPending begins, after explicit sealing, in
Defeated/Faulted/Cleaned state, or on dependency failure. Phase 10 creates no
tower state or callback.

Failure is closed and non-retrying:

- endpoint callback failure still terminalizes that enemy, then faults enemy
  mutation admission and closes spawn;
- remaining-enemy cleanup/preflight failure closes spawn and tower input, does
  not attempt Results, and faults the base/defeat coordinator;
- Results begin/commit failure does not reopen spawn, restore enemies, restore
  health, retry the transition, or create a second defeat; it resolves the
  prepared base token to Faulted without a result seed;
- once Results commit succeeds, that transition remains committed exactly once.
  A subsequent MatchSnapshot publication failure returns the explicit detached
  outcome `{ committed = true, published = false }`, leaves MatchLifecycle in
  read-only Results with all mutation admission closed, and does not misclassify
  the committed transition as a failure or move it to Closing;
- a committed Results outcome always installs the prebuilt Defeated snapshot and
  result seed. A base logical-publication failure after that point marks only the
  publisher unhealthy; it cannot change Defeated, erase the seed, or disable
  direct read-only base snapshot recovery;
- per-recipient sender failure is contained, consumes that attempted send, and
  leaves snapshot recovery available; an invalid sender/payload/recipient set or
  publisher invariant failure faults publication and closes the coordinator;
- a shutdown requested during an endpoint/defeat operation is deferred to the
  same safe boundary, after which normal reverse lifecycle cleanup runs; and
- captured callbacks check availability and cannot mutate or publish after
  cleanup.

If defeat coordination faults before Results commit, zero health and closed
admissions remain fixed in Faulted state and no completed result seed exists. If
Results did commit, BaseRuntime is Defeated and preserves its completed seed even
when either Match or base event publication failed. No path invents or rolls
back Results success.

## Detached future result seed

The one successful terminal seed is detached, deeply frozen, Instance-free, and
contains only:

```luau
type BaseResultSeed = {
    matchId: Ids.MatchId,
    mapId: Ids.MapId,
    difficultyId: Ids.DifficultyId,
    outcome: "Defeat",
    reason: "BaseHealthDepleted",
    completionServerTime: number,
    currentHealth: 0,
    maximumHealth: number,
    baseRevision: number,
}
```

It is prebuilt and validated behind an opaque prepared-defeat token, becomes
observable only after the Results commit, its revision equals the final Defeated
snapshot revision, and repeated queries return detached frozen values.
It contains no participant, reward, wave, enemy, tower, Player, Instance,
recipient, persistence record, UI, or return/retry data. It remains available
until BaseRuntime cleanup, then no result seed or base state remains.

## Reliable base protocol

Phase 10 adds exactly two Match-only definitions beneath the existing
`ReplicatedStorage.ATDNetwork.v1` root:

| Endpoint | Direction/kind | Exact purpose | Response |
| --- | --- | --- | --- |
| `GetBaseSnapshot` | client-to-server Request | exact empty `{}` recovery request | one required `BaseSnapshot` |
| `BaseReplication` | server-to-client Event | tagged full-state/feedback publication | none |

`GetBaseSnapshot` has exact production token-bucket capacity `2` and refill
`0.25` per second. The empty payload selects no health, damage, identity,
difficulty, map, marker, revision, recipient, result, defeat, state, or
transition. The existing dispatcher authenticates the actual Player, validates
the exact envelope/payload, rate-limits, executes the handler synchronously,
validates the response, and replies only to the origin. Public failures are
fixed `UNAVAILABLE`, `NOT_AUTHORIZED`, or `INTERNAL_ERROR` without metadata.

The exact full snapshot is:

```luau
type BaseSnapshot = {
    matchId: Ids.MatchId,
    enemyEpoch: number,
    mapId: Ids.MapId,
    difficultyId: Ids.DifficultyId,
    basePosition: Vector3,
    baseRevision: number,
    status: "Active" | "Defeated" | "Faulted",
    currentHealth: number,
    maximumHealth: number,
    lowHealth: boolean,
    initializedServerTime: number,
    updatedServerTime: number,
}
```

Health and revision are safe integers, maximum is positive, current is within
range, basePosition has bounded finite components, time is finite/non-negative
and ordered, and `lowHealth` equals the exact 25% policy. Defeat has current
zero; Active has current greater than zero.
DefeatPending is an internal synchronous state and is never externally
published. Uninitialized/Cleaned runtimes have no snapshot.

`BaseReplication` is this exact tagged union:

```luau
type BaseStateMessage = {
    kind: "State",
    snapshot: BaseSnapshot,
}

type BaseDamageMessage = {
    kind: "Damage",
    snapshot: BaseSnapshot,
    appliedDamage: number,
    leakCount: number,
    lowHealthCrossed: boolean,
}
```

Every event contains a complete authoritative snapshot and can converge the
client independently. `appliedDamage` is the total actual clamped health loss,
not the sum of unbounded requested overkill; it cannot exceed maximum health.
`leakCount` counts health-changing outcomes in the coalesced enemy pass and is
bounded by 128. Low-health crossing is true at most once. Zero-damage outcomes
create no event.

The publisher owns exactly one pending latest state and one pending feedback
aggregate, no retry queue and no delivery ledger. All leaks resolved in one
server simulation pass merge into one Damage message. A later terminal commit
replaces its snapshot while preserving that pass's bounded feedback, so defeat
also emits only one base event in the pass. Initialization and explicit fault
publication may emit one State message outside an enemy pass. The lifetime
event-publication ceiling is 4,098. Each publication validates a dense set of
actual live Players with unique Player and UserId identities, faults on more than
four instead of selecting a subset, sorts by UserId, and makes at most four
`FireClient` attempts. Base publication owns no Heartbeat, per-leak, per-enemy,
or per-client loop/connection.

An attempted recipient send is never retried. Other recipients continue. A
later full event or `GetBaseSnapshot` response recovers the missed state. Sender
failures, attempted/publication counts, and current queue occupancy are bounded
numeric diagnostics only; they retain no Player.

## Logging and privacy boundary

Phase 10 adds no logger subsystem, custom field, per-leak record, or
player/outcome keyed aggregate. Lifecycle or network failure call sites may emit
only static developer-authored messages and fixed codes through the existing
`lifecycle` or `network` subsystems, using only already allowlisted `code`,
`service`, `state`, and `endpoint` fields. Production logs never contain health
payloads, damage, MatchId, epoch, RuntimeEnemyId, EnemyId, difficulty/map
definition, result seed, Player/UserId, recipient, request/envelope, marker/UI,
raw error, trace, or catalog. Studio processing/convergence/publication and
connection/tween counts are bounded returned diagnostics, not production logs.

## Client convergence

Bootstrap ordering is fixed:

1. resolve and connect `BaseReplication`;
2. connect the `GetBaseSnapshot` response path and register its schemas;
3. send the exact empty snapshot request;
4. pass every valid event/response through one state reducer.

Before the first valid state, the reducer is unlocked. The first accepted
snapshot pins `(MatchId, enemyEpoch)` plus immutable mapId, difficultyId,
basePosition, maximumHealth, and initializedServerTime, then installs its full
state. Thereafter all immutable fields must match, updatedServerTime must be
nondecreasing, and only a strictly greater baseRevision can replace persistent
state. Health cannot increase; lowHealth cannot return false; legal visible
status transitions are Active to Active/Defeated/Faulted, Defeated to Defeated,
and Faulted to Faulted. A first late snapshot may already be Defeated or Faulted.
Lower revisions and foreign identity are stale until controller
cleanup/recreation. A higher revision is accepted even when intermediate
revisions were missed because every message is full state; this is deliberate
gap convergence, not a partial merge. Malformed, extra-field, metatable, cyclic,
Instance-bearing, nonfinite, out-of-range, immutable-field conflict, illegal
status/health/time transition, wrong-match/epoch, stale, duplicate, and
out-of-order data cannot mutate or roll back cached state.

Thus an event can beat its request response, a response can recover a missed
event, and a later event can repair a sender failure. A reconnect creates a new
controller with a fresh two-attempt request bound. If both attempts fail, the
controller retains its newest valid event state or stays hidden; it never
invents health or defeat.

The reducer tracks `lastFeedbackRevision` separately. A newly accepted Damage
message that advances persistent state also advances feedback. If a snapshot
response installed the exact same revision first, one later Damage event may
produce feedback only when its embedded snapshot is byte-for-byte equivalent to
the cached canonical state and that revision has not produced feedback. Further
equal-revision events, lower revisions, and conflicts cannot pulse or repeat
text. Snapshot and State messages correct the persistent bar without fabricating
damage feedback. This preserves legitimate event/response races without making
equal-revision state mutable.

## World-space base presentation

The client creates one `BillboardGui` under the local `PlayerGui`. It contains:

- one background and clamped horizontal fill bar;
- exact numeric text `current / maximum`;
- a persistent visible `LOW` text label whenever authoritative lowHealth is
  true; and
- a bounded textual `-N` damage label plus cancellable visual pulse for a newly
  accepted Damage message.

Color and pulse are supplemental. Numeric health, `LOW`, and `-N` ensure health,
low state, and damage are not color- or sound-only. There is no audio dependency,
global/top-screen HUD, asset ID, authored GUI, or authoritative marker value.

The fixed marker lookup is exactly
`Workspace.ATDRuntimeMap.Markers.DefenderBase`, and every component is rechecked
for expected name, immediate ancestry, and class; `DefenderBase` must be a Part
whose position matches the pinned authenticated basePosition within the fixed
transport tolerance. The position is only a binding cross-check, never client
authority. The marker is assigned only to `BillboardGui.Adornee`. The client
writes no Attribute, ValueBase, health, revision, tag, or child beneath the
marker or runtime map. The GUI remains under PlayerGui.

If the marker is missing, removed, streamed out, renamed, moved away from its
authenticated position, replaced incorrectly, reparented within Workspace, or
leaves Workspace, the GUI clears its Adornee and hides without changing cached
state. Two Workspace DescendantAdded/DescendantRemoving listeners find broad
arrival/removal. One bounded watcher set adds AncestryChanged and exact
Name/Parent/CFrame property listeners for the bound runtime root, Markers folder,
and marker. Rebinding disconnects that whole set before atomically installing a
new one. Thus rename/reparent within Workspace is covered without a loop or
connection growth.

The PlayerGui view likewise owns fixed ChildAdded/ChildRemoved coverage plus a
bounded watcher set for the BillboardGui and every required owned descendant's
AncestryChanged and exact Name/Parent properties. Any deletion, rename, or
reparent within PlayerGui invalidates the whole exact view and recreates it from
the cached canonical state after disconnecting the old watcher set. The total
maximum marker/view listener count is a declared construction constant and does
not vary with leaks, enemies, streaming cycles, or recreations. No
RenderStepped/Heartbeat loop is added.

The view owns at most one active tween and no completion connection. Starting a
newer pulse cancels and destroys the old tween, restores the damage label/pulse
properties, then creates one replacement tween on that same textual visual.
Cleanup first disables callbacks/recreation, then cancels/destroys and normalizes
the tween, disconnects both bounded watcher sets and all fixed listeners,
destroys the exact GUI, clears Adornee/state/cache references, and is idempotent.

## Studio-only evidence seam

The exact Match Studio target is PlaceId `136401514513678`, GameId
`10757629094`, CreatorType Group, CreatorId `35420107`, PHJGAMES,
`ATDPlaceRole = Match`, and Edit mode before and after. Only current-branch
mapped source from `match.project.json` may synchronize after a bounded
persistent inventory and mapped-source capture. No map, marker, terrain, model,
setting, unmapped instance, or Team Create content is saved or published.

EnemySimulation remains the single server-only runtime-trigger owner and extends
the Phase 09 trigger into one fixed Phase 10 coordinator; BaseRuntime creates no
second trigger. The trigger exists only while `RunService:IsStudio()` and owns a
closed command set for: one fresh schema-validated fixture install, one base
initialization, the evidence-only PreWave -> WaveActive transition, fixed
server-selected zero/ordinary/exact/high endpoint fixtures and bounded batches,
detached diagnostics, and cleanup probes. The fixture install builds fresh raw
synthetic assets/difficulty/enemy records, validates them through the real
schemas, and uses BaseRuntime's one-shot empty-catalog replacement rule before
any enemy ID or base outcome is issued.

The trigger cannot accept raw health, damage, MatchId, epoch, RuntimeEnemyId,
revision, recipient, result, arbitrary enemy/difficulty definition,
callback/code/property, cadence, or transition target. Every fixture variant and
batch size is a fixed allowlisted token. EnemySimulation destroys this one
trigger first during shutdown; it is absent outside Studio and in Edit mode.

The same endpoint ladder `1, 32, 64, 128` is predeclared. Measurement health is
high enough that the ladder cannot accidentally defeat; the defeat scenario is
separate. Processing time uses a high-resolution local server clock. Client
convergence uses synchronized server time. Programmatic diagnostics record
publication attempts, sender failures, connection/tween counts, assertion
counts, cleanup, identities, revisions, and outcomes. Studio console and
available Stats/MicroProfiler data record errors and relevant engine timing;
engine-connection/tween ownership is not inferred from Stats.

If adding a true late client ends the active server, Phase 10 immediately uses
the established delayed-bootstrap second-client fallback and labels it as such.
Lune proves only deterministic state and adapter behavior; it does not prove
engine UI, Adornee, streaming, tween, or visual behavior.

Studio acceptance requires both clients to converge within 0.5 seconds at every
checkpoint; zero identity/health/revision mismatch; no more than one coalesced
base event per simulation pass excluding direct snapshot responses; exactly one
defeat and Results transition; constant service/controller connections and
tweens; marker/UI removal followed by recreation without server-state change;
future spawn rejection; ascending Defeat cleanup without extra leak damage; zero
Phase 10 console errors; and zero runtime residue after End Session.

## Executed Studio evidence — 2026-08-28

The accepted runs used only the exact connected Match place: PlaceId
`136401514513678`, GameId `10757629094`, CreatorType `Group`, CreatorId
`35420107`, owner `PHJGAMES`, and `ATDPlaceRole = Match`. The task-owned
`match.project.json` connection synchronized only mapped current-branch source.
Every run began and ended in Edit mode; no map, marker, terrain, model, setting,
unmapped instance, Team Create content, save, or publication changed.

The non-defeat measurement initialized authenticated synthetic health at
`1,000,000 / 1,000,000`. The predeclared endpoint ladder converged on both
clients at these exact `(baseRevision, currentHealth)` checkpoints:

| Outcomes | Base revision | Current health |
| ---: | ---: | ---: |
| 1 | 2 | 999999 |
| 32 | 34 | 999967 |
| 64 | 98 | 999903 |
| 128 | 226 | 999775 |

The ladder used five base publications including initialization. A zero-damage
endpoint left revision `226`, health `999775`, and publication count `5`
unchanged. The ordinary fixture produced revision `227`; the low-health fixture
produced revision `228`, current health `249750`, and publication count `7`,
with one low-health crossing, a persistent textual `LOW` state, and visible
damage feedback. The later
stale, duplicate, skipped, out-of-order, and recovery probe ended at revision
`231`, current health `249675`, and publication count `9` without rollback. No
simulation pass emitted more than one coalesced base-state publication.

The measurement run's maximum ordinary client convergence was `0.030816`
seconds. The established delayed-bootstrap active-session fallback recovered
the suspended second client in `0.049293` seconds; this fallback was used because
adding a true late Studio client terminates the local multiplayer server on the
tested Studio build. Both values are below the `0.5`-second requirement. Each
accepted checkpoint had zero MatchId, epoch, map/difficulty identity, health, or
revision mismatches between the server and either client. Each client retained
constant BaseController/BaseWorldView connection ownership of `2/38`; the one
temporary measurement probe was disconnected and did not remain after the
checkpoint. Lifetime BaseWorldView tween creation totals were `8` for Player1
and `7` for Player2. Owned active tweens were `0` while idle and after UI
recreation, bounded at `1` during visible damage feedback, and `0` after client
cleanup; no connection or tween count grew with the `231` processed outcomes.
The world bar used the real
`Workspace.ATDRuntimeMap.Markers.DefenderBase` Part only as Adornee, hid and
rebound across marker removal/restoration, and recreated after GUI deletion
without changing server health or revision.

The measured server simulation-pass maximum was `0.007418` seconds, with p50
approximately `0.0000271` seconds and p95 approximately `0.0000360` seconds.
Exact, overkill, and high-damage defeat scenarios each reached base revision
`3` and Match Results revision `9`, with one defeat, one Results commit, and
closed spawn admission. Each scenario recorded exactly `2` base publications:
the initialized full state and the single coalesced terminal full state. In the
exact scenario, one pre-existing survivor was
the second terminal enemy while only the endpoint enemy leaked; the corrected
run's maximum client convergence was `0.033782` seconds. Post-defeat spawn was
rejected and active-enemy cleanup did not add leak damage.

An earlier instrumented exact-defeat probe exposed one terminal MatchSnapshot
recipient-capture seam: callback admission was already closed before the
broadcaster asked for recipients. The implementation now captures and freezes
the authenticated terminal recipient set during defeat preflight and permits
only that set for the committed terminal snapshot. The focused regression and
corrected exact/overkill/high Studio runs passed. The diagnostic warning from
the discarded probe is not represented as an accepted-run console error.

An offline replay over the immutable accepted Studio MCP response records
executed `804` explicit identity, authority, arithmetic, ordering, convergence,
publication, UI, connection/tween, console, and cleanup assertions with `0`
failures. The discarded diagnostic probe was excluded from that ledger. The
accepted measurement and defeat runs had zero console errors. End Session
removed base state, outcome ledger, result seed, request/recovery state,
feedback, listeners, tween, GUI, trigger, enemies, runtime map, network root, and
caches; no runtime residue remained.

## Cleanup and residue contract

EnemySimulation shutdown first closes all mutation/callback admission,
disconnects its shared connections, destroys the sole combined Studio trigger,
revokes authenticated endpoint outcomes, and clears active enemies, terminal
records, queues, publisher state, request ledgers, and store references. Only
then does BaseRuntime disable snapshot/record/boundary callbacks; clear
publication state, copied outcome ledger, feedback, health, revision, identity,
result seed, clocks, provenance predicate, callbacks, and detached
map/difficulty references; replace its payload with nil; and enter Cleaned.
MatchLifecycle then clears Ready/roster/state/map ownership, and Network destroys
the remote root last.

Client cleanup precedes Ready/map shutdown and removes the base replication and
response listeners, pending request tracker state, marker/UI listeners, active
tween, GUI, Adornee, cached snapshot/feedback, and all
recreation state. Repeated shutdown is a no-op. No captured endpoint, sender,
simulation, response, marker, UI, tween, or Studio-trigger callback can mutate,
publish, or recreate after cleanup.

The final residue check requires no base state, health, result seed, outcome
ledger, queue, listener, UI, tween, connection, runtime trigger, active enemy,
enemy terminal data, network root, runtime map, request record, buffer, visual,
or cache.

## Verification boundary

Focused deterministic tests cover authentic initialization and mutation
isolation; every runtime/lifecycle state; exact, zero, overkill, simultaneous,
and high-damage leaks; duplicate/stale/wrong identity; hostile/nonfinite values;
ledger/revision caps; low crossing; defeat re-entry; callback, sender,
publication, transition, and cleanup faults; spawn closure; ascending Defeat
despawns; one Results transition; replication races/gaps/reconnect; UI state
calculations; marker/view recreation adapters; and mass idempotent cleanup.
Injected clocks/schedulers never wait in real time.

The structural verifier must authenticate every new mapping and source byte,
retain exactly one production Script and one LocalScript in each production
build and zero runnable Test scripts, exclude every spec/fixture/Studio harness
from production, keep Lobby free of Match source and Match free of Lobby source,
prove production `Difficulties`, `Maps`, `Waves`, `Enemies`, and `Assets` remain
empty, reject generated output, and prove no Phase 11 source or behavior began.
The actual final gate passed `593` cases across `48` suites. Default, Lobby,
Match, and Test contain `71/45/71/129` ModuleScripts respectively; production
builds each retain exactly one Script and one LocalScript, while Test has zero
runnable scripts. The registry contains `7` reliable Match-only endpoints
(`4` requests and `3` events) and `4` inbound rate policies.
