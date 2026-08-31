# Common Service Lifecycle Contract

## Purpose

This document records the implementation and verification evidence for Packet
03.1 of `docs/DEVELOPMENT_PLAN.md`. The lifecycle contract gives future common,
lobby, and match services one typed startup model without introducing any
gameplay service, network boundary, cleanup utility, logging framework, or
automatic shutdown hook.

## Packet status

- Packet: 03.1
- Status: Complete
- Recorded: 2026-08-25
- Shared implementation: `src/shared/lifecycle/ServiceLifecycle.luau`
- Bootstraps integrated: common client and common server only
- Registered production services: 0
- Gameplay behavior added: none
- Studio-authored content changed: no
- Place saved or published: no

Those fields record Packet 03.1 at completion. Packet 06.1 later registered one
foundation-only `NetworkRegistry` service on the server after configuration
validation. Phase 08 added the Match-only `MatchLifecycle` server service and
`MatchReadyController` client service. Phase 09 added `EnemySimulation` and
`EnemyController`; Phase 10 added `BaseRuntime` and `BaseController` between
those Match owners. Phase 11 adds `WaveRuntime` after EnemySimulation and
`WaveController` after EnemyController. Phase 12 adds the server-only
`TowerRuntime` after WaveRuntime and no client controller at that checkpoint.
Phase 13 adds `TowerPlacement` after TowerRuntime and
`TowerPlacementController` after WaveController. Phase 08 and its Studio, consolidated-review, and
complete-local-gate evidence passed on 2026-08-27. Phase 09 code, exact Match
Studio gate, consolidated review, 467-case local gate, and all four structural
builds passed on 2026-08-27. Phase 09 is complete. Phase 10 focused and exact
Studio checks, consolidated review, `593`-case local gate, and all four
structural builds passed on 2026-08-28. Phase 10 is complete; exact-final-SHA CI
is cited at handoff. Phase 11's exact Studio, consolidated-review,
`742`-case/`56`-suite local, and four-build gates also pass. Phase 11 is complete;
Phase 12 focused and exact unsaved Studio lifecycle/cleanup checks,
consolidated review, `840`-case/`64`-suite local gate, and all four structural
builds pass. Phase 12 is complete; exact-final-SHA CI is recorded at handoff,
and the current Phase 13 composition is recorded below.

## Public contract

`ServiceLifecycle.new(logger)` creates an independent runner. The argument must
be a genuine context-bound logger from `src/shared/logging/Log.luau`; that
logger supplies client/server, place-role, PlaceId, and Studio/production
context without a second lifecycle-specific setting. A runner exposes:

| Method | Valid state | Successful next state or result |
| --- | --- | --- |
| `register(service)` | `Registering` | Remains `Registering` |
| `initialize()` | `Registering` | `Initialized` |
| `start()` | `Initialized` | `Started` |
| `shutdown()` | `Started` | `Shutdown` |
| `getState()` | Any | Current typed lifecycle state |
| `getRegisteredServiceCount()` | Any | Number of registered services |
| `getServiceOrder()` | After order resolution | New array of ordered service names |

A service definition has one required unique `name`, an optional array of
dependency names, and optional zero-argument `initialize`, `start`, and
`shutdown` functions. Registration validates and snapshots the definition; the
runner does not retain a caller-owned dependency table.

Service names must start with an ASCII letter and may then contain letters,
digits, `_`, `.`, or `-`. Dependencies are explicit names, not module load order
or implicit table iteration order.

## Deterministic ordering

Initialization resolves a stable topological order:

1. Every dependency must already have a registered definition by the time
   `initialize()` is called.
2. A dependency always initializes and starts before its dependents.
3. When multiple services are eligible at the same time, registration order is
   the tie-breaker.
4. Initialization and start traverse the resolved order forward.
5. Explicit shutdown traverses the resolved order in reverse, so dependents
   release before their dependencies.

The resolved name array returned by `getServiceOrder()` is a copy. Callers
cannot mutate the runner's internal order.

## State and failure behavior

The complete state set is:

```text
Registering -> Initializing -> Initialized -> Starting -> Started
                                                     -> ShuttingDown -> Shutdown
Any invoked lifecycle method failure -> Failed
```

