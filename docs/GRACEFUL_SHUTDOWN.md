# Graceful Server Shutdown

## Purpose

This document records the implementation contract and verification evidence for
Packet 03.4 of `docs/DEVELOPMENT_PLAN.md`. The packet gives both server places
one ordered shutdown path with a scheduler-cooperative deadline. It composes the
existing lifecycle, cleanup, environment-context, and logging contracts without
adding profile persistence or gameplay behavior.

## Packet status

- Packet: 03.4
- Status: Complete
- Recorded: 2026-08-25
- Shutdown runner: `src/server/common/bootstrap/Shutdown.luau`
- Server hook: `src/server/common/bootstrap/Main.server.luau`
- Shared logging vocabulary: `src/shared/logging/Log.luau`
- Server `BindToClose` hooks in `src/`: exactly 1
- Client `BindToClose` hooks in `src/`: 0
- Default shutdown budget: 10 seconds
- Maximum accepted shutdown budget: 25 seconds
- Registered gameplay services: 0
- Profile saving or persistent-data access added: none
- Studio-authored content changed: no
- External services enabled: no
- Place saved or published: no

## Roblox shutdown constraints

Roblox's official [`DataModel:BindToClose()` documentation](https://create.roblox.com/docs/reference/engine/classes/DataModel.md#BindToClose)
defines three constraints that shape this implementation:

