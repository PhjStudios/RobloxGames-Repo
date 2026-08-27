# Match Lifecycle and Initial Ready Contract

## Decision status and scope

- Phase: 08 — Match Lifecycle and Initial Ready Check
- Decision recorded: 2026-08-27, before executable Phase 08 source changes
- Packets covered: 08.1–08.5
- Implementation status: complete on 2026-08-27; Packets 08.1–08.5, the exact
  four-client Match Studio gate, consolidated review, and complete local exit
  gate passed
- Phase 09 status: next but not begun

This is the authoritative Phase 08 lifecycle, roster, ready-protocol, minimal-UI,
and four-client test decision. Phase 08 adds no enemies, waves, combat, towers,
placement, rewards, persistence, matchmaking, teleports, Lobby behavior,
monetization, production content, art, audio, effects, or unrelated interface.
`PreWave` and `WaveActive` are contract states only; Phase 08 never starts wave
or combat behavior.

## Official Roblox behavior that constrains the decision

`Players.PlayerAdded` reports a newly connected `Player`, while
`Players.PlayerRemoving` fires immediately before removal. A listener can miss
players that already exist, particularly in solo Studio tests, so initialization
connects first and then processes a sorted copy of `Players:GetPlayers()` through
the same idempotent path. A `Player` represents only a presently connected
client. `Player.UserId`, not a mutable or non-unique name, is the stable account
identity. Studio test-player IDs are treated as opaque nonzero safe integers;
the implementation makes no sign assumption.

`RemoteEvent` is asynchronous and one-way. On `FireServer`, Roblox supplies the
originating `Player` as the first `OnServerEvent` argument. A client therefore
never sends its UserId, participant, target, state, deadline, map, service, or
handler. A server event is not durable recovery state because delivery requires
a connected listener.

`Workspace:GetServerTimeNow()` gives clients a monotonic approximation of server
Unix time for synchronized presentation, but it is not a client authority and
can fail after disconnect. The server alone records and enforces the deadline.

`GuiButton.Activated` is the common click, touch-release, and selected-gamepad
A/cross activation event. `ContextActionService:BindAction` supplies scoped
keyboard and gamepad shortcuts and must be paired with `UnbindAction` when the
context ends. The custom Ready button owns touch presentation, so the context
action does not create a second touch button.

Studio Server & Clients launches separate server and client DataModels and
supports up to eight clients. Phase 08 uses exactly four. Touch and controller
emulation feed the corresponding client input paths, and End Session closes the
server and all simulated clients.

Primary sources:

- [Players](https://create.roblox.com/docs/reference/engine/classes/Players)
- [Player.UserId](https://create.roblox.com/docs/reference/engine/classes/Player#UserId)
- [RemoteEvent](https://create.roblox.com/docs/reference/engine/classes/RemoteEvent)
- [Remote events and callbacks](https://create.roblox.com/docs/scripting/events/remote)
- [Client/server security](https://create.roblox.com/docs/scripting/security/client-server-boundary)
- [Workspace.GetServerTimeNow](https://create.roblox.com/docs/reference/engine/classes/Workspace#GetServerTimeNow)
- [GuiButton.Activated](https://create.roblox.com/docs/reference/engine/classes/GuiButton#Activated)
- [ContextActionService.BindAction](https://create.roblox.com/docs/reference/engine/classes/ContextActionService#BindAction)
- [Studio testing modes](https://create.roblox.com/docs/studio/testing-modes#multi-client-simulation)

## Match identity, states, and transitions

One server process owns one immutable, validated `Ids.MatchId`. Production
creates it once from a server-generated GUID; deterministic tests inject an
already validated ID. Disconnects, returns, roster mutations, and state changes
never replace it. Phase 08 has no match reset or service re-entry.

The strict state union and complete legal transition table are fixed:

| Current state | Legal next states | Phase 08 cause |
| --- | --- | --- |
| `Loading` | `ReadyCheck`, `Closing` | Fixed graybox loaded, or load/start failure |
| `ReadyCheck` | `PreWave`, `Closing` | All active ready/mixed timeout, or zero-ready cancellation/shutdown |
| `PreWave` | `WaveActive`, `Closing` | Contract-only future progression, or shutdown |
| `WaveActive` | `Results`, `Closing` | Contract-only future result, or shutdown |
| `Results` | `Closing` | Shutdown/close |
| `Closing` | none | Terminal |

Phase 08 production code invokes only `Loading -> ReadyCheck`,
`ReadyCheck -> PreWave`, and a nonterminal state to `Closing`. It never invokes
`PreWave -> WaveActive`.

Transitions use an authenticated begin/commit token. `beginTransition` checks an
exact expected revision, rejects an illegal or duplicate target, locks re-entry,
and returns one opaque token. Only that token can commit or roll back. Commit
changes state and increments the revision once; rollback clears the lock without
changing state or revision. A stale expected revision, second begin while
locked, repeated commit/rollback, transition after `Closing`, and counterfeit
token all fail without mutation. `Closing` is queryable until lifecycle
shutdown, but it is terminal and cannot restart.

## Revisioned deterministic snapshots

Revision `1` is the initial `Loading` snapshot. Every client-visible logical
commit increments exactly once: a state/deadline commit, participant add or
state change, readiness acceptance, or timeout roster outcome. One synchronous
operation can perform a roster batch followed by a state transition, producing
two ordered revisions while publishing only the final snapshot; skipped
intermediate delivery is valid.

The exact snapshot is:

```luau
type ParticipantSnapshot = {
    userId: number,
    state: "Active" | "Disconnected" | "Returned" | "Spectator",
    ready: boolean,
}

type MatchSnapshot = {
    matchId: Ids.MatchId,
    revision: number,
    state: "Loading" | "ReadyCheck" | "PreWave" | "WaveActive" | "Results" | "Closing",
    deadlineServerTime: number?,
    participants: { ParticipantSnapshot },
}
```

The deadline is present only in `ReadyCheck`. UserIds are nonzero finite safe
integers. Revisions are positive safe integers. Participant arrays contain at
most four lifetime-admitted entries and are sorted by numeric UserId. Every
nested record and array is newly allocated and frozen. Snapshots retain no
`Player`, Instance, connection, thread, cleanup owner, map object, mutable
table, or private error.

## Roster and participant policy

The roster is a private dictionary keyed only by validated UserId. A record has
one exact state and a ready boolean. `ready = true` is valid only for an
`Active` participant. Detached queries are sorted copies.

- During `Loading` or `ReadyCheck`, the first four distinct validated UserIds
  become lifetime-admitted `Active` records. A disconnected or returned record
  retains its slot; Phase 08 never backfills it with another UserId. Any later
  distinct connection is an untracked spectator, receives no roster record,
  and is denied Ready.
- A duplicate add for an existing `Active` or `Spectator` record is a no-op
  rejection.
- Removing `Active` immediately changes it to `Disconnected` and clears ready.
  Repeated removal is a no-op rejection.
- The same UserId reconnecting from `Disconnected` during `ReadyCheck` returns
  to `Active` with ready reset to false. After `ReadyCheck`, it becomes
  `Spectator`; Phase 28 reconnect admission is not pulled forward.
- A `Returned` placeholder remains `Returned` if that UserId reconnects. Phase
  08 does not kick or teleport it.
- Spectators, disconnected records, and returned placeholders never count as
  active readiness voters.
- Cleanup clears the complete dictionary and all detached snapshot caches once.

The service also owns a private connection epoch per admitted UserId and a
weak-key `Player -> { userId, epoch }` connection table. Roster records still
contain no Player Instance. A PlayerAdded for a known disconnected UserId
advances its epoch. PlayerRemoving mutates the roster only when its captured
epoch is still current; a repeated or delayed removal for an older Player can
never disconnect a newer connection. Cleanup clears both epoch dictionaries.

The active threshold is computed from current `Active` records, never from the
original roster size or connected `Player` count. Early progression requires
`activeCount > 0` and every active participant ready. Disconnect immediately
recomputes that condition. Zero active participants never progresses early.

## Authoritative ready deadline and timeout

Entering `ReadyCheck` samples the injected server clock once and records the
absolute deadline as exactly `start + 45`. It also records the entry revision
and schedules one owned callback. The production clock uses
`Workspace:GetServerTimeNow`; production scheduling uses `task.delay` and
`task.cancel`. Headless tests inject deterministic clock and scheduler adapters.

Every clock sample is protected and must be a finite, nonnegative number no
earlier than the last accepted sample. A throwing, wrong-type, nonfinite, or
backwards sample fails closed through `Closing` and can never accept Ready.
Failure of the initial sample prevents entry into `ReadyCheck`.

Ready is accepted only when the authoritative sample is strictly less than the
deadline. At `now >= deadline`, the server resolves timeout before returning a
Ready outcome. The service owns exactly one current timer handle. A callback
clears that handle before sampling time; if it ran early, it replaces the handle
with one schedule for only the remaining duration. Every callback captures the
immutable match identity and a private timer generation, then rechecks lifecycle
state, match state, deadline, clock, and generation before mutation. Exit from
`ReadyCheck` or cleanup advances the generation and cancels only the current
live handle. No callback may reschedule after invalidation. Schedule/cancel
failure also closes the match without accepting Ready. Tests never wait 45 real
seconds.

Timeout policy is fixed:

- one or more ready active participants: mark every unready active participant
  `Returned`, keep ready active participants, then transition to `PreWave`;
- zero ready active participants: transition through `Closing` without kick or
  teleport; and
- disconnected, returned, and spectator records never satisfy the
  at-least-one-ready condition.

## Production remote contracts and rates

Phase 08 adds exactly three reliable `RemoteEvent` definitions, active only for
the Match role:

| Endpoint | Direction/kind | Exact payload | Response |
| --- | --- | --- | --- |
| `GetMatchSnapshot` | client-to-server Request | exact empty record `{}` | required `MatchSnapshot` |
| `SubmitReady` | client-to-server Request | `{ matchId: MatchId, observedRevision: positive safe integer }` | required `MatchSnapshot` |
| `MatchSnapshot` | server-to-client Event | `MatchSnapshot` | none |

`SubmitReady` carries only the server-issued match identity and the revision of
the client's last accepted ReadyCheck snapshot. It carries no UserId, ready
boolean, state, deadline, participant, map, target, or transition. The server
derives ownership from the dispatcher-authenticated `Player.UserId`.

The exact server rate bindings are:

| Inbound endpoint | Capacity | Refill per second | Reason |
| --- | ---: | ---: | --- |
| `GetMatchSnapshot` | 2 | 1 | Initial recovery plus one prompt race retry |
| `SubmitReady` | 2 | 0.5 | One action plus one bounded recovery retry |

There is no rate-policy binding for the outbound event. The network owner
validates every outbound event payload, builds the exact event envelope, and
exposes only a captured server-owned `FireClient` operation. The Match service
derives recipients at send time from current Players whose UserIds are among the
four retained roster identities, sorts them by UserId, and sends the same public
snapshot to at most four recipients. The client cannot select a recipient.

Outbound event publication has exact resource bounds:

- `SNAPSHOT_MIN_INTERVAL_SECONDS = 0.1`: one immediate batch burst and at most
  ten event batches per second;
- `MAX_SNAPSHOT_EVENT_BATCHES = 64` for the one-shot service lifetime;
- at most four per-batch `FireClient` calls;
- exactly one latest-snapshot coalescing slot and one current flush handle;
- no retry queue, delivery ledger, retained recipient, or emission for a
  rejected/no-op mutation; and
- cleanup invalidates/cancels the flush handle and clears the slot and counters.

A later mutation replaces the one coalescing slot. Send failure is contained
and not retried. `GetMatchSnapshot` responses remain available under their own
inbound rate/correlation bounds if an event is coalesced, dropped, or the
lifetime event budget is exhausted.

The existing dispatcher remains the sole inbound path. Exact envelope and
payload validation, rate limiting, correlation, liveness, context-only
authorization, non-yielding protected handler execution, outcome validation,
and origin-only responses remain in their recorded order. A Ready handler is
synchronous and performs no yield, wait, spawn, deferred task, or unowned
connection.

Public rejection mapping is privacy-safe and metadata-free:

- malformed schema: dispatcher `INVALID_PAYLOAD`;
- rate limit: dispatcher `RATE_LIMITED`;
- stale/wrong match or revision outside the accepted ReadyCheck window:
  `STALE_REQUEST`;
- new request after already ready: `DUPLICATE_REQUEST`;
- disconnected, returned, or spectator participant: `NOT_AUTHORIZED`;
- wrong lifecycle or match state: `UNAVAILABLE`; and
- private failure: `INTERNAL_ERROR`.

No response payload, public-error metadata, or log contains a Player, UserId,
request ID, client payload, deadline input, caught error, map reference, or
internal roster object. Only the origin-bound response envelope repeats the
validated correlation request ID required by the shared protocol. The snapshot
itself is replicated gameplay state, not diagnostic output.

## Stale action and snapshot recovery

A Ready submission is current only when all of these are true:

1. its validated MatchId equals the one server-owned identity;
2. the service and match state are `Started` and `ReadyCheck`;
3. `observedRevision` is at least the ReadyCheck entry revision and no greater
   than the current server revision;
4. the engine-authenticated Player maps to an `Active`, not-ready record; and
5. the authoritative clock is still before the deadline.

The revision window deliberately remains valid while peers ready or roster
state changes. Requiring equality with the newest global revision would make
simultaneous clients reject each other and could deadlock the gate.

The client connects the snapshot-event listener and both response listeners
before sending `GetMatchSnapshot`. The first valid snapshot locks the one MatchId
for this controller. Thereafter only a snapshot for that identity with a
strictly greater revision mutates the view model. Equal revisions are harmless
duplicates; lower revisions and another identity are ignored. Thus an event can
win the initial-request race, a response can recover a missed event, and neither
can roll the UI backward.

## Service, map, and cleanup ownership

The role-specific Match composition root runs only after place-role and complete
configuration validation. It constructs the common `NetworkRegistry`, registers
its two inbound contracts and one outbound sender while networking is still in
`Registering`, then registers the fully configured `MatchLifecycle` service with
`dependencies = { "NetworkRegistry" }`. Lifecycle therefore initializes and
starts network before Match, then shuts Match down before network.

Every production project contains exactly one `Script` and one `LocalScript`.
Default and Lobby map `src/server/common/bootstrap/Main.server.luau` and
`src/client/common/bootstrap/Main.client.luau` at the established DataModel
paths. Match maps the exact files
`src/server/match/bootstrap/Main.server.luau` and
`src/client/match/bootstrap/Main.client.luau` at those same established paths.
The Default and Match manifests explicitly map the non-bootstrap Match module
subfolders instead of naturally mapping either Match bootstrap a second time;
Lobby maps no Match source. Structural verification checks exact path, class,
source, and count for all three projects.

This explicit composition-root exception preserves the allowed
match-to-common/shared dependency direction, replaces the known Rojo-owned Main
source in place, and avoids a second runner or an unknown stale Main. The common
Development server bootstrap returns after place-role and full-configuration
validation, before `ServerRemoteRegistry.new`; otherwise Development's union
registry view would require real Match handlers in common. Default is therefore
build/inspection and validation-only runtime evidence after Phase 08. Isolated
Lobby and Match projects remain the role-runtime evidence.

During Match initialization, one server-selected MapLoader loads only
`map:phase07-graybox`. A missing/invalid/conflicting template or runtime root
transitions `Loading -> Closing` without publishing partial map state. The client
never supplies a MapId or Instance. Match cleanup invokes the loader's terminal
`cleanup`, which unloads the exact owned `Workspace.ATDRuntimeMap`.

Match cleanup registers resources in this ownership order: map loader, roster
and snapshot-cache clear callbacks, Player connections, then ready timer.
Reverse cleanup therefore invalidates/cancels the timer, disconnects
PlayerAdded/PlayerRemoving, clears roster/snapshots, and unloads the map. The
service enters `ShuttingDown` first, so network handlers that race before the
network owner's later shutdown can only return `UNAVAILABLE`. Repeated shutdown
and every child cleanup are idempotent; no post-clean callback can publish or
mutate.

The map cleanup callback must inspect `MapLoader:cleanup()`. A failure Result is
converted to one static privacy-safe thrown failure so the established Cleanup
aggregate and lifecycle shutdown cannot report success while a runtime root may
remain. No loader error payload or Instance enters that failure.

## Minimal client controller and UI

The Match client owns one `MatchReadyController` lifecycle service and one
programmatically constructed `ScreenGui`, all under `src/client/match`. It uses
the common fixed lookup and request tracker; it creates no remote and accepts no
dynamic path.

The UI shows the state, presentation-only remaining seconds, and each sorted
participant as `Player 1` through `Player 4` with `(You)` where applicable. It
shows Ready/Waiting/Disconnected/Returned/Spectator without retaining names or
Player objects. The Ready TextButton is selectable and uses `Activated` for
mouse, touch, and UI-navigation activation. A scoped action binds keyboard `R`
and gamepad `ButtonA` with no generated touch button. Only `Begin` activates.

The controller changes local request presentation through Idle, Pending,
Accepted, Rejected, and StateChanged. It sets Pending before firing, so an
overlapping ButtonA/Activated path cannot send twice. Pending is presentation
only; all server checks remain mandatory. Rejection shows only the allowlisted
public code and initiates bounded snapshot recovery where useful. A protected
`GetServerTimeNow` sample updates countdown projection; failure displays an
unknown countdown and never changes authority.

Controller Cleanup unbinds the context action, disconnects GUI/render/remote
listeners, clears the request tracker and view model, and destroys the exact
ScreenGui in reverse dependency order. The Match client bootstrap owns an
explicit `script.Destroying` cleanup trigger in addition to test-invoked
shutdown, because the prior empty client lifecycle had no process-close owner.

## Packet 08.5 four-client procedure

Before any sync or Play action:

1. list connected Studio instances and select only PlaceId `136401514513678`;
2. require Edit mode, GameId `10757629094`, CreatorType `Group`, CreatorId
   `35420107`, PHJGAMES ownership, and `ATDPlaceRole = Match`;
3. inventory the bounded persistent roots under mapped common/match script
   folders, `ReplicatedStorage.Shared`, `ReplicatedStorage.ATDNetwork`,
   `ServerStorage.ATDMapTemplates`, `Workspace.ATDRuntimeMap`, and relevant GUI
   templates; and
4. capture exact Rojo-managed Script.Source hashes/values. Stop if sync would
   modify an unrelated or unmapped Instance.

Connect only `match.project.json`. Do not use Script Sync, manual Script.Source
edits, save, or publish. Use one focused four-client gate composed of fresh
Server & Clients sub-sessions where terminal one-shot state requires isolation:

1. four Ready activations and early `PreWave`;
2. mixed ready/unready timeout, returned placeholders, and ready roster
   `PreWave`;
3. disconnect during ReadyCheck and immediate threshold recalculation;
4. same-UserId reconnect placeholder behavior. When Studio can add the departed
   client back, exercise it live. Otherwise, within the active four-client
   session, use a runtime-only MCP harness to require the real roster module and
   assert disconnect, reconnect, and stale-removal epochs for the departed
   UserId. The fallback owns separate state, never touches the production match,
   and is discarded at End Session;
5. zero-ready timeout to `Closing`;
6. duplicate and stale Ready envelopes rejected without a second transition;
7. equal final MatchId/revision/state/participants in all four client UIs;
8. rendered mouse/keyboard, touch, and gamepad activation; and
9. End Session with no timer, connection, roster, snapshot, remote, UI, runtime
   map, or cache residue.

MCP Luau execution performs server/client assertions and console inspection.
MCP keyboard/mouse input is primary when supported; limited computer control is
used only for the authorized four-client/device controls MCP lacks. Every
sub-session ends all clients/server. The final state must be Edit mode with the
original persistent inventory and no `Workspace.ATDRuntimeMap`.

## Studio execution evidence — 2026-08-27

The gate selected only the connected Match Studio instance and verified all of
its identity fields before synchronization or Play: PlaceId
`136401514513678`, GameId `10757629094`, CreatorType `Group`, CreatorId
`35420107`, official Roblox group API name `PHJGAMES`, resolved
`ATDPlaceRole = Match`, and Edit mode. Only `match.project.json` synchronized
the authorized mapped branch source. No manual Script.Source edit, Script Sync,
Save, or publish occurred.

Fresh four-client Server & Clients sub-sessions produced the following exact
server and client evidence:

1. Zero Ready actions reached `Closing` at revision `7`; the MatchId, state,
   revision, and participant snapshots were identical on all four clients.
2. One Ready action followed by the mixed timeout reached `PreWave` at revision
   `9`; every client showed one `Active` ready participant and three `Returned`
   unready placeholders in the same order.
3. The all-ready session activated keyboard `R` on Players 1 and 4, virtual
   `ButtonA` on Player 2, and the touch-translated Ready button on Player 3.
   Player 3 used iPhone 17 Pro device emulation with `TouchEnabled` and a
   `750x361` viewport. All four clients reached `PreWave` at revision `11` with
   four `Active`, ready participants and identical snapshots.
4. The protocol session first returned a successful snapshot at revision `7`,
   then returned privacy-safe `STALE_REQUEST` and `DUPLICATE_REQUEST`
   rejections for their respective Ready submissions without an extra
   transition.
5. In the early-disconnect session, three participants became ready and Player
   2/UserId `-2` became `Disconnected`. Active-threshold recalculation caused an
   immediate `PreWave` at revision `11`, consistently across the server and
   surviving clients.
6. The same-UserId reconnect/returned-placeholder fallback was repeated while
   a fresh four-client Server & Clients session remained live. Direct MCP probes
   confirmed four registered client DataModels, each seeing four players in the
   exact Match place. A runtime-only Edit execution then required the exact
   production roster module into isolated state and passed `43` assertions for
   ReadyCheck reactivation, readiness reset, stale-removal epochs, post-check
   Spectator admission, sticky `Returned` placeholders, active-voter exclusion,
   and idempotent cleanup. It never touched the production match and was cleaned
   before End Session.

Every Server & Clients sub-session was ended before the next one. The final
Edit-mode probe counted `54` ModuleScripts, one Script, and one LocalScript at
the bounded persistent roots. It confirmed the exact
`ServerScriptService.Server.common.bootstrap.Main`,
`ServerScriptService.Server.common.bootstrap.ServerBootstrap`,
`StarterPlayer.StarterPlayerScripts.Client.common.bootstrap.Main`, and
`StarterPlayer.StarterPlayerScripts.Client.common.bootstrap.ClientBootstrap`
paths and found `24` descendants under the map catalog. It found no
`Workspace.ATDRuntimeMap`, `ReplicatedStorage.ATDNetwork`, Ready GUI,
`AutomatedTests`, or `TestRunner`. Device emulation was reset to default, no
server or simulated-client window remained, and Studio was left in Edit mode.

## Review and completion record

The single focused architecture/security review completed on 2026-08-27 before
source work. It found no P0 and seven material items, all resolved in this
decision: the roster now has a four-identity lifetime cap and connection epochs;
outbound emission has exact burst, sustained, lifetime, recipient, queue, and
cleanup bounds; MapLoader failure is surfaced; clock/timer anomalies fail
closed; manifests enforce one exact bootstrap; reconnect has a mandatory live or
runtime-harness path; and correlation-ID privacy wording matches the wire
contract. No overlapping review round was started.

The one consolidated independent final review then covered architecture,
source, networking security, cleanup, tests, UI, Studio safety, and affected
documentation. It found no P0/P1 defect and three P2 findings, all resolved:
inactive `R`/`ButtonA` input now returns `Pass` unless a Ready action actually
starts; the reconnect fallback was repeated during a fresh live four-client
session with `43` passing assertions; and the lifecycle document now records
transactional initialize/start unwind and all-service shutdown behavior.

The complete local exit gate passes formatting, lint, `347` tests across `28`
suites, all four structural builds, diff, scope, generated-output,
production-test-exclusion, exact remote/rate-catalog, and Lobby/Match isolation
checks. Studio ended in Edit mode with the bounded persistent inventory intact
and no runtime residue. Phase 08 is complete on 2026-08-27; Phase 09 is next but
unbegun. The final exact-SHA Repository Verification run is cited at task
handoff rather than copied into this tracked record by a self-referential
evidence commit.
