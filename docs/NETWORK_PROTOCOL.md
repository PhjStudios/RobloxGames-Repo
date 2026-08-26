# Network Protocol and Remote-Security Foundation

## Decision status

- Phase: 06 — Network Protocol and Remote-Security Foundation
- Architecture decision recorded: 2026-08-26, before Phase 06 source changes
- Primary-source research accessed: 2026-08-26
- Packet 06.1 status: complete — 2026-08-26
- Transport decision: fixed, reliable, asynchronous `RemoteEvent` endpoints
- Production feature endpoints: none; the lasting authenticated registry is empty
- `RemoteFunction`: prohibited unless a later recorded concrete need changes the
  decision
- Generic remote bus, client-selected action, service, handler, or path: prohibited
- Gameplay, persistence, external service, place save, or publication authorized:
  none

This is the authoritative Phase 06 network-boundary document. The decision
section was recorded before implementation. The sections below also record the
completed Packet 06.1 implementation and evidence. Phase 06 and Gate A remain
open until Packets 06.2–06.5 and the fresh exit audit pass.

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

### Primary sources

- [Remote events and callbacks](https://create.roblox.com/docs/scripting/events/remote)
- [`RemoteEvent.OnServerEvent`](https://create.roblox.com/docs/reference/engine/classes/RemoteEvent/OnServerEvent)
- [`RemoteFunction.InvokeClient` hazards](https://create.roblox.com/docs/reference/engine/classes/RemoteFunction/InvokeClient)
- [`UnreliableRemoteEvent.OnClientEvent`](https://create.roblox.com/docs/reference/engine/classes/UnreliableRemoteEvent/OnClientEvent)
- [Securing the client-server boundary](https://create.roblox.com/docs/scripting/security/client-server-boundary)
- [Security tactics and server authority](https://create.roblox.com/docs/scripting/security/security-tactics)
- [Server-side detection and directional remotes](https://create.roblox.com/docs/scripting/security/server-side-detection)
- [Replication and confidentiality](https://create.roblox.com/docs/scripting/security/access-control)
- [Replication ordering](https://create.roblox.com/docs/scripting/attributes#replication-order)
- [`Instance.WaitForChild`](https://create.roblox.com/docs/reference/engine/classes/Instance/WaitForChild)
- [Streaming and Instances sent remotely](https://create.roblox.com/docs/workspace/streaming/techniques#instances-sent-remotely)
- [Networking and replication performance](https://create.roblox.com/docs/performance-optimization/improve#networking-and-replication)

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

The lasting production registry remains empty until a later packet introduces a
concrete feature remote. Phase 06 tests use deterministic test-only definitions;
they never populate a gameplay catalog or production endpoint.

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
definition is unbound. The production registry is empty, so Packet 06.1
publishes only `ATDNetwork/v1` and binds no production request or event handler.

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

## Payload-validation architecture decision

This Packet 06.2 decision was recorded on 2026-08-26 before payload-validator
source changes. One shared, authenticated, frozen schema API will compose every
future remote payload boundary. It reuses `Result`, `Validation.Issue`, and the
existing typed `Ids` validators; it does not introduce a second result or issue
shape and contains no gameplay schema.

Every validation starts at the fixed public path `payload` and owns one traversal
budget. Technical ceilings are depth 8, 512 visited nodes, 64 fields in one
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

Strings and enumerations are exact and non-coercing. Numeric validators reject
NaN and both infinities before integer/range checks. `Vector2`, `Vector3`, and
all twelve `CFrame` components must be finite. Optional values accept only an
actual `nil`. IDs delegate to their exact existing family validator and retain
only its allowlisted cause code.

An Instance validator without a policy rejects every Instance. An explicit
trusted policy must bind a class, an allowed ancestor, and actual server
execution context; exact class matching is the default, while any subclass rule
must be explicit. The payload may never select the class, ancestor, context, or
Instance path. Headless context injection, if needed for engine-adapter tests,
must exist only behind the isolated non-replicated Test-project structure and
must be absent from the production client API.

## Direction and dispatch rules

A physical `RemoteEvent` is engine-bidirectional, so direction is enforced by
which listener the server installs and which send method the wrapper exposes.
A client firing a server-to-client endpoint is anomalous and can never reach a
feature handler. A response is sent only with `FireClient(originatingPlayer)`;
there is no caller-selected target or relay API.

There is no action field. There is no service name, handler name, path, Instance
path, module name, or arbitrary operation selector in an envelope. One physical
endpoint maps to one reviewed contract and one handler binding. Duplicate
binding is rejected.

The complete client-to-server request pipeline is fixed as:

1. fixed endpoint and direction selected by server binding;
2. cheap exact envelope shape and request-ID syntax/size checks without walking
   the payload;
3. server-authoritative per-player/per-endpoint token bucket;
4. authorization from the engine-supplied player and server-owned context;
5. strict bounded payload validation and canonicalization;
6. protected handler execution; and
7. allowlisted response translation to the originating player only.

No rejected request may invoke its feature mutation. Handler failures remain
server-side and become one static public failure code. Raw errors, traces,
payloads, rejected values, catalogs, private state, and secrets never enter a
response or log.

## Correlation decision

A client-generated request ID is a bounded typed correlation value only. It is
not identity, authorization, ownership, freshness proof, transaction identity,
or idempotency proof.

An in-flight repeated ID is a duplicate. A recently completed repeated ID is a
stale replay while it remains in a bounded server ledger. A first-seen ID cannot
be classified as stale from a client timestamp, so request envelopes contain no
client time. Once bounded history expires, a server cannot infer earlier use;
future value-granting systems must add their own authoritative idempotency
records where required.

On the client, a response must match both a live pending request ID and its fixed
endpoint. A response with no live pending entry is stale; one using the right ID
for another endpoint is mismatched. Neither can mutate pending state for the
valid request.

## Lifecycle and cleanup ownership

One common server network service is registered before lifecycle initialization.
Beginning with Packet 06.1, it owns the server-created root and every listener
connection through one `Cleanup` container. Later Phase 06 packets will extend
the same owner with rate-limit state, correlation history, and the
player-removal connection. The root is registered before connections so LIFO
cleanup disconnects listeners before destroying Instances.

Initialization preflights conflicts before publishing the tree and rolls back
its own partial work if any step fails. Shutdown clears bounded per-player state,
disconnects listeners, and destroys the exact owned tree through the existing
reverse lifecycle and graceful-shutdown path. No independent `BindToClose` hook
is added.

The current common server ready record reports lifecycle `Started` with one
registered service. The client lifecycle remains at zero services; the client
lookup module is a fixed utility and is not a lifecycle owner.

## Logging boundary

Networking extends the existing closed structured logger only with reviewed
aggregate fields. Logs may contain a fixed registry endpoint name, stable code,
bounded count, and bounded interval. They never contain a player payload,
request envelope, request ID, UserId, display name, player-authored string,
Instance path supplied by a client, raw exception, or trace.

Rate-limit and malformed-input signals are aggregated and interval-limited. The
server does not log every request or every rejection, and Phase 06 adds no ban,
punishment, persistence, analytics delivery, or external sink.

## Future endpoint registration procedure

Until the final Packet 06.5 checklist is recorded, no production feature remote
may be added. A later approved feature change must:

1. add exactly one fixed definition to `ProductionRemotes.luau`, using the
   canonical name grammar and the narrowest Lobby/Match role set;
2. select only an allowed direction, `ReliableRemoteEvent` transport, Request or
   Event semantic, and explicit response behavior;
3. add one strict bounded payload schema, one explicit rate policy, one
   server-derived authorization function, one protected handler, and allowlisted
   public response behavior;
4. bind the server handler by its registry constant before lifecycle
   initialization and expose only the definition-shaped client operation;
5. add positive, boundary, adversarial, role-isolation, duplicate-binding,
   cleanup, privacy, and zero-partial-mutation tests; and
6. prove the test fixture remains test-only and all production project source
   maps, role isolation, lifecycle ownership, and build exclusions still pass.

The registry module, root/version names, client lookup, or runtime binder must
not be bypassed by a second folder, generic action bus, client-selected path, or
ad hoc remote creation.

## Packet 06.1 completion evidence

The current canonical headless run discovered ten suites and passed all 106
cases. Of those, 18 cases cover registry structure, limits, canonical order,
immutability, provenance, malformed/conflicting definitions, hostile
metatables, and privacy; 12 cases cover parent-last publication, exact role
trees, handler completeness and uniqueness, conflict preservation, re-entry,
rollback, LIFO cleanup, every endpoint leaf shape, production seam exclusion,
and bounded client lookup. The fixtures exist only under `tests/`.

The four-project structural verifier currently reports 34 ModuleScripts, one
Script, and one LocalScript in each production build. The Test build's production
source subset contains 31 shared ModuleScripts plus exactly the two explicitly
mapped production networking runtime modules; 19 additional ModuleScripts are
test-owned specs, fixtures, support, or negative controls. Test contains zero
runnable scripts. Tests and test-only fixtures remain absent from Default,
Lobby, and Match; Lobby contains no Match source and Match contains no Lobby
source. The targeted architecture/security review resolved every normal finding
and finished with no unresolved P0, P1, P2, or P3 finding. Packet 06.1 is
complete; Phase 06 and Gate A remain open.
