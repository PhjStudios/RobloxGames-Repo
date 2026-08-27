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

Those fields describe Packet 03.2 at completion. Packet 06.1 reuses this utility
inside the common server network service; it does not add a second cleanup
implementation. Phase 08 now applies the same one-owner/idempotent rules to the
Match lifecycle, roster, deadline, snapshot broadcaster, MapLoader, request
tracker, input bindings, and ready GUI. Phase 08 and its Studio,
consolidated-review, and complete-local-gate evidence passed on 2026-08-27.
Phase 09 is next but has not begun.

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
was added. Phase 08's `MatchReadyController` now owns and releases its real
remote/render/GUI connections, request state, input binding, view model, and
ScreenGui through its idempotent lifecycle shutdown.

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

## Phase 08 Match ownership and release order

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
next but has not begun.

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
all 200 cases across 16 suites. Phase 07 adds focused loader rollback,
unload/reload, and cleanup coverage; the current complete local run passes 241
cases across 19 suites. Packet 06.5 and the fresh Phase 06/Gate A audit pass,
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

Packet 06.5 subsequently passed the current unsaved networking regression.
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
5. Repeat through `match.project.json`, expecting role `Match` and no lobby
   executable source.
6. Do not save or publish merely to run this regression.

Phase 03 is complete. Packet 03.4 evidence is in
`docs/GRACEFUL_SHUTDOWN.md`. Packet 04.5 now gates construction before cleanup
ownership without changing this cleanup behavior. Packet 06.1's completed
network ownership contract is described in `docs/NETWORK_PROTOCOL.md`; it reuses
the same contract. Packet 06.5 is complete with review-driven dispatcher
hardening, test-only adversarial fixtures, and unsaved Studio evidence. The
fresh Phase 06/Gate A audit and clean workflow run `33022784985` pass. Phase 06
is complete and Gate A passed.
Configuration evidence is in
`docs/CONFIGURATION_VALIDATION.md`.