Registration is closed as soon as initialization begins. Repeating a stage,
skipping a stage, registering late, requesting the order too early, or invoking
shutdown before start is rejected. A lifecycle callback is protected with
`pcall`; if it throws, the runner becomes `Failed` before the contextual error
is raised. Arbitrary callback error text is discarded and replaced with a
static summary so callback secrets cannot be reflected into Output.

Packet 03.1 originally did not define rollback after partial initialization or
startup. Phase 08 hardens the current runner with a transactional unwind:

- initialization stops forward traversal at the first failure, then invokes
  `shutdown` in reverse order from the failing service through every service
  already reached;
- startup stops forward traversal at the first failure, then invokes `shutdown`
  for every initialized service in reverse resolved order; and
- explicit shutdown always attempts every service in reverse resolved order,
  even if one or more shutdown callbacks fail.

The runner remains `Failed` after any of these failure paths. Initialize/start
report the service whose forward callback failed; explicit shutdown reports the
first service that failed in reverse traversal. Unwind callback errors never
replace that primary static diagnostic, and no arbitrary callback error text is
reflected. Cleanup ownership still belongs to Packet 03.2, while process
shutdown hooks belong to Packet 03.4.

## Structured development errors

Lifecycle rejections use this directly readable structure:

```text
[ATD][ERROR][context=<client|server|unknown>][role=<role>][placeId=<id>][environment=<environment>][subsystem=lifecycle][event=<event>][code=<code>][service=<name-or-runner>][state=<state>] <message>
```

Every error identifies execution context, place role, PlaceId, runtime
environment, lifecycle event, stable error code, affected service (or
`<runner>`), and state. Construction with an invalid logger uses the canonical
unknown-context fallback and `state=Uninitialized` because no runner exists yet.

| Code | Rejection |
| --- | --- |
| `INVALID_CONTEXT` | Constructor argument is not a genuine context-bound logger |
| `INVALID_STATE` | Operation is unavailable in the current state |
| `INVALID_SERVICE` | Service definition is not a table |
| `INVALID_SERVICE_NAME` | Service or dependency name is invalid |
| `DUPLICATE_SERVICE` | A service name is registered twice |
| `INVALID_DEPENDENCIES` | Dependencies are not a contiguous array |
| `DUPLICATE_DEPENDENCY` | One service lists the same dependency twice |
| `INVALID_METHOD` | A lifecycle field is neither a function nor `nil` |
| `MISSING_DEPENDENCY` | A named dependency was not registered |
| `DEPENDENCY_CYCLE` | No valid topological order exists |
| `INITIALIZE_FAILED` | A service initialization callback threw |
| `START_FAILED` | A service start callback threw |
| `SHUTDOWN_FAILED` | A service shutdown callback threw |

These are development diagnostics emitted through Packet 03.3's local logger,
not a recoverable gameplay-result API. Service names and messages remain
developer-authored metadata; arbitrary player or service payloads must never be
passed into them.

## Bootstrap integration

The common server and client bootstrap owners validate the centralized place
role and the complete nine-family configuration before creating a lifecycle
runner. Each resolves one environment context, creates one local logger, calls
the shared `ConfigurationValidator.validateLoaded()` gate, and passes the
logger to the runner only after success. At the historical Phase 06 checkpoint
the client initialized an empty runner and the server registered only
`NetworkRegistry`. The current Phase 10 Match composition extends those
validated owners without bypassing them:

```text
Lobby server/client: [serviceCount=1]/[serviceCount=0]
Match server/client: [serviceCount=4]/[serviceCount=3]
```

The runner remains local to its bootstrap. No global registry or service locator was
introduced. Packet 03.2 subsequently registered each runner's existing
`shutdown()` operation as a callback in its bootstrap cleanup container. Packet
03.4 now invokes the server container through the one ordered `BindToClose`
path. The lifecycle runner therefore shuts down in reverse dependency order
before the server hook completes. The Match client composition also connects
its exact LocalScript's `Destroying` signal to client bootstrap cleanup; Lobby
retains the common historical behavior.

Invalid configuration raises a structured error before `ServiceLifecycle.new`,
so no partially validated configuration can reach a service and no runner needs
rollback. The valid path and every lifecycle state contract remain unchanged.

