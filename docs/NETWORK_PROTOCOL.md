# Network Protocol and Remote-Security Foundation

## Decision status

- Phase: 06 — Network Protocol and Remote-Security Foundation
- Architecture decision recorded: 2026-08-26, before Phase 06 source changes
- Primary-source research accessed: 2026-08-26
- Packet 06.1 status: complete — 2026-08-26
- Packet 06.2 status: complete — 2026-08-26
- Packet 06.3 status: complete — 2026-08-26
- Packet 06.4 status: complete — 2026-08-26
- Packet 06.5 status: complete — 2026-08-26
- Phase 06 / Gate A status: complete / passed — 2026-08-26
- Transport decision: fixed, reliable, asynchronous `RemoteEvent` endpoints
- Phase 06 checkpoint endpoints: none; that completed checkpoint used an empty
  authenticated registry
- Current Phase 13 endpoints: `GetMatchSnapshot`, `SubmitReady`,
  `MatchSnapshot`, `GetEnemySnapshot`, `EnemyReplication`, `GetBaseSnapshot`,
  `BaseReplication`, `GetWaveSnapshot`, `SubmitSkipVote`, and
  `WaveReplication`, plus `GetTowerPlacementQuery`, `SubmitTowerPlacement`, and
  `TowerPlacementRevision`, all Match-only reliable `RemoteEvent` contracts
- `RemoteFunction`: prohibited unless a later recorded concrete need changes the
  decision
- Generic remote bus, client-selected action, service, handler, or path: prohibited
- Gameplay, persistence, external service, place save, or publication authorized:
  none

This is the authoritative Phase 06 network-boundary document. The decision
section was recorded before implementation. The sections below also record the
completed Packet 06.1–06.5 implementations and evidence. Statements that the
production registry or rate-policy catalog was empty describe those historical
  checkpoints. The current Phase 11 extension is recorded below and uses the same
authenticated registry, validation, dispatcher, limiter, correlation, logging,
and cleanup boundary. Phase 08 is complete. Phase 09 implementation, exact
Studio gate, consolidated review, 467-case local gate, and all four structural
builds pass on 2026-08-27. Phase 09 is complete; exact-final-SHA CI evidence is
cited at handoff. Phase 10 focused and exact Match Studio checks, consolidated
review, `593`-case local gate, and all four structural builds passed on
  2026-08-28. Phase 10 is complete. Phase 11's exact Studio gate, consolidated
  review, `742`-case local gate, and all four structural builds also passed on
  2026-08-28. Exact-final-SHA CI is cited at handoff. Phase 11 is complete.
  Phase 12's trusted Tower seam is server-only and adds no endpoint or rate
  policy; its exact Studio, consolidated-review, `840`-case/`64`-suite local,
  and four-build checks pass. Phase 12 is complete; the current Phase 13
  placement extension is recorded below.

## Official Roblox behavior that shapes the design

Roblox documents `RemoteEvent` as asynchronous, one-way, and non-yielding. A
client `FireServer()` invocation reaches `OnServerEvent` with the originating
`Player` supplied by the engine as the first argument. `FireClient()` requires an
explicit target player. These properties support an asynchronous request and
optional response pair without allowing the client to supply its identity.

Roblox documents `RemoteFunction` as synchronous and yielding. Only the last
assigned callback runs, and server-to-client invocation can raise when the client
errors or disconnects or can yield indefinitely when the client never returns.
Phase 06 has no need that justifies those hazards. `UnreliableRemoteEvent` is
unordered and lossy, is intended for disposable continuously changing data, and
drops payloads over its current 1,000-byte encoded limit. It is unsuitable for
requests, responses, or correlation.

Roblox's current client-to-server engine throttle is described as approximately
500 invocations per second per client, shared among remotes of the same type.
That approximate implementation limit is not an application security policy.
The project therefore enforces its own much lower action-specific server token
buckets.

Remote serialization copies tables, removes metatables, converts non-string table
keys, and cannot carry functions or sender-only Instances faithfully. Roblox also
documents that NaN and positive and negative infinity are valid numeric values
that applications must reject. No fixed byte ceiling for a standard reliable
`RemoteEvent` payload is published in the reviewed current documentation. The
project therefore owns strict envelope, string, array, record, depth, node, and
field limits and tests hostile tables directly before transport.

Replication order is not guaranteed. `WaitForChild()` without a timeout can
yield indefinitely and warns after five seconds. Clients will wait only for
fixed registry-derived segments with one bounded total deadline, exact class
checks, and no creation or recursive search. Instances referenced by a remote
may arrive after the signal or never be available under streaming, so Instance
payloads are rejected by default and require an explicit server-side policy.

Anything replicated to a client can be inspected, including endpoint names and
shared definitions. They are identifiers, not secrets. Authorization and
handlers remain server-only.

Studio's current `Server & Clients` mode launches separate server and client
DataModels. `StudioTestService:LeaveTest()` is client-only and documents a
disconnect from the active multiplayer test, but publishes no latency bound.
In Studio `0.735.0.7351131` on 2026-08-26, the successful local regression
delivered the corresponding server disconnect about 63 seconds after the client
call was accepted. The manual harness therefore retains five-second ordinary
response checks while bounding only the disconnect phase at 90 seconds and the
complete protocol/server run at 120 seconds. This observed local latency is
test-harness evidence, not a production-network timing contract.

### Primary sources

