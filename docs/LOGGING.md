# Structured Logging and Environment Context

## Purpose

This document records the implementation contract and verification evidence for
Packet 03.3 of `docs/DEVELOPMENT_PLAN.md`. The packet gives the common client
and server bootstraps one deterministic, context-bound logging surface without
adding a global logger, gameplay service, network boundary, or shutdown hook.

## Packet status

- Packet: 03.3
- Status: Complete
- Recorded: 2026-08-25
- Environment implementation:
  `src/shared/logging/EnvironmentContext.luau`
- Logging implementation: `src/shared/logging/Log.luau`
- Integrated consumers: common client/server bootstraps, service lifecycle, and
  cleanup utility
- Registered gameplay services: 0
- Gameplay or networking behavior added: none
- Studio-authored content changed: no
- External services enabled: no
- Place saved or published: no

Those fields record Packet 03.3 at completion. Packet 06.1 adds the common
server network registry as an integrated consumer and
narrowly extends the closed vocabulary with the `network` subsystem plus
`endpoint` and `networkState`. It adds no remote log sink or client-authored log
path. Packet 06.3 adds only the finite numeric fields
`rateLimitRejectionCount` and `rateLimitWindowSeconds` for one bounded global
abuse aggregate; it still adds no remote sink or per-request log path.
Packet 06.4 adds only `protocolRejectionCount` and
`protocolWindowSeconds` for a separate bounded dispatcher aggregate. It does not
add request IDs, Players, payloads, handler errors, or response contents to the
logging vocabulary.

## Architecture boundary

`EnvironmentContext` creates validated runtime identity records. `Log` binds
exactly one of those records to a local logger. A caller passes that logger to
the lifecycle runner and cleanup container that it owns. There is no singleton,
global registry of active loggers, service locator, mutable global verbosity
setting, remote sink, serializer, or client-to-server log path.

The modules use private weak-key registries to distinguish objects they created
from lookalike tables. Contexts and loggers are frozen after construction, and
logger methods verify that `self` is a genuine registered logger. A copied table
or a table given the logger metatable is therefore not accepted as a context or
logger.

## Environment context contract

`EnvironmentContext.new(executionContext, placeRole, placeId, isStudio)` returns
a frozen context with these fields:

| Field | Allowed value or derivation |
| --- | --- |
| `executionContext` | `client` or `server` |
| `placeRole` | `Unresolved`, `Development`, `Lobby`, or `Match` |
| `placeId` | Finite, non-negative integer |
| `isStudio` | Boolean supplied from `RunService:IsStudio()` |
| `runtimeEnvironment` | Derived as `studio` when `isStudio` is true, otherwise `production` |

The constructor rejects an invalid execution context, role, PlaceId, or Studio
flag without reflecting the rejected value. `EnvironmentContext.isContext()`
checks provenance as well as table type.

`EnvironmentContext.withRole(context, resolvedRole)` accepts only a genuine
context and one resolved `Development`, `Lobby`, or `Match` role. It returns a
new frozen context while preserving execution context, PlaceId, and Studio
state. It never mutates the provisional context and never accepts `Unresolved`
as a resolved result.

### Provisional boot context

Each common bootstrap snapshots `game.PlaceId` and `RunService:IsStudio()` once.
It then creates an `Unresolved` context and logger before validating the central
place-role configuration. This gives configuration and role-pairing failures a
canonical client/server, PlaceId, and environment prefix even though the place
role has not been trusted yet.

Only a successful `PlaceRoles.resolve()` result is passed to `withRole()`. The
bootstrap then creates its resolved logger and uses it for lifecycle, cleanup,
and the ready record. Raw PlaceIds remain centralized in `PlaceRoles`; the
logging modules only carry the already-observed runtime ID.

Environment construction errors use the reserved internal `environment`
subsystem with unknown context fields when no genuine context exists yet.

| Code | Rejection |
| --- | --- |
| `INVALID_CONTEXT` | `withRole()` did not receive a genuine context |
| `INVALID_EXECUTION_CONTEXT` | Execution context is not `client` or `server` |
| `INVALID_PLACE_ROLE` | Provisional or resolved role is not allowed |
| `INVALID_PLACE_ID` | PlaceId is not a finite, non-negative integer |
| `INVALID_STUDIO_FLAG` | Studio state is not a boolean |

## Logger contract

`Log.new(context)` requires a genuine `EnvironmentContext` and returns a frozen,
context-bound logger. `Log.isLogger()` exposes the provenance check without
exposing the private registry.

