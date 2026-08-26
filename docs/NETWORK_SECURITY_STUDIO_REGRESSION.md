# Phase 06 Unsaved Studio Networking Regression

## Status and scope

- Status: **Passed — fresh Gate A rerun**
- Date: 2026-08-26
- Operator: Codex, under the repository owner's explicit Phase 06 authorization
- Studio version: `0.735.0.7351131`; installation build directory
  `version-dcbeee682ce74ee0`
- Lobby: PlaceId `100561454756026`, paired only with `lobby.project.json`
- Match: PlaceId `136401514513678`, paired only with `match.project.json`
- Plain lifecycle runs: Lobby 3/3; Match 3/3
- Final networking run: Match `Server & Clients`, exactly two clients
- Places saved or published: none
- External/API services enabled or used: none
- Edit-mode or Studio-authored instances modified: none

This is the Roblox-engine portion of the Phase 06 gate. Headless tests are
authoritative for deterministic registry, validation, rate, correlation,
privacy, and lifecycle logic. Studio proves only behavior the isolated runner
cannot: real `RemoteEvent` delivery and table copying, the engine-supplied
originating `Player`, origin-only `FireClient`, live Roblox datatypes, server and
client execution contexts, and real `PlayerRemoving` delivery.

This pass does not approve a gameplay endpoint, published-client behavior,
adverse-network behavior, external services, or any deferred Phase 07/later
test. The lasting production registry and production rate-policy list remain
empty.

## Safety and ownership boundary

The tracked harness sources are:

- `tests/studio/Phase06NetworkServer.server.luau`
- `tests/studio/Phase06NetworkClient.client.luau`

The exact sources staged for the accepted Gate A run matched the tracked files
both before injection and after the session:

- server SHA-256:
  `883bcdb665f54cb5adff9f935af90992cc5b71e5a486f7293a6f5a2f27bdec6a`;
- client SHA-256:
  `8223e9e95dfb4caee94986da9f722917b68ec23ee5e7c7e1992d2173fc1ea290`.

`tests/studio` is absent from Default, Lobby, Match, and Test mappings. The
sources are injected only into live local-test DataModels after `Server &
Clients` starts:

- one `ATDPhase06NetworkServerRuntime` Script in the live server's
  `ServerScriptService`; and
- one `ATDPhase06NetworkClientRuntime` LocalScript in each live client's
  `PlayerScripts`.

No temporary Script is created in the Edit DataModel. Ending the test discards
all three runtime scripts. The harness server alone creates the distinct
`ReplicatedStorage.ATDPhase06StudioFixture` test root parent-last. One fixture
Cleanup container owns the root, listeners, limiter, dispatcher, and
player-removal state. Every protected remote and `PlayerRemoving` callback is
non-yielding and records only bounded state; one protected main coordinator
performs waits and ordered transitions outside those callbacks. The Cleanup
container owns coordinator cancellation, while the terminal/finishing gates
prevent it from advancing during reverse resource teardown. Clients use bounded
exact-segment lookup and create no Instance.

The production bootstrap separately owns the unique
`ReplicatedStorage.ATDNetwork/v1` tree. The fixture must never adopt, delete,
rename, reparent, populate, or second-initialize that tree. A conflicting
fixture name fails closed and is never adopted or deleted.

Only the correctly paired Match place and exactly two clients are accepted.
The harness uses fixed registry definitions rather than an action field or
generic bus and composes the production `RemoteRegistry`, `RequestProtocol`,
`PayloadValidation`, `ServerRateLimiter`, and `ServerRequestDispatcher`
modules.

## Bounded harness contract

- Client source/fixture discovery: 45 seconds.
- Ordinary assignment, request/response, and final-event waits: 5 seconds.
- Real disconnect/continuation phase: 90 seconds.
- Complete client protocol and server run: 120 seconds.
- Server post-`PlayerRemoving` limiter/dispatcher cleanup polling: 5 seconds.

The ordinary checks remain narrow. Only the engine disconnect phase has the
larger bound. Official documentation says `LeaveTest()` disconnects the calling
client but gives no latency guarantee. In the installed build, successful
`PlayerRemoving` delivery occurred about 63 seconds after the client call was
accepted. Earlier 5- and 20-second continuation bounds failed closed; the
server cleanup still reached `Cleaned`, and neither failed run was accepted as
completion evidence.

The server sends an explicit leave-phase barrier to both clients: `leave=true`
to the departing client and `leave=false` to the remaining client. The
remaining client's disconnect clock begins only after that barrier. The
departing client deliberately emits no terminal after `LeaveTest()` because its
DataModel is being torn down. The server-observed `PlayerRemoving`, the
remaining-client terminal, and the server terminal are authoritative.

## Fixed cases

1. Verify one empty production `ATDNetwork/v1` tree and leave it untouched.
2. Publish the distinct test fixture parent-last and resolve it from both
   clients without client creation.
3. Use the same bounded request ID from both clients and prove engine-origin
   identity plus origin-only response routing.
4. Reject forged identity/ownership fields and a private sentinel before the
   identity mutation sentinel.
5. Reject non-finite `Vector2`, `Vector3`, and `CFrame` components at stable safe
   paths before numeric mutation, then accept one finite record per client.
6. Reject Instances by default; reject explicit policy from the client; accept
   only the exact server class/ancestry policy and reject wrong class/ancestry.
7. Prove one-token burst limits are independent by player and endpoint.
8. Prove rate/protocol reports retain only exact bounded aggregate fields.
9. Use protected `CanLeaveTest()`/`LeaveTest()`, observe real
   `PlayerRemoving`, clear only that player's limiter/correlation state, and
   continue serving the remaining client.
10. Receive the final acknowledgment, disconnect listeners, clear dispatcher
    and limiter state, destroy the exact fixture, and emit one bounded server
    terminal.

