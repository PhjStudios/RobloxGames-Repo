# Wave Runtime Contract

## Status and authority

This document is the authoritative Phase 11 decision for the finite authored-wave runtime, difficulty composition, skip voting, reliable wave replication, and their cleanup boundaries.

Phase 11 implements only `AuthoredFinite` schedules. `GeneratedEndless` remains Phase 32. Production `Assets`, `Enemies`, `Maps`, `Difficulties`, `Waves`, and difficulty-specific `Economy` rules remain frozen and empty, so the production scheduler is dormant until a future content phase supplies an authenticated selection. Phase 11 permits only fresh schema-validated test fixtures and one Studio-only runtime fixture seam.

The following remain outside Phase 11:

- Phase 12 tower definitions and tower runtime;
- player balances, grants, income, purchases, rewards, or an economy service;
- boss identity, boss behavior, boss presentation, or boss-specific scheduling;
- a wave HUD, countdown renderer, or world-space wave UI;
- victory, a victory result, a healthy-completion transition to `Results`, or a results screen;
- persistence, analytics, matchmaking, or production authored content.

## Runtime composition

There is exactly one non-restartable `WaveRuntime` record per Match server. Its identity and immutable configuration are distinct from its private mutable scheduler state.

The immutable side retains only authenticated values:

- the Match-owned `MatchId`;
- the exact detached frozen `RuntimeMapSnapshot` returned by that `MatchLifecycle` instance;
- enemy epoch `1` and the exact Match/epoch identity reported by `EnemySimulation`;
- the exact canonical `CoreConfiguration` and its canonical map, finite difficulty, authored schedule, enemy catalog, and economy rule;
- the schedule identity `(mapId, difficultyId, exact canonical schedule object)`; the schema has no separate schedule ID;
- detached finite health and movement multipliers copied from the selected difficulty; and
- one detached frozen starting-cash placeholder containing only configuration version, difficulty ID, and `startingBattleCash`.

The mutable side contains only bounded server-owned values:

- runtime state, timer phase, the one-shot final-deadline guard, current wave number, total waves, and `waveRevision`;
- absolute wave-start, deadline, intermission-end, skip-availability, and completion times;
- an ordered absolute spawn-event queue and cursor;
- per-origin-wave counters and aggregate counters;
- the `RuntimeEnemyId -> originating wave` ownership ledger;
- the authenticated terminal-outcome queue and processed-terminal ledger;
- current-wave voter UserIds, the sampled Active-member set, threshold, and pending-quorum flag;
- publisher dirty/pass state and one-time completion, defeat, fault, and cleanup guards.

The record retains no `Player`, `Instance`, UI object, client object, mutable authored table, Workspace visual, coroutine, task, timer object, or per-entity callback.

## State machine and revisions

The private runtime states are:

```text
Uninitialized
  -> Running
  -> Intermission -> Running
  -> FiniteComplete

Running | Intermission -> DefeatClosed
Running | Intermission -> Faulted
Uninitialized | Running | Intermission | FiniteComplete | DefeatClosed | Faulted -> Cleaned
```

`FiniteComplete`, `DefeatClosed`, `Faulted`, and `Cleaned` are terminal. Cleanup is idempotent. `FiniteComplete` closes scheduler spawn and vote admission but deliberately leaves `MatchLifecycle` in `WaveActive`. `DefeatClosed` observes Phase 10 defeat and never initiates a second lifecycle result. `Cleaned` exposes no snapshot and retains no identity.

`waveRevision` is a positive safe integer in an independent domain. It is not `MatchStateMachine.revision`, `baseRevision`, enemy epoch, enemy record revision, or enemy replication sequence. A semantic public-state transaction advances it exactly once after all of that transaction's mutations validate. One integrated simulation pass is one such transaction even if it consumes several spawn, terminal, roster, or boundary work items. Each accepted synchronous vote is also one transaction. Timer passage by itself does not advance the revision. Every increment is preflighted; exhaustion faults closed without rollover.

## Authentication and initialization

### Canonical configuration

Initialization accepts one exact authenticated `CoreConfiguration`, never independent caller-supplied definitions. Authentication follows the real schema dependency graph in one ModuleScript VM:

1. Assets;
2. Towers and Enemies from those Assets, and Difficulties;
3. Maps from the authenticated Assets and Difficulties;
4. Waves from the authenticated Maps, Difficulties, and Enemies;
5. Economy from the authenticated Difficulties;
6. Banners and default settings; and
7. the resulting authenticated `CoreConfiguration` root.

The runtime then requires all of these exact identities:

- `mapCatalog.byId[runtimeMap.mapId] == selectedMap`;
- `difficultyCatalog.byId[difficultyId] == selectedDifficulty`;
- `waveCatalog.byMapId[mapId][difficultyId] == selectedSchedule`;
- every scheduled `enemyCatalog.byId[enemyId] == selectedEnemy`;
- `economy.byDifficultyId[difficultyId] == selectedEconomyRule`; and
- the map/difficulty/enemy catalogs accepted by `WaveSchema` are the same catalog objects retained by the core configuration.

Weak-key schema authenticity and exact index identity are both required. Raw sources, detached copies, serialized values, frozen lookalikes, values from another ModuleScript VM, metatable-bearing tables, cross-catalog definitions, and mutated sources are rejected before mutation.

`GeneratedEndless`, a non-finite difficulty, mismatched map/difficulty pairs, a missing or extra economy rule, or inconsistent finite `waveCount` is rejected.

### Runtime map identity

Callers never provide a runtime map. `WaveRuntimeService` obtains it directly from `MatchLifecycle:getRuntimeMapSnapshot()` and requires the same object to pass a narrow MatchLifecycle identity predicate. Its `mapId` must identify the exact canonical map. Its dense lane IDs, order, and count must exactly match the canonical map lane definitions. World CFrames, positions, distances, and route geometry remain owned by the detached runtime snapshot; no difficulty, timing, enemy, economy, or balance value comes from it.

### Selected-schedule preflight

Before any Base, lifecycle, enemy, or scheduler mutation, the selected finite schedule is flattened and preflighted. The preflight requires:

- `#schedule.waves == difficulty.waveCount` and at least one wave;
- total scheduled enemies no greater than the EnemySimulation lifetime limit of `4,096`;
- each absolute timestamp product and sum finite, nonnegative, and within safe numeric bounds;
- each simultaneous authored burst no greater than the active-enemy limit of `128`;
- every `AllSpawnsByDeadline` group's exact authored last-spawn time no greater than the exact deadline; and
- every lane/enemy reference to resolve through the authenticated runtime map and canonical catalog.

`WaveSchema` uses a scale-aware tolerance while admitting authored `AllSpawnsByDeadline` data. Runtime preflight is intentionally stricter: it never moves a positive-epsilon event earlier. A selected `AllSpawnsByDeadline` schedule whose exact formula exceeds the deadline fails closed. Only `AllowScheduledOverlap` may retain events after its originating deadline.

Static preflight cannot prove that all dynamic overlap stays below `128` active enemies. A due spawn that cannot be admitted because of active, lifetime, publisher, ID, arithmetic, or callback capacity faults the runtime closed; it is never silently dropped, retried out of order, or counted as consumed.

### Production dormancy and Studio installation

With the production-empty configuration, `WaveRuntimeService` initializes and starts in a dormant `Uninitialized` state. It does not initialize BaseRuntime, bind EnemySimulation, activate `WaveActive`, connect another loop, or publish wave state.

In Studio only, the sole combined Phase 11 trigger may accept fresh raw synthetic sources and run the real `ConfigurationValidator` once. It passes the resulting canonical root only to a Wave-owned prepare/commit transaction. The seam is one-shot, fixed-operation, server-only, absent outside Studio, and unavailable after any runtime mutation. Separately validated or separately installed catalogs are not composable into a Phase 11 runtime.

Preparation is mutation-free and requires all of these exact preconditions at once:

- WaveRuntime is `Uninitialized` and has no previous prepare/commit token;
- MatchLifecycle identifies the same Match and is in `PreWave`;
- the exact retained RuntimeMapSnapshot, map identity, and enemy epoch agree;
- BaseRuntime is uninitialized and can accept the exact canonical difficulty;
- EnemySimulation has zero active/lifetime enemies, no difficulty bind, no Wave admission owner, and an intact empty production catalog seam; and
- all three services independently preflight the same authenticated CoreConfiguration, definition identities, capacities, callbacks, clocks, and initial publications.

Preparation returns one opaque weak-key-authenticated token. Commit first reserves every no-fail Wave ledger/counter/revision slot, then installs the exact canonical difficulty/enemy catalogs, binds modifiers, assigns scheduler spawn ownership, and retains the same canonical root in WaveRuntime. The ordinary/legacy EnemySimulation spawn facade is revoked for the rest of that service lifetime, and the former standalone Phase 9/10 Studio trigger is disabled or migrated before commit. During a running Phase 11 configuration, every admitted enemy is scheduler-owned, so an authentic unknown RuntimeEnemyId is impossible unless an integration invariant has failed.

Every commit step is preflighted to be non-yielding and allocation-bounded. An unexpected failure after any service has committed is irreversible: Wave, EnemySimulation, and BaseRuntime fail closed, the token is revoked, no retry or partial rollback is attempted, and reverse cleanup removes the partial state. A failure before the first commit mutates nothing and revokes the token.

