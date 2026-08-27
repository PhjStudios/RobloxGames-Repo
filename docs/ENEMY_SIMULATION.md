# Phase 09 Enemy Simulation and Replication Contract

## Decision status and scope

This is the authoritative Phase 09 architecture decision for server-owned enemy
runtime state, fixed-lane movement, bounded replication, late-client recovery,
and programmatic client presentation. It was recorded before executable Phase
09 source was added. Its focused architecture, security, and performance review
approved implementation after the recorded epoch, capacity, ordering, terminal
delivery, renderer, and measurable-stress corrections were resolved.

Phase 09 owns only placeholder enemy runtime records, deterministic movement on
the Phase 07 detached lane snapshot, endpoint outcomes without base damage,
replication and recovery, client-created placeholder visuals, deterministic
tests, and an unsaved Match Studio stress sample. It does not add base health,
leak damage, defeat, Results transitions, waves, automatic match-state
progression, combat, towers, placement, rewards, persistence, production enemy
content, production art, asset IDs, animation, audio, effects, or Lobby source.

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
a future server wave scheduler calls the spawn API with production content.

Headless fixtures build fresh symbolic `EnemyModel` manifests and enemy
catalogs through the real `AssetSchema` and `EnemySchema`. In Studio only, one
server-only runtime trigger may install the same kind of freshly validated
test catalog while the store is empty and has issued zero IDs. Raw input is
copied, validated, and discarded; production config files remain empty. The
trigger is absent outside `RunService:IsStudio()`, is inaccessible to clients,
owns no arbitrary callback or code execution surface, and is destroyed on
service shutdown.

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
definition and detached frozen lane snapshot required for computation. They
retain no Player, Instance, marker, map Model, client object, visual, connection,
timer, or coroutine. Health initializes exactly to definition `maxHealth`; Phase
09 exposes no damage or healing operation. The sole status representation is a
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

The Match composition registers:

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

No Phase 09 code invokes a match-state transition. Production remains dormant
in `ReadyCheck`/`PreWave` until a future authoritative scheduler calls spawn. It
does not add automatic `PreWave -> WaveActive` progression.

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
`max(1, lane.totalDistance) * 1e-9`; position and replicated correction tests use
`1e-6` studs. Accepted partitionings of the same elapsed time are equivalent
within those tolerances until the same exact endpoint clamp. No backwards
progress API exists.

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

The Phase 09 production callback is a no-op success. It does not read
`leakDamage`, change base health, defeat the match, transition state, publish a
Results outcome, or create world UI. Phase 10 can replace this callback through
a later reviewed server-only composition without changing enemy identity or
replaying old outcomes.

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
advertised window, and `worldCFrame` must equal the canonical route sample
within the movement tolerances. Server emitters construct these values only
from authenticated records; client validation repeats the structural, finite,
range, and CFrame-component checks before staging a message. No message contains
a Player, recipient, map Instance, marker, visual, definition table, caught
error, or private state.

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
strictly greater enemy revision. A despawn records a terminal tombstone for that
RuntimeEnemyId; no later spawn/correction/state entry in the same epoch can
resurrect it. Tombstones are bounded by the 4,096 lifetime ID ceiling and clear
only on epoch replacement or controller cleanup.

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
`ServerStorage` with a fixed private development name and exact operations:
install one validated test catalog, spawn by server-selected EnemyId/lane,
set the one slow multiplier, manually despawn, return detached snapshots/metrics,
and clear test enemies. Inputs pass the same strict server validation and fixed
bounds. It cannot change match state, base state, recipient, remote payload,
map, service, module, or arbitrary property. It is created at runtime, destroyed
at shutdown, and absent from Edit mode and production servers.

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

## Verification and completion boundary

Headless tests use injected clocks, deltas, schedulers, senders, connections,
and visual adapters; they never wait real time. They prove runtime IDs and caps,
definition provenance/mutation isolation, lane binding, numeric movement,
corners/overshoot, slows, endpoint exact-once, replication bounds/convergence,
snapshot races/gaps, renderer interpolation/correction/recreation, constant
connection ownership, and idempotent mass cleanup. Synthetic fixtures prove
multiple lanes; Studio uses only the real authored one-lane graybox.

The structural verifier must authenticate all mappings/source bytes, retain
exactly one Script and one LocalScript per production build and zero runnable
Test scripts, exclude every spec/fixture/Studio harness from production, keep
Lobby free of Match source and Match free of Lobby source, prove production
`Enemies`/`Assets` remain empty, and reject Phase 10/11 source markers. Final
module/suite/test counts are recorded only from the actual final run.

Phase 09 can be marked complete only after Packets 09.1–09.5, the focused Studio
gate, consolidated independent review, complete local gate, clean exact branch,
one final push, and exact-final-SHA Repository Verification with zero artifacts
all pass. Phase 10 is next and remains not begun.
