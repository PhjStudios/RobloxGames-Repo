# Network Protocol and Remote-Security Foundation

## Decision status

- Phase: 06 — Network Protocol and Remote-Security Foundation
- Architecture decision recorded: 2026-08-26, before Phase 06 source changes
- Primary-source research accessed: 2026-08-26
- Transport decision: fixed, reliable, asynchronous `RemoteEvent` endpoints
- Production feature endpoints: none at the decision checkpoint
- `RemoteFunction`: prohibited unless a later recorded concrete need changes the
  decision
- Generic remote bus, client-selected action, service, handler, or path: prohibited
- Gameplay, persistence, external service, place save, or publication authorized:
  none

This is the authoritative Phase 06 network-boundary document. Packet-level
implementation details and evidence will be added here as the five packets are
completed. The decision section is intentionally recorded before implementation.

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

The server constructs an unparented tree, binds only reviewed server listeners,
and sets `Parent` last. Any pre-existing root, wrong class, duplicate endpoint,
or conflicting semantic leaf fails closed without deleting or adopting the
unowned object. Re-entry and a second owner are rejected rather than silently
sharing mutable state.

## Registry contract

Every definition will declare exactly:

- one bounded canonical endpoint name;
- reliable `RemoteEvent` transport;
- `ClientToServer` or `ServerToClient` direction;
- `Request` or `Event` semantic kind;
- whether a request has a separate response endpoint; and
- a nonempty fixed set of active place roles.

The registry copies, canonicalizes, deeply freezes, and authenticates accepted
definitions. Lookup returns only canonical definitions. Definition and registry
order is deterministic and never depends on dictionary iteration.

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

One common server network service will be registered before lifecycle
initialization. It owns the server-created root, every listener connection,
rate-limit state, correlation history, and player-removal connection through one
`Cleanup` container. The root is registered before connections so LIFO cleanup
disconnects listeners before destroying Instances.

Initialization preflights conflicts before publishing the tree and rolls back
its own partial work if any step fails. Shutdown clears bounded per-player state,
disconnects listeners, and destroys the exact owned tree through the existing
reverse lifecycle and graceful-shutdown path. No independent `BindToClose` hook
is added.

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
may be added. At minimum, a future change must add one fixed registry definition,
one strict payload schema, one explicit rate policy, one server-derived
authorization function, one protected handler, public response behavior, and
positive/boundary/adversarial tests. It must also prove place-role isolation,
cleanup, privacy, zero partial mutation on rejection, and production-build test
exclusion.
