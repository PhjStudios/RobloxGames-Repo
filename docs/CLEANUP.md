# Typed Cleanup Utility

## Purpose

This document records the implementation and verification evidence for Packet
03.2 of `docs/DEVELOPMENT_PLAN.md`. The shared cleanup utility gives future
services and controllers one deterministic ownership contract without adding a
logging framework, external shutdown trigger, gameplay system, or networking.

## Packet status

- Packet: 03.2
- Status: Complete
- Recorded: 2026-08-25
- Shared implementation: `src/shared/util/Cleanup.luau`
- Existing common bootstraps integrated: client and server
- Existing controllers available for integration: none
- Gameplay behavior added: none
- Studio-authored content changed: no
- Place saved or published: no

Those fields describe Packet 03.2 at completion. Packet 06.1 later reused this
utility inside the common server network service; it did not add a second
cleanup implementation. Phase 08 applied the same one-owner/idempotent rules to
the Match lifecycle, roster, deadline, snapshot broadcaster, MapLoader, request
tracker, input bindings, and Ready GUI. Phase 09 extended the ownership model to
enemy simulation, replication queues and ledgers, client recovery state, and
programmatic visuals. Phase 10 extends it to base state/outcome ledgers,
coalesced publication, defeat coordination, marker watchers, a cancellable
  tween, and the world GUI. Phase 11 extends it to the Wave schedule/heap/cursors,
  origin ownership and terminal ledgers, votes/roster copies, publisher queue,
  recovery requests, controller cache, and Studio-only trigger. Phase 12
  extends the same ownership contract to temporary loadouts/UnitIds,
  single-use capabilities, RuntimeTower records/counters, private templates,
  live graybox Models, the exact runtime root, one participant observer, and one
  Wave-owned Studio boundary. Phase 08 is complete. Phase 09 code, exact Match Studio
gate, consolidated review, 467-case local gate, and all four structural builds
passed on 2026-08-27. Phase 09 is complete. Phase 10 focused and exact Studio
cleanup checks, consolidated review, `593`-case local gate, and all four
structural builds passed on 2026-08-28. Phase 10 is complete; exact-final-SHA CI
is cited at handoff. Phase 11's exact Studio cleanup, consolidated review,
`742`-case/`56`-suite local gate, and four structural builds also pass. Phase 11
is complete. Phase 12's focused and exact unsaved primary/defeat cleanup gates,
consolidated review, `840`-case/`64`-suite local gate, and all four structural
builds pass. Phase 12 is complete; exact-final-SHA CI is recorded at handoff,
and Phase 13 is next but remains unbegun.

## Public contract

`Cleanup.new(logger, label)` creates a typed container in the `Active` state.
The logger must be a genuine Packet 03.3 context-bound logger. Labels must start
with an ASCII letter and may then contain letters, digits, `_`, `.`, or `-`.
The logger supplies execution, role, PlaceId, and runtime-environment context;
the label identifies the owned container within that context.

| Method | Behavior |
| --- | --- |
| `add(task)` | Validates and stores one supported task while `Active`; returns the same task |
| `cleanup()` | Cleans every task once in reverse registration order |
| `getState()` | Returns `Active`, `Cleaning`, or `Cleaned` |
| `getTaskCount()` | Returns the number of currently retained tasks |
| `getLabel()` | Returns the validated owner label |

The supported task union is:

| Task | Cleanup operation |
| --- | --- |
| `RBXScriptConnection` | `Disconnect()` |
| `Instance` | `Destroy()` |
| Callback | Invoke once |
| Thread | `task.cancel()` unless already dead |
| Cleanup container | Invoke the child's `cleanup()` |

Arbitrary tables with method-shaped fields or a copied metatable are not
accepted as containers. Instances created by this module are tracked through a
private weak-key registry.

## Ordering and ownership rules

Tasks clean in strict last-in, first-out order. This lets a later dependent task
release before an earlier resource it depends upon. Each registration remains
independent; registering the same callback twice invokes it twice.