Phase 07's server-only `MapLoader` remains a child resource rather than a
separate lifecycle service. Phase 08 `MatchLifecycle` constructs it for the
fixed server-selected `map:phase07-graybox`, owns it through Loading, fails
closed through `Closing` on load failure, and invokes its terminal `cleanup()`
during Match shutdown.

The network service has no declared dependencies. Its lifecycle callbacks own a
separate typed state machine: initialization creates the fixed server-owned tree
before parent-last publication, initializes the server limiter, initializes the
secure request dispatcher, and then binds the captured endpoint listeners. The
parent cleanup container registers the remote root first, the limiter child
second, the dispatcher child third, and inbound listeners last. Reverse LIFO
cleanup therefore disconnects endpoint listeners, cleans the dispatcher,
cleans the limiter, and destroys the root in that exact order.

The dispatcher and limiter each own a distinct `PlayerRemoving` connection. The
dispatcher connection removes the departing Player's bounded pending/completed
request-ID ledger and invalidates in-flight work; the limiter connection removes
that Player's token buckets. Each child disconnects its own connection before
clearing all remaining ledgers or buckets and aggregate state during whole-service
shutdown. These children are not lifecycle services and add no independent
close hook.

Start starts the limiter and then the dispatcher before the network owner reaches
`Started`; it changes no endpoint definition. Registration is split into
`registerRequest` and `registerEvent`, and each call creates one authenticated
schema/authorization/handler contract for an active fixed definition. The old
raw-handler route is absent. Duplicate initialization, start, shutdown, or
contract registration is rejected rather than creating duplicate resources.
The existing reverse lifecycle and outer bootstrap cleanup remain the sole
shutdown route.

## Phase 08 Match composition (historical baseline)

`src/server/common/bootstrap/ServerBootstrap.luau` performs role and complete
configuration validation, constructs `NetworkRegistry`, and exposes a bounded
configuration callback while the runner is still Registering. The Match server
entrypoint uses that callback to register the two authenticated requests and one
outbound snapshot sender, then registers `MatchLifecycle` with the exact
dependency `{ "NetworkRegistry" }`. The resolved server order is therefore:

```text
initialize/start: NetworkRegistry -> MatchLifecycle
shutdown:         MatchLifecycle -> NetworkRegistry
```

`MatchLifecycle` owns one immutable MatchId; the strict `Loading`,
`ReadyCheck`, `PreWave`, `WaveActive`, `Results`, and `Closing` state machine;
revisioned frozen snapshots; a roster keyed by validated UserId; Player-added
and Player-removing connections; the fixed Phase 07 MapLoader; the ready
coordinator; and the bounded snapshot broadcaster. Player Instances are used
only as live authenticated connection keys and are absent from detached roster
queries and snapshots. Disconnect immediately recomputes the current Active
threshold without replacing match identity.

Loading selects only `map:phase07-graybox`. Successful loading enters the
server-owned ReadyCheck with one exact 45-second absolute deadline. The clock,
scheduler, and cancellation operations are injected in tests, so no headless
case waits in real time. All current Active participants ready progresses to
`PreWave`; mixed timeout marks unready Active records `Returned` before
progression; zero-ready timeout enters terminal `Closing`. Phase 08 never
invokes `PreWave -> WaveActive` and starts no wave or combat behavior.

`src/client/common/bootstrap/ClientBootstrap.luau` applies the same role and
configuration gates. The Match client entrypoint then registers exactly one
`MatchReadyController` service. That service owns the fixed remote lookups,
request tracker, first-snapshot MatchId lock, revision filtering, presentation
clock projection, `MatchReadyViewModel`, and the one `MatchReadyView`. It binds
`TextButton.Activated`, keyboard `R`, and gamepad `ButtonA`; the context action
creates no touch button. Its service shutdown unbinds input, disconnects render,
GUI, and remote listeners, clears Pending correlation and view-model state, and
destroys the exact ScreenGui. The entrypoint's `script.Destroying` connection
triggers the same idempotent client bootstrap cleanup.

Packets 08.1–08.5, the four-client Studio gate, consolidated final review, and
complete local exit gate passed. At that dated checkpoint Phase 08 was complete
and Phase 09 was next but had not begun. The current Phase 09 extension follows.