1. A bound callback may receive the engine's
   [`Enum.CloseReason`](https://create.roblox.com/docs/reference/engine/enums/CloseReason).
2. Multiple bound callbacks run in parallel, not in registration order.
3. The server waits at most 30 seconds for all bound callbacks before the engine
   shuts the server down.

Ant Tower Defense therefore has exactly one common server hook. Future server
systems must join the existing lifecycle and cleanup chain instead of registering
independent `BindToClose` callbacks. One hook preserves deterministic ordering;
multiple hooks would run concurrently and make their relative cleanup order
undefined.

The runner's 10-second default is intentionally below both its 25-second maximum
and Roblox's 30-second outer cap. The maximum leaves nominal headroom for final
logging and scheduler delay. Neither value extends Roblox's cap, and all bound
callbacks in the process still share the same engine-controlled shutdown window.

## Shutdown runner contract

`Shutdown.run(logger, callback, budgetSeconds)` requires:

| Argument | Contract |
| --- | --- |
| `logger` | Genuine context-bound `Log.Logger` |
| `callback` | Function with no required result |
| `budgetSeconds` | Finite number greater than 0 and no greater than 25 |

Invalid input fails closed through a structured error:

| Code | Rejection |
| --- | --- |
| `INVALID_CONTEXT` | Logger is not a genuine `Log.Logger` |
| `INVALID_CALLBACK` | Callback is not a function |
| `INVALID_BUDGET` | Budget is zero, negative, non-finite, non-numeric, or greater than 25 seconds |

The module and each returned result are frozen. A result has only:

```luau
export type Result = {
    status: "Completed" | "Failed" | "TimedOut",
    elapsedSeconds: number,
}
```

The status rules are deterministic:

| Status | Meaning |
| --- | --- |
| `Completed` | The protected callback returned successfully at or before the deadline |
| `Failed` | The protected callback raised at or before the deadline |
| `TimedOut` | The callback had not completed by the deadline, or its recorded completion time was after the deadline |

`elapsedSeconds` uses `os.clock()` from runner entry to the callback's recorded
completion or the runner's timeout observation. It remains result-only data; it
was not added as an unrestricted logging field.

The callback runs under `pcall`. Only success or failure status crosses the
runner boundary. Its return values and raw failure reason are discarded.

### Deadline race semantics

The callback records its own completion time. A completion recorded at or before
the deadline remains `Completed` or `Failed` even if the polling thread resumes
slightly later. A completion recorded after the deadline remains `TimedOut`, even
if it has already finished by the time the caller inspects the result. Tests must
therefore assert the status contract, not depend on a fragile exact-boundary
scheduler race.

## Cooperative timeout behavior

`TimedOut` means the hook stopped waiting at its private deadline. It does not
mean the callback was forcibly terminated. The runner deliberately does not call
`task.cancel()` after a timeout. If Roblox's scheduler and the closing process are
still available, the callback may finish before the engine terminates the server.

This no-cancel behavior preserves the state machines it composes. Canceling a
yielding callback while cleanup was `Cleaning` or lifecycle was `ShuttingDown`
could prevent their final transitions and permanently poison those objects.
Allowing cooperative completion instead permits:

```text
Cleanup:   Active -> Cleaning -> Cleaned
Lifecycle: Started -> ShuttingDown -> Shutdown
```

The runner is not a preemptive watchdog. Luau scheduling is cooperative, so a
long callback that never yields can prevent the polling thread from checking its
deadline. Current cleanup callbacks must remain bounded and complete quickly; a
callback must never use a non-yielding busy loop. Future yielding operations,
including profile persistence when its own roadmap packet exists, must be
designed around both this cooperative deadline and Roblox's hard outer cap.

No profile save was added to Packet 03.4.

## Exact cleanup and lifecycle order

The common server path is:

```text
Roblox server close
  -> one common server BindToClose callback
  -> structured shutdown-start record
  -> Shutdown.run with the 10-second default
  -> bootstrap Cleanup container in LIFO order
  -> lifecycle runner shutdown callback
  -> services in reverse resolved dependency order
  -> Cleanup reaches Cleaned
  -> Completed, Failed, or TimedOut terminal record
```

The current bootstrap cleanup container owns one task: shut down its lifecycle
runner if that runner is still `Started`. The current lifecycle runner owns zero
gameplay services, so ordinary Play-Stop completion transitions directly from
`Started` to `Shutdown`, then the cleanup container transitions to `Cleaned`.

Packet 04.5 now validates the complete core configuration before constructing
the lifecycle runner, cleanup container, or this `BindToClose` hook. Rejected
boot therefore creates no shutdown-owned resource and needs no partial cleanup.
Successful validation follows the same single-hook sequence above unchanged.

When future cleanup resources are registered in the same container, the cleanup
utility releases them in last-in, first-out order. When future services are
registered, lifecycle shutdown traverses the already-resolved dependency order
in reverse, so dependents release before their foundations. A second cleanup
call after successful completion remains an idempotent no-op.

Cleanup continues across independently owned task failures and aggregates them.
The lifecycle runner retains its Packet 03.1 contract: a lifecycle method failure
sets the runner to `Failed` and raises a safe static error. That error becomes a
`Failed` shutdown result when it reaches the protected runner.

## Logging and privacy contract

Packet 03.4 extends the closed logger vocabulary only with:

- subsystem `shutdown`;
- structured field `budgetSeconds`;
- structured field `closeReason`.

The hook derives `closeReason` from the engine-provided enum item's `Name`. A
missing or non-enum value safely becomes `Unknown`. No arbitrary close payload is
serialized.

The server emits these event families:

| Event | Severity | Behavior |
| --- | --- | --- |
| `started` | `INFO` | Studio-only start record with budget and close reason |
| `completed` | `INFO` | Studio-only successful terminal record with cleanup/lifecycle state |
| `failed` | `WARN` | Always-emitted safe cleanup-failure summary |
| `timed_out` | `WARN` | Always-emitted safe deadline summary |
| `runner_failed` | `WARN` | Always-emitted safe wrapper-failure summary |

`DEBUG` and `INFO` retain Packet 03.3's production suppression. Warnings retain
production visibility. Shutdown records include execution context, resolved
place role, PlaceId, runtime environment, subsystem, and event through the local
context-bound logger.

Callback errors, cleanup failure reasons, runner errors, profile contents,
teleport access codes, purchase details, and arbitrary payloads are never copied
into shutdown records. Failure messages and codes are developer-authored static
summaries. Focused tests used a secret sentinel and confirmed it did not appear
in a shutdown result or formatted failure.

## Focused Studio Edit-mode validation

These packet harnesses are historical Studio evidence, not committed Phase 05
headless specs. The current coverage boundary is indexed in
`docs/TEST_MATRIX.md`.

The synchronized modules were exercised in Studio Edit mode without saving a
place. The focused harness ran 15 cases: 10 shutdown-runner cases, 3 timeout-state
cases, and 2 cleanup/lifecycle composition cases. All 15 passed.

### Shutdown runner — 10 cases

| Case label | Verified behavior |
| --- | --- |
| Constants, frozen, immediate | Exact 10-second default and 25-second maximum; frozen module/result; immediate callback completes |
| Success and repeats | Successful calls return `Completed`; repeating the runner remains deterministic |
| Yielding success | A yielding callback that finishes inside its budget returns `Completed` |
| Failure privacy | Callback failure returns `Failed`; arbitrary failure reason and secret sentinel are discarded |
| Yield timeout returns, then finishes | A yielding callback returns `TimedOut` at the deadline and can complete cooperatively afterward |
| Strict over-budget | A completion recorded after the deadline remains `TimedOut` |
| Invalid callback | A non-function callback is rejected with `INVALID_CALLBACK` |
| Invalid budgets | `0`, `-1`, `NaN`, positive infinity, `25.1`, and a string are rejected with `INVALID_BUDGET` |
| Invalid logger | A lookalike or otherwise non-genuine logger is rejected with `INVALID_CONTEXT` |
| Log vocabulary | `shutdown`, `budgetSeconds`, and `closeReason` validate and format through the closed logger contract |

### Timeout state safety — 3 cases

| Case label | Verified behavior |
| --- | --- |
| Timed-out callback can finish | The runner returns `TimedOut` without canceling the callback; the callback later completes |
| Cleanup state is not poisoned | State is `Cleaning` when the timeout returns, later reaches `Cleaned`, and repeated cleanup is a no-op |
| Lifecycle state is not poisoned | State is `ShuttingDown` when the timeout returns and later reaches `Shutdown` |

### Cleanup/lifecycle composition — 2 cases

| Case label | Verified behavior |
| --- | --- |
| Order and idempotence | Exact cleanup order was `resource.last`, `resource.first`, `Dependent`, `Foundation`; a second cleanup changed nothing |
| Safe composed failure | A cleanup failure produced `Failed`, left cleanup `Cleaned`, and exposed neither the raw reason nor the secret sentinel |

The harness used the real synchronized modules rather than a rewritten test
double. Temporary test objects and connections were removed, and no Studio place
was saved.

## Formatting, lint, build, and structure verification

| Check | Result |
| --- | --- |
| `stylua src` | Pass |
| `stylua --check --verify src` | Pass |
| `selene src` | Pass; 0 errors, 0 warnings, 0 parse errors |
| `rojo build default.project.json` | Pass |
| `rojo build lobby.project.json` | Pass |
| `rojo build match.project.json` | Pass |
| Source hook scan | Pass; exactly one server hook and no client hook |
| Shutdown cancellation scan | Pass; the shutdown runner does not call `task.cancel()` |

At the Packet 03.4 verification snapshot, each independent build contained six
ModuleScripts: `PlaceRoles`, `EnvironmentContext`, `Log`, `ServiceLifecycle`,
`Cleanup`, and `Shutdown`. Packet 04.1 later added `Ids` and `Result` without
changing this shutdown evidence.

| Build | Declared role | ModuleScripts | Server Scripts | Client LocalScripts | Role-source structure |
| --- | --- | ---: | ---: | ---: | --- |
| Default | `Development` | 6 | 1 | 1 | Combined common plus empty lobby and match layers |
| Lobby | `Lobby` | 6 | 1 | 1 | Common plus lobby; no match source |
| Match | `Match` | 6 | 1 | 1 | Common plus match; no lobby source |

Generated build artifacts remained untracked and were removed after inspection.

## Final Lobby and Match Play-Stop evidence

This is Studio solo evidence. Phase 05 changed no production source, so it did
not rerun or relabel these historical cycles as current automation; see
`docs/TEST_MATRIX.md`.

The final synchronized code completed three consecutive Play-Stop cycles in each
isolated Studio place, for six cycles total.

| Place | Cycles | State before Stop | Terminal state | Warnings/errors | Final Studio mode |
| --- | ---: | --- | --- | ---: | --- |
| Lobby (`100561454756026`) | 3/3 | Lifecycle `Started`; cleanup `Active` with 1 task | Lifecycle `Shutdown`; cleanup `Cleaned` | 0 | Edit after every cycle |
| Match (`136401514513678`) | 3/3 | Lifecycle `Started`; cleanup `Active` with 1 task | Lifecycle `Shutdown`; cleanup `Cleaned` | 0 | Edit after every cycle |

Every cycle emitted the expected server shutdown-start and shutdown-completed
records with `budgetSeconds=10`, the place's correct resolved role and PlaceId,
and the engine-provided close-reason name. No timeout, cleanup failure, runner
failure, script warning, or script error occurred. The client emitted its normal
ready record but registered no shutdown hook. Each Stop returned promptly to
Edit mode; neither Studio session hung.

No place was saved or published to perform these tests.

## Manual regression procedure

Run this after changing common bootstrap, lifecycle, cleanup, logging, or shutdown
code:

1. Start the Lobby Rojo project and connect it only to Lobby PlaceId
   `100561454756026`.
2. Confirm the synchronized server bootstrap contains `Shutdown`, and confirm
   there is no executable match source.
3. Clear Output and enter Play.
4. Confirm the server and client ready records report role `Lobby`, lifecycle
   `Started`, cleanup `Active`, one cleanup task, and zero registered services.
5. Stop Play.
6. Confirm one server `started` record reports budget `10` and a safe close
   reason.
7. Confirm one server `completed` record reports cleanup `Cleaned` and lifecycle
   `Shutdown`.
8. Confirm there is no `failed`, `timed_out`, or `runner_failed` record and no
   unrelated warning or error.
9. Confirm Studio returns promptly to Edit mode.
10. Repeat until three consecutive Lobby cycles pass.
11. Stop the Lobby Rojo server, start `match.project.json`, and connect only to
    Match PlaceId `136401514513678`.
12. Repeat the same checks for role `Match`, confirm there is no executable lobby
    source, and complete three consecutive cycles.
13. Leave both places in Edit mode. Do not save or publish merely to run this
    regression.

Timeout behavior should be tested only with a focused temporary harness and a
small private budget. Do not deliberately stall the real 10-second
`BindToClose` path during ordinary Play-Stop regression.

## Scope boundary and Phase 03 exit gate

Packet 03.4 adds no gameplay service, client shutdown hook, profile save,
DataStore or MemoryStore access, remote, network protocol, teleport, queue,
purchase flow, analytics sink, external dependency, Studio-authored instance, or
publishing action.

The Phase 03 exit gate passed on 2026-08-25. Services start in deterministic
dependency order; cleanup and lifecycle release in deterministic reverse order;
the server hook has a bounded cooperative wait; timeout does not poison cleanup
state; and repeated Studio Play-Stop sessions return cleanly to Edit mode without
warnings, errors, or leaked bootstrap connections.

Phase 04 added pure shared configuration contracts. Packet 04.5 now gates the
valid startup path before shutdown registration, while preserving the one-hook
shutdown behavior recorded here. Current bootstrap evidence is in
`docs/CONFIGURATION_VALIDATION.md`.