Containers may own nested containers, but ownership must remain acyclic. Direct
self-nesting and indirect cycles are rejected at registration. A nested
container must still be `Active` when registered. If a child is independently
cleaned after registration, the parent's later call is an idempotent no-op when
the child succeeded, or reproduces the child's cached failure when it did not.

Callbacks must remain bounded and scheduler-cooperative. They may yield only for
intentional asynchronous shutdown work governed by Packet 03.4's overall
server budget; they must never busy-loop. This utility does not invent
per-callback deadlines.

## State and failure behavior

The state transition is:

```text
Active -> Cleaning -> Cleaned
```

- Tasks can only be registered while `Active`.
- `cleanup()` detaches the live task array before invoking any operation.
- Adding during cleanup and cleanup re-entry are rejected, then captured as the
  current task's failure so the outer sweep can continue.
- Every individual operation is protected with `pcall`.
- One failing task never prevents later tasks from cleaning.
- Arbitrary task failure text is discarded; only static index/kind/type
  metadata appears in the aggregate error.
- After the complete sweep, the container becomes `Cleaned` and releases all
  retained task references.
- If any task failed, one aggregate error is raised after the sweep.
- Repeated successful cleanup is a no-op.
- Repeated failed cleanup raises the exact cached aggregate failure without
  retrying a possibly partially completed task.

Already-disconnected connections, already-destroyed Instances, and dead threads
are harmless cleanup inputs.

## Development errors

Direct errors use a stable, readable structure:

```text
[ATD][ERROR][context=<client|server>][role=<role>][placeId=<id>][environment=<environment>][subsystem=cleanup][event=<event>][code=<code>][container=<label>][state=<state>] <message>
```

Aggregate task details also include registration index, classified kind, and
runtime type. Packet 03.2 emits no per-task warnings, avoiding log flooding.
Packet 03.3 now formats the one direct or aggregate error through the
container's local logger.

| Code | Rejection |
| --- | --- |
| `INVALID_CONTEXT` | Constructor argument is not a genuine context-bound logger |
| `INVALID_LABEL` | Container label is invalid |
| `INVALID_STATE` | Add or cleanup re-entry is invalid in the current state |
| `UNSUPPORTED_TASK` | Value is outside the supported task union |
| `INVALID_NESTED_STATE` | Nested container is not `Active` at registration |
| `NESTING_CYCLE` | Nested ownership would become cyclic |
| `CLEANUP_FAILED` | One or more tasks failed after the full sweep completed |

## Bootstrap integration

After place-role and Packet 04.5 whole-configuration validation, each common
bootstrap starts its lifecycle and creates a `bootstrap` cleanup container using
its own server or client logger. The environment context distinguishes the
otherwise identical container labels. Invalid configuration exits before the
lifecycle or cleanup container exists, so there is no partial owner to unwind.

Each container owns one real callback that shuts down its existing lifecycle
runner if that runner is still `Started`. The Studio-only ready record therefore
reports:

```text
[cleanupState=Active][cleanupTaskCount=1]
```

Packet 03.4 now invokes the server container from the one ordered
`BindToClose` path. The Match client entrypoint additionally connects the exact
LocalScript's `Destroying` signal to its bootstrap cleanup. No save operation
was added. Phase 08's `MatchReadyController` owns and releases its real
remote/render/GUI connections, request state, input binding, view model, and
ScreenGui through its idempotent lifecycle shutdown. Phase 09's
`EnemyController` independently owns its enemy endpoint listeners, one shared
`PreRender` connection, tracker/state buffers, renderer, placeholder Models, and
client-created visual root through the same reverse lifecycle path. Phase 10's
`BaseController` independently owns its two endpoint listeners, tracker and
bounded recovery state, marker/UI watchers, one cancellable feedback tween, and
client-created BillboardGui.

Packet 06.1's `NetworkRegistry` lifecycle service creates one internal
`network-registry` cleanup container during initialization. Packet 06.4 preserves
that owner while making its complete registration order explicit: the
unparented `ATDNetwork` root first, the rate-limiter child second, the request
dispatcher child third, and captured inbound listener connections last. The
reverse sweep is therefore listener connections, dispatcher, limiter, then the
exact root.