## Phase 09 Match composition (historical current-at-completion extension)

At Phase 09 completion, the Match server entrypoint bound the authenticated
`GetEnemySnapshot` request and captured the `EnemyReplication` sender while
`NetworkRegistry` was still Registering. It constructed `EnemySimulation` from
`MatchLifecycle`, the validated production enemy catalog, and that sender, then
registered its service definition with exact dependencies
`{ "NetworkRegistry", "MatchLifecycle" }`. The resolved server order was:

```text
initialize/start: NetworkRegistry -> MatchLifecycle -> EnemySimulation
shutdown:         EnemySimulation -> MatchLifecycle -> NetworkRegistry
```

`EnemySimulation` captures the immutable MatchId and detached frozen runtime-map
snapshot only after `MatchLifecycle` has loaded the map. It owns exactly one
shared server `Heartbeat` connection for all enemies and one service-level
`PlayerRemoving` connection for the bounded snapshot-request ledger; enemy
records do not own connections, tasks, timers, or coroutines. Shutdown first
closes spawn, snapshot-request, simulation/update, and publication admission. It
then disconnects both owned connections, destroys the Studio-only runtime
trigger, clears the publisher's pending and coalesced queues, representations,
snapshot publication state/counters, and per-Player request ledger, clears the
runtime store and all active, issued-ID, and terminal state, and releases
retained timing/dependency references. Only after that may `MatchLifecycle`
cancel Ready work, disconnect its Player listeners, clear Match state, and clean
the MapLoader/runtime map; the network registry and remote tree shut down last.

The Phase 09 Match client entrypoint registered `EnemyController` after
`MatchReadyController`. Its service definition depended on
`{ "MatchReadyController" }`, so the resolved client order was:

```text
initialize/start: MatchReadyController -> EnemyController
shutdown:         EnemyController -> MatchReadyController
```

`EnemyController` owns the `EnemyReplication` event listener,
`GetEnemySnapshot` response listener, request tracker, replication state and
bounded recovery buffers, renderer, and exactly one `PreRender` connection for
all enemy visuals. No enemy Model owns a render connection. Its shutdown closes
callbacks, disconnects the render and endpoint listeners, cancels and clears
request correlation, clears locked identity/records/tombstones/snapshot and gap
buffers, and destroys every exact owned visual Model and the client-created
`Workspace.ATDEnemyVisuals` root. `MatchReadyController` then disconnects its
match response/event, render, activation, and input bindings, clears its tracker
and view-model state, and destroys its Ready UI. Finally the outer bootstrap
owner completes; its LocalScript `Destroying` listener still invokes this same
idempotent reverse lifecycle path.

Packets 09.1–09.5 and the exact two-client Match Studio gate passed on
2026-08-27, including constant one-server-simulation/one-client-render
connection ownership and residue-free shutdown. The consolidated review and
complete local/structural gates also pass. Phase 09 is complete. The historical
Phase 10 extension follows; Phase 11 had not begun at that checkpoint.

## Phase 10 Match composition (historical)

The Match entrypoints bind `GetBaseSnapshot` and capture `BaseReplication` while
NetworkRegistry is still Registering. The server registers BaseRuntime after
MatchLifecycle and before EnemySimulation; EnemySimulation declares BaseRuntime
as a dependency. The client registers BaseController after MatchReadyController
and makes EnemyController depend on BaseController. The resolved order is:

```text
server initialize/start: NetworkRegistry -> MatchLifecycle -> BaseRuntime -> EnemySimulation
server shutdown:         EnemySimulation -> BaseRuntime -> MatchLifecycle -> NetworkRegistry
client initialize/start: MatchReadyController -> BaseController -> EnemyController
client shutdown:         EnemyController -> BaseController -> MatchReadyController
```

BaseRuntime authenticates and copies only detached difficulty/map identity and
base state; it owns no Player, enemy Instance, map marker Instance, UI, or client
object. Its synchronous endpoint sink mutates health and the bounded ledger but
never re-enters EnemySimulation. Defeat work is returned to EnemySimulation's
next safe pass boundary, where spawn closes and remaining enemies terminalize
before MatchLifecycle commits Results through its narrow opaque-token API.
Initialization, start, shutdown, callbacks, transition, publication, and cleanup
faults are non-yielding and fail closed.