The trigger may drive controlled terminal resolutions and participant operations for evidence, but it creates no client authority or production content. Phase 9/10 evidence operations that remain needed are migrated into this one combined trigger; there is never a second concurrent runtime trigger.

## PreWave activation transaction

Phase 11 adds a narrow server-only opaque-token transaction to `MatchLifecycle`:

1. `beginWaveActivation(matchId)` authenticates the exact current Match, requires `PreWave`, prepares exactly `PreWave -> WaveActive`, snapshots recipients, and reserves the lifecycle revision.
2. The Wave coordinator commits the prepared one-shot configuration transaction, initializes BaseRuntime once from the same exact canonical finite `DifficultyDefinition`, and confirms the exact enemy modifier bind and scheduler admission owner.
3. It installs the integrated Wave boundary, stages wave 1's prevalidated relative event head, and preflights the initial public snapshot.
4. `commitWaveActivation(token)` commits `WaveActive` and attempts the reliable Match snapshot publication.
5. Only after lifecycle commit succeeds does WaveRuntime enter `Running`, set wave 1's start timestamp, expose its first snapshot, and admit due spawns.

No spawn occurs before the lifecycle commit. The API cannot select a target state, map, difficulty, recipient, or Player and is unavailable to clients. The Phase 10 Studio evidence method remains a Studio-only compatibility wrapper around the same guarded transition machinery, not an alternate production authority path.

Any failure before lifecycle commit rolls back the opaque transition token and closes/faults the Wave coordinator. BaseRuntime initialization is intentionally one-shot: if Base initialization has committed and a later dependency fails, the coordinator never resets or reinitializes Base. It fails closed and relies on reverse service cleanup. If the lifecycle transition commits but its Match snapshot send fails, the transition is irreversible truth; the result reports `committed=true, published=false`, Wave starts, and normal snapshot recovery remains available.

## Difficulty composition

Every finite match starts at authored wave index `1`. Total waves is exactly `DifficultyDefinition.waveCount`; no starting-wave field exists.

BaseRuntime receives the exact canonical difficulty and takes maximum health only from `difficulty.base.maxHealth`. Base initialization completes before `WaveActive` commits.

EnemySimulation binds one canonical difficulty before any Phase 11 spawn. For each accepted scheduler-owned spawn, EnemyRuntimeStore copies these values exactly once:

```text
maximumHealth = EnemyDefinition.maxHealth * enemyHealthMultiplier
currentHealth = maximumHealth
difficultyAdjustedMoveSpeed = EnemyDefinition.moveSpeedStudsPerSecond * enemyMoveSpeedMultiplier
effectiveSpeed = difficultyAdjustedMoveSpeed * slowMultiplier
```

The finite positive products are the same products already admitted by the authenticated `WaveSchema` dependency check. There is no rounding, integer conversion, clamping, later difficulty rescaling, or definition mutation. Slow effects multiply only the record-owned difficulty-adjusted speed. `EnemyDefinition.leakDamage` is copied unchanged into the existing authenticated Base leak outcome and is never scaled. Boss kind and reward class remain inert wave metadata.

The starting-cash placeholder is a detached frozen server record. It is queryable only through trusted server diagnostics and is never replicated as a balance or applied to a player.

## One combined simulation boundary

EnemySimulation remains the sole owner of one `RunService.Heartbeat` connection. WaveRuntime adds no Heartbeat, task, per-wave timer, per-group timer, per-spawn timer, or PlayerRemoving connection. During lifecycle initialization, WaveRuntime installs one authenticated non-yielding post-simulation boundary adapter into EnemySimulation. Reverse cleanup removes and invalidates this adapter before EnemySimulation cleanup.

One processing sample has this order:

1. EnemyRuntimeStore reads its protected monotonic server clock exactly once while stepping and returns that committed `sampleServerTime`; EnemySimulation analytically advances enemies that existed at the beginning of the pass to that same sample.
2. EnemyRuntimeStore commits endpoint/despawn records. Endpoint leak outcomes synchronously reach BaseRuntime through the existing narrow non-reentrant sink.
3. EnemySimulation completes exactly one Base enemy-pass boundary and coordinates any `DefeatPending` transition, active-enemy defeat removal, and the one `WaveActive -> Results` commit.
4. EnemySimulation finishes its own store mutation guard, then invokes the Wave boundary with that exact returned sample time and a short-lived scheduler-spawn capability authenticated for MatchId, epoch, enemy-pass ordinal, and sample time.
5. WaveRuntime first observes defeat, then drains already queued authenticated terminal copies, reconciles Active membership/votes, processes bounded chronological scheduler work, and marks at most one full Wave publication dirty.
6. EnemySimulation advances its reliable publisher once, and WaveRuntime flushes at most one coalesced `WaveReplication` event for that simulation pass.