The dispatcher child owns a state-clearing callback followed by its own
`PlayerRemoving` connection, so its reverse sweep first disconnects that
connection and then invalidates and releases all bounded pending/completed
request-ID ledgers, registered contracts, protocol aggregates, and failure
counters. The limiter child independently disconnects its own `PlayerRemoving`
connection before clearing all Player buckets and limiter aggregate state. A
departing Player triggers both narrowly scoped callbacks: dispatcher correlation
and limiter state are released independently, without trusting a client identity.

Initialization failures roll back only those owned resources; pre-existing
conflicting Instances are diagnosed and preserved. A cleanup failure is
contained as a static network error, and no arbitrary callback, request ID,
payload, or rejected endpoint value is retained or logged.

The outer server `bootstrap` container still owns exactly one callback: lifecycle
shutdown. That reverse lifecycle call reaches the network service's internal
container through the existing graceful-shutdown path, so no duplicate root,
connection owner, or `BindToClose` hook is introduced.

`ClientRequestTracker` is not a lifecycle service. Its explicit `clear()`
operation drops all pending and recent terminal correlation state. The Phase 08
Match ready controller owns both fixed response listeners and the outbound-event
listener, cancels its authentic live Pending values where possible, and calls
`clear()` during shutdown. Clearing client correlation never cancels or
authorizes a server request.

Phase 07's `MapLoader` creates a fresh `match-map-loader` Cleanup container for
each load. It registers the detached clone immediately, publishes only after
both validation passes and snapshot derivation, and destroys that exact clone
on rollback, `unload()`, or terminal `cleanup()`. Idempotent unload/reload and
cleanup leave no runtime root, template reference, cache, connection, or mutable
query state; pre-existing conflicting roots are preserved.

## Phase 08 Match ownership and release order (historical baseline)

The Match server lifecycle registers child ownership in dependency order:
MapLoader cleanup, state-machine cleanup, roster cleanup, PlayerAdded and
PlayerRemoving connections, snapshot-broadcaster cleanup, then ready-coordinator
cleanup. Reverse cleanup therefore:

1. invalidates and cancels the authoritative Ready timer and prevents any later
   callback from rescheduling or publishing;
2. cancels the broadcaster's one flush handle and clears its one coalesced
   snapshot slot and counters;
3. disconnects both Player listeners;
4. clears roster records, UserId epochs, weak live-connection keys, and detached
   snapshot state;
5. cleans the terminal state-machine snapshot; and
6. invokes the owned MapLoader's terminal cleanup and removes only the exact
   `Workspace.ATDRuntimeMap` that it published.

The service sets callbacks unavailable before this sweep. Shutdown first moves
any nonterminal match through `Closing`, and a MapLoader cleanup failure is
converted to one static failure so lifecycle shutdown cannot report success
while an owned runtime root may remain. Repeated shutdown and child cleanup are
idempotent; pre-existing or unrelated Studio instances are never adopted or
deleted.

The Match client controller uses the corresponding reverse dependency order:
unbind the scoped context action; disconnect Activated, RenderStepped, event,
and response listeners; cancel owned Get/Ready Pending states and clear the
tracker; clear the view model and locked snapshot identity; then destroy the
exact `ATDMatchReadyGui`. The Match LocalScript's `Destroying` connection is
owned by the outer client bootstrap cleanup and is disconnected before reverse
lifecycle shutdown. Every callback checks the controller's live state, so a
captured post-clean test callback cannot send, render, recover, or mutate.

The deterministic Phase 08 suites cover timer invalidation, early callbacks,
roster and snapshot mutation isolation, state-exit Pending cancellation,
listener/input/GUI release, repeated cleanup, and no post-clean callbacks. The
four-client Studio gate also ended every server/client session with no runtime
map or ready UI residue and returned Studio to Edit mode. The consolidated
review and complete local exit gate pass; Phase 08 is complete and Phase 09 is
next but has not begun at that dated checkpoint. The current extension follows.