| Method | Behavior |
| --- | --- |
| `formatRecord(severity, subsystem, event, message, fields?)` | Validates and returns one record without emitting it |
| `debug(...)` | In Studio, prints and returns one `DEBUG` record; in production, returns `nil` without formatting or emitting |
| `info(...)` | In Studio, prints and returns one `INFO` record; in production, returns `nil` without formatting or emitting |
| `warn(...)` | In every environment, calls `warn()` once and returns the exact `WARN` record |
| `error(...)` | In every environment, raises the exact `ERROR` record with stack level zero and never returns |
| `getContext()` | Returns the logger's frozen context |

Production suppression happens before `debug` or `info` formats the supplied
record. Development-only verbosity therefore cannot make a production code path
fail because of a diagnostic payload. Warnings remain non-throwing evidence of
a degraded condition. Errors are fail-closed control flow, not recoverable
result values.

## Canonical record shape

Every public record uses this exact base-field order:

```text
[ATD][<SEVERITY>][context=<client|server>][role=<Unresolved|Development|Lobby|Match>][placeId=<integer>][environment=<studio|production>][subsystem=<subsystem>][event=<event>][<custom fields sorted by name>] <message>
```

The ordering rules are deterministic:

1. Product marker and severity come first.
2. `context`, `role`, `placeId`, `environment`, `subsystem`, and `event` always
   follow in that order.
3. Optional structured fields are sorted lexicographically by field name and
   appended after `event`.
4. One space separates the structured prefix from the human-readable message.

For example, the Lobby server bootstrap emits:

```text
[ATD][INFO][context=server][role=Lobby][placeId=100561454756026][environment=studio][subsystem=bootstrap][event=ready][cleanupState=Active][cleanupTaskCount=1][lifecycleState=Started][serviceCount=1] Server bootstrap ready
```

An event must begin with an ASCII letter and may then contain ASCII letters,
digits, `_`, `.`, or `-`. A message must be non-empty and contain no control
characters, including tabs, nulls, carriage returns, or line feeds. This keeps
one logical record on one Output line.

## Closed public vocabulary

Packet 03.3 introduced a deliberately small public vocabulary. The current
public logger calls accept only these subsystems, including the two later narrow
configuration and network extensions:

| Subsystem | Current owner |
| --- | --- |
| `bootstrap` | Common client/server startup readiness |
| `configuration` | Whole-catalog validation success and fail-closed rejection |
| `place-role` | Configuration and place-pairing rejection |
| `lifecycle` | Service registration, ordering, stage, and callback failure |
| `cleanup` | Cleanup construction, ownership, state, and aggregate failure |
| `network` | Fixed endpoint ownership, binding, lifecycle state, and static rejection |
| `shutdown` | Server close hook, private wait budget, and terminal outcome |

`environment` and `log` are reserved internal diagnostic categories. The former
is used before a valid environment context exists. The latter reports logger
construction, method, or record rejection. They are intentionally absent from
the public `Subsystem` type and cannot be selected through a valid public
logger call.

The logger owns these base names and rejects attempts to supply them as custom
fields: `context`, `environment`, `event`, `placeId`, `role`, `severity`, and
`subsystem`.

The current complete custom-field allowlist is:

| Field | Intended safe value |
| --- | --- |
| `budgetSeconds` | Validated cooperative shutdown wait budget |
| `cleanupState` | Typed cleanup state |
| `cleanupTaskCount` | Number of registered cleanup tasks |
| `closeReason` | Engine-authored `Enum.CloseReason.Name` token |
| `code` | Stable configuration, lifecycle, cleanup, network, or logging error code |
| `configurationFamilyCount` | Fixed number of loaded core configuration families |
| `container` | Static cleanup-owner label |
| `endpoint` | Canonical registry endpoint or static `<unknown>`/`<multiple>` placeholder |
| `issueCount` | Number of root validation issues in a frozen report |
| `lifecycleState` | Typed lifecycle state |
| `networkState` | Typed network-owner lifecycle state or static construction state |
| `protocolRejectionCount` | Saturating count of aggregated dispatcher protocol rejections |
| `protocolWindowSeconds` | Fixed finite dispatcher aggregate-reporting window |
| `rateLimitRejectionCount` | Saturating count of aggregated server-side rejections |
| `rateLimitWindowSeconds` | Fixed finite aggregate-reporting window |
| `service` | Static service label or `<runner>` |
| `serviceCount` | Number of registered lifecycle services |
| `state` | Typed state attached to an error |
| `validationPath` | First canonical configuration path; never an offending value |