- [Remote events and callbacks](https://create.roblox.com/docs/scripting/events/remote)
- [`RemoteEvent.OnServerEvent`](https://create.roblox.com/docs/reference/engine/classes/RemoteEvent/OnServerEvent)
- [`RemoteFunction.InvokeClient` hazards](https://create.roblox.com/docs/reference/engine/classes/RemoteFunction/InvokeClient)
- [`UnreliableRemoteEvent.OnClientEvent`](https://create.roblox.com/docs/reference/engine/classes/UnreliableRemoteEvent/OnClientEvent)
- [Securing the client-server boundary](https://create.roblox.com/docs/scripting/security/client-server-boundary)
- [Security tactics and server authority](https://create.roblox.com/docs/scripting/security/security-tactics)
- [Defensive design](https://create.roblox.com/docs/scripting/security/defensive-design)
- [Server-side detection and directional remotes](https://create.roblox.com/docs/scripting/security/server-side-detection)
- [Replication and confidentiality](https://create.roblox.com/docs/scripting/security/access-control)
- [Replication ordering](https://create.roblox.com/docs/scripting/attributes#replication-order)
- [`Instance.WaitForChild`](https://create.roblox.com/docs/reference/engine/classes/Instance.md#WaitForChild)
- [Streaming and Instances sent remotely](https://create.roblox.com/docs/workspace/streaming/techniques#instances-sent-remotely)
- [Networking and replication performance](https://create.roblox.com/docs/performance-optimization/improve#networking-and-replication)
- [`typeof` for Roblox host types](https://create.roblox.com/docs/reference/engine/globals/RobloxGlobals#typeof)
- [Luau standard library and byte-string behavior](https://luau.org/library/)
- [`Vector2` datatype](https://create.roblox.com/docs/reference/engine/datatypes/Vector2)
- [`Vector3` datatype](https://create.roblox.com/docs/reference/engine/datatypes/Vector3)
- [`CFrame` component contract](https://create.roblox.com/docs/reference/engine/datatypes/CFrame.md)
- [`Instance` class and ancestry API](https://create.roblox.com/docs/reference/engine/classes/Instance.md)
- [`RunService` execution-context API](https://create.roblox.com/docs/reference/engine/classes/RunService)
- [`Players.PlayerRemoving`](https://create.roblox.com/docs/reference/engine/classes/Players.md#PlayerRemoving)
- [Luau clock comparison](https://luau.org/news/2020-06-20-luau-recap-june-2020/#os-enhancements)
- [`DataModel.BindToClose`](https://create.roblox.com/docs/reference/engine/classes/DataModel.md#BindToClose)
- [Studio multi-client testing](https://create.roblox.com/docs/studio/testing-modes#multi-client-simulation)
- [`StudioTestService`](https://create.roblox.com/docs/reference/engine/classes/StudioTestService)
- [`LogService.ClearOutput`](https://create.roblox.com/docs/reference/engine/classes/LogService#ClearOutput)
- [Luau protected-call and coroutine semantics](https://luau.org/library/#coroutine-library)

## Approved physical layout

The server owns this one replicated tree:

```text
ReplicatedStorage
  ATDNetwork                         Folder, server-created
    v1                               Folder, fixed protocol version
      <registry endpoint name>       Folder, one fixed contract
        Request                      RemoteEvent, request contracts only
        Response                     RemoteEvent, only when declared
        Event                        RemoteEvent, event contracts only
```

Endpoint names are single bounded registry tokens, never paths. A contract is
active only for its declared Lobby and/or Match role. The combined Development
project may expose the union for inspection, but Lobby creates no Match-only
endpoint and Match creates no Lobby-only endpoint.

The canonical endpoint-name grammar is one through 48 bytes: the first byte is
an uppercase ASCII letter, and every remaining byte is an ASCII letter or digit.
Names are exact and case-sensitive after validation. `ATDNetwork`, `v1`,
`Request`, `Response`, and `Event` are reserved case-insensitively. Slashes,
dots, separators, whitespace, Unicode, empty names, and path fragments are not
valid endpoint identities. A registry contains at most 128 definitions.

The server creates an unparented root, immediately registers that exact root in
its `Cleanup` container, constructs the version/endpoints/leaves beneath it,
binds only reviewed server listeners, and sets the root's `Parent` last. It
preflights the root before construction and checks again immediately before
publication. Any pre-existing root, wrong class, duplicate owner, late
publication race, or conflicting tree fails closed without deleting or adopting
the unowned object. Failed initialization rolls back only the service's own
listeners and unparented tree. Re-entry and a second owner are rejected rather
than silently sharing mutable state.

## Registry contract

Every definition will declare exactly:

- one bounded canonical endpoint name;
- reliable `RemoteEvent` transport;
- `ClientToServer` or `ServerToClient` direction;
- `Request` or `Event` semantic kind;
- whether a request has a separate response endpoint; and
- a nonempty fixed set of active place roles.

`RemoteRegistry.create()` accepts only a plain dense definition array and exact
plain definition records. It reads tables without invoking `__index`, rejects
metatables, copies caller input, canonicalizes role order as Lobby then Match,
sorts definitions bytewise by endpoint name, and deeply freezes the definitions,
role views, lookup dictionary, and registry. Private weak-key provenance
registries authenticate both definitions and registry receivers, so a copied or
metatable-shaped table is not accepted. Validation returns the existing frozen
`Result` branches with stable public `code`, `path`, and static `message` fields;
it never retains or echoes a rejected value.

The read-only typed API is `get(name)`, `list()`, `listForRole(role)`, and
`count()`. `Lobby` and `Match` views contain only definitions declared for that
role; `Development` is the deterministic union. Lookup returns only canonical
authenticated definitions, and no result order depends on dictionary iteration.

The following combinations are invalid:

- a request whose direction is not client-to-server;
- an event with a response;
- a response without a request;
- an unsupported transport;
- an empty, duplicate, malformed, reserved, path-like, or oversized name;
- an empty, duplicate, malformed, or unsupported place-role list; or
- two definitions that claim the same physical identity.

At the Phase 06 checkpoint the production registry was empty. Phase 08 later
added only the three Match-ready definitions below, Phase 09 added two enemy
definitions, and Phase 10 adds the two base definitions recorded in its current
extension. The Phase 06 tests continue
to use deterministic test-only definitions; they do not populate any additional
production endpoint.

## Server runtime ownership and binding

`ServerRemoteRegistry.new()` accepts a genuine context-bound logger, an
authenticated registry, the actual `ReplicatedStorage` service, and one resolved
runtime role. It exposes one frozen lifecycle service definition named
`NetworkRegistry`. The common server bootstrap constructs this owner only after
place-role and whole-configuration validation, registers it before lifecycle
initialization, and starts no gameplay service.

Every active client-to-server definition must receive exactly one handler while
the network owner is in `Registering`. Unknown names, inactive role definitions,
server-to-client definitions, non-function handlers, late binding, and duplicate
binding fail closed. Initialization refuses to publish if any active inbound
definition is unbound. At Packet 06.1 completion the production registry was
empty, so that historical checkpoint published only `ATDNetwork/v1`. The
current Match composition binds the four Phase 08–10 inbound requests and
captures the three outbound events before network initialization.

The service-owned `Cleanup` container registers the root before connection
objects. Its LIFO sweep therefore disconnects all listeners before destroying
the replicated tree. The outer bootstrap cleanup owns lifecycle shutdown; the
existing reverse lifecycle and one graceful-shutdown path consequently release
the network owner without adding a second `BindToClose` hook.

## Bounded client lookup

The production `ClientRemoteLookup.resolve(endpointName, timeoutSeconds)` API is
internally anchored to `ProductionRemotes`, the actual `ReplicatedStorage`
service, and the role resolved from the centralized `PlaceRoles` contract. A
production caller cannot supply or replace a registry, parent, role, clock, wait
adapter, path, service, or handler. The lookup rejects an unknown or inactive
endpoint before waiting. The caller supplies one finite positive total timeout
of at most five seconds; every fixed segment consumes the decreasing remainder
of that single deadline. The default clock is monotonic `os.clock()`, and
non-finite, failed, or backwards clock reads fail closed.

Lookup waits only for `ATDNetwork`, `v1`, the canonical endpoint folder, and the
definition-required `Request`, optional `Response`, or `Event` leaf. Every
returned value must have the expected direct parent, exact name, and exact
`Folder` or `RemoteEvent` class. Lookup never calls `Instance.new`, reparents an
Instance, performs recursive discovery, accepts a caller path, or creates a
missing object. Its success and failure envelopes are frozen and privacy-safe.
They reuse the established shared `Result` contract.
The dependency-injected resolver is exposed only when this exact production
ModuleScript has the exact
`ServerStorage.AutomatedTests.ProductionClientNetworking.ClientRemoteLookup`
test identity. That non-replicated structural gate cannot be satisfied by the
normal `StarterPlayerScripts` production location, where the seam is `nil`.

## Phase 08 Match-ready protocol

Phase 08 adds exactly three production definitions. All use reliable
`RemoteEvent` transport, are active only for the Match role, and remain under
the fixed `ReplicatedStorage.ATDNetwork.v1` tree:

| Endpoint | Direction and kind | Exact payload | Response |
| --- | --- | --- | --- |
| `GetMatchSnapshot` | client-to-server Request | exact empty record `{}` | required revisioned Match snapshot |
| `SubmitReady` | client-to-server Request | `{ matchId: MatchId, observedRevision: positive safe integer }` | required revisioned Match snapshot |
| `MatchSnapshot` | server-to-client Event | revisioned Match snapshot | none |

The snapshot schema contains one immutable server-generated MatchId, a positive
revision, one of `Loading`, `ReadyCheck`, `PreWave`, `WaveActive`, `Results`, or
`Closing`, an authoritative deadline only while in `ReadyCheck`, and at most
four UserId-sorted participant records. Participant records contain only a
nonzero safe-integer `userId`, `Active`/`Disconnected`/`Returned`/`Spectator`
state, and a ready boolean that may be true only for `Active`. Validation
detaches and freezes the complete graph. It carries no Player Instance, map
Instance, client-selected state, target, deadline, participant, or transition.

The engine-authenticated Player supplied to `OnServerEvent` is the only Ready
actor. `SubmitReady` never accepts a UserId or ready value from the payload.
The dispatcher validates the exact envelope and payload, applies the endpoint's
rate policy, derives authorization from that Player context, and invokes one
non-yielding protected handler. The current production rate bindings are:

| Endpoint | Capacity | Refill per second |
| --- | ---: | ---: |
| `GetBaseSnapshot` | 2 | 0.25 |
| `GetEnemySnapshot` | 2 | 0.25 |
| `GetMatchSnapshot` | 2 | 1 |
| `SubmitReady` | 2 | 0.5 |

The outbound event has no inbound rate-policy entry. `SnapshotBroadcaster`
instead validates every snapshot and bounds publication to one immediate batch,
at most one batch per 0.1 seconds, 64 lifetime batches, one latest-value
coalescing slot, and at most four current server-derived recipients per batch.
It retains no Player as roster or snapshot state and performs no retry.

Ready failures expose only the existing allowlisted public codes:
`INVALID_PAYLOAD`, `RATE_LIMITED`, `STALE_REQUEST`, `DUPLICATE_REQUEST`,
`NOT_AUTHORIZED`, `UNAVAILABLE`, or `INTERNAL_ERROR`. Only
`INVALID_PAYLOAD` may carry the dispatcher's canonical validation path. No
public error or log includes a UserId, Player, request payload, deadline input,
map reference, caught error, or internal roster object.

The client connects the `MatchSnapshot` listener and both response listeners
before its initial `GetMatchSnapshot` fire. The first valid snapshot locks the
controller to one MatchId. Only strictly greater revisions for that identity
mutate the view model; equal revisions terminalize event/response races without
rolling back state, and lower or foreign snapshots are ignored. The controller
sends one initial Get and at most one lifetime recovery Get. It clears or
cancels owned Pending correlation on malformed terminal traffic, state exit,
fire failure, and cleanup. Ready is marked locally Pending before `FireServer`,
but every authorization and transition remains server-owned.

The Match server composition is created only after place-role and complete
configuration validation. It registers `NetworkRegistry`, binds the two inbound
contracts and one outbound sender while the network is still Registering, then
registers `MatchLifecycle` with `dependencies = { "NetworkRegistry" }`.
Network therefore initializes first and shuts down last. Phase 08 and its
four-client Studio, consolidated-review, and complete-local-gate evidence pass.
The enemy extension below does not change this ready protocol.

## Phase 09 enemy protocol (historical current-at-completion extension)

Phase 09 adds exactly two production definitions under the same reliable Match
registry:

| Endpoint | Direction/kind | Exact payload | Response |
| --- | --- | --- | --- |
| `GetEnemySnapshot` | client-to-server Request | exact empty record `{}` | required bounded snapshot receipt |
| `EnemyReplication` | server-to-client Event | strict tagged enemy message | none |

At Phase 09 completion, `GetEnemySnapshot` was the third production
request-rate binding:
capacity `2`, refill `0.25` per second. The service independently accepts at most
two requests per actual Player connection through a weak-key counter cleared by
one service-level `PlayerRemoving` connection. The dispatcher still supplies the
engine-authenticated Player, exact envelope/payload validation, rate limiting,
non-yielding protected authorization/handling, origin-only response, and
privacy-safe errors. The empty request cannot select an enemy, lane, transform,
state, time, health, speed, transition, or recipient.

`EnemyReplication` carries only `SpawnBatch`, `CorrectionBatch`,
`StateChangeBatch`, `DespawnBatch`, `SnapshotBegin`, `SnapshotChunk`, or
`SnapshotEnd`. Enemy epoch, delta sequence, enemy revision, snapshot ID, and
snapshot base sequence are separate bounded domains; none reuses
`MatchStateMachine.revision`. Delta and chunk arrays contain at most eight
entries, snapshots at most 128 entries/16 chunks, and a client buffers at most
32 gap messages. The publisher emits at most 12 reliable messages per 0.1-second
flush opportunity, coalesces corrections, reserves terminal capacity, and
preserves deterministic causal ordering. Complete limits and recovery races are
specified in `docs/ENEMY_SIMULATION.md`. In particular, a snapshot-covered
active ID consumes its later queued contiguous spawn sequence idempotently,
merging only a newer revision; tombstoned or seen-inactive IDs remain terminal.

Every enemy state entry is self-contained, Instance-free, and validated for
finite/ranged identity, health, progress, segment, time, speed, positions, and
canonical route orientation. Position remains within `1e-6` of the authenticated
route sample. The reliable Studio wire changed diagonal CFrame rotation
components by at most `0.00003069639205932617`; validation therefore permits an
explicit `1e-4` rotation-component transport tolerance, rechecks the tangent,
and replaces accepted wire CFrames with the canonical route CFrame. Excessive
position/rotation drift and wrong tangents fail before client mutation.

The server composition registers `EnemySimulation` after `MatchLifecycle` and
`NetworkRegistry`; reverse shutdown disables simulation/publication and clears
enemy queues/store before the map loader and remote tree. The client registers
`EnemyController` after `MatchReadyController`; reverse shutdown stops its one
render connection/listeners and destroys placeholder visuals first. At that
checkpoint Phase 09 had added no client-to-server spawn/movement endpoint,
unreliable transport, generic bus, base-health behavior, or Phase 11 scheduler.
Phase 10's separate base extension follows.

## Phase 10 base protocol (current)

Phase 10 adds exactly two definitions beneath the same reliable Match registry:

| Endpoint | Direction/kind | Exact payload | Response |
| --- | --- | --- | --- |
| `GetBaseSnapshot` | client-to-server Request | exact empty record `{}` | required bounded full `BaseSnapshot` |
| `BaseReplication` | server-to-client Event | strict tagged full-state/feedback message | none |

`GetBaseSnapshot` has exact token-bucket capacity `2` and refill `0.25` per
second. The dispatcher still derives the actual Player from `OnServerEvent`,
validates the exact request and response, runs the handler synchronously, and
responds only to that origin. The empty payload cannot select health, damage,
enemy, difficulty, map, marker, revision, recipient, result, defeat, or
transition data.

Every base snapshot contains the authenticated MatchId and enemy epoch, map and
difficulty IDs, detached base position, independent positive `baseRevision`,
`Active`/`Defeated`/`Faulted` status, safe-integer current/maximum health, the
exact low-health boolean, and ordered server timestamps. `baseRevision` is not
the Match state-machine revision or enemy replication sequence. The
`BaseReplication` union is either `State { snapshot }` or
`Damage { snapshot, appliedDamage, leakCount, lowHealthCrossed }`; every message
contains a full snapshot sufficient to converge independently. Zero damage emits
no event. One enemy simulation pass coalesces all changing leaks into at most one
event, with clamped applied damage and a bounded leak count.

The publisher has one latest-state slot and one bounded feedback aggregate, no
retry queue, and no delivery ledger. It validates and UserId-sorts at most four
live authenticated recipients and attempts each send once. A sender failure is
isolated; a later event or direct snapshot recovers state. The client registers
the BaseReplication listener before requesting a snapshot, locks to the first
valid MatchId/epoch, accepts only a newer base revision, and treats equal/lower,
foreign, malformed, hostile, or out-of-order traffic as non-mutating. Studio's
active-session delayed-bootstrap fallback has its own one-shot bounded recovery
allowance after the normal bounded bootstrap attempts; it creates no unbounded
retry loop.

The current server composition registers BaseRuntime between MatchLifecycle and
EnemySimulation; the current client composition registers BaseController
between MatchReadyController and EnemyController. Reverse shutdown clears enemy
traffic first, then base response/event state and presentation, then Match/map,
and destroys the one network root last. There is no `RemoteFunction`, unreliable
transport, generic bus, or client-to-server base mutation.

## Payload-validation architecture decision

This Packet 06.2 decision was recorded on 2026-08-26 before payload-validator
source changes. One shared, authenticated, frozen schema API now composes every
future remote payload boundary. It reuses `Result`, `Validation.Issue`, and the
existing typed `Ids` validators; it does not introduce a second result or issue
shape and contains no gameplay schema.

The constructor surface is fixed: `string(maximumBytes, minimumBytes?)`,
`enum(values)`, `id(kind)`, `number(minimum, maximum)`,
`integer(minimum, maximum)`, `boolean()`,
`array(itemValidator, maximumItems, minimumItems?)`, `record(fields)`,
`optional(validator)`, `union(branches)`, `vector2()`, `vector3()`, `cframe()`,
and `instance(policy)`. Instance policies come only from
`instancePolicy(className, ancestor, allowSubclasses?)`.
`schema(validator, limits?)` compiles an authenticated root, while
`schema:validate(value)` or
`validate(schema, value)` returns the established frozen `Result`. Weak-key
provenance authenticates validators, schemas, and Instance policies; copied or
lookalike tables fail closed.

Every validation starts at the fixed public path `payload` and owns one shared
validation-work/node budget. Optional and union composition cannot reset that
budget: every speculative union branch and nested union attempt consumes it,
even though branch-local seen-table state remains isolated for correct matching.
Technical ceilings are depth 8, 512 work nodes, 64 fields in one
record, 128 array items, 1,024 bytes in one string, 128 enum values, and eight
union branches. A trusted remote schema may choose a narrower bound but never a
wider one. Limits are technical containment, not authorization or gameplay
policy.

Payload tables must be plain and metatable-free. Traversal uses `next`, `rawget`,
and `rawlen`; it never uses attacker-controlled indexing, length, iteration, or
string conversion. Cycles and repeated table references are rejected. Record
fields are validated in canonical sorted name order, arrays in ascending index
order, and union branches in authored order. A bounded union must have exactly
one successful branch; zero matches and ambiguous multiple matches fail closed.
All accepted table graphs are detached, owned, and deeply frozen.

Strings and enumerations are exact and non-coercing. The generic string
validator intentionally treats strings as opaque bounded bytes, so embedded NUL
or invalid UTF-8 is not itself a failure; any future human-text contract must
layer explicit UTF-8 and semantic rules over this byte boundary. Numeric
validators reject NaN and both infinities before integer/range checks.
`Vector2` and `Vector3` fail at the exact `X`, `Y`, or `Z` component path;
`CFrame` checks position components `X`, `Y`, `Z` and rotation components `R00`
through `R22`. Optional values accept only an actual `nil`. IDs delegate to
their exact existing family validator and retain only its allowlisted cause
code.

An Instance validator without a policy rejects every Instance. An explicit
trusted policy must bind a class, an allowed ancestor, and actual server
execution context; exact class matching is the default, while any subclass rule
must be explicit. Production acceptance additionally requires a live running
server context; Studio Edit mode and clients fail closed. The payload may never
select the class, ancestor, context, or Instance path. The headless engine seam
is gated by the exact isolated non-replicated Test-project structure and is
absent from the production client API.

## Server rate-limiting architecture decision

This Packet 06.3 decision was recorded on 2026-08-26 before rate-limiter source
changes. The existing `NetworkRegistry` lifecycle service remains the sole
production network owner. The server-only limiter is owned as a child of its
existing `Cleanup` container; no second service, independent shutdown hook,
shared/client limiter, punishment system, or analytics sink is added.

One authenticated frozen policy is required for every definition whose fixed
registry direction is `ClientToServer`, including definitions inactive in the
current place role. Policies for unknown or `ServerToClient` definitions,
duplicates, malformed tables, and missing inbound definitions fail construction.
The canonical policy set follows registry order and filters an active role view
without accepting a runtime action string. At the Packet 06.3 checkpoint, the
server-only production policy list and registry were empty. Phase 08 later added
the two inbound definitions and their explicit policies together, as recorded
in the current extension above; that paired-registration rule remains
mandatory.

Each explicitly selected default policy starts with capacity 4, refill 2 tokens
per second, and fixed cost 1. A missing policy never receives an implicit
default. Custom capacity must be a safe integer from 1 through 100; refill must
be finite from 0.01 through 100 tokens per second. These are technical ceilings,
not recommendations to grant high throughput. Policy creation, sets, decisions,
and diagnostic summaries are detached and frozen.

Runtime state is one lazy token bucket per actual connected engine `Player`
Instance and captured canonical registry-definition identity. The API accepts no
payload, UserId, name, client timestamp, arbitrary action, or path. Unknown,
inactive, wrong-direction, counterfeit, departing-player, unavailable-state,
and invalid-clock decisions fail closed before allocating a bucket. State is
bounded by connected Players multiplied by at most 128 fixed definitions.

The injected clock has a server-local monotonic contract; production supplies
`os.clock()` for the same high-precision duration behavior already used by fixed
client lookup. One protected sample is taken per decision. It must be a finite,
nonnegative number no earlier than the last accepted sample across the whole
limiter. A thrown, wrong-type, non-finite, or backwards sample rejects without
bucket, aggregate, or clock-state mutation, and a later valid sample can recover.
Elapsed-time multiplication is avoided once the remaining capacity is known to
be filled, so even a huge finite forward jump only saturates at capacity. There
is no epsilon-based early allowance.

The limiter owns a `PlayerRemoving` connection and removes every bucket for the
exact departing Player identity; lifecycle cleanup remains the independent
whole-state guarantee. The parent registers its remote root first, the limiter
child second, and inbound listeners last. Existing LIFO cleanup therefore
disconnects inbound listeners, disconnects `PlayerRemoving`, clears limiter and
aggregate state, and destroys the owned tree in that order. Cleanup failure
isolation remains the established `Cleanup` contract.

Rate-limit rejections feed one global O(1) abuse aggregate, never a per-player or
per-request log. The first rejection may emit one static warning; later warnings
are globally limited to one per ten-second window across every endpoint. The
pending count saturates at 4,096 and the endpoint is either one fixed canonical
registry name or the static token `<multiple>`. The structured log adds only
allowlisted finite `rateLimitRejectionCount` and `rateLimitWindowSeconds` fields
beside the existing fixed endpoint and code. Reporter failure is contained and
still advances the cadence, so it cannot change a decision or retry-flood output.
The rate-limit aggregate retains or logs no Player identity, request ID, payload,
client-supplied timestamp, caught error, or trace. Separate bounded limiter
enforcement state keys buckets by actual `Player` and canonical definition
identity and retains server-local token balances, refill times, cadence, and
aggregate counts. `PlayerRemoving` removes that Player's keys, lifecycle cleanup
clears all remaining state, and raw enforcement values are never logged. Counts
summarize delivered server events only; Roblox's approximate transport throttle
is not forensic or security evidence.

Packet 06.3 creates and tests the limiter but does not wrap the current raw test
handlers. Packet 06.4 makes its dispatcher the sole limiter caller after
cheap envelope checks and before authorization, payload validation, or handler
execution. Invoking the limiter earlier would violate the recorded pipeline;
invoking it from an optional feature handler would leave a bypass.

## Request, correlation, and public-error architecture decision

This Packet 06.4 decision was recorded on 2026-08-26 before request-protocol or
dispatcher source changes. The implementation uses three narrow modules:
shared pure `RequestProtocol`, server-only `ServerRequestDispatcher`, and
client-only `ClientRequestTracker`. `NetworkRegistry` remains the only lifecycle
service. The raw handler-binding seam is removed so a client-to-server
endpoint cannot bypass its authenticated schema, rate policy, authorization,
correlation, protected handler, or response translation.

A Request wire value is the exact plain record `{ requestId, payload }`. A
client-to-server Event wire value is the exact plain record `{ payload }` and
has no request ID. A successful response is exactly
`{ requestId, state = "Success", payload }`; a rejected response is exactly
`{ requestId, state = "Rejected", error }`. Endpoint, action, Player, UserId,
permission, ownership, role, timestamp, target, service, handler, and path never
appear in these envelopes. Top-level records are checked with raw traversal and
without walking `payload`; metatables, missing or extra fields, multiple remote
arguments, and wrong value types fail the cheap boundary.

The internal request-ID type is authenticated and frozen; its wire form is a
case-sensitive string from 8 through 48 ASCII bytes. The first byte is an ASCII
letter or digit and later bytes may additionally use `_` or `-`, so the default
client-generated GUID form is accepted without treating its entropy as a
security property. Empty, short, oversized, non-ASCII, malformed, existing
domain-ID objects, and counterfeit request IDs are rejected without coercion.
Malformed envelopes or IDs receive no response and enter no ledger because the
server has no trusted correlation target to echo; they contribute only to one
bounded aggregate signal.

The public rejection-code allowlist is exactly `RATE_LIMITED`,
`NOT_AUTHORIZED`, `INVALID_PAYLOAD`, `DUPLICATE_REQUEST`, `STALE_REQUEST`,
`UNAVAILABLE`, and `INTERNAL_ERROR`. There is no public message, cause, caught
error, actual type, stack, or arbitrary metadata map. The sole optional metadata
shape is exact `{ validationPath }` for `INVALID_PAYLOAD`. The production
dispatcher supplies it only from strict payload-validator output. The shared
constructor accepts the structural `Validation.Issue` type rather than proving
the issue's provenance, so future server code must not synthesize metadata; it
revalidates the canonical developer-authored path and omits paths over 256
bytes. Public errors and server handler outcomes use local provenance and
freezing; after RemoteEvent copying, the client revalidates the exact wire record
rather than trusting provenance.

Correlation state is scoped to the actual engine `Player` and then globally by
request-ID string across every fixed request endpoint. Each connected Player is
bounded to 32 in-flight IDs and the most recent 128 completed IDs in a fixed-size
count-evicted ring. There is no client timestamp, TTL, unbounded queue, or
payload retention. A new ID is reserved before authorization or handler work.
Every terminal success or rejection, including an admitted rate-limit rejection,
moves it to completed history before a response send. A repeated in-flight ID is
a duplicate and is dropped without a second response, because a duplicate
rejection could race and incorrectly terminate the original client pending
request. A retained completed ID is stale. A response-required replay always
receives `STALE_REQUEST` on the incoming endpoint's captured response leaf; a
no-response Request sends nothing. The same ID on another endpoint is still a
duplicate or stale replay. Once count eviction removes an ID, it is first-seen
again; correlation never promises idempotency or exactly-once effects.

The server contract APIs are separate fixed request and event registrations.
They accept only a captured canonical active registry definition, authenticated
payload/response schemas with response presence matching the registry, one
context-only authorizer, and one protected handler. The frozen server context
contains only the engine `Player`, canonical definition identity, and resolved
server role. The authorizer sees no raw or canonical client payload. A future
operation whose authorization cannot be derived without a canonical payload may
not bypass this order; it requires a separately reviewed post-validation,
pre-handler guard before that endpoint can ship.
Every context-only authorizer must be side-effect-free. Its deny and throw paths
must pass a zero-feature-mutation sentinel before registration approval.

The complete client-to-server Request pipeline is fixed as:

1. a listener closure supplies the active canonical definition and engine
   `Player`, then forwards the complete remote argument list;
2. the dispatcher verifies exactly one argument and runs cheap exact envelope
   and request-ID checks without traversing payload;
3. the server-authoritative per-Player/per-endpoint limiter consumes one token;
4. the bounded per-Player correlation ledger classifies, caps, and reserves the
   global request ID;
5. protected authorization uses only server-derived context;
6. the contract's strict payload schema produces canonical frozen table
   containers; an explicitly approved Instance retains its authenticated server
   identity rather than being copied;
7. the protected handler returns an authenticated success or public rejection;
8. success output is validated by the fixed response schema, while every
   failure is translated to the allowlist;
9. the ledger records completion before any send; and
10. a protected sender calls only `FireClient(originatingPlayer, envelope)` on
    the response leaf captured during server-owned tree creation.

After every external or protected boundary, the dispatcher rechecks lifecycle,
ledger, and actual-Player liveness before continuing.

Events use steps 1 through 3 and 5 through 7, with their exact event envelope and
no ledger or response. A no-response Request still uses its envelope and ledger
but never sends a response. A rate-limited delivery still reaches correlation
classification, so a new syntactically valid ID can be completed as rejected and
cannot later execute while retained. Pending duplicates consume a limiter token
but never execute or race the original response.

The dispatcher never invokes the feature handler after a pre-handler rejection.
Injected authorization code is itself capable of external mutation, so the
side-effect-free authorizer contract and its deny/throw mutation sentinel are
mandatory. Protected handler failure becomes only `INTERNAL_ERROR`;
invalid/counterfeit outcomes and invalid success payloads do the same. A generic
dispatcher cannot roll back arbitrary authorizer or handler code that mutates
and then throws, so every future stateful handler must perform all fallible work
before its atomic commit and must prove that behavior with a mutation sentinel
before registration approval.

### Non-yielding protected-callback and validation-metadata decision

This decision was recorded on 2026-08-26 during the Packet 06.5 independent
protocol-security review, before the corresponding source change. Luau permits
the target of `pcall` to yield, which also yields the calling coroutine. A plain
protected call therefore does not bound the lifetime of a remote listener: a
yielding Event handler could accumulate suspended work even when admission is
rate-limited.

Every endpoint authorizer and handler must instead complete synchronously. The
dispatcher starts each protected feature callback in a fresh coroutine, resumes
it exactly once, accepts a result only when the coroutine is dead, and closes a
directly suspended Luau coroutine immediately. A throw or detected suspension
follows the same private failure translation: authorization fails closed and a
handler becomes
`INTERNAL_ERROR` for a response-required Request or a bounded
`HANDLER_FAILED` aggregate for an Event. No yielded value or caught error is
retained, returned, or logged. This mechanism does not claim to cancel an
engine-owned waiter, scheduled callback, connection, or child task; callback
code therefore may not wait, yield, spawn, defer, schedule, connect, or otherwise
create unowned asynchronous work. The endpoint review must reject those APIs;
the headless suspension test proves only direct Luau suspension and closure. A later
feature that truly needs an asynchronous operation requires a separately
reviewed lifecycle-owned job protocol with explicit global and per-player
bounds, cancellation, deadlines, and mutation semantics; it may not weaken this
dispatcher implicitly.

Only the dispatcher's strict payload-validation failure path may attach public
`validationPath` metadata. Feature handlers may construct allowlisted public
codes, but their rejected outcomes must be metadata-free. This keeps the
structural shared error constructor useful for wire validation while preventing
a handler from reflecting a client-influenced string as diagnostic metadata.

The client tracker registers only canonical Request definitions and
authenticated schemas. It generates and builds every Request envelope, including
no-response Requests, but allocates Pending state and registers a response
schema/handling path only when the registry requires a response. It holds at
most 32 global Pending states and 128 recent terminal IDs, generates bounded IDs
with collision checks, and exposes frozen `Pending`, `Success`, and `Rejected`
records without UI. The tracker does not connect a `RemoteEvent`; future
fixed-endpoint client code
must own that listener through Cleanup and supply its captured definition
identity to the tracker. An unknown or
completed ID is stale, while a live ID arriving through another endpoint is
mismatched. Malformed envelopes, public errors, or success payloads and
mismatched/stale responses do not mutate the valid pending entry. Explicit
cancel and whole-tracker clear operations bound lost-response state without a
client timestamp.

The dispatcher owns a second `PlayerRemoving` connection for correlation state;
the limiter keeps its already reviewed independent connection. Parent ownership
order is root, limiter child, dispatcher child, then endpoint listeners. LIFO
shutdown therefore disconnects endpoint listeners, disconnects and clears the
dispatcher, disconnects and clears the limiter, and destroys the exact root.
Malformed, authorization, validation, handler, outcome, and response-send
signals use one global O(1), saturating, interval-limited aggregate. It can expose
only canonical endpoint or `<multiple>`, a static code, bounded count, and fixed
window; never request ID, Player identity, payload, response, public metadata,
or caught error. Reporter and observation-clock failures cannot change dispatch
results or flood output.

## Direction and dispatch rules

A physical `RemoteEvent` is engine-bidirectional, so the security boundary is
the server's fixed listener and authenticated-contract binding. The server
installs no inbound listener for a server-to-client definition and rejects a
contract with the wrong direction. `ClientRemoteLookup` returns captured raw
`RemoteEvent` leaves; any narrower client wrapper is an ergonomic API, not an
authority boundary. A client firing a server-to-client endpoint is anomalous
but can never reach a feature handler. A private response is sent only with
`FireClient(originatingPlayer)`; there is no caller-selected target or relay
API.

There is no action field. There is no service name, handler name, path, Instance
path, module name, or arbitrary operation selector in an envelope. One physical
endpoint maps to one reviewed contract and one handler binding. Duplicate
binding is rejected.

The detailed ten-step Request and seven-step Event pipelines are fixed by the
Packet 06.4 decision above. No rejected pre-handler request may invoke feature
mutation. Handler failures remain server-side and become one static public
failure code. Raw errors, traces, payloads, rejected values, catalogs, private
state, and secrets never enter a response or log.

## Correlation decision

A client-generated request ID is the bounded typed correlation value described
above only. It is not identity, authorization, ownership, freshness proof,
transaction identity, or idempotency proof.

An in-flight repeated ID is a silently dropped duplicate. A completed repeated
ID is a stale replay while it remains in the fixed 128-entry server ring. A
first-seen ID cannot be classified as stale from a client timestamp, so request
envelopes contain no client time. Once count eviction removes history, a server
cannot infer earlier use; future value-granting systems must add their own
authoritative idempotency records where required.

On the client, a response must match both a live pending request ID and its fixed
endpoint. A response with no live pending entry is stale; one using the right ID
for another endpoint is mismatched. Neither can mutate pending state for the
valid request.

## Lifecycle and cleanup ownership

One common server network service is registered before lifecycle initialization.
It owns the server-created root, limiter child, dispatcher child, two separate
Player-removal connections, and every endpoint-listener connection through
nested `Cleanup` containers. The parent registers the root first, limiter child
second, dispatcher child third, and inbound listeners last. LIFO cleanup
therefore disconnects endpoint listeners first, then the dispatcher disconnects
`PlayerRemoving` and clears correlation/aggregate state, then the limiter does
the same for bucket state, and finally the parent destroys the remote tree.

Initialization preflights conflicts before publishing the tree and rolls back
its own partial work if any step fails. Shutdown clears bounded per-player state,
disconnects listeners, and destroys the exact owned tree through the existing
reverse lifecycle and graceful-shutdown path. No independent `BindToClose` hook
is added.

Lobby and the combined Development composition retain the common network-only
behavior described by the historical Phase 06 records. In Match, the server
runner resolves `NetworkRegistry -> MatchLifecycle -> BaseRuntime ->
EnemySimulation`; the client resolves `MatchReadyController -> BaseController ->
EnemyController`. Client lookup and request tracking remain fixed utilities
owned and cleared by their controllers rather than becoming separate lifecycle
services.

## Logging boundary

Networking extends the existing closed structured logger only with reviewed
aggregate fields. Logs may contain a fixed registry endpoint name, stable code,
bounded count, and bounded interval. They never contain a player payload,
request envelope, request ID, UserId, display name, player-authored string,
Instance path supplied by a client, raw exception, or trace.

Rate-limit and malformed-input signals are aggregated and interval-limited. The
server does not log every request or every rejection, and Phase 06 adds no ban,
punishment, persistence, analytics delivery, or external sink.

## Packet 06.5 adversarial-test and Studio-fixture decision

This decision was recorded on 2026-08-26 before Packet 06.5 test or harness
source was added. Packet 06.5 changes no production endpoint. Its final
independent review added only the non-yielding callback and validation-metadata
hardening recorded above; no generic dispatch or feature architecture was
introduced. The deterministic `NetworkSecurity.spec.luau` suite reuses the
existing test-only registry definitions and composes the real registry owner,
limiter, dispatcher, protocol, payload validation, fixed client lookup, and
client tracker through captured test adapters. Its nine integrated cases
consolidate hostile payloads, forged authority fields, replay/spam, topology
misuse, failure translation, disconnect/cleanup, privacy, and mutation-sentinel
behavior while the existing focused suites remain the exhaustive boundary
evidence.

Actual `RemoteEvent` transport, engine-supplied originating `Player`,
`FireClient` recipient isolation, replication/marshalling, and live connection
teardown are Roblox-engine behaviors rather than Lune claims. Reusable Studio
harness source therefore lives only under unmapped `tests/studio/`. The manual
unsaved regression injects those exact tracked sources only into the live
Server & Clients DataModels: one runtime server Script and one runtime
LocalScript per client. It never creates or edits an Edit-mode instance. The
server creates a distinct `ATDPhase06StudioFixture` root and must never adopt,
rename, remove, or second-initialize the production `ATDNetwork` root. Ending
the local session discards the runtime scripts; the fixture owns exact cleanup.
Both places remain in Edit mode and are never saved, published, or given an
external-service permission.

The mandatory endpoint approval boundary is the standalone
`REMOTE_SECURITY_CHECKLIST.md`. It governs the procedure below; no unexplained
omission may permit a future production remote to ship.

## Future endpoint registration procedure

No production feature remote may be added without one completed
`REMOTE_SECURITY_CHECKLIST.md` approval record. A later approved feature change
must:

1. add exactly one fixed definition to `ProductionRemotes.luau`, using the
   canonical name grammar and the narrowest Lobby/Match role set;
2. select only an allowed direction, `ReliableRemoteEvent` transport, Request or
   Event semantic, and explicit response behavior;
3. for a client-to-server definition, add one strict inbound payload schema,
   one explicit rate policy, one server-derived authorization function, one
   synchronous protected handler, and allowlisted public response behavior;
   for a server-to-client Event, add one strict outbound schema, server-derived
   recipient/audience rules, and bounded emission/fan-out policy instead;
4. bind an inbound handler by its registry constant before lifecycle
   initialization, or capture an outbound leaf only through server ownership;
   client ergonomics must expose only the definition-shaped operation and are
   never treated as the direction security boundary;
5. add positive, boundary, adversarial, role-isolation, duplicate-binding,
   cleanup, privacy, and zero-partial-mutation tests; and
6. prove the test fixture remains test-only and all production project source
   maps, role isolation, lifecycle ownership, and build exclusions still pass.

The registry module, root/version names, client lookup, or runtime binder must
not be bypassed by a second folder, generic action bus, client-selected path, or
ad hoc remote creation.

## Packet 06.1 completion evidence

At Packet 06.1 completion, the canonical headless run discovered ten suites and
passed all 106 cases. Of those, 18 cases cover registry structure, limits,
canonical order,
immutability, provenance, malformed/conflicting definitions, hostile
metatables, and privacy; 12 cases cover parent-last publication, exact role
trees, handler completeness and uniqueness, conflict preservation, re-entry,
rollback, LIFO cleanup, every endpoint leaf shape, production seam exclusion,
and bounded client lookup. The fixtures exist only under `tests/`.

The Packet 06.1 four-project structural verifier reported 34 ModuleScripts, one
Script, and one LocalScript in each production build. The Test build's production
source subset contains 31 shared ModuleScripts plus exactly the two explicitly
mapped production networking runtime modules; 20 additional ModuleScripts are
test-owned specs, fixtures, support, or negative controls. Test contains zero
runnable scripts. Tests and test-only fixtures remain absent from Default,
Lobby, and Match; Lobby contains no Match source and Match contains no Lobby
source. The targeted architecture/security review resolved every normal finding
and finished with no unresolved P0, P1, P2, or P3 finding. Packet 06.1 is
complete. Packets 06.2–06.5, the fresh exit audit, and its clean workflow
evidence have since passed; Phase 06 is complete and Gate A passed.

## Packet 06.2 completion evidence

At Packet 06.2 completion, the canonical headless run discovered eleven suites
and passed all 128 cases in deterministic path and declaration order.
`PayloadValidation.spec.luau`
contributes 22 focused cases covering authenticated schema provenance; exact
string, enum, ID, number, integer, boolean, array, record, optional, and union
boundaries; exact cap and cap-plus-one behavior; shared nested-union work
budgeting; canonical detached frozen table containers while explicitly approved
Instances retain authenticated identity; stable paths; cycles and repeated
references; hostile metatables and keys without metamethod invocation; private
diagnostic containment; finite `Vector2`, `Vector3`, and all twelve `CFrame`
components; and explicit exact/subclass Instance class and ancestry policy
behind the structurally gated server-context boundary.

The restricted Lune ModuleScript environment exposes only the project-required
Roblox datatype constructors `Vector2`, `Vector3`, and `CFrame` in addition to
the existing `Instance` surface; it still exposes no filesystem, network,
process, authentication, or secret API. The Instance server-context fallback is
reachable only through the exact non-replicated Test-project module/support
structure.

At the Packet 06.2 checkpoint, headless foreign datatypes proved validator
behavior but could not prove Roblox's wire serialization of non-finite datatype
components or a real client's execution context. Packet 06.5 subsequently ran
the required unsaved Studio regression: it sent non-finite `Vector2`, `Vector3`,
and `CFrame` cases through the fixed test boundary, proved rejection before
mutation, and proved that the explicit Instance policy accepts only on the
running server and rejects from a client. No place was saved or published, and
no external service was enabled.

At that checkpoint, the four-project verifier reported 35 ModuleScripts, one
Script, and one LocalScript in each production build: 32 shared modules, the two
server-only common modules, and the one client-only common module. Test contains the same
32 shared modules, exactly the two explicitly mapped common networking runtime
modules, 21 test-owned ModuleScripts, and zero runnable scripts, for 55
ModuleScripts total. At that checkpoint, all 37 production Lua source containers
matched their fixed path, class, authoritative file, and source content. Tests remain absent from
Default, Lobby, and Match; Lobby contains no Match source and Match contains no
Lobby source. Lasting production endpoints and gameplay catalogs remain empty.

Packet 06.2 completed with this evidence; Packet 06.3 has since completed.

## Packet 06.3 completion evidence

At the Packet 06.3 checkpoint, the canonical headless run discovered 12 suites
and passed all 145 cases in deterministic path and declaration order.
`ServerRateLimiter.spec.luau`
contributes 17 focused cases for exact policy validation, complete global
client-to-server policy coverage, burst/refill boundaries, independent
Player/endpoint buckets, finite monotonic clock failures and recovery,
Player-removal and shutdown cleanup, bounded state, aggregate warning cadence,
reporter failure isolation, and privacy. `RemoteRuntime.spec.luau` retains its
12 ownership/lookup cases while also proving the limiter child participates in
the parent's exact LIFO lifecycle order.

The four-project verifier reports 37 ModuleScripts, one Script, and one
LocalScript in each production build, for 39 exact production Lua source
containers. Test contains 32 shared modules, exactly four explicitly mapped
common networking modules, 22 test-owned ModuleScripts, and zero runnable
scripts, for 58 ModuleScripts total. Tests remain absent from Default, Lobby,
and Match; Lobby contains no Match source and Match contains no Lobby source.
The lasting production registry and frozen production rate-policy list are both
empty, and no gameplay definition, punishment, persistence, analytics, external
service, or Phase 07 source was added.

Packet 06.3 is complete; Packet 06.4 and the remainder of Phase 06 have since
completed. Gate A passed, and Phase 07/gameplay work has not begun.

## Packet 06.4 completion evidence

`RequestProtocol.luau` implements the exact Request, Event, Success, and
Rejected wire records, authenticated 8–48-byte request IDs, the fixed seven-code
public error allowlist, validation-path-only bounded metadata, and frozen
Pending/Success/Rejected states. Its cheap parsers use raw exact-record
traversal without walking payloads. `ClientRequestTracker.luau` requires
canonical registered Request definitions and authenticated request/response
schemas, generates IDs with bounded collision retries, holds at most 32 global
Pending records plus a 128-ID terminal ring, and rejects malformed, stale, or
mismatched responses without changing the valid pending entry.

`ServerRequestDispatcher.luau` is the sole post-envelope limiter caller. It
uses one per-Player global request-ID ledger across endpoints, server-derived
frozen context, context-only authorization, strict payload and response schemas,
protected handler outcomes, allowlisted translation, and the response leaf and
originating Player captured by `ServerRemoteRegistry`. Raw handler registration
is gone; lifecycle initialization fails unless every active client-to-server
definition has exactly one secure Request or Event contract. Valid requests in
the initialized-but-not-started publication window cannot execute a handler,
and state/ledger/player checks stop cleanup re-entry after limiter, reporter,
authorization, validation, or handler calls.

The canonical headless run discovers 15 suites and passes all 189 cases in
deterministic path and declaration order. The three new focused suites contribute
13 protocol, 12 client-tracker, and 19 dispatcher cases; the existing 12-case
runtime suite now proves secure contract binding, exact captured response routing,
place-role isolation, rollback, and listener → dispatcher → limiter → root LIFO
cleanup. The four-project verifier reports 40 ModuleScripts, one Script, and one
LocalScript in Default, Lobby, and Match. Test contains 33 shared modules,
exactly six explicitly mapped common networking modules, 25 test-owned modules,
and zero runnable scripts, for 64 ModuleScripts total. Tests remain absent from
production projects and Lobby/Match source isolation remains intact.

The lasting production registry and production rate-policy list remain frozen
and empty. No gameplay definition, generic bus, `RemoteFunction`, punishment,
persistence, external service, Phase 07 source, place save, or publication was
added. Packet 06.4 is complete; Packet 06.5, the fresh exit audit, and its clean
workflow evidence have since passed. Phase 06 is complete and Gate A passed.

## Packet 06.5 completion evidence

The canonical headless run discovers 16 suites and passes all 200 cases in
deterministic path and declaration order. `NetworkSecurity.spec.luau` adds nine
integrated cases covering cheap malformed-envelope rejection; hostile payload,
Instance, finite-number, depth, size, cycle, and metatable containment;
engine-origin-shaped authorization with forged authority rejection; duplicate,
stale, cross-endpoint, and oversized IDs; independent burst limits; wrong
direction/kind/unknown topology and arbitrary-path attempts; contained Request
and Event handler failures; zero partial mutation; bounded privacy-safe
aggregates; Player removal; and lifecycle re-entry/shutdown cleanup.

`ServerRequestDispatcher.spec.luau` now contributes 21 focused cases. The two
review-driven additions prove that Request and Event authorizer/handler yields
are closed with no post-yield work or retained Pending state, and that handler
rejections cannot supply validation metadata. The dispatcher is the only
production source changed during Packet 06.5; definitions, policies,
bootstraps, mappings, and runnable entrypoints are unchanged.

The four-project verifier reports 40 ModuleScripts, one Script, and one
LocalScript in each production build. Test contains 33 shared modules, exactly
six mapped common networking modules, 26 test-owned modules, and zero runnable
scripts, for 65 ModuleScripts total. `tests/studio` is mapped into none of the
four projects. Production endpoints and policies remain empty, Lobby contains
no Match source, Match contains no Lobby source, and no other lasting production
source changed during Packet 06.5.

Three unsaved plain Lobby Play/Stop cycles and three unsaved plain Match cycles
passed with server service count one, client service count zero, one unique
empty production `ATDNetwork/v1` tree, and clean shutdown. The final exactly
two-client Match run passed real `RemoteEvent` transport, engine-supplied
origin, origin-only responses, forged-field rejection, non-finite Roblox
datatypes, default and explicit Instance policies, independent burst buckets,
real `LeaveTest()`/`PlayerRemoving`, per-player state removal, remaining-peer
service, and fixture cleanup. Its bounded terminals were:

```text
[ATD_PHASE06_STUDIO][PASS][context=client][case=completed][caseCount=10]
[ATD_PHASE06_STUDIO][PASS][context=server][caseCount=10][clientCount=2][cleanupState=Cleaned]
```

Post-pass inspection reported one Folder production root, one Folder `v1`, zero
endpoints, and zero fixture roots. Client and server log-history audits each
reported zero forbidden-value matches and zero error records. The runtime-only
scripts were discarded by ending the local session, both production places
were left in Edit mode, and no place was saved or published. Exact procedure
and evidence are in `NETWORK_SECURITY_STUDIO_REGRESSION.md`; the mandatory
future-remote gate is `REMOTE_SECURITY_CHECKLIST.md`. Packet 06.5 and the fresh
Phase 06/Gate A audit pass, including the exact clean workflow evidence. Phase
06 is complete and Gate A passed.

## Fresh Phase 06/Gate A audit evidence

The combined exit audit reran the exact pinned toolchain, formatting, Selene,
three byte-identical 200-case canonical runs, all six isolated failure controls,
and the complete four-project verifier. The verifier now also authenticates all
26 Test-owned ModuleScripts against an exact path/class/authoritative-source
allowlist; unlisted Test-owned source fails. Production remains 40
ModuleScripts, one Script, and one LocalScript per project, while Test remains
65 ModuleScripts with no runnable script.

The accepted fresh two-client Studio run used the exact tracked server SHA-256
`883bcdb665f54cb5adff9f935af90992cc5b71e5a486f7293a6f5a2f27bdec6a`
and client SHA-256
`8223e9e95dfb4caee94986da9f722917b68ec23ee5e7c7e1992d2173fc1ea290`.
It repeated the ten engine assertions, real disconnect and cleanup, remaining-
peer service, empty production topology, zero fixture residue, zero forbidden
log matches, and zero error records. Both places returned to Edit mode without
save or publication.

Exact combined evidence is in `PHASE_06_EXIT_AUDIT.md`. Audit-content commit
`7ada807586164c8ab0c940c749393c243d4fe9e3` passed genuine clean workflow run
`33022784985` with zero retained artifacts. Phase 06 is complete, Gate A passed,
and Phase 07 is next but has not begun. No gameplay endpoint or Phase 07 system
is approved or implemented by this audit.

## Phase 11 Wave protocol (current)

Phase 11 adds exactly three definitions beneath the existing reliable
`ATDNetwork/v1` Match registry:

- `GetWaveSnapshot`: client-to-server Request with exact payload `{}` and one
  bounded full `WaveSnapshot` response;
- `SubmitSkipVote`: client-to-server Request with exact payload
  `{ matchId, waveNumber }`, where engine request context supplies the Player and
  the server derives membership, time, threshold, and target state; and
- `WaveReplication`: server-to-client Event carrying a complete independently
  convergent `WaveSnapshot`.

The exact production token buckets are capacity `2`, refill `0.25` per second
for `GetWaveSnapshot`, and capacity `2`, refill `0.5` per second for
`SubmitSkipVote`. This brings the current catalog to ten reliable Match-only
definitions and six inbound policies. No `RemoteFunction`,
`UnreliableRemoteEvent`, generic bus, client-selected recipient, second root, or
Phase 12 endpoint was added.

`WaveController` connects `WaveReplication` before its first Get. It accepts only
validated matching full state ordered by `(MatchId, waveRevision)`. One skipped
episode arms one bounded Get; later events coalesce behind it, healing rearms the
budget for a later gap, and every semantic skip rejection forces one bounded Get
even if no gap was already recorded. A direct authenticated Get may replace a
locked Match generation; events cannot. Studio ordering tests injected stale,
duplicate, skipped, out-of-order, and delayed messages through the real
`WaveReplication:FireClient` sender path.

Each safe server pass queues at most one newest full Wave event. Sender false or
throw is contained per recipient and never rolls back server truth. A terminal
dependency fault retains the exact canonical `Faulted` snapshot for read-only
Get recovery until cleanup even when every terminal send fails; voting and all
other mutation remain closed. Only `DefeatClosed` uses the exact recipient set
captured during Phase 10 defeat preflight. Other states query live trusted
recipients synchronously, and the publisher caches no Player, UserId, or
recipient array.

## Phase 12 Tower network boundary

Phase 12 deliberately adds zero shared Tower protocol modules, zero client
Tower controller, and zero production remote or rate-policy definition. A
client cannot submit a TowerId, UnitId, RuntimeTowerId, CFrame, owner, slot,
level, target mode, investment, cooldown, Model, or capability. Temporary
loadouts are server-only snapshots; occupied-slot capabilities are opaque
weak-key-authenticated server objects; trusted transforms come only from tests
or the fixed Studio evidence boundary. Phase 13 preserves those rules through
the narrow placement contract below.

The Phase 12 structural and exact Studio checks both confirm the unchanged
network: ten reliable Match-only endpoint definitions, six client-request rate
policies, one `ATDNetwork/v1` root, sixteen resulting reliable RemoteEvent
instances, zero RemoteFunctions, zero UnreliableRemoteEvents, and no name or
source token for a tower mutation endpoint. Tower visual replication is normal
server-owned Instance replication, not a gameplay protocol or client authority.

## Phase 13 placement network boundary

Phase 13 adds exactly three reliable Match-only definitions:
`GetTowerPlacementQuery` and `SubmitTowerPlacement` are correlated C2S requests
with required origin-only responses, while `TowerPlacementRevision` is an S2C
event containing only MatchId and query revision. The two inbound policies are
respectively capacity/refill `4/1s` and `3/0.5s`. The resulting catalog is 13
endpoint definitions and eight inbound policies; no RemoteFunction,
UnreliableRemoteEvent, generic bus, client-selected recipient, or second
network root is introduced.

The existing authenticated MatchLifecycle sender emits the current placement
revision to the same recipient after each canonical `PreWave` or `WaveActive`
Match snapshot. That is the production initial-recovery source when a client's
startup query reached the server during `ReadyCheck`; committed placements then
broadcast the advanced revision. Neither path trusts a client revision, and the
Studio-only refresh trigger is not part of production recovery.

The query payload is exactly empty. The submit payload contains only MatchId,
observed query revision, temporary loadout revision, slot `1..5`, bounded
finite `Vector2` XZ, and bounded finite yaw. It cannot express owner, TowerId,
UnitId, RuntimeTowerId, Y/pitch/roll/CFrame, definition/model/cost/cap, target
mode, capability, or recipient. The dispatcher performs exact graph/schema,
rate, sender-context, replay/correlation, and privacy checks before the server
recomputes every placement rule. Full wire contracts and receipts are in
`docs/TOWER_PLACEMENT.md`.