The Wave callback may enqueue/copy terminal facts or invoke the short-lived scheduler spawn capability. It never calls a public EnemySimulation mutation, never retains the spawn capability, and never runs while EnemyRuntimeStore is mutating. A terminal sink called inside an EnemyRuntimeStore transaction may only authenticate and append a bounded detached copy; any yield, throw, re-entry attempt, overflow, or malformed callback result faults closed.

The scheduler spawn capability makes EnemyRuntimeStore use the pass's authenticated `sampleServerTime` without another clock read. Every terminal outcome produced by that store step and every scheduler spawn accepted in the boundary therefore carries the same sample. A different, missing, backward, nonfinite, wrong-pass, wrong-Match, or wrong-epoch sample is rejected and faults closed. Outside Heartbeat, a vote handler reads the same protected clock source once and requires its sample to be no earlier than WaveRuntime's last accepted pass/vote sample.

EnemySimulation delivers exactly one disposition to the installed Wave adapter for every started enemy pass, including every early-return and fault-drain path:

- `Healthy`, with the sample and a live spawn capability;
- `DefeatCommitted`, after Phase 10 closes the match;
- `DependencyFault`, after a store, publisher, Base, callback, or invariant failure; or
- `Shutdown`, when admission/service teardown has closed the pass.

The capability is invalidated before any non-`Healthy` disposition and in a finally-style path immediately after a healthy callback returns. A retained capability cannot be reused. `DefeatCommitted` moves Wave to `DefeatClosed`; `DependencyFault` moves it to `Faulted`; and `Shutdown` closes it without later mutation. The existing Enemy `spawnAdmissionClosed` fast path still reports a disposition. A missing adapter after successful installation is itself a dependency fault. If the primary Wave step callback throws or yields, EnemySimulation invokes a separate one-shot non-yielding Wave close method; if that also fails, EnemySimulation faults and every later Wave request synchronously checks the exact boundary generation/status before it can mutate or answer. Thus Wave cannot remain apparently `Running` after its sole driver has stopped.

Before every spawn, wave boundary, and completion commit, WaveRuntime rechecks the Base defeat state and Match lifecycle state. A lethal leak in the pass therefore commits defeat and closes scheduler admission before any later Wave spawn, boundary, or finite-completion mutation.

### Large-delta semantics

The combined pass uses processing-sample semantics, not retroactive sub-frame simulation. Existing enemies advance to the single authenticated sample time first. If that advance causes lethal defeat, defeat cancels all not-yet-emitted scheduled work even when some authored timestamps became overdue during the large delta.

If no defeat occurs, overdue events are consumed afterward in stable authored order. Their actual spawn time is the exact authenticated processing sample; `spawnServerTime` is never backdated and they receive no retroactive movement. Lateness is `actualSpawnServerTime - authoredScheduledServerTime`, is always nonnegative, and is exposed only in bounded diagnostics. This rule is deterministic under coarse and fine clocks without pretending that a late Heartbeat occurred earlier.

## Absolute schedule and bounded catch-up

Selected-schedule preflight, before any runtime mutation, flattens each wave into one immutable relative-time event array using zero-based authored ordinal:

```text
relativeScheduledTime = group.startDelaySeconds
    + spawnOrdinal * group.spawnIntervalSeconds
```

Each relative array is validated and sorted once by group index and ordinal under the schema's authored group order. Across started waves, events are globally ordered by:

1. `scheduledServerTime`;
2. originating wave index;
3. group index; and
4. authored spawn ordinal.

Zero-interval and simultaneous groups follow that key exactly. The total preflattened event count is capped at `4,096`, so configuration preparation has an explicit finite worst case. Runtime does not bulk insert or sort a wave. It retains one cursor per started origin and a bounded min-heap containing only the next event head for each started origin, keyed by absolute time, origin, group, and ordinal. Starting a wave pushes one head. Accepting one spawn pops that head and pushes at most the next head from the same origin. Old pending events and active enemies remain owned by their originating wave.

One Wave pass processes at most `256` scheduler work units, of which at most `128` are spawn events and at most `128` are terminal outcomes. Consuming one terminal outcome, spawn event/head replacement, wave start/head insertion, intermission transition, deadline/skip/final-deadline boundary, completion, or terminal close costs one unit. Each heap operation is bounded by the at-most-`1,000` started origins and does no bulk schedule traversal. Roster reconciliation and the one coalesced publication do not create unbounded per-member work because the Match roster is capped at four.