Fields must be a dictionary or `nil`. Names must follow the event-label pattern.
Values are limited to booleans, finite numbers, or reviewed safe strings.
Ordinary string fields use the logger's safe token characters. The sole
bracket-bearing field, `validationPath`, instead requires the exact canonical
`Identifier(.Identifier|[positive-integer])*` grammar and a 512-byte limit.
Tables, instances, functions, threads, NaN, infinity, whitespace, equals signs,
control characters, and malformed path brackets are not valid field values.
Unknown fields are rejected, and custom field order never depends on Lua table
iteration order.

Field names containing normalized sensitive tokens such as `profile`,
`accesscode`, `teleportcode`, `teleportdata`, `purchase`, `receipt`, `payment`,
or `product` receive a dedicated `SENSITIVE_FIELD` rejection. The rejection
does not echo the prohibited name. The closed allowlist would also reject those
names, but the dedicated code makes the privacy boundary explicit.

| Logging code | Rejection |
| --- | --- |
| `INVALID_CONTEXT` | Context or method receiver is not genuine |
| `INVALID_SEVERITY` | Severity is not `DEBUG`, `INFO`, `WARN`, or `ERROR` |
| `INVALID_SUBSYSTEM` | Subsystem is outside the public closed set |
| `INVALID_EVENT` | Event label is malformed |
| `INVALID_MESSAGE` | Message is empty or contains a control character |
| `INVALID_FIELDS` | Optional fields value is not a dictionary or `nil` |
| `INVALID_FIELD_NAME` | A field key is not a valid label string |
| `RESERVED_FIELD` | Caller attempted to replace a logger-owned base field |
| `SENSITIVE_FIELD` | Field name is prohibited by privacy policy |
| `UNKNOWN_FIELD` | Field name is outside the safe allowlist |
| `INVALID_FIELD_VALUE` | Value is not an allowed finite scalar or safe token string |

## Privacy and data-minimization policy

The logger is a structural guard, not a redaction or secret-detection engine.
Its allowlist prevents arbitrary dictionary serialization and its character
rules prevent structured-field injection, but an allowed string can still be a
secret if a caller misuses it. Messages are also developer-authored text, not
sanitized payload containers.

All current and future call sites must therefore obey these rules:

- Use static developer-authored summaries, stable error codes, typed states,
  counts, and static service/container labels only.
- Never pass complete or partial profile contents, player-authored text,
  teleport data, reserved-server access codes, credentials, cookies, API keys,
  purchase or receipt details, payment data, or other personal information.
- Never stringify arbitrary tables, client requests, DataStore documents,
  exception objects, callback results, or third-party responses into a field or
  message.
- Add a new field or subsystem only by extending the reviewed typed allowlist;
  do not encode unrelated data into an existing safe field.
- Treat a record returned by `formatRecord()` with the same privacy rules even
  if it is not immediately emitted.

Logger validation errors report stable codes, expected shapes, and runtime
types where useful. They do not echo rejected field values, prohibited field
names, or arbitrary structures. The codebase must still review every new call
site because no character whitelist can determine the meaning of a value.

### Lifecycle and cleanup callback failures

Lifecycle and cleanup callbacks run under `pcall`, but their thrown values are
deliberately discarded:

- A lifecycle callback failure records a static summary, method, stable code,
  static service name, and resulting `Failed` state. It never appends the
  callback's error reason.
- Cleanup continues its reverse sweep and aggregates only task registration
  index, classified task kind, and runtime type. It never appends a callback or
  nested-container error reason. Repeating a failed cleanup raises the exact
  cached safe aggregate.

Studio regression cases threw unique secret sentinels from both paths and
confirmed that neither sentinel appeared in the resulting records.

### Network construction and binding failures

The server network owner emits only static developer-authored summaries with a
stable `code`, typed `networkState`, and either an authenticated canonical
registry name or `<unknown>` in `endpoint`. Unknown, malformed, arbitrary-path,
or non-string endpoint inputs are never copied into a record. Connector errors,
handler values, callback errors, payloads, request IDs, Players, UserIds, and
Instance paths are discarded rather than stringified. Packet 06.1 emits no
per-request records. Packet 06.3 adds one global O(1) rate-limit rejection
aggregate: the first rejection may emit one static warning, later warnings are
limited to one per ten-second window across all endpoints, the pending count
saturates at 4,096, and the endpoint is one authenticated canonical name or the
static token `<multiple>`. Reporter failure is contained and advances the
cadence.

