# Phase 09 Enemy Simulation and Replication Contract

## Decision status and scope

This is the authoritative Phase 09 architecture decision for server-owned enemy
runtime state, fixed-lane movement, bounded replication, late-client recovery,
and programmatic client presentation. It was recorded before executable Phase
09 source was added. Its focused architecture, security, and performance review
approved implementation after the recorded epoch, capacity, ordering, terminal
delivery, renderer, and measurable-stress corrections were resolved.

At its completed checkpoint, Phase 09 owned only placeholder enemy runtime
records, deterministic movement on the Phase 07 detached lane snapshot, endpoint
outcomes without base damage, replication and recovery, client-created
placeholder visuals, deterministic tests, and an unsaved Match Studio stress
sample. Phase 10 now consumes the existing endpoint seam through the separate
authoritative [Defender Base Runtime and Replication](BASE_RUNTIME.md) contract;
it does not change Phase 09 movement, client enemy replication, or production
enemy content. Phase 11 subsequently adds the separate authenticated finite
[Wave Runtime](WAVE_RUNTIME.md), scheduler-owned spawn admission, difficulty
composition, and terminal attribution while preserving this movement and
replication contract. Phase 12 now adds only separate server Tower records and
inert runtime-owned Models; it does not change enemy movement, ownership,
replication, presentation, or terminal outcomes. Combat, placement, rewards,
persistence, production art/content, and Lobby source remain absent; Phase 13
is unbegun.

`src/shared/config/Enemies.luau` and `src/shared/config/Assets.luau` remain frozen
empty arrays. `docs/TOWER_ENEMY_SCHEMAS.md` is the repository's existing enemy
and symbolic-asset contract; there is no separate `docs/ASSET_MANIFEST.md` at
the Phase 08 baseline.

## Engine constraints and transport decision

Roblox `RunService.Heartbeat` fires after physics with elapsed frame time, and
network/property send follows it. `PreRender` is client-only, runs immediately
before drawing, and supersedes `RenderStepped` for new work. Phase 09 therefore
uses one server `Heartbeat` connection for all enemies and one client
`PreRender` connection for all visuals. It does not change fixed-simulation
place settings or use a per-enemy connection, task, timer, or coroutine.

`RemoteEvent` is asynchronous and non-yielding. Roblox describes
`UnreliableRemoteEvent` as unordered and unreliable and directs callers that
need ordering and reliability to `RemoteEvent`; unreliable payloads over 1,000
bytes are dropped. Phase 09 keeps the existing authenticated reliable
`RemoteEvent` registry. Sequence numbers still detect listener/bootstrap races,
cross-endpoint snapshot races, stale epochs, duplicates, and application gaps.
There is no foundational transport expansion.

`Workspace:GetServerTimeNow()` is a smoothed monotonic approximation of server
Unix time on clients. It aligns presentation samples but never grants client
authority. Server movement consumes only engine-supplied/injected deltas. Clock
sampling is protected and monotonic; presentation clock failure cannot select
or change enemy state.

`PVInstance:PivotTo()` is the primary scripted Model mover and avoids cumulative
inter-part drift on repeated Model moves. `CFrame:Lerp()` linearly interpolates
position and spherically interpolates rotation, but blind world-space lerp cuts
polyline corners. The renderer therefore interpolates authoritative scalar
progress through the bounded segment windows carried by adjacent samples.

Streaming applies to `Workspace`, but client-created instances are exempt from
stream-out unless parented below a server-created instance. Placeholder visuals
live below one client-created direct `Workspace` root, never below
`Workspace.ATDRuntimeMap`. They are anchored and moved directly, so they do not
depend on streamed physics.

Primary Roblox documentation:

- [RunService](https://create.roblox.com/docs/reference/engine/classes/RunService)
- [Task scheduler](https://create.roblox.com/docs/performance-optimization/microprofiler/task-scheduler)
- [Workspace.GetServerTimeNow](https://create.roblox.com/docs/reference/engine/classes/Workspace#GetServerTimeNow)
- [RemoteEvent](https://create.roblox.com/docs/reference/engine/classes/RemoteEvent)
- [UnreliableRemoteEvent](https://create.roblox.com/docs/reference/engine/classes/UnreliableRemoteEvent)
- [Remote events and callbacks](https://create.roblox.com/docs/scripting/events/remote)
- [PVInstance.PivotTo](https://create.roblox.com/docs/reference/engine/classes/PVInstance#PivotTo)
- [CFrame.Lerp](https://create.roblox.com/docs/reference/engine/datatypes/CFrame#Lerp)
- [Instance streaming](https://create.roblox.com/docs/workspace/streaming)
- [Studio testing modes](https://create.roblox.com/docs/studio/testing-modes)
- [StudioTestService](https://create.roblox.com/docs/reference/engine/classes/StudioTestService)
- [Stats](https://create.roblox.com/docs/reference/engine/classes/Stats)
- [MicroProfiler](https://create.roblox.com/docs/performance-optimization/microprofiler)

## Identity, definition, and storage contract

`EnemyId` remains the immutable content identity with the existing `enemy:*`
grammar. `RuntimeEnemyId` is a positive safe integer scoped only by the pair
`(MatchId, enemyEpoch)`. It is not an `EnemyId`, global ID, persistent ID,
secret, or authorization token.

The production Phase 09 service has exactly one non-restartable enemy epoch,
the positive integer `1`, for its unique MatchId. Initialization may occur only
once and cleanup permanently closes that service object; reinitializing it for
the same MatchId is rejected. Tests may inject an epoch in `1..4,096` to prove
replacement behavior. A future design that deliberately replaces the enemy
service while retaining a MatchId must persist and increment that counter,
must never reuse an earlier value, and must fail closed after `4,096`; Phase 09
does not add that restart feature or silently roll over. Recreating the client
controller does not create an epoch. The pair, rather than epoch alone, is the
stale-identity lock.

One enemy epoch has these exact technical ceilings:

| Resource | Limit |
| --- | ---: |
| Active enemies | 128 |
| Lifetime-issued RuntimeEnemyIds | 4,096 |
| RuntimeEnemyId range | 1–4,096 |
| Lanes consumed | 1–32 |
| Route points in one lane | 2–258 |
| Speed modifiers per enemy | exactly one slow multiplier |

The ID allocator starts at `1` and advances by one after each successful spawn.
IDs are ordered numerically, never reused in an epoch, and remain issued after
despawn until epoch cleanup. A generated collision with the issued set fails
closed without skipping, mutation, or reuse. Allocation beyond `4,096` returns
`ID_EXHAUSTED`. A stale ID from an older match/epoch cannot resolve because
every public wire operation is locked to the current `(MatchId, enemyEpoch)`;
server APIs are direct references to the current match-scoped service only.

Definitions come only from an authenticated immutable `EnemySchema` catalog.
The runtime store resolves a server-selected `EnemyId` against that catalog and
never accepts a client definition or caller-owned mutable definition. Current
production receives the already-validated empty catalog, so it is dormant until
production content exists. Phase 11's WaveRuntime is now the sole authenticated
scheduler caller after its one-shot configuration transaction commits.

Headless fixtures build fresh symbolic `EnemyModel` manifests and enemy
catalogs through the real `AssetSchema` and `EnemySchema`. In Studio, Phase 11's
sole combined server-only runtime trigger validates one fresh complete Core
Configuration and installs its exact canonical enemy catalog only while the
store is empty and has issued zero IDs. Raw input is copied, validated, and
discarded; production config files remain empty. The trigger is absent outside
`RunService:IsStudio()`, is inaccessible to clients, owns no arbitrary callback
or code execution surface, and is destroyed on service shutdown.

Immutable definition fields never enter mutable runtime ownership. The strict
runtime record is conceptually:

```luau
type RuntimeEnemyId = number
type EnemyLifecycle = "Active" | "EndpointResolved" | "Despawned"
type SpeedModifiers = { slowMultiplier: number }
type RuntimeEnemy = {
    runtimeEnemyId: RuntimeEnemyId,
    enemyId: Ids.EnemyId,
    laneId: string,
    pathProgress: number,
    currentHealth: number,
    maximumHealth: number,
    speedModifiers: SpeedModifiers,
    spawnServerTime: number,
    lifecycle: EnemyLifecycle,
    revision: number,
    worldCFrame: CFrame,
}
```

Internal records additionally retain only the authenticated immutable
definition and detached frozen lane snapshot required for computation. Under
Phase 11, creation copies `maxHealth * enemyHealthMultiplier` and
`moveSpeedStudsPerSecond * enemyMoveSpeedMultiplier` exactly once into the
record; later slows multiply only that record-owned adjusted speed. Leak damage
and every authored definition remain unchanged. Records retain no Player,
Instance, marker, map Model, client object, visual, connection,
timer, or coroutine. At the Phase 09 checkpoint health initialized exactly to
definition `maxHealth`; Phase 09 itself exposed no difficulty composition,
damage, or healing operation. The sole status representation is a
server-owned finite `slowMultiplier` in `[0, 1]`, initially `1`. Zero means
fully stopped. This is not a general status-effect framework and has no expiry
timer, resistance, stacking, source, combat, or client mutation path.

Active storage is keyed by RuntimeEnemyId. Issued IDs and terminal outcome
markers remain separately bounded until cleanup. Queries return newly allocated,
deeply frozen, Instance-free snapshots sorted by ascending RuntimeEnemyId.
Definition, lane, record, status, query, and caller mutation cannot cross the
ownership boundary.

The legal lifecycle is:

```text
spawn commit -> Active -> Despawned
                       -> EndpointResolved -> Despawned
```

There is no transition out of `Despawned`, no endpoint re-entry, and no spawn
rollback that exposes a partial record. Duplicate spawn requests receive a new
identity only when every new spawn precondition succeeds; a caller cannot supply
an ID. Duplicate endpoint resolution or despawn is a no-op rejection. Mass
cleanup terminalizes and releases all remaining records without publishing one
despawn per enemy, and repeated cleanup is idempotent.

## Detached map integration and lifecycle order

`MatchLifecycle` remains the only owner of the Phase 07 `MapLoader`. It retains
the successful already-loaded `RuntimeMapSnapshot` and exposes one narrow
server-only `getRuntimeMapSnapshot()` Result that returns that same detached,
deeply frozen, Instance-free value. It never returns the loader, template,
runtime Model, markers, tags, or a mutable cache. No second map is loaded.

The Phase 09 Match composition registered:

```text
initialize/start: NetworkRegistry -> MatchLifecycle -> EnemySimulation
shutdown:         EnemySimulation -> MatchLifecycle -> NetworkRegistry
```

`EnemySimulation` depends on both `NetworkRegistry` and `MatchLifecycle`. Its
initialization captures only the authenticated empty enemy catalog, immutable
MatchId/epoch, and detached runtime-map snapshot. Its shutdown first makes spawn,
snapshot, update, and publication callbacks unavailable; disconnects the one
update connection and any service-level test/removal connections; clears
replication assemblies, queues, and request counters; clears the runtime store;
and destroys its Studio-only trigger. Only then may `MatchLifecycle` clean its
MapLoader and `Workspace.ATDRuntimeMap`.

Phase 10 inserted BaseRuntime before EnemySimulation. Phase 11 now appends
WaveRuntime and uses this current order:

```text
initialize/start: NetworkRegistry -> MatchLifecycle -> BaseRuntime -> EnemySimulation -> WaveRuntime
shutdown:         WaveRuntime -> EnemySimulation -> BaseRuntime -> MatchLifecycle -> NetworkRegistry
```

Wave cleanup closes and detaches the scheduler boundary before EnemySimulation
clears the one Heartbeat, active Store state, publisher, terminal authenticators,
and sole Studio trigger.

No Phase 09 code invokes a match-state transition. Production remains dormant
because the canonical production catalogs are empty. Phase 11 now owns the only
narrow authenticated `PreWave -> WaveActive` scheduler transaction; this does
not give EnemySimulation a lifecycle transition API.

## Movement and numeric policy

Movement uses analytic variable-delta distance integration on one bounded
Heartbeat pass. This is deliberately not a fixed-step accumulator:

- update cadence is the server Heartbeat cadence;
- tests call the same injected `step(deltaSeconds)` seam directly;
- catch-up step count is exactly zero;
- one accepted frame visits each ID present in the ascending start-of-frame ID
  snapshot at most once;
- a large finite delta is consumed in that one pass instead of replaying missed
  frames; and
- correction publication coalesces current state rather than replaying missed
  network sends.

`deltaSeconds` must be a finite number at least zero. A wrong type, NaN,
infinity, or negative/backwards delta is rejected before clock sampling or
mutation. Zero is an accepted no-op. The synchronized server clock is sampled
once at initialization and once per nonzero accepted update. A throwing,
wrong-type, nonfinite, negative, or backwards sample faults the service before
that frame mutates progress or queues. Faulting disconnects the update path and
closes spawn, slow, and manual-despawn admission, but it does not discard or
suppress already committed replication. The bounded publisher may drain its
existing queue; cleanup remains available and idempotent.

For one active enemy:

```text
effectiveSpeed = definition.moveSpeedStudsPerSecond * slowMultiplier
remaining = lane.totalDistance - pathProgress
```

Both definition speed and multiplier are already finite; the multiplier is at
most one. If effective speed is zero, progress is unchanged. Otherwise the
implementation compares `deltaSeconds` with `remaining / effectiveSpeed` first.
If the delta reaches or exceeds that duration, progress becomes exactly
`lane.totalDistance`. Only when it does not reach the endpoint is
`effectiveSpeed * deltaSeconds` evaluated; that product is then bounded by the
finite remaining distance. This handles huge finite speed/delta without
overflow, unbounded segment walking, or lost overshoot.

`pathProgress` is cumulative studs clamped to `[0, lane.totalDistance]`.
MapLoader points are already ordered spawn → nodes → base and carry strictly
increasing cumulative distances. Segment lookup is a bounded binary search.
At progress zero the first segment tangent applies. At an exact interior corner,
the outgoing segment tangent applies. At the endpoint, the final incoming
tangent applies. A multi-segment update samples only the final cumulative
progress; it never iterates once per crossed segment.

Position is Euclidean interpolation between the selected segment endpoints.
Facing is reconstructed from the normalized current route tangent, never from
marker rotation. World `Vector3.yAxis` is the preferred up vector; when the
tangent is within `1e-6` of parallel, `Vector3.xAxis` is the fixed fallback.
The resulting deterministic `CFrame.lookAt` policy is shared by spawn, exact
corners, corrections, snapshots, and endpoint outcomes.

Distance/progress comparisons use a scale-aware tolerance of
`max(1, lane.totalDistance) * 1e-9`; position comparisons use `1e-6` studs.
Studio transport measured a maximum `0.00003069639205932617` rotation-component
change when a reliable RemoteEvent carried the real diagonal-lane CFrame. Wire
validation therefore keeps position at `1e-6`, permits rotation-component drift
only through an explicit `1e-4` transport tolerance, revalidates the advertised
tangent, and canonicalizes the accepted CFrame from authenticated segment data.
Accepted partitionings of the same elapsed time are equivalent within the
movement tolerances until the same exact endpoint clamp. No backwards progress
API exists.

## Endpoint outcome and despawn semantics

Endpoint arrival performs one atomic terminal sequence:

1. set progress to exact `lane.totalDistance` and sample the endpoint CFrame;
2. transition `Active -> EndpointResolved` and increment the enemy revision;
3. capture one detached frozen endpoint snapshot and mark the endpoint outcome
   issued before invoking the future-facing callback;
4. invoke the one injected server callback at most once in a fresh coroutine,
   resume it exactly once, and treat either an error or a suspended/yielded
   coroutine as a contained callback fault (closing the coroutine when needed);
5. transition `EndpointResolved -> Despawned`, increment revision, queue the
   terminal state/despawn records, and remove active state; and
6. if the callback failed or attempted forbidden re-entry, close further
   mutation admission only after the enemy is terminal. Terminal publication
   remains enabled, so a callback fault cannot strand or resurrect the client
   visual.

At Phase 09 completion the production callback was a no-op success. Phase 10
replaces that composition seam with one synchronous, non-yielding BaseRuntime
sink. `EnemyRuntimeStore` creates a detached frozen authenticated outcome only
after an immutable validated definition reaches the endpoint; it contains the
bound MatchId, enemy epoch, runtime enemy ID, EnemyId, copied server-derived
`leakDamage`, and server time. No damage field enters client enemy replication.
The store issues and authenticates the outcome before invoking the sink, then
always finishes the current enemy's terminal transaction before
EnemySimulation processes any defeat work at its next safe boundary. Duplicate,
stale, foreign, revoked, or unauthenticated outcomes cannot replay base damage.

Phase 11 adds a distinct detached frozen scheduler terminal outcome for every
`Endpoint`, `Manual`, or `Defeat` terminal record. It contains only MatchId,
enemy epoch, RuntimeEnemyId, EnemyId, reason, and the Store-owned server sample;
the authenticated leak outcome above remains the only Base-damage authority.
EnemySimulation copies bounded terminal facts to WaveRuntime only after Store
mutation has ended, so the Wave sink cannot re-enter EnemyRuntimeStore.

If a Wave callback throws after the scheduler capability has already committed
a spawn, EnemySimulation retains the exact committed `{ event, outcome }` for
that pass. After the callback returns, outside any Store mutation and while the
authenticated scheduler sample remains live, the narrow Store
`despawnScheduledForFault` transaction authenticates that exact spawned
snapshot, removes the active record, and issues one `Manual` terminal outcome.
EnemySimulation defers Wave's one-shot dependency-fault close until its own
operation-active guard has cleared, then passes the committed pair plus that
terminal outcome. Store active count is zero for that enemy, and Wave reconciles
the cursor, originating ownership, counters, and terminal resolution once before
exposing `Faulted`. A callback failure before Store commit carries no pair.
Re-entry, forged identity/sample, conflicting replay, publisher
preflight/commit failure, and cleanup races remain closed and cannot admit
another mutation.

Spawn, slow, manual despawn, endpoint resolution, and nested step operations
reject mutation re-entry. Cleanup is the sole exception: a cleanup request made
during an update or endpoint callback sets one private `cleanupRequested` flag
and returns without clearing live data. The current enemy completes its atomic
terminal sequence; at the next safe update boundary, the service skips every
remaining start-of-frame ID and performs normal cleanup exactly once. Since
this path is whole-service shutdown, queued messages are then discarded only
after the publisher and listener have been disabled. No callback can mutate a
second enemy, publish after cleanup, or observe a half-cleared store.

## Production network contract

Phase 09 adds exactly two Match-only reliable definitions beneath the existing
`ReplicatedStorage.ATDNetwork.v1` owner:

| Endpoint | Direction/kind | Exact purpose | Response |
| --- | --- | --- | --- |
| `GetEnemySnapshot` | client-to-server Request | exact empty `{}` recovery request | required bounded snapshot receipt |
| `EnemyReplication` | server-to-client Event | one tagged enemy message | none |

`GetEnemySnapshot` has exact token-bucket capacity `2` and refill `0.25` per
second. In addition, the enemy service accepts at most two snapshot requests per
actual Player connection. A weak Player-key counter cannot retain a departed
Player; one service-level `PlayerRemoving` connection removes its entry. The
dispatcher remains the sole inbound path and supplies exact envelope/schema
validation, token limiting, correlation, actual-Player context, non-yielding
protected execution, response validation, origin-only response, and privacy-safe
errors. The empty request selects no enemy, lane, identity, state, progress,
transform, health, speed, time, transition, or recipient.

The sole outbound event is a strict tagged union with these logical kinds:

- `SpawnBatch`
- `CorrectionBatch`
- `StateChangeBatch`
- `DespawnBatch`
- `SnapshotBegin`
- `SnapshotChunk`
- `SnapshotEnd`

All four delta batches are exact records
`{ kind, matchId, enemyEpoch, sequence, entries }`. Spawn, correction, and state
entries use the same self-contained `EnemyStateEntry`; their distinct tags
describe why the authoritative mutation was published, not a partial merge
format. The exact entry fields are:

```text
runtimeEnemyId, enemyId, laneId, revision, lifecycle,
pathProgress, currentHealth, maximumHealth, slowMultiplier,
spawnServerTime, sampleServerTime, worldCFrame, effectiveSpeed,
segmentIndex, segmentStartDistance, segmentEndDistance,
segmentStartPosition, segmentEndPosition
```

Snapshots contain active `EnemyStateEntry` values only. `DespawnEntry` is the
exact record `{ runtimeEnemyId, revision, sampleServerTime, reason }`, where
reason is `Manual` or `Endpoint`. Snapshot records are exactly:

```text
Begin = { kind, matchId, enemyEpoch, baseSequence, snapshotId,
          chunkCount, totalEntries }
Chunk = { kind, matchId, enemyEpoch, baseSequence, snapshotId,
          chunkIndex, entries }
End   = { kind, matchId, enemyEpoch, baseSequence, snapshotId,
          chunkCount, totalEntries }
Receipt = { matchId, enemyEpoch, baseSequence, snapshotId,
            chunkCount, totalEntries }
```

The tagged schema rejects extra fields, malformed tables, metatables, cycles,
Instances, and oversized arrays before client mutation. Its numeric and string
domains are exact:

| Field | Domain |
| --- | --- |
| enemy epoch | safe integer `1..4,096` |
| RuntimeEnemyId | safe integer `1..4,096` |
| enemy revision / delta sequence | safe integer `1..9,007,199,254,740,991` |
| snapshot base sequence | safe integer `0..9,007,199,254,740,991` |
| snapshot ID | safe integer `1..16` |
| chunk index/count | index `1..16`; declared count `0..16` |
| entry counts | each array `0..8`; total `0..128` |
| EnemyId / lane ID | authenticated ID; lane string `1..64` bytes |
| progress / segment distances | finite `0..32,768`, with semantic lane bounds |
| health | finite current `0..maximum`; maximum greater than zero |
| slow / time / effective speed | slow `[0,1]`; finite times/speed at least zero |
| segment index | safe integer `1..257`, semantically present in the lane |
| positions / CFrame | finite; position components in `[-100,000,100,000]`; canonical orientation |

Segment start is strictly below segment end, the entry progress lies in the
advertised window, and `worldCFrame` must equal the canonical route sample. The
wire check uses exact `1e-6` position tolerance and the recorded `1e-4`
rotation-component transport tolerance; accepted values are replaced with the
canonical route CFrame before client state can observe them. Server emitters
construct these values only from authenticated records; client validation
repeats the structural, finite, range, tangent, and CFrame-component checks
before staging a message. No message contains a Player, recipient, map Instance,
marker, visual, definition table, caught error, or private state.

Exact replication bounds are:

| Resource | Limit |
| --- | ---: |
| Entries in one delta or snapshot chunk | 8 |
| Snapshot chunks / active snapshot entries | 16 / 128 |
| Current snapshot assembly per client | 1 |
| Buffered delta messages per client | 32 |
| Pending causal entries | 3 per represented ID / 384 total |
| Publication cadence | one flush opportunity per 0.1 seconds |
| Delta messages emitted in one flush | 12 |
| Current broadcast recipients | 4, sorted by UserId |
| Lifetime delta messages in one service epoch | 131,072 |
| Lifetime snapshot messages | 160 |
| Snapshot requests per Player connection | 2 |
| Client snapshot attempts per controller lifetime | 2 |

The shared payload validator retains its stricter global depth `8`, node `512`,
record-field `64`, array-item `128`, and string-byte `1,024` ceilings. Eight
entry chunks fit beneath the node limit; snapshot chunking prevents active count
from widening the foundation.

Each mutating server API samples the authoritative clock once; a nonzero step
samples once and gives every mutation in that pass the same time. Every
committed enemy mutation increments that enemy's revision exactly once and
receives a private global mutation ordinal. Spawn starts at revision `1`; spawn
time never changes. A movement correction, slow change, endpoint transition,
and despawn each have distinct increasing revisions and their operation's
sample time. Sequence is separate: it increments once only when a delta batch
is emitted. Snapshot capture never advances sequence.

Each represented ID owns a causal chain of at most three pending entries. An
unpublished spawn absorbs later active corrections/state into its full state.
After spawn publication, at most one full state change and its later correction
remain: a newer full state subsumes an older correction, while a later
correction stays after that state. Terminalization drops obsolete active
corrections, then retains endpoint state when applicable and the later despawn.
Thus a slow-state revision followed by movement has two different revisions and
cannot lose the later correction under strict client revision checks.

The publisher walks the smallest mutation ordinal globally, breaking an
impossible ordinal tie by RuntimeEnemyId and then kind, and batches only
consecutive same-kind entries in ascending causal order, eight at a time. It
never drains all spawns before older terminal records. Moreover, while any
departed ID has pending terminal data, spawn admission is closed with
`CAPACITY_EXCEEDED` until that data drains. This preserves the client/server
128-ID bound during full-cap replacement churn while still guaranteeing spawn
before terminal data for one rapidly resolved ID. The `3 * 128 = 384` chain
bound is structural; a would-be 385th entry is rejected before server mutation,
while coalescible active state replaces its owned slot.

Each accepted spawn conservatively reserves three future delta-message and
sequence slots: spawn, possible endpoint state, and despawn. Admission requires
those slots in both the `131,072` message budget and safe-integer sequence
space. Corrections publish only from unreserved capacity and otherwise remain
coalesced at their latest state. Used reservations are released on emission;
unused endpoint-state capacity is released after a manual despawn. This makes
terminal delivery possible for all 4,096 accepted lifetime IDs even at the
ordinary-message ceiling. Exhausted admission returns a privacy-safe
`CAPACITY_EXCEEDED` before assigning an ID; sequence never rolls over.

Twelve messages are drained per cadence; remainder stays in the fixed queue.
There is no retry queue or delivery ledger. Sender failure is contained: other
recipients continue, the logical sequence remains consumed, and that client
detects a later gap and recovers by snapshot.

Snapshot delivery is recipient-specific and synchronous inside the bounded
request handler. It captures active entries and the current delta base sequence,
sends `Begin`, ascending chunks, and `End` through the same outbound event, then
returns a small receipt naming the snapshot ID/base/counts. A partially sent
snapshot is never applied because `End` and all declared chunks are required.
Cross-RemoteEvent response/event order is irrelevant. Before `Begin`, the
handler reserves the exact `2 + ceil(active / 8)` messages from the 160-message
snapshot budget; if unavailable, it rejects the whole request without sending a
partial snapshot. Attempted sends consume that reservation even when the sender
fails. Snapshot IDs start at `1`, never repeat in the service epoch, and reject
the seventeenth request before sending; the ID and message budgets are both
checked.

Broadcast recipients are the current values of `Players:GetPlayers()`, sorted
by UserId and bounded by the configured four-player Match cap. The inbound
snapshot caller must be the actual Player supplied by the dispatcher and still
be parented to `Players`; it need not be in the Phase 08 ready roster because a
true late join or spectator still requires public match presentation. A caller
cannot choose another recipient. Player removal clears the weak request counter;
reconnect receives a new controller and counter without retaining the old
Player Instance.
More than four current Players is a composition invariant fault; the publisher
does not choose an arbitrary subset.

## Client convergence policy

The client connects the replication-event listener and snapshot-response
listener before its first request. Before one complete snapshot locks identity,
it buffers at most 32 valid deltas. A completed snapshot for
`(MatchId, enemyEpoch)` at base sequence `S` atomically replaces all client
enemy state, records every included enemy revision, discards buffered messages
at `<= S`, and applies only contiguous buffered sequences above `S`.

After lock, only sequence `last + 1` can mutate. Equal/older values are duplicate
or stale and ignored. A higher value creates a gap: it and later bounded values
are buffered without mutation and one recovery is requested if available.
Buffer overflow clears the buffer, preserves the last converged state, and
requires recovery. A snapshot/delta entry can update an enemy only with a
strictly greater enemy revision. A snapshot may contain an active enemy whose
queued spawn has not yet received a publication sequence. Its later contiguous
`SpawnBatch` is therefore idempotent only while that same ID remains active and
untombstoned: the client consumes the sequence, merges a strictly newer
revision, otherwise keeps the snapshot state, and counts only genuinely unseen
IDs against the active cap. A seen-but-inactive or tombstoned ID still forces
recovery and can never be resurrected. A despawn records a terminal tombstone
for that RuntimeEnemyId; no later spawn/correction/state entry in the same epoch
can resurrect it. Tombstones are bounded by the 4,096 lifetime ID ceiling and
clear only on epoch replacement or controller cleanup.

Only a complete snapshot may replace a locked MatchId/epoch. Foreign deltas do
not replace it. A new-epoch snapshot clears records, tombstones, samples,
visuals, pending chunks, and buffered deltas before installing its state. A
new controller after reconnect starts unlocked with fresh request bounds.

Snapshot response arrival before event chunks is safe. The controller retains
one bounded receipt deadline using its existing single render loop rather than
starting a timer. If the declared snapshot is incomplete after two seconds, it
discards the assembly and uses its one remaining attempt. Exhaustion freezes at
the last converged state and cannot invent or roll back authority.

## Renderer and interpolation contract

One Match-only `EnemyController` owns the replication store and one
`EnemyRenderer`. It is a lifecycle service ordered after
`MatchReadyController`; reverse client shutdown therefore stops rendering and
enemy listeners before the ready controller and bootstrap owners.

The renderer creates one client-owned Folder named `ATDEnemyVisuals` directly
under `Workspace`. Each active RuntimeEnemyId owns exactly one Model made from
three primitive smooth-plastic Parts (head, thorax, abdomen). There is no asset
ID, mesh, uploaded content, Studio-authored enemy, animation, sound, effect,
health bar, or UI. Every Part is anchored, massless, non-colliding,
non-touching, non-querying, and shadowless. Visuals contain no authoritative
state. Phase 09 deliberately does not pool: despawn destroys the exact Model;
the 128-model ceiling bounds allocation and cleanup.

At each `PreRender`, the renderer reads one detached client snapshot and updates
all IDs in numeric order. Render time is protected synchronized server time
minus `0.15` seconds. Between two samples, scalar progress/time is interpolated.
If the resulting progress lies in either adjacent sample's authenticated segment
window, the renderer samples that straight segment and uses its tangent; this
preserves an exact shared corner instead of cutting it with world-space lerp.
At the exact shared corner it deliberately selects the newer/outgoing segment
tangent; at the route endpoint it retains the final incoming tangent. A
multi-segment unknown gap or malformed time relation snaps to the current
authoritative sample.

After the newest sample, extrapolation uses server-owned effective speed on the
current segment for at most `0.1` seconds and never passes its segment end.
Clients do not select speed, lane, progress, or the next segment. There is no
extrapolation before the oldest sample.

On a new authoritative sample, positional error below `0.25` studs is accepted
without a correction offset. Error from `0.25` up to but not including `8`
studs preserves the current displayed position as an offset and decays it
linearly to zero over `0.2` seconds. Error at least `8` studs, an epoch/identity
replacement, a segment gap, or a nonfinite presentation sample snaps
immediately. Rendered progress never changes client authority.

The one render pass recreates a missing visual or missing client root from the
detached converged state. A visual is missing when its Model, any of its three
required primitive Parts, its expected parent, or its fixed non-authoritative
Part properties is absent/invalid; the renderer destroys that damaged owned
Model and recreates all three Parts rather than retaining a partial visual.
Correctly parented client-created visuals are exempt from normal stream-out;
explicit recreation also covers local destruction or other presentation loss.
Renderer reset, despawn, snapshot replacement, epoch
change, LocalScript destruction, and lifecycle shutdown remove exact owned
visuals/root and clear all caches once. Repeated cleanup is a no-op and a
captured post-clean callback cannot recreate anything.

## Studio-only runtime trigger and safety

The exact Match place is the only Studio target: PlaceId `136401514513678`,
GameId `10757629094`, CreatorType `Group`, CreatorId `35420107`, PHJGAMES,
resolved role `Match`, and Edit mode before/after. Only `match.project.json`
may synchronize current-branch mapped source. Persistent roots and exact mapped
Script.Source values are captured before sync. No source is edited manually in
Studio; no Script Sync, map mutation, save, publish, setting change, Lobby test,
or unrelated instance change is allowed.

In Studio only, `EnemySimulation` owns one server-only BindableFunction beneath
`ServerStorage` with a fixed private development name. At the Phase 09
checkpoint its exact operations installed one validated enemy catalog and drove
server-selected spawn/slow/despawn evidence. Phase 11 migrates the same sole
trigger into one combined, fixed-operation Wave harness: it validates one fresh
complete configuration, admits only the server-selected authored fixture and
bounded evidence operations, and revokes the legacy spawn facade after commit.
Inputs pass the same strict server validation and fixed bounds. It cannot accept
client-selected match, base, recipient, remote payload, map, module, callback,
code, or arbitrary property. It is created at runtime, destroyed at shutdown,
and absent from Edit mode and production servers.

## Predeclared Studio late-client and stress gate

The target is the connected Windows desktop Studio build reported at execution,
one local Match server, and two desktop simulated clients. No engine smoothness
claim comes from Lune.

True late-client procedure:

1. start Server & Clients with one client;
2. install the validated runtime-only definition and spawn 16 enemies on the
   real authored bent lane;
3. allow at least three seconds of authoritative progress;
4. from the active Server DataModel call `StudioTestService:AddPlayers(1)`;
5. require the new client to lock the same MatchId/epoch, complete its snapshot,
   and converge to the first client's active ID/revision set while the first
   client continues receiving deltas; and
6. record request count, snapshot ID/chunks/base sequence, convergence time, and
   zero resurrection/stale rollback.

The connected build must first prove `AddPlayers` exists and is callable in an
active multiplayer server. If that API is unavailable, the explicitly labeled
fallback is an active two-client session in which the second client's enemy
controller bootstrap is delayed until enemies have progressed. That proves the
listener/snapshot race but is not called a true join.

Stress uses the real single authored lane without modifying or saving it. The
ladder is `1, 32, 64, 128` active enemies (1, 25%, 50%, and 100% of the cap).
Each rung begins from a converged cleared set, then has two seconds of warm-up
followed by ten measured seconds, for 48 warm-up/measured seconds total. Stress
definition speed is `4` studs/second so the real route retains every rung's
declared active count for the full 12 seconds; endpoint travel is exercised in
a separate speed-12 traversal. Health is inert.
The harness records actual server/client sample counts, p50/p95/max pass times,
available `Stats` frame/network/memory values, correction errors, active/visual
counts, sequences, sender failures, endpoint outcomes, connection counts,
assertions, and console errors. `debug.profilebegin/end` labels the one server
simulation pass and one client render pass.

Acceptance criteria:

- server simulation p95 at most 8 ms and max at most 16 ms;
- each client render pass p95 at most 12 ms and max at most 25 ms;
- client frame-time p95 at most 33.4 ms when the runtime-readable Stat is
  available, otherwise the missing Stat is recorded rather than invented;
- post-policy visual error never exceeds the 8-stud snap threshold and the
  pivot-to-computed-target residual after a render pass is at most 0.05 studs;
- both clients have exactly the server's active RuntimeEnemyId set after each
  convergence point, with visual count equal to active count;
- exactly one enemy-service Heartbeat connection and one enemy-render PreRender
  connection per client at every rung, independent of enemy count;
- endpoints/despawns occur once, with unchanged base/Results behavior;
- no error/warning attributable to Phase 09, no unbounded queue, and no
  post-clean callback; and
- after End Session, enemy connections are zero and no enemy record, issued-ID
  set, outcome, queue, chunk, request counter, test trigger, visual root, Part,
  remote root, runtime map, timer, UI, or cache remains.

MCP Luau execution is primary for setup, assertions, metrics, console inspection,
and cleanup. Limited UI control is used only if MCP lacks Server & Clients,
client focus, late-player, or visual-observation controls. All clients/server
are stopped, task-owned Rojo is disconnected, emulation/profiling state is
reset, and Studio is left in Edit mode without saving or publishing.

## Executed Studio evidence — 2026-08-27

The accepted run used the exact connected Match place and Windows desktop Studio
installation `version-dcbeee682ce74ee0`, one local server, and two simulated
clients. Identity was rechecked before and after: PlaceId `136401514513678`,
GameId `10757629094`, CreatorType `Group`, CreatorId `35420107`, visible owner
PHJGAMES, and `ATDPlaceRole = Match`. Only current-branch `match.project.json`
source was synchronized. The saved 25-record graybox catalog remained unchanged;
there was no map edit, manual Script.Source edit, Script Sync, save, or publish.

`StudioTestService:AddPlayers(1)` existed and the active-server call returned,
but this Studio build ended the multiplayer server and disconnected the existing
client instead of adding a late client. That attempt is not claimed as a true
late join. The declared active-session fallback was therefore used in a fresh
two-client session: Player 2's controller recovery was suspended before 16
server-owned spawns, the enemies advanced for three seconds to
`11.9991526119411` studs, and Player 2 then resumed through the existing
authenticated empty snapshot request. It converged in
`0.16652670002076776` seconds at enemy sequence `56`, with 16 authoritative
entries, 16 visuals, no buffered gap, one render connection, and two lifetime
snapshot attempts. Player 1 stayed converged throughout.

The live ordering injection proved stale sequence `55` and duplicate sequence
`56` were ignored, sequence `58` waited for missing `57`, and the authenticated
snapshot path recovered the gap. Both clients converged at sequence `64` with
the same 16 IDs/revisions/progress values. Runtime ID `16` then despawned once;
a duplicate despawn returned `ILLEGAL_LIFECYCLE`, and an older correction could
not resurrect it. Destroying Player 1's visual for ID `1` recreated one exact
three-Part model without changing the server's 16 active records.

The separate speed-12 endpoint enemy traversed the real five-point bent lane in
`9.565340995788575` seconds. The terminal count increased exactly from `16` to
`17`; active count became zero; a repeated manual despawn returned
`STALE_RUNTIME_ID`; both clients reached sequence `160` with zero entries and
zero visuals; Ready UI stayed `PreWave`; and no base health, Results state, or
wave progression occurred. The two visual motion samples observed two real route
turns, maximum individual pivot steps `2.219654083251953` and
`2.1900634765625` studs, and zero final pivot residual.

The accepted increasing-count ladder used two seconds of warm-up plus ten
measured seconds at each rung. Every server row contains 601 simulation samples;
client rows show `{p50 / p95 / max}` render-pass milliseconds:

| Active | Server `{p50 / p95 / max}` ms | Player 1 `{p50 / p95 / max}` ms | Player 2 `{p50 / p95 / max}` ms |
| ---: | ---: | ---: | ---: |
| 1 | `0.0399 / 0.2558 / 0.8079` | `0.0833 / 0.1135 / 0.3352` (150) | `0.0816 / 0.1048 / 0.1955` (150) |
| 32 | `0.1481 / 2.6609 / 3.7279` | `0.9972 / 1.4166 / 1.7170` (150) | `1.0024 / 1.3758 / 1.5714` (150) |
| 64 | `0.2519 / 4.7050 / 6.5431` | `1.9511 / 2.5769 / 3.2257` (150) | `2.0418 / 2.7853 / 3.2785` (151) |
| 128 | `0.5448 / 7.7824 / 10.6230` | `3.4835 / 4.4726 / 5.4417` (150) | `3.7056 / 4.9146 / 5.9445` (151) |

Every rung retained one server simulation connection and one client render
connection, exact active/entry/visual counts, no buffered recovery gap, and zero
sender failures. At 128, each client owned exactly 128 Models and 384 anchored,
massless, non-colliding, non-touching, non-querying Parts below a direct
`Workspace.ATDEnemyVisuals` root, never below `ATDRuntimeMap`. Total client
memory samples were `1692.293` and `1737.250` MB. Maximum observed correction
errors over the complete session were `4.551680088043213` and
`4.585128784179688` studs, both below the 8-stud snap threshold; maximum
post-pivot residual was zero.

LibMP captured 256 foreground frames per client at the 128-enemy rung. Player 1
frames `1..256` / absolute `61971..62226` measured
`16.707 / 17.669 / 18.217` ms p50/p95/max; Player 2 frames `1..256` / absolute
`61919..62174` measured `16.643 / 17.466 / 18.035` ms. Both satisfy the
33.4-ms frame-p95 criterion. Capture buffers were `5,794,128` and `5,794,280`
bytes and were disposed; capture, profiler UI, and device emulation were reset.

The accepted evidence folder reached 388 successful runtime assertions,
including bounded exploratory reruns used to correct the client capture timing;
the final rungs above replaced those exploratory measurements. Each client
console contained only the two expected configuration/bootstrap info records and
no warning/error. Final live cleanup removed 128 active records and reached
server active/pending/dirty/sender-failure counts `0/0/0/0`; both clients reached
zero entries, visuals, descendants, and buffered deltas before their test-only
watchers and evidence folder were destroyed. End Session then removed the visual
roots, enemy trigger, network root, runtime map, timers, caches, UI, and every
service connection. The task-owned Rojo server stopped, its port closed, all
simulated windows closed, and Studio remained in Edit mode with zero runtime
residue. The three pre-existing user Rojo servers were not touched.

## Phase 11 scheduler integration evidence — 2026-08-28

The accepted Phase 11 sessions reused EnemySimulation's real one-Heartbeat
boundary, Store, publisher, endpoint/Base seam, and both client renderers. The
primary finite run (`match:67f2240b-1636-4073-a667-a6d0e6fc0184`) verified
that each scheduler-owned spawn received the exact authenticated health and
movement products once. The overlap run
(`match:b3f75fcb-cdc4-4db7-8818-0ae6ef555491`) retained old scheduled work,
active enemies, and originating-wave attribution across a later wave start.

The due-spawn ladder used exact MatchIds
`match:6555b115-c5f7-428b-9190-091d7ffde547` (1),
`match:f0856bed-d155-496c-ac0d-a9b136e07738` (32 measurement),
`match:20bf272c-993c-4782-9ec1-4c880c7e3f12` (64), and
`match:5344703b-2de0-4f84-a86f-db976a4a7281` (128). Every rung was at or
below WaveRuntime's explicit `128`-spawn per-pass bound, preserved stable
authored ordering, spawned nothing early, and retained constant Enemy service
and controller connection ownership. The separate real-WaveReplication
recovery/order session used
`match:39dde4e4-2dc2-48e8-8e58-8862c2b7155a`.

The lethal run (`match:0c0771bc-82b5-40bb-a13a-9ef04026f874`) allowed one
scheduled enemy to leak, then closed the later `+2` and `+3` spawns, removed
active state, and reached Wave `DefeatClosed`, Base `Defeated`, and Match
`Results` at revisions `3/3/9`. It recorded exactly one defeat and one Results
transition, with zero finite completions. Both clients converged in
`0.0344388485` and `0.0335118771` seconds. Accepted Phase 11 sessions had zero
console errors and ended without Enemy records, visuals, terminal data,
callbacks, trigger state, connections, or other runtime residue.

## Verification and completion boundary

Headless tests use injected clocks, deltas, schedulers, senders, connections,
and visual adapters; they never wait real time. They prove runtime IDs and caps,
definition provenance/mutation isolation, lane binding, numeric movement,
corners/overshoot, slows, endpoint exact-once, replication bounds/convergence,
snapshot races/gaps, renderer interpolation/correction/recreation, constant
connection ownership, and idempotent mass cleanup. Synthetic fixtures prove
multiple lanes; Studio uses only the real authored one-lane graybox.

At the Phase 09 checkpoint, the structural verifier authenticated all
mappings/source bytes, retained exactly one Script and one LocalScript per
production build and zero runnable Test scripts, excluded every
spec/fixture/Studio harness from production, kept Lobby free of Match source and
Match free of Lobby source, proved production `Enemies`/`Assets` remained empty,
and rejected Phase 11 source or behavior.
Phase 11's verifier now authenticates the Wave-owned extension while preserving
the same empty production catalogs, test exclusion, project isolation, and
runnable-script constraints. Current module/suite/test counts are recorded only
from the actual final run.

The consolidated independent review found no P0, one P1, and one P2. The P1
snapshot-covered-spawn race now consumes later queued spawn sequences
idempotently while preserving newer revisions and tombstone non-resurrection;
the new 128-enemy integration regression crosses two bounded spawn flushes and
continues through sequence `32`. The P2 stale H-06 record was reconciled. The
same reviewer confirmed both findings resolved.

The complete local gate passes `467` tests across `39` suites. The Phase 09
subset is `120` cases across `11` suites. Structural verification passes Default
`63/1/1`, Lobby `44/1/1`, Match `63/1/1`, and Test `111/0/0`; Test contains 35
authoritative shared modules, 25 exact production mirrors, and 51 test-owned
modules. Formatting, lint, diff, scope, generated-output, exact remote/rate
catalogs, production-test exclusion, Lobby/Match isolation, empty production
`Enemies`/`Assets`, and the then-unbegun Phase 10/11 boundary all passed.

Packets 09.1–09.5, Studio, review, local, and structural gates are complete on
2026-08-27. The exact-final-SHA Repository Verification run and zero-artifact
result are cited at handoff rather than through a self-referential evidence
commit. Phase 09 is complete. Phase 10 subsequently implemented its separately
reviewed endpoint consumer and passed focused and exact Studio checks on
2026-08-28; its final all-repository/CI record is maintained in
`docs/BASE_RUNTIME.md`. Phase 11 subsequently implemented the authenticated
finite scheduler and passed its exact Match Studio and consolidated-review
gates; its current contract and evidence are maintained in
`docs/WAVE_RUNTIME.md`. Phase 12 subsequently passed its exact unsaved primary
and defeat Studio checks without changing enemy spawn/movement/outcome truth;
its current contract and evidence are maintained in `docs/TOWER_RUNTIME.md`.
Phase 13 remains unbegun.