## Phase 09 enemy ownership and release order (historical current-at-completion extension)

At Phase 09 completion the Match lifecycle order was:

```text
server initialize/start: NetworkRegistry -> MatchLifecycle -> EnemySimulation
server shutdown:         EnemySimulation -> MatchLifecycle -> NetworkRegistry
client initialize/start: MatchReadyController -> EnemyController
client shutdown:         EnemyController -> MatchReadyController
```

`EnemySimulation` owns one server `Heartbeat` connection for all enemies and one
service-level `PlayerRemoving` connection for snapshot-request accounting. It
creates no per-enemy connection, task, timer, coroutine, or cleanup container.
On shutdown it first disables spawn, snapshot-request, simulation/update, and
publication callbacks. It disconnects both owned connections, destroys the
Studio-only trigger, and cleans the publisher and runtime store. Publisher
cleanup clears pending/dirty replication queues, retained representations,
snapshot IDs/counters, sender/recipient references, and the weak per-Player
request ledger. Store cleanup clears active records, issued IDs, terminal
outcomes, authenticated definitions, and detached lane state. Timing samples and
construction references are also released. The cleanup is idempotent and a
captured post-clean callback cannot spawn, request, simulate, publish, or retain
enemy state.

Only after enemy cleanup does `MatchLifecycle` invalidate Ready work, disconnect
its Player-added/removing listeners, clear roster and match state, and clean the
one MapLoader and exact `Workspace.ATDRuntimeMap`. `NetworkRegistry` then
disconnects its endpoint listeners and the dispatcher/limiter Player-removal
listeners, clears their request ledgers and buckets, and destroys the exact
remote root. Thus the enemy service cannot read a released map snapshot or
publish through a destroyed network tree.

`EnemyController` owns its `EnemyReplication` event listener,
`GetEnemySnapshot` response listener, and one shared `PreRender` connection for
every visual. Reverse connection cleanup stops render first, then snapshot
response and replication delivery. It cancels the live Pending request and
clears the request tracker; clears locked match/epoch identity, records,
tombstones, snapshot assembly/receipt, gap buffer, recovery flags, and cached
render state; then cleans the renderer, destroying every exact three-Part enemy
Model and the exact client-created `Workspace.ATDEnemyVisuals` root. The later
`MatchReadyController` cleanup unbinds input, disconnects its render,
activation, match-event, and response listeners, clears its tracker/view model,
and destroys the exact Ready GUI. The outer LocalScript `Destroying` connection
is disconnected before the reverse client lifecycle sweep.

The exact two-client Match Studio gate passed this ownership boundary on
2026-08-27 with one server simulation connection, one enemy render connection
per client, and no enemy record, request ledger, queue, buffer, trigger, visual,
runtime map, remote root, Ready UI, or service connection after End Session.
The consolidated review and complete local/structural gates also pass. Phase 09
is complete. The historical Phase 10 ownership extension follows; Phase 11
ownership had not been introduced at that checkpoint.

## Phase 10 base ownership and release order (historical)

The current order is:

```text
server shutdown: EnemySimulation -> BaseRuntime -> MatchLifecycle -> NetworkRegistry
client shutdown: EnemyController -> BaseController -> MatchReadyController
```

EnemySimulation first closes spawn, endpoint callbacks, snapshot requests,
updates, and publication; disconnects its shared connections; destroys the sole
Studio trigger; revokes issued outcome provenance; and clears active/terminal
enemy state and publisher queues. Only then may BaseRuntime disable its
snapshot/record/boundary callbacks and clear its copied outcome ledger,
feedback aggregate, publication state, health, independent revision, identity,
result seed, clocks, provenance predicate, callbacks, and detached
map/difficulty references. MatchLifecycle subsequently clears terminal-recipient
capture, roster/state, and the exact runtime map, and NetworkRegistry destroys
the one remote root last.