When the bound is exhausted, the cursor and dirty state remain for the next Heartbeat. Backlog never reorders, deletes, duplicates, or backdates work; never declares early clear or completion while earlier work remains; and never crosses a deadline/skip boundary before all earlier due events are consumed. No event is emitted before its authored absolute time. The `1`, `32`, `64`, and `128` due-spawn Studio ladder therefore fits the explicit per-pass spawn bound when active capacity is available.

Clock values must be finite, nonnegative, and monotonic. A backward/nonfinite clock, unsafe timestamp arithmetic, exhausted work cursor/ledger/revision, impossible counter equation, callback failure, or dependency invariant failure transitions once to `Faulted`, closes admission, cancels pending work, and attempts one bounded terminal full-state publication.

## Boundary ordering

At a safe pass, WaveRuntime first observes Base defeat/Match `Results`, authenticates queued terminal outcomes, and reconciles current Active UserIds/votes. It then follows a state-specific loop:

- In `Intermission`, the expired prior-wave deadline is ignored. No skip or spawn is admitted until `now >= intermissionEnd`. Starting the next wave is anchored to the exact intermission end, pushes that origin's first event head, and resumes `Running` work.
- In pre-deadline `Running`, emit global head events with `scheduledServerTime <= min(now, currentWaveDeadline)` in stable order and recheck defeat after every accepted spawn. When `now >= currentWaveDeadline`, consume the current wave's deadline guard exactly once before considering skip or clear.
- A nonfinal consumed deadline starts the next wave anchored to that exact deadline and resumes the loop. A final consumed deadline changes timer phase once to `PostDeadline`, disables skip, and does not start a wave.
- In final `PostDeadline`, emit every global event with `scheduledServerTime <= now`, including late final-origin or older-origin overlap. No deadline boundary repeats.
- Before a due deadline, a pending skip boundary precedes early clear. Otherwise evaluate global early clear or final completion.

Deadline wins an exact deadline/skip tie and an exact deadline/clear tie. A vote submitted at or after the deadline is rejected. Due events exactly at the deadline are emitted before the deadline transition. If that transition starts another wave at the same timestamp, the new wave's zero-delay head follows the already ordered prior-origin events and may run in the same pass if work and active capacity remain.

Deadline and skip boundaries start a nonfinal next wave immediately. Deadline anchors the next start to the current authored deadline; skip anchors it to the safe-boundary sample time. Each consumes the boundary guard exactly once. Neither cancels old pending events nor despawns old enemies.

Early clear is eligible only when `now < currentWaveDeadline`, every scheduled event for every already-started origin has been emitted, and every scheduler-owned active enemy across every origin has resolved. A nonfinal early clear enters `Intermission` at the observation time. The next wave starts exactly at `intermissionStartedServerTime + difficulty.timing.earlyClearIntermissionSeconds`; the primary fixture uses exactly `5` seconds. Once begun, the full intermission survives past the old deadline if necessary. Skip is unavailable during intermission. Empty nonfinal waves follow this rule.

A final wave never enters an intermission. It commits `FiniteComplete` immediately when the final wave has started and global pending and alive counts both reach zero, even before its deadline. Empty final waves may therefore complete at their start. If work remains at the final deadline, the one-shot `PostDeadline` phase allows every intentionally late event to emit and every active enemy to resolve before the same completion predicate is reconsidered. Completion commits exactly once, closes scheduler spawn/vote admission, and does not call MatchLifecycle. Phase 10 defeat wins every completion race.

## Counters, ownership, and terminal outcomes

Each started origin wave owns safe-integer counters:

- `totalScheduled`;
- `pending`;
- `spawned`;
- `alive`;
- `leaked`; and
- `otherwiseResolved`.

The invariants are:

```text
pending = totalScheduled - spawned
alive = spawned - leaked - otherwiseResolved
aggregate field = bounded sum of that field across started origins
```

Before invoking the scheduler spawn capability, WaveRuntime preflights every counter, ownership slot, event cursor, revision, and fault-state assignment needed after acceptance. The capability returns one exact authenticated commit-aware outcome bound to the current Match, epoch, pass ordinal, and sample:

- `committed=false` contains no RuntimeEnemyId and proves Store state did not change; or
- `committed=true` contains the genuine frozen spawned snapshot and whether publisher commit succeeded.

Once Store spawn commits, the event is irrevocably consumed and WaveRuntime performs only preflighted no-fail assignments: map the RuntimeEnemyId to its one origin, advance the origin cursor/head, and increment `spawned`/`alive` while decrementing `pending`. If publisher commit then failed, those ownership facts still commit exactly once before WaveRuntime and EnemySimulation fault closed. Only a proven `committed=false` rejection consumes nothing. A malformed/missing outcome after a possible Store mutation is an integration fault; EnemySimulation's own retained committed-spawn record supplies the exact ID to the one-shot Wave close path so cleanup cannot leave an unowned live enemy. Old ownership is never reassigned at deadline, skip, or a later wave start.