BaseController owns two remote connections, bounded request/recovery state,
BaseStateReducer/BaseViewModel state, one BaseWorldView, marker ancestry
watchers, and at most one cancellable feedback tween. It has no permanent render
loop. Reverse client cleanup removes enemy presentation first, then base
listeners/UI/tween, and then Ready state. The exact Studio gate retained constant
`2/38` BaseController/BaseWorldView connections per client, cleaned its one
temporary evidence probe, and left no runtime residue.

## Focused Studio Edit-mode validation

A read-only Studio Edit-mode harness required the Rojo-synchronized module and
executed assertions against fresh runners. All 17 cases passed:

| Area | Verified behavior |
| --- | --- |
| Success | Three-service dependency graph, registration-order tie-break, forward initialize/start, reverse shutdown, all state transitions |
| Empty boot | Zero-service client runner reaches `Initialized`, `Started`, and `Shutdown` |
| Registration | Duplicate service and duplicate dependency rejected |
| Dependencies | Missing dependency and two-service cycle rejected |
| Methods | Non-function lifecycle method rejected |
| State guards | Start/shutdown/order before initialization, late registration, repeated start, and repeated shutdown rejected |
| Context | Invalid runner context rejected |
| Callback failures | Initialize, start, and shutdown errors preserve context/service details and leave state `Failed` |

Every rejection assertion checked relevant structured fields rather than merely
checking that some error occurred. This was executed against the synchronized
Lobby copy of the real module, not a rewritten test double. Packet 03.1 did not
pull a persistent framework forward.

Phase 05 subsequently added a repository-owned runner. It does not include a
dedicated general `ServiceLifecycle` suite; the network-runtime suite instead
exercises the frozen network service definition and its
initialize/start/shutdown state adapter. Packet 06.4 extends that composition to
the limiter, dispatcher, two `PlayerRemoving` owners, and fixed listener
bindings. Packet 06.5 adds nine integrated adversarial cases that exercise the
same registry, limiter, dispatcher, protocol, client tracker, Player-removal,
and whole-network cleanup boundaries. That Phase 06 canonical run passed all
200 cases across 16 suites. Phase 07 added separate focused map suites without
changing this lifecycle contract; its complete local run passed 241 cases across
19 suites and the Phase 07 gate completed. The evidence in this
section remains historical Studio validation; reusable general lifecycle
coverage is deferred until a dedicated regression packet. See
`docs/TEST_MATRIX.md`.

Packet 03.3 reran 12 focused lifecycle cases through the migrated logger-based
constructor. Dependency order, registration/state rejection, and all three
callback-failure stages passed. Every callback-failure record retained safe
context, role, PlaceId, environment, service, and state fields while a deliberate
secret sentinel thrown by the callback was absent.

Packet 03.4 composed the runner with the real cleanup and bounded-shutdown
contracts. It verified reverse dependency shutdown, exact LIFO ownership order,
zero-service shutdown, repeated idempotent cleanup, and eventual state
finalization after a cooperative timeout. Three final Lobby and Match Play–Stop
cycles each ended in lifecycle state `Shutdown`.

## Historical Packet 03 toolchain and build verification

| Check | Result |
| --- | --- |
| `stylua src` | Pass |
| `stylua --check --verify src` | Pass |
| `selene src` | Pass; 0 errors, 0 warnings, 0 parse errors |
| `rojo build default.project.json` | Pass |
| `rojo build lobby.project.json` | Pass |
| `rojo build match.project.json` | Pass |
| Shared module mapping | Pass; `ServiceLifecycle` present in all three builds |
| Role-source isolation | Pass; Lobby build has no match source and Match build has no lobby source |

The three ignored verification builds were inspected and removed. Generated
`.rbxlx` files remain untracked under `docs/CODE_STYLE.md`.

## Historical isolated Studio verification

Both already-open Studio places were synchronized through their correct Rojo
projects and tested without editing, saving, or publishing them.

This table records the then-current pre-network lifecycle. Phase 06 has since
added one foundation-only `NetworkRegistry` server service while the client
remains at zero services. The table is historical and is not the current Phase
06 Studio evidence.