On clients, EnemyController releases its render connection and visuals before
BaseController disconnects `BaseReplication` and `GetBaseSnapshot` response,
cancels/clears request correlation, releases marker and UI ancestry watchers,
cancels its active damage tween, clears locked snapshots/feedback/recovery
state, and destroys the exact `ATDDefenderBaseGui` from PlayerGui. The later
Ready cleanup remains unchanged. Deleted UI can recreate only while the
controller is live; captured callbacks after cleanup cannot send, bind, tween,
or recreate.

The exact Studio gate retained constant BaseController/BaseWorldView ownership
of `2/38` connections per client; one temporary evidence probe was explicitly
disconnected. End Session left no base state, outcome ledger, result seed,
publication queue, listener, UI, tween, trigger, enemy, network root, runtime
map, request record, visual, or cache. Cleanup remained idempotent and Studio
returned to Edit mode without save or publish.

## Focused Studio Edit-mode validation

Three read-only Studio Edit-mode harness groups cloned and required the current
Rojo-synchronized module to avoid stale `require` cache entries. All 19 focused
cases passed:

| Area | Verified behavior |
| --- | --- |
| Supported values | Connection, Instance, live/dead thread, callback, and nested container |
| Existing terminal values | Disconnected connection, destroyed Instance, and dead thread are harmless |
| Ordering | Exact three-callback LIFO order and duplicate registrations |
| Idempotence | Successful cleanup runs once; failed cleanup reproduces the same cached error |
| Threads | Cancelled delayed task never executes |
| Nesting | Child order, direct cycle, indirect three-container cycle, and cleaned-child rejection |
| State guards | Late add, add during cleanup, and cleanup re-entry |
| Type safety | Number and metatable-spoofed table rejected without mutation |
| Failure handling | Callback and nested-container failures aggregate after later siblings clean |
| Context | Invalid label and every rejection's stable code/container/state fields |

Temporary test Instances remained unparented or under an unparented temporary
root and were destroyed before the harness returned. No Studio-authored content
was created or saved. This is historical Studio evidence, not a committed test
framework.

Packet 05 subsequently added persistent headless coverage. The current Cleanup
suite contains 14 deterministic cases covering ordering, ownership, supported
task forms, idempotence, nesting/cycles, reentry, post-clean guards, cached
failures, and sibling failure isolation. Run `lune run tests/run.luau`; the
environment distinction and cleanup rules are indexed in `docs/TEST_MATRIX.md`.

The current network-runtime, rate-limiter, dispatcher, and client-tracker suites
exercise listener-before-dispatcher-before-limiter-before-root LIFO cleanup,
rollback after partial initialization, preservation of pre-existing root
conflicts, duplicate-owner/re-entry rejection, both exact Player-removal state
releases, whole-child shutdown clearing, explicit client correlation clearing,
and removal of the exact published root. Packet 06.5 adds nine integrated
adversarial cases over those real boundaries; the Phase 06 canonical run passed
all 200 cases across 16 suites. Phase 07 added focused loader rollback,
unload/reload, and cleanup coverage; its complete local run passed 241 cases
across 19 suites. Packet 06.5 and the fresh Phase 06/Gate A audit pass,
including clean workflow run `33022784985`. Phase 07's cleanup gate is also
complete.

Packet 03.3 reran 10 focused cleanup cases through the logger-based constructor.
Supported runtime types, LIFO/idempotence, state/nesting guards, failure
continuation, cached failure equality, and constructor authenticity passed. A
deliberate secret sentinel thrown by a cleanup callback was absent from both the
first aggregate error and its exact cached repeat.

Packet 03.4 additionally verified cleanup inside the bounded server-shutdown
runner. Normal and repeated cleanup reached `Cleaned`; failure still completed
the sweep; a yielding task that crossed the private wait deadline was allowed
to finish later instead of being canceled and poisoning the container state.

## Historical Packet 03 toolchain and build verification