Packet 06.4 adds a separate global O(1) dispatcher aggregate with the same
ten-second cadence and 4,096 saturation bound. A report contains only a
canonical endpoint or `<unknown>`/`<multiple>`, one fixed dispatcher code or
`MULTIPLE_SIGNALS`, `protocolRejectionCount`, and
`protocolWindowSeconds`. It combines malformed envelopes, invalid runtime
context, duplicate/stale correlation, authorization or payload rejection,
handler/outcome/response failure, and unavailable state without emitting one
record per request. Reporter failure, observation-clock failure, and response
send failure are contained and counted internally; none permits a caller value
into Output. No Player, UserId, request ID, payload, public-error metadata,
client-supplied timestamp, caught error, handler result, response content, or
trace is retained or logged by either aggregate. The limiter necessarily keeps
bounded server-local token balances and refill times, and both aggregates keep
bounded server-local cadence/count state; those enforcement values are cleared
on cleanup and are never emitted as raw values.

## Bootstrap integration

The common server and client bootstraps now follow the same sequence:

1. Snapshot execution environment and PlaceId.
2. Create an `Unresolved` environment context and logger.
3. Validate centralized role configuration and resolve the declared place role.
4. Fail through the provisional logger if either role check is rejected.
5. Derive a resolved context and logger.
6. Validate all nine configuration families through the shared
   `ConfigurationValidator.validateLoaded()` entry point.
7. On validation failure, raise a production-visible static error containing
   only first code, issue count, and canonical path; create no lifecycle,
   cleanup, or shutdown resource.
8. On success, emit a Studio-only `configuration/validated` record. The client
   creates an empty lifecycle runner; the server constructs the fixed network
   owner from the empty production registry and empty production rate-policy
   list and registers its one `NetworkRegistry` service before lifecycle
   initialization. Both create a `bootstrap` cleanup container with the same
   logger.
9. Emit one Studio-only `ready` record containing resolved context, lifecycle
   state/count, and cleanup state/count.

The cleanup container still owns one callback that can shut down a started
lifecycle runner. Packet 03.3 did not invoke that container. Packet 03.4 has
since added the one server-only close signal and uses the same logger for safe
start, completion, failure, and timeout records.

## Focused Studio validation

The synchronized modules were tested in Studio Edit mode through temporary
clones of the complete `ReplicatedStorage.Shared` tree. Cloning the tree kept
all relative module dependencies within one provenance registry. The clones
were destroyed after the harness; no place was saved.

All 13 focused logging/environment cases passed. Together they verified:

- valid client/server, provisional/resolved, Studio/production contexts;
- derived environment fields, immutability, provenance, and spoof rejection;
- exact canonical field order and deterministic custom-field sorting;
- Studio `debug`/`info` emission and production suppression;
- non-throwing `warn` and fail-closed `error` behavior;
- genuine logger construction and method-receiver enforcement;
- severity, subsystem, event, message, fields, reserved-name, sensitive-name,
  unknown-name, scalar-value, and control-character rejection; and
- non-reflection of secret sentinels supplied through prohibited inputs.

An additional 22 lifecycle/cleanup compatibility regression cases passed
against the logger-integrated modules. They retained deterministic lifecycle
ordering and state guards, cleanup LIFO ownership and idempotence, contextual
structured failures, continued cleanup after a task failure, exact cached
aggregate behavior, and suppression of arbitrary callback error reasons.

These are focused packet harnesses, not a committed test framework. Phase 05
later added a repository-owned runner. It still has no dedicated full `Log` or
`EnvironmentContext` suite, though the network runtime exercises genuine
loggers and proves private endpoint and connector sentinels are absent from
network failures. The limiter and dispatcher suites additionally exercise both
aggregate cadence/count bounds, reporter failure isolation, and absence of
private identity, request, payload, handler-error, and clock sentinels. The
Studio evidence here and the deferred reusable coverage boundary are indexed in
`docs/TEST_MATRIX.md`.

## Toolchain and build verification

| Check | Result |
| --- | --- |
| `stylua src` | Pass |
| `stylua --check --verify src` | Pass |
| `selene src` | Pass; 0 errors, 0 warnings, 0 parse errors |
| `rojo build default.project.json` | Pass |
| `rojo build lobby.project.json` | Pass |
| `rojo build match.project.json` | Pass |
| Packet 03.3 forbidden-scope source scan | Pass at that checkpoint; no shutdown hook, remote, DataStore, teleport, purchase, or gameplay system added |