| Place | Role/PlaceId | Server result | Client result | Opposite-role executable source |
| --- | --- | --- | --- | ---: |
| Lobby | `Lobby` / `100561454756026` | `Started`, 0 services | `Started`, 0 services | 0 |
| Match | `Match` / `136401514513678` | `Started`, 0 services | `Started`, 0 services | 0 |

Both Play sessions emitted exactly the expected common server and client ready
records with no application warning or error and were then stopped. The Lobby
Edit DataModel still contains preserved empty `match` folders from earlier
combined synchronization; each has zero descendants and zero scripts/modules.
They are not match source and were not deleted because unknown Studio instances
remain preserved by policy.

Packet 06.5 subsequently passed the then-current unsaved networking regression.
Three plain Lobby and three plain Match Play/Stop cycles each reported one
server `NetworkRegistry` service and zero client services. The final runtime-only
Match Server & Clients harness used exactly two clients and passed real
`PlayerRemoving`, continued request handling for the remaining peer, server and
remaining-client `caseCount=10` terminals, test-fixture cleanup `Cleaned`, and
preservation of the empty production `ATDNetwork/v1` tree. Its bounded Output
audits reported `forbiddenMatches=0` and `errorCount=0`. The complete evidence is
in `docs/NETWORK_SECURITY_STUDIO_REGRESSION.md`.

## Manual regression procedure

1. Serve `lobby.project.json` and connect only the Lobby place.
2. Confirm `ATDPlaceRole = Lobby`, `ServiceLifecycle` exists, and the opposite
   role folders contain no executable source.
3. Play and expect one server and one client ready record with role `Lobby` and
   lifecycle state `Started`. The server service count is `1` for
   `NetworkRegistry`; the client service count remains `0`.
4. Stop Play.
5. Repeat with `match.project.json` and the Match place, expecting role `Match`,
   server order `NetworkRegistry -> MatchLifecycle -> EnemySimulation`, and
   client order `MatchReadyController -> EnemyController` (service counts `3`
   and `2`).
6. When exercising the Phase 09 Studio-only enemy trigger, confirm one server
   enemy `Heartbeat` and one client enemy `PreRender` connection regardless of
   enemy count. Stop Play and confirm the enemy trigger, visual root, runtime
   map, remote root, Ready UI, service connections, and retained enemy/match
   state are gone.
7. Do not save or publish either place merely to perform this test.

Phase 03 is complete. Packet 03.4 evidence is in
`docs/GRACEFUL_SHUTDOWN.md`. Phase 04 added pure content contracts, and Packet
04.5 placed their centralized gate before runner construction without changing
this lifecycle behavior. Packets 06.1–06.5 add only the common server network
service, its nested limiter/dispatcher ownership, and test-only security
evidence described in `docs/NETWORK_PROTOCOL.md`. Packet 06.5 and the fresh
Phase 06/Gate A audit pass, including clean workflow run `33022784985`. Phase 06
is complete and Gate A passed. Phase 08 is also complete. Phase 09 code, exact
Match Studio evidence, consolidated review, 467-case local gate, and all four
structural builds pass on 2026-08-27. Phase 09 is complete. Phase 10's focused
and exact Studio lifecycle evidence, consolidated review, complete local gate,
and all four structural builds passed on 2026-08-28. Phase 10 is complete;
exact-final-SHA CI is cited at its handoff. Phase 11 remained unbegun at that
historical checkpoint. Earlier lifecycle evidence is in
`docs/ENEMY_SIMULATION.md` and `docs/BASE_RUNTIME.md`.
Configuration evidence remains in
`docs/CONFIGURATION_VALIDATION.md`.

## Phase 12 Match composition (current)

The current server registration order is:

```text
NetworkRegistry -> MatchLifecycle -> BaseRuntime -> EnemySimulation -> WaveRuntime -> TowerRuntime
```

The current client order is:

```text
MatchReadyController -> BaseController -> EnemyController -> WaveController
```

WaveRuntime depends on the exact loaded Match/runtime-map identity, BaseRuntime,
and EnemySimulation, but adds no Heartbeat. EnemySimulation remains the sole
server step owner and invokes one non-yielding sampled Wave boundary. The Wave
service is production-dormant while canonical production configuration is empty.
Its Studio-only trigger is absent outside Studio and cannot become a second
production lifecycle path.