| Check | Result |
| --- | --- |
| `stylua src` | Pass |
| `stylua --check --verify src` | Pass |
| `selene src` | Pass; 0 errors, 0 warnings, 0 parse errors |
| `rojo build default.project.json` | Pass |
| `rojo build lobby.project.json` | Pass |
| `rojo build match.project.json` | Pass |
| Shared mapping | Pass; `Cleanup` appears in all three builds |
| Role isolation | Pass; Lobby has no match source and Match has no lobby source |

The ignored verification builds were inspected and removed. Generated place
files remain untracked under `docs/CODE_STYLE.md`.

## Historical isolated Studio verification

Both isolated places synchronized the shared utility and booted without an
application warning or error:

This table records the then-current pre-network lifecycle. Phase 06 has since
added one foundation-only `NetworkRegistry` server service and its nested remote,
limiter, dispatcher, connection, and state ownership while the client remains at
zero services. The table remains historical rather than current Phase 06 Studio
evidence.

| Place | Role/PlaceId | Lifecycle | Cleanup | Opposite-role executable source |
| --- | --- | --- | --- | ---: |
| Lobby | `Lobby` / `100561454756026` | `Started`, 0 services | `Active`, 1 task | 0 |
| Match | `Match` / `136401514513678` | `Started`, 0 services | `Active`, 1 task | 0 |

Both Play sessions were stopped and returned to Edit mode. No external service,
save, or publish operation occurred.

Packet 06.5 subsequently passed the then-current unsaved networking regression.
Three plain Lobby and three plain Match Play/Stop cycles each reported one
server `NetworkRegistry` service, zero client services, and clean shutdown. The
final runtime-only Match harness used two clients and proved real
`PlayerRemoving` cleanup while the remaining peer completed another request.
The test-only fixture's separate cleanup reached `Cleaned`; the production
`ATDNetwork/v1` tree remained empty; the server and remaining-client terminals
reported `caseCount=10`; and bounded Output audits reported
`forbiddenMatches=0` and `errorCount=0`. See
`docs/NETWORK_SECURITY_STUDIO_REGRESSION.md`.

## Manual regression procedure

1. Connect `lobby.project.json` only to the Lobby place.
2. Confirm `ReplicatedStorage.Shared.util.Cleanup` exists.
3. Play and expect server/client ready records with lifecycle `Started`, cleanup
   `Active`, and one outer cleanup task. The server has one registered
   `NetworkRegistry` service; the client has zero services.
4. Confirm no match executable source and stop Play.
5. Repeat through `match.project.json`, expecting role `Match`, server service
   order `NetworkRegistry -> MatchLifecycle -> EnemySimulation`, client service
   order `MatchReadyController -> EnemyController`, and counts `3`/`2`.
6. When using the Phase 09 Studio-only trigger, confirm one shared enemy
   `Heartbeat` and one shared enemy `PreRender` connection per client. Stop Play
   and confirm no enemy queue, ledger, record, buffer, trigger, visual root,
   runtime map, remote root, Ready UI, or service connection remains.
7. Do not save or publish merely to run this regression.

Phase 03 is complete. Packet 03.4 evidence is in
`docs/GRACEFUL_SHUTDOWN.md`. Packet 04.5 now gates construction before cleanup
ownership without changing this cleanup behavior. Packet 06.1's completed
network ownership contract is described in `docs/NETWORK_PROTOCOL.md`; it reuses
the same contract. Packet 06.5 is complete with review-driven dispatcher
hardening, test-only adversarial fixtures, and unsaved Studio evidence. The
fresh Phase 06/Gate A audit and clean workflow run `33022784985` pass. Phase 06
is complete and Gate A passed. Phase 08 is also complete. Phase 09 code, exact
Match Studio cleanup evidence, consolidated review, 467-case local gate, and all
four structural builds pass on 2026-08-27. Phase 09 is complete. Phase 10's
focused and exact Studio cleanup evidence, consolidated review, complete local
gate, and all four structural builds passed on 2026-08-28. Phase 10 is complete;
exact-final-SHA CI is cited at its handoff. Phase 11 remained unbegun at that
historical checkpoint. Earlier cleanup evidence is in
`docs/ENEMY_SIMULATION.md` and `docs/BASE_RUNTIME.md`.
Configuration evidence is in
`docs/CONFIGURATION_VALIDATION.md`.