EnemyRuntimeStore creates a separate authenticated terminal outcome for every terminal reason relevant to scheduler ownership:

```text
{
    matchId,
    enemyEpoch,
    runtimeEnemyId,
    enemyId,
    reason = "Endpoint" | "Manual" | "Defeat",
    serverTime,
}
```

The outcome is detached, exactly shaped, frozen, weak-key authenticated by its producing store, and revoked on cleanup. It contains no Player, definition, Instance, damage authority, or client data. Endpoint outcomes do not replace the existing authenticated leak outcome; BaseRuntime continues to receive that distinct outcome synchronously.

WaveRuntime copies a valid outcome tuple into its bounded queue and never retains the provenance object after processing. Exact MatchId, epoch, enemy ID, RuntimeEnemyId ownership, reason, finite monotonic server time, and unprocessed status are required. Outcomes behave as follows:

- the same authenticated outcome delivered again is an idempotent no-op;
- a detached/forged/revoked outcome is rejected without mutation;
- wrong MatchId/epoch, conflicting enemy ID/reason/time, authentic unknown ID, unsafe time, or a second distinct terminal for one owned ID is an integration fault and closes the runtime;
- a valid owned endpoint increments `leaked`; a valid owned non-endpoint increments `otherwiseResolved`; both decrement `alive` once;
- post-defeat queued outcomes may be discarded only after `DefeatClosed` cancels scheduler truth; they cannot reopen or complete the runtime;
- post-completion, faulted, or cleaned callbacks cannot mutate and cannot publish.

The ledgers are bounded by `4,096`, the EnemySimulation lifetime cap, and are cleared in Wave-first cleanup.

## Skip voting

`SubmitSkipVote` has exact payload `{ matchId, waveNumber }`. The network dispatcher authenticates a genuine synchronous request context; the handler transiently derives `context.player.UserId`, then drops the Player reference. Clients cannot submit a voter, threshold, membership list, difficulty, timer, or target wave.

A vote is accepted only when all conditions hold:

- MatchLifecycle and WaveRuntime identify the exact same current Match;
- the current timer phase is a nonfinal `Running` wave;
- `waveNumber` equals the current wave;
- server time is at or after `waveStartedServerTime + skipVoteMinimumDelaySeconds` and strictly before the deadline;
- the derived UserId appears as `Active` in the latest detached MatchLifecycle snapshot; and
- that UserId has not voted in this wave.

The action is yes-only and once per UserId per wave. There is no retract. Votes reset on every wave start. The runtime stores only UserIds.

At every safe boundary, WaveRuntime synchronously fetches and authenticates a fresh bounded detached MatchLifecycle participant snapshot rather than adding another PlayerRemoving connection. Active membership only shrinks after `WaveActive`; a returned participant remains a Spectator under the existing roster contract. Votes belonging to no-longer-Active UserIds are removed before threshold calculation.

Every `SubmitSkipVote` handler repeats that operation under the Wave mutation guard before authorization: fetch a fresh snapshot, authenticate exact MatchId/revision/shape, remove departed voters, recompute the threshold, then check the context-derived UserId against that same Active set. It also takes one fresh protected clock sample and monotonic-checks it against the last accepted pass/vote time. A lifecycle snapshot/clock failure never falls back to cached membership; it rejects the request and faults closed when the dependency invariant is no longer trustworthy. A disconnect immediately before a request therefore cannot leave stale authorization, and a disconnect between vote recording and the safe boundary is removed by the next reconciliation before quorum executes.

For `activeParticipantCount > 0`:

```text
requiredVoteCount = floor(activeParticipantCount / 2) + 1
```

Zero Active participants can never pass. Removing a voter or non-voter recomputes counts and threshold, and may set the one pending quorum boundary. A request handler records an accepted vote and a pending quorum but never re-enters EnemySimulation or starts a wave inline. The next combined safe boundary applies it once. If the deadline is then due, the deadline path wins and clears the pending quorum. Simultaneous requests are serialized by the runtime mutation guard; only the first transition that creates quorum can arm the boundary.

Early, stale-wave, duplicate, final-wave, non-Active, intermission, deadline-tied, defeat, completion, fault, and cleanup attempts are rejected with fixed metadata-free public errors. Rejection does not advance `waveRevision`.

## Reliable wave protocol

Phase 11 adds exactly three Match-only definitions under the existing reliable `ATDNetwork` root:

- `GetWaveSnapshot`: client-to-server Request, exact `{}`, returns one full `WaveSnapshot`;
- `SubmitSkipVote`: client-to-server Request, exact `{ matchId, waveNumber }`, returns the newest full `WaveSnapshot`; and
- `WaveReplication`: server-to-client Event, carries one full `WaveSnapshot`.

The exact inbound token buckets are:

- `GetWaveSnapshot`: capacity `2`, refill `0.25` tokens/second;
- `SubmitSkipVote`: capacity `2`, refill `0.5` tokens/second.

No `RemoteFunction`, `UnreliableRemoteEvent`, generic message bus, second network root, or client-selected recipient is added.

### Bounded snapshot

Every `WaveSnapshot` is detached, exactly shaped, frozen after validation, and contains:

- MatchId, enemy epoch, map ID, difficulty ID, and independent `waveRevision`;
- public state `Running | Intermission | FiniteComplete | DefeatClosed | Faulted`;
- current wave ID/number, total waves, boss kind, and timer phase `WaveDeadline | EarlyClearIntermission | PostDeadline | None`;
- absolute wave-start, deadline, intermission-end, skip-available, and finite-completion timestamps, using `0` only where the field is not applicable;
- current-origin and aggregate `{ totalScheduled, pending, spawned, alive, leaked, otherwiseResolved }`; and
- skip state `{ available, activeParticipantCount, yesVoteCount, requiredVoteCount, quorumPending }`.

The full per-wave ledger, schedule queue, starting-cash placeholder, voter identities, Player/UserId values, reward class, definitions, and runtime map geometry are not replicated. Count fields are bounded by `4,096`; participant/vote fields are bounded by the Match roster cap. Absolute timestamps support future local display without publishing countdown ticks.

Every event is a full state, never a delta. Scheduler semantic changes in one integrated pass are coalesced into at most one `WaveReplication` event, excluding direct request responses. Synchronous votes may advance revisions between Heartbeats; the next event carries only the newest full state.

A logical publisher invariant, revision, schema, or dependency failure faults WaveRuntime. For each event, the publisher obtains one fresh trusted connected-recipient snapshot from MatchLifecycle, capped at four and sorted by server-derived UserId. Recipient records may transiently contain a Player only for the synchronous send loop; WaveRuntime and the publisher never cache the Player, UserId, or array after that call. Request/client data never selects recipients. One disconnected or failing recipient's `FireClient` attempt is contained, counted as consumed, does not roll back server truth, and recovers through a later full event or `GetWaveSnapshot`. No payload, MatchId, UserId, voter list, definition, or raw error is logged.

### Client convergence

`WaveController` owns a bounded request tracker and exactly three network listeners: `WaveReplication`, `GetWaveSnapshot` response, and `SubmitSkipVote` response. It registers the event listener before issuing the initial snapshot request. It creates no HUD, world UI, `RenderStepped` loop, authoritative Instance, or timer connection.

`WaveStateReducer` validates and freezes a detached full snapshot before mutation. For one locked MatchId:

- duplicate and lower revisions are ignored;
- a contiguous `waveRevision + 1` event is accepted;
- an event revision gap is classified as `Skipped`, rejected without rollback, and arms one bounded `GetWaveSnapshot` recovery request;
- a valid direct `GetWaveSnapshot` or `SubmitSkipVote` response may accept a higher full revision and heal the gap;
- malformed, impossible-transition, stale-wave, wrong-identity, and out-of-order values are rejected;
- an unlocked controller may lock from its first valid event or correlated direct response;
- a valid wrong-MatchId event while locked is rejected but arms exactly one bounded `GetWaveSnapshot` recovery request;
- `WaveReplication` alone cannot replace a locked MatchId; only a valid direct snapshot response correlated to the current controller generation may replace it, which first clears old pending skip/recovery/request state; stale responses from an earlier match or controller generation remain rejected; and
- event/response races always retain the highest accepted revision and never roll back.

Thus full events are self-contained while explicit gap policy preserves the requested skipped-state rejection and bounded recovery. Delayed bootstrap or a recreated controller registers first, requests a fresh full snapshot, and converges without server-side client state. Skip requests use only the cached MatchId and current wave number; pending request state is bounded and never treated as authority.

Cleanup disconnects listeners, invalidates callback generations, clears pending requests/recovery flags/cache/reducer diagnostics, and prevents delayed responses from recreating state.

## Service graph and cleanup

The server dependency graph is:

```text
NetworkRegistry -> MatchLifecycle -> BaseRuntime -> EnemySimulation -> WaveRuntime
```

The corresponding shutdown order begins:

```text
WaveRuntime -> EnemySimulation -> BaseRuntime -> MatchLifecycle/MapLoader -> NetworkRegistry
```

The client order is:

```text
MatchReadyController -> BaseController -> EnemyController -> WaveController
```

and cleanup is the reverse. The lifecycle runner retains transactional initialize/start unwind behavior and attempts every reverse shutdown even after a failure.

Wave cleanup first closes request, vote, spawn, boundary, completion, terminal, and publication admission. It invalidates the boundary adapter and Studio trigger, clears the terminal callback/queue/provenance copies, pending schedule/cursor/backlog, ownership and processed ledgers, counters, votes and Active UserIds, publisher/request state, timestamps/revisions/identities, configuration references, and starting-cash placeholder. It then detaches from EnemySimulation. EnemySimulation subsequently clears its one Heartbeat, PlayerRemoving connection, publisher, store, active enemies, terminal authenticators, and callbacks; Base clears health/leak/result state; Match clears roster/runtime map; Network destroys the one root.

The server and client connection counts are constant. No count depends on waves, groups, spawns, enemies, votes, or clients beyond the already bounded recipient iteration.

## Test and Studio evidence contract

Headless tests use injected deterministic clocks, boundary invocations, senders, and roster snapshots. They never wait in real time and do not claim engine networking, Heartbeat timing, rendering, or client behavior. In addition to the Studio ladder, a headless worst-case selected schedule with `4,096` events proves preflatten bounds, heap-head work, large-delta backlog, and exact-once cursor progress without one-pass bulk insertion.

The sole Studio fixture is fresh on every run, real-schema validated, below `128` active and `4,096` lifetime enemies, and maps exactly to the loaded Match `RuntimeMapSnapshot`. It includes zero/nonzero intervals, multiple groups and lanes where the real map permits, empty waves, all boss/reward metadata, exact-deadline events, a deliberate `AllowScheduledOverlap`, and a five-second early-clear intermission.

Studio evidence is valid only in Edit-started fresh two-client sessions for PlaceId `136401514513678`, GameId `10757629094`, Group CreatorId `35420107`, PHJGAMES ownership, and `ATDPlaceRole=Match`. Synchronization is limited to branch-owned `match.project.json` sources. No map, terrain, model, setting, marker, unmapped instance, or Team Create content is saved or published.

The evidence records the `1`, `32`, `64`, and `128` due-spawn ladder, scheduler processing time, maximum lateness/no-early result, client convergence time, publication count, wave/base/enemy identities and revisions, constant connection counts, assertion totals, console errors/warnings, and residue. Healthy finite completion must occur exactly once with MatchLifecycle still `WaveActive`; the defeat scenario must record exactly one defeat and one `Results` transition.

After evidence, all clients/server stop, the task-owned Rojo process disconnects, profiling/emulation resets, the combined trigger and all runtime/network/map/enemy/client state are absent, and the exact Match place remains in Edit mode. Studio content is not saved or published.

## Fault and privacy policy

All public failures use the existing fixed public error vocabulary without metadata. Internal failures use static bounded codes and existing logging fields only. Phase 11 adds no per-spawn, per-enemy, per-vote, per-wave, or per-client log stream and never logs payloads, MatchIds, UserIds, voter identities, definitions, raw Roblox errors, or object stringifications.

Every dependency call is synchronous and non-yielding. A dependency throw, yield, malformed result, re-entry attempt, callback after cleanup, unsafe arithmetic, impossible state, or capacity breach fails closed according to whether lifecycle/base truth is already irreversible. Cleanup remains idempotent and cannot recreate callbacks, state, network roots, maps, enemies, or client caches.

## Pre-implementation review disposition

One focused independent architecture/security/lifecycle review completed on 2026-08-28 before executable Phase 11 work. It required eight material corrections, all incorporated above:

1. final-wave post-deadline overlap and intermission state-specific ordering;
2. preflattened bounded relative arrays plus one-head-per-origin heap work;
3. one authenticated EnemyRuntimeStore processing sample shared by step, terminal outcomes, Wave, and scheduled spawns;
4. commit-aware spawn outcomes and no-fail exact-once Wave ownership after Store commit;
5. a Wave disposition on every Enemy pass and a one-shot close path for callback failure;
6. one mutation-free prepare/commit fixture installation transaction that revokes legacy spawn admission;
7. fresh MatchLifecycle roster and clock authentication in every vote request; and
8. wrong-match client recovery plus fresh MatchLifecycle-owned replication recipients.

After these corrections, the review found no remaining material architecture, authority, timing, bounds, lifecycle, privacy, cleanup, or testability issue and cleared the decision for executable implementation. No overlapping review round was performed.
