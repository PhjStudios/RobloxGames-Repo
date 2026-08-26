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

Those fields record Packet 03.1 at completion. Packet 06.1 registers one
foundation-only `NetworkRegistry`
service on the server after configuration validation; the client remains at
zero registered services. No gameplay service has been added.

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
static summary so callback secrets cannot be reflected into Output. The runner
never continues to later services after a callback failure.

Packet 03.1 deliberately does not define rollback after partial initialization
or startup. Cleanup ownership belongs to Packet 03.2, and process shutdown
hooks belong to Packet 03.4.

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

The common server and client bootstraps validate the centralized place role and
the complete nine-family configuration before creating a lifecycle runner. Each
resolves one environment context, creates one local logger, calls the shared
`ConfigurationValidator.validateLoaded()` gate, and passes the logger to the
runner only after success. The client initializes and starts its empty runner.
The server first creates `ServerRemoteRegistry` from the empty authenticated
production registry and registers its frozen `NetworkRegistry` service
definition, then initializes and starts the runner. Their current Studio-only
ready records therefore include:

```text
server: [lifecycleState=Started][serviceCount=1]
client: [lifecycleState=Started][serviceCount=0]
```

The runner is local to its bootstrap. No global registry or service locator was
introduced. Packet 03.2 subsequently registered each runner's existing
`shutdown()` operation as a callback in its bootstrap cleanup container. Packet
03.4 now invokes the server container through the one ordered `BindToClose`
path. The lifecycle runner therefore shuts down in reverse dependency order
before the server hook completes. The client still has no process-shutdown hook.

Invalid configuration raises a structured error before `ServiceLifecycle.new`,
so no partially validated configuration can reach a service and no runner needs
rollback. The valid path and every lifecycle state contract remain unchanged.

The network service has no declared dependencies. Its lifecycle callbacks own a
separate typed state machine: initialize creates and binds the fixed server-owned
tree before parent-last publication, start changes no endpoint definition, and
shutdown cleans its exact listeners and root. Duplicate initialization, start,
shutdown, or handler registration is rejected by the network owner rather than
creating duplicate resources. The existing reverse lifecycle and outer
bootstrap cleanup remain the sole shutdown route.

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

Phase 05 subsequently added a repository-owned runner. Its current 106 cases do
not include a dedicated general `ServiceLifecycle` suite; the Packet 06.1
runtime suite instead exercises the frozen network service definition and its
initialize/start/shutdown state adapter. The evidence in this section remains
historical Studio validation; reusable general lifecycle coverage is deferred
until a dedicated regression packet. See `docs/TEST_MATRIX.md`.

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

## Toolchain and build verification

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

## Isolated Studio verification

Both already-open Studio places were synchronized through their correct Rojo
projects and tested without editing, saving, or publishing them.

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

## Manual regression procedure

1. Serve `lobby.project.json` and connect only the Lobby place.
2. Confirm `ATDPlaceRole = Lobby`, `ServiceLifecycle` exists, and the opposite
   role folders contain no executable source.
3. Play and expect one server and one client ready record with role `Lobby` and
   lifecycle state `Started`. The server service count is `1` for
   `NetworkRegistry`; the client service count remains `0`.
4. Stop Play.
5. Repeat with `match.project.json` and the Match place, expecting role `Match`.
6. Do not save or publish either place merely to perform this test.

Phase 03 is complete. Packet 03.4 evidence is in
`docs/GRACEFUL_SHUTDOWN.md`. Phase 04 added pure content contracts, and Packet
04.5 placed their centralized gate before runner construction without changing
this lifecycle behavior. Packet 06.1's source and 106-of-106 completion evidence
add only the common server network service described in
`docs/NETWORK_PROTOCOL.md`. Packet 06.1 is complete; Phase 06 remains open.
Configuration evidence remains in
`docs/CONFIGURATION_VALIDATION.md`.