## Phase 11 Wave ownership and release order (current)

Wave owns the authenticated configuration reference and detached starting-cash
placeholder; schedule heap, origin cursors, backlog state, absolute timestamps,
per-origin counters, RuntimeEnemyId ownership and processed-outcome ledgers;
vote and Active-UserId copies; revision/publication queue and boundary adapter;
request state; and the Studio trigger. The client owns one detached reducer
snapshot, bounded request/recovery generations, pending skip state, diagnostics,
and exactly three listeners. None retains a Player, Instance, UI, authored
definition copy, per-wave task, or timer.

Shutdown first closes Wave request, vote, spawn, boundary, completion, terminal,
publication, and Studio-trigger admission. It detaches the Enemy boundary and
clears the heap/cursors/origins, ownership/outcomes/counters, votes/roster copies,
publisher queue, recoverable `Faulted` snapshot, starting-cash placeholder,
identities/revisions/timestamps, and client cache/listeners. Enemy then clears its
single step and PlayerRemoving connections, Store, publisher, committed-spawn
reconciliation pair, terminal token, trigger, and active enemies; Base,
Match/Map, and Network follow in reverse dependency order.

The exact Match Studio scenarios ended every two-client server, found zero Wave,
Enemy, Base, runtime-map, network-root, trigger, request, timer, connection, UI,
cache, or retained-instance residue, and left Studio in Edit mode without save or
publish. Headless cleanup repeats shutdown, invokes captured stale callbacks,
and proves no post-clean mutation or publication.

## Phase 12 Tower ownership and release order (current)

While configured, TowerRuntime owns one exact canonical configuration
reference; detached participant snapshot; four-user/five-slot loadout indexes;
temporary UnitIds; issued/prepared capability ledgers; RuntimeTower identity,
active/lifetime/cap counters, and records; three private graybox templates;
live Models indexed by RuntimeTowerId; at most one privately authenticated
`Workspace.ATDTowerRuntime` Folder; one MatchLifecycle observer; and one
Studio-only Wave boundary. Runtime records own no Player or Instance, and the
model owner owns no gameplay truth. There is no per-user, per-slot, per-tower,
per-level, or per-model connection, task, timer, or loop.

Cleanup first closes participant, create/remove/recreate, diagnostics mutation,
and evidence admission. Normal lifecycle shutdown then detaches the Tower Wave
boundary and revokes the exact participant handle. Wave-originated close skips
the callback into Wave because Wave is already executing that boundary and
invalidates it itself. Both paths revoke every capability, destroy prepared/live
owned Models and the exact owned root, destroy private templates, clear records
and cap counters, clear every loadout/slot/UnitId and canonical identity, and
enter `Cleaned`. Captured observer callbacks and capabilities are inert after
closure. Cleanup is idempotent and never adopts or destroys a foreign
same-named Workspace object.

The final-source accepted primary Studio cleanup removed twelve active
records/Models and all supporting state in `0.0019925` seconds. The fresh
final-source defeat rerun proved that
the authentic cleanup-only participant detach remains available after ordinary
Match callbacks close and removed three unchanged Tower records/Models in
`0.0015069` seconds. Both returned exact all-zero residue receipts, rejected
late creation with `UNAVAILABLE`, removed the runtime root on server and both
clients, recorded zero console errors, and left the unchanged Match place in
Edit mode without save or publish. The focused MatchLifecycle regression also
proves reserve/refresh/activate remain unavailable after committed defeat and
detach remains unavailable after lifecycle shutdown.

Fatal child Store or rollback failure is now adopted at the Tower coordinator:
admission closes, service capability expectations clear, both Stores fault, and
later work is unavailable. Cleanup remains the sole owner of any prepared
child residue; no failure reopens allocation.
