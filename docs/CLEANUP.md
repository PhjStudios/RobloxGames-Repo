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

After place-role validation and lifecycle startup, each common bootstrap creates
a `bootstrap` cleanup container using its own server or client logger. The
environment context distinguishes the otherwise identical container labels.

Each container owns one real callback that shuts down its existing lifecycle
runner if that runner is still `Started`. The Studio-only ready record therefore
reports:

```text
[cleanupState=Active][cleanupTaskCount=1]
```

Packet 03.4 now invokes the server container from the one ordered
`BindToClose` path. The client container still has no process-close trigger.
No save operation was added. The current source tree contains no controllers,
so adding placeholder controllers or fake resources would not be honest
integration. Future controllers must own their real connections, Instances,
callbacks, threads, and child containers through this utility when introduced.

## Focused automated validation

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
was created or saved. Packet 05 still owns selection and repository integration
of a persistent Luau test runner.

Packet 03.3 reran 10 focused cleanup cases through the logger-based constructor.
Supported runtime types, LIFO/idempotence, state/nesting guards, failure
continuation, cached failure equality, and constructor authenticity passed. A
deliberate secret sentinel thrown by a cleanup callback was absent from both the
first aggregate error and its exact cached repeat.

Packet 03.4 additionally verified cleanup inside the bounded server-shutdown
runner. Normal and repeated cleanup reached `Cleaned`; failure still completed
the sweep; a yielding task that crossed the private wait deadline was allowed
to finish later instead of being canceled and poisoning the container state.

## Toolchain and build verification

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

## Isolated Studio verification

Both isolated places synchronized the shared utility and booted without an
application warning or error:

| Place | Role/PlaceId | Lifecycle | Cleanup | Opposite-role executable source |
| --- | --- | --- | --- | ---: |
| Lobby | `Lobby` / `100561454756026` | `Started`, 0 services | `Active`, 1 task | 0 |
| Match | `Match` / `136401514513678` | `Started`, 0 services | `Active`, 1 task | 0 |

Both Play sessions were stopped and returned to Edit mode. No external service,
save, or publish operation occurred.

## Manual regression procedure

1. Connect `lobby.project.json` only to the Lobby place.
2. Confirm `ReplicatedStorage.Shared.util.Cleanup` exists.
3. Play and expect server/client ready records with lifecycle `Started`, zero
   services, cleanup `Active`, and one cleanup task.
4. Confirm no match executable source and stop Play.
5. Repeat through `match.project.json`, expecting role `Match` and no lobby
   executable source.
6. Do not save or publish merely to run this regression.

Phase 03 is complete. Packet 03.4 evidence is in
`docs/GRACEFUL_SHUTDOWN.md`; Phase 04 has not begun.