## Repeatable unsaved procedure

### Repository and place preflight

1. Run formatting, Selene, the canonical headless suite, the four-project
   verifier, and `git diff --check`.
2. Confirm no project maps `tests/studio`, no production build contains a
   harness marker, and production endpoints/policies remain empty.
3. Leave both production places in Edit mode. Connect only
   `lobby.project.json` to Lobby or `match.project.json` to Match, one at a
   time. Never use Script Sync.
4. Confirm no `ATDPhase06StudioFixture` exists and do not adopt or delete an
   ambiguous same-named object.
5. Do not save, publish, enable API access, or use a public server.

### Plain Lobby and Match lifecycle checks

For each correctly paired place, run three ordinary Play/Stop cycles without a
harness. During each cycle confirm:

- exactly one production `ATDNetwork` Folder, one `v1` Folder, and zero
  endpoints on server and client;
- configuration validation precedes ready;
- server ready reports one `NetworkRegistry` service and client ready reports
  zero services; and
- Stop reports server shutdown `Shutdown`/`Cleaned` with no unexpected ATD
  warning/error and returns to Edit mode.

Disconnect Lobby before connecting Match. Do not save or publish either place.

### Runtime-only two-client injection

1. Remain in Match with only `match.project.json` connected.
2. Select `Server & Clients`, exactly two clients, and press F7.
3. Open Command Bar in both live client windows and the live server window.
4. Stage all three commands before executing any of them. Each command creates
   an unparented runtime Script, assigns the exact corresponding tracked file as
   Source with a safe long-bracket delimiter, calls
   `LogService:ClearOutput()`, and only then parents the Script into the live
   DataModel. Clearing occurs after Command Bar echoes the injected source but
   before the harness starts, so log privacy is measured without operator-source
   echo contamination.
5. Execute both client commands, then the server command, without changing the
   staged sources.
6. Do not interact with gameplay, Explorer objects, or network simulation while
   the bounded harness runs.
7. One client window must leave. The remaining client and server must emit the
   exact terminals below within 120 seconds, with no harness failure or engine
   error.
8. Before ending the session, inspect the live server: production root count
   one, root/version classes Folder, endpoint count zero, fixture count zero.
9. Audit `LogService:GetLogHistory()` in the server and remaining client with
   forbidden values assembled dynamically so the audit command does not add
   them. Require zero private/request-value/failure-marker matches and zero
   `MessageError` entries.
10. End Session. Runtime scripts are discarded automatically; confirm Match
    returns to Edit mode. Leave Lobby in Edit mode as well.

Do not replace `LeaveTest()` with `Player:Kick()`, widen ordinary response
timeouts, install an Edit-mode Script, or weaken the disconnect requirement.

## Passing evidence

### Plain places

- Lobby Play/Stop: 3/3 passed.
- Match Play/Stop: 3/3 passed.
- Every inspected production tree: root count 1, Folder root, Folder `v1`,
  endpoint count 0.
- Ready service counts: server 1, client 0.
- Every captured server shutdown: lifecycle `Shutdown`, cleanup `Cleaned`.
- Final Lobby mode: Edit.
- Final Match mode: Edit.

### Final two-client run

The accepted fresh Gate A pass launched the existing current-source server and
both client scripts within one second at `2026-08-26 18:07:38` local
(`America/Toronto`; `22:07:38Z`). The real client disconnect was logged at
`18:08:40.666`, the remaining client passed at `18:08:40.816`, and the server
passed at `18:08:41.050`.

```text
[ATD_PHASE06_STUDIO][PASS][context=client][case=completed][caseCount=10]
[ATD_PHASE06_STUDIO][PASS][context=server][caseCount=10][clientCount=2][cleanupState=Cleaned]
```

Post-pass bounded records:

```text
[ATD_PHASE06_STUDIO][LOG_AUDIT][context=client][forbiddenMatches=0][errorCount=0]
[ATD_PHASE06_STUDIO][LOG_AUDIT][context=server][forbiddenMatches=0][errorCount=0]
[ATD_PHASE06_STUDIO][INSPECT][context=server][rootCount=1][rootClass=Folder][versionClass=Folder][endpointCount=0][fixtureCount=0]
```

The server inspection completed at `18:09:49.430`; the server and client log
audits completed at `18:10:36.995` and `18:11:01.344`, respectively. Each log
audit dynamically assembled the private sentinel, representative request IDs
and values, and terminal failure markers so its own command could not create a
false match. Both also required zero `MessageError` records.

Observed engine behavior and assertions:

- origin identity and response routing: pass;
- forged fields and zero identity mutation: pass;
- non-finite `Vector2.X`, `Vector3.Y`, and `CFrame.Z`: delivered and rejected at
  their safe paths before mutation;
- default and explicit Instance policies: pass;
- per-player and per-endpoint burst isolation: pass;
- real `PlayerRemoving`, limiter/ledger cleanup, and remaining-peer service:
  pass;
- aggregate privacy and bounds: pass;
- fixture cleanup and production-root preservation: pass;
- private sentinel and representative request values absent from audited log
  history: pass;
- unexpected error records: zero;
- place save/publication and external services: none.

## Primary references

- [Studio testing modes](https://create.roblox.com/docs/studio/testing-modes)
- [`StudioTestService`](https://create.roblox.com/docs/reference/engine/classes/StudioTestService)
- [`RemoteEvent`](https://create.roblox.com/docs/reference/engine/classes/RemoteEvent)
- [Remote events and callbacks](https://create.roblox.com/docs/scripting/events/remote)
- [Securing the client-server boundary](https://create.roblox.com/docs/scripting/security/client-server-boundary)
- [`LogService`](https://create.roblox.com/docs/reference/engine/classes/LogService)