TowerRuntime depends exactly on `NetworkRegistry`, `MatchLifecycle`, and
`WaveRuntime`. The Wave dependency is lifetime/Studio-boundary ordering only;
Tower reads no scheduler state and adds no step, Heartbeat, timer, per-player,
per-slot, per-level, per-record, or per-model connection. Non-Studio production
starts Tower in `Dormant`, owns no observer/boundary/runtime state, and releases
its construction dependencies immediately. Studio configuration moves through
`AwaitingFixture -> Preparing -> Prepared -> Configured`; fault or cleanup is
permanent and non-restartable.

Reverse shutdown is TowerRuntime -> WaveRuntime -> EnemySimulation -> BaseRuntime ->
MatchLifecycle/MapLoader -> NetworkRegistry on the server. Client Wave state
cleans before Enemy, Base, Ready, map, and network owners. Each owner has a
constant connection budget: WaveRuntime has no simulation connection, and
WaveController owns exactly three network listeners regardless of waves,
groups, spawns, enemies, votes, or revisions.

If the sole Wave callback fails after an Enemy Store spawn commits,
EnemySimulation finishes its operation, fault-despawns the exact committed
snapshot at the authenticated sample, and invokes the one-shot Wave close with
the exact frozen `{ event, outcome }` plus authenticated Manual terminal. Wave
reconciles ownership and counters once, enters `Faulted`, and the service retains
read-only truth until cleanup. A pre-first-pass dependency fault first obtains a
fresh authenticated zero-delta Store sample and uses pass ordinal one. An
unsuccessful private close is not falsely reported as `Faulted` and is not
retried.

TowerRuntime owns one constant MatchLifecycle participant observer and one
Studio-only Wave boundary while configured. Ordinary shutdown first detaches
the Wave boundary, then revokes the authentic participant handle and clears
loadout/runtime/model state. Wave-originated initialization failure uses a
separate non-recursive `closeFromWave` path; Wave invalidates its retained
boundary itself. Committed base defeat closes ordinary Match callbacks but
still permits only the authentic cleanup-only observer detach, so reverse
shutdown cannot strand Tower ownership after Match reaches `Results`.

Every Tower coordinator operation is non-yielding and guarded against re-entry.
The coordinator now adopts a child loadout/runtime Store's fatal state: a
throw, yield, malformed result/metrics, `faulted`/`cleaned` child flag, or failed
capability rollback immediately closes admission, clears service capability
expectations, and faults both Stores. Recoverable invalid input, `NOT_FOUND`,
placement-cap, and active-cap rejection pass through only while exact bounded
child metrics prove both Stores remain healthy. Focused injected
throw/yield/fatal-child and rollback-failure coverage proves no repeated
capability can be issued after such a fault.

## Phase 13 placement composition

Server registration is now `MatchLifecycle -> BaseRuntime -> EnemySimulation ->
WaveRuntime -> TowerRuntime -> TowerPlacement`. Reverse shutdown therefore
closes placement admission, its reservation/affordability state, revision
publication, and Studio trigger before TowerRuntime revokes capabilities or
destroys records/models. `TowerPlacement` depends explicitly on
`NetworkRegistry`, `MatchLifecycle`, `WaveRuntime`, and `TowerRuntime`; it owns
no timer, loop, Heartbeat, Player, or Instance model.

The Match bootstrap decorates the existing MatchLifecycle snapshot sender with
the current `TowerPlacement` query revision. Only after one canonical
`PreWave`/`WaveActive` Match snapshot is accepted for its authenticated
recipient does the same composition send that recipient the bounded revision
event. This lifecycle publication lets an early rejected placement query
recover without a timer, retry loop, client authority, or Studio evidence hook.

Client registration appends `TowerPlacementController` after `WaveController`.
The controller owns exactly eight constant connections, one query and one
submit tracker at most, one reducer/input/view stack, and—only in Studio—one
bounded evidence trigger. Reverse shutdown cancels trackers, destroys the
trigger, disconnects all eight callbacks, and destroys local preview UI/world
parts. Captured response, revision, render, input, and trigger callbacks are
inert after shutdown.