At the Packet 03.4 follow-up verification snapshot, every build contained the
five then-current shared modules (`PlaceRoles`, `EnvironmentContext`, `Log`,
`ServiceLifecycle`, and `Cleanup`) plus Packet 03.4's server-only common
`Shutdown` module. Packet 04.1 later added `Ids` and `Result`; the table below is
the historical logging-packet build snapshot.

| Build | Declared role | ModuleScripts | Server Scripts | Client LocalScripts | Role-source structure |
| --- | --- | ---: | ---: | ---: | --- |
| Default | `Development` | 6 | 1 | 1 | Contains combined common, lobby, and match layers |
| Lobby | `Lobby` | 6 | 1 | 1 | Contains no match source |
| Match | `Match` | 6 | 1 | 1 | Contains no lobby source |

Generated `.rbxlx` verification outputs are ignored, reproducible artifacts and
are not authoritative Studio content. They are inspected only for structure and
removed after verification under `docs/CODE_STYLE.md`.

## Historical isolated live Studio verification

The Lobby and Match places were each synchronized through their correct
isolated Rojo project and tested in Play without saving or publishing.

This table records the then-current pre-network ready records. Phase 06 has
since added one foundation-only `NetworkRegistry` server service while the
client remains at zero services. The required current unsaved networking
regression is pending, so the historical zero-service values are not current
Phase 06 evidence.

| Place | Resolved role and PlaceId | Server ready result | Client ready result | Opposite-role executable source |
| --- | --- | --- | --- | ---: |
| Lobby | `Lobby` / `100561454756026` | `studio`, `Started`, 0 services, cleanup `Active` with 1 task | Same context with `context=client` | 0 |
| Match | `Match` / `136401514513678` | `studio`, `Started`, 0 services, cleanup `Active` with 1 task | Same context with `context=client` | 0 |

Each Play session emitted exactly one common server and one common client ready
record with the expected role, PlaceId, environment, and four sorted status
fields. Neither session produced an application warning or error. Both sessions
were stopped and both Studio windows returned to Edit mode. No Studio-authored
instance was changed, no external service was enabled, and neither place was
saved or published.

## Manual regression procedure

1. Serve `lobby.project.json` and connect it only to the Lobby place.
2. Confirm `ATDPlaceRole = Lobby`, the current shared modules listed in
   `docs/SOURCE_LAYOUT.md` exist, and no match folder contains executable source.
3. Clear Output and start Play.
4. Expect exactly one server and one client `[ATD][INFO]` bootstrap `ready`
   record. Confirm role `Lobby`, PlaceId `100561454756026`, environment `studio`,
   lifecycle `Started`, and cleanup `Active` with `cleanupTaskCount=1`. The
   server has `serviceCount=1` for `NetworkRegistry`; the client has
   `serviceCount=0`.
5. Confirm there is no application warning or error, then stop Play.
   Current Packet 03.4 behavior also emits one server `shutdown started` record
   and one `shutdown completed` record with cleanup `Cleaned` and lifecycle
   `Shutdown`.
6. Serve `match.project.json` and repeat in the Match place. Expect role `Match`,
   PlaceId `136401514513678`, the same lifecycle/cleanup values, and no lobby
   executable source.
7. Stop Play and leave both places in Edit mode. Do not save or publish merely
   to perform this regression.

## Scope boundary and next packet

Packet 03.3 adds no gameplay service, controller, remote, network protocol,
DataStore access, profile data, queue, teleport, purchase handling, analytics,
rate-limited production telemetry, or high-frequency tracing. It creates no
instances, tasks, or event connections. It also adds no `BindToClose`, close
signal, automatic cleanup trigger, or retry/timeout policy.

Packet 03.4 has since completed while preserving this contract. Its server-only
hook and cooperative deadline are recorded in `docs/GRACEFUL_SHUTDOWN.md`.
Phase 04 subsequently added pure schema contracts. Packet 04.5 is the first
Phase 04 packet to extend the public vocabulary, narrowly adding the
`configuration` subsystem and three fields documented above. Its source-load,
report, privacy, bootstrap, and Studio evidence is recorded in
`docs/CONFIGURATION_VALIDATION.md`.

Packets 06.1–06.4 make the narrow `network` vocabulary and aggregate-field
extensions recorded above. The lasting production registry and rate-policy list
remain empty, and no gameplay endpoint was created. Packet 06.5 and the fresh
Phase 06/Gate A exit audit remain open. The architecture and privacy boundary
are recorded in `docs/NETWORK_PROTOCOL.md`.
