# Future Remote Security Checklist

## Authority and status

This is the mandatory shipping gate for every future Ant Tower Defense
production remote. `docs/NETWORK_PROTOCOL.md` defines the protocol mechanics;
this document defines the evidence and approval record that a concrete endpoint
must have before it can enter `ProductionRemotes.luau`; every C2S endpoint must
also enter `ProductionRateLimits.luau`, while an S2C endpoint must not.

- Recorded: 2026-08-26 during Packet 06.5
- Applies to: every production `RemoteEvent` definition and every server or
  client binding that uses it
- Current production endpoint records: none
- Current production registry and rate-policy list: intentionally empty
- Gameplay or Phase 07 endpoint authorized by this document: none

No checklist item is satisfied merely because the shared foundation implements
it in general. The endpoint owner must prove the behavior for that endpoint's
exact definition, schemas, policy, authorization, handler, client consumer, and
place-role set. Sections identify universal, client-to-server (`C2S`), and
server-to-client (`S2C`) requirements. Universal items and every item matching
the endpoint's direction may not be marked `N/A`. Opposite-direction items must
be marked `N/A` with the fixed direction as the reason. Any other conditional
`N/A` requires a written reason and reviewer acceptance.

## Approval rule

A production endpoint may ship only when all of the following are true:

1. one completed endpoint approval record uses the template below;
2. every mandatory check is supported by an exact source or evidence link;
3. formatting, lint, the canonical tests, and the four-project structural
   verifier pass from the proposed combined state;
4. all applicable unsaved Studio checks pass without saving, publishing, or
   enabling an external service;
5. independent source, protocol-security, test-quality, and documentation
   reviews have no unresolved P0, P1, or P2 finding; and
6. the implementation commit has a genuine clean GitHub Actions run.

Review or CI evidence from a different endpoint, schema, policy, role set, or
commit cannot be substituted. A later material contract change invalidates the
old approval record and requires the affected checks to be repeated.

## Mandatory checklist

### 1. Scope and fixed identity

- [ ] The owning roadmap packet and feature are identified and are currently
  authorized; the endpoint does not pull a later phase forward.
- [ ] The endpoint has one canonical registry name that satisfies the fixed
  grammar and is referenced as a constant, never assembled from client input.
- [ ] The narrowest required `Lobby` and/or `Match` role set is recorded.
- [ ] Direction, `Request` or `Event` semantics, and `Required` or `None`
  response behavior are explicit and match the feature's one operation.
- [ ] Transport remains reliable asynchronous `RemoteEvent`.
- [ ] The endpoint is not a generic bus and accepts no client-selected action,
  service, handler, module, remote path, Instance path, or response target.
- [ ] No `RemoteFunction` is introduced. A concrete need for one requires a new
  architecture decision based on current official engine behavior before code.
- [ ] The endpoint does not duplicate or bypass `ATDNetwork/v1`, the registry,
  the server owner, or the client lookup. C2S also may not bypass the limiter or
  dispatcher; S2C may not bypass its approved sender and audience policy.

### 2. Registry, ownership, and role isolation

This section is universal except where a bullet explicitly names a direction.

- [ ] The definition is added once to `ProductionRemotes.luau` and canonical
  registry lookup returns that exact authenticated definition.
- [ ] Only `ServerRemoteRegistry` creates and publishes the production Folder
  and `RemoteEvent` Instances; clients create none.
- [ ] Conflicting or wrong-class pre-existing Instances fail closed and are not
  adopted, overwritten, renamed, or deleted.
- [ ] Every active client-to-server definition has exactly one secure Request
  or Event contract before lifecycle initialization.
- [ ] Every active server-to-client definition has no inbound listener or
  dispatcher contract and is captured only by its fixed reviewed server sender.
- [ ] Unknown, inactive, wrong-direction, wrong-kind, late, and duplicate
  registrations fail before listener publication.
- [ ] Lobby creates no Match-only endpoint and Match creates no Lobby-only
  endpoint; Development is inspection-only union behavior.
- [ ] Parent-last publication and listener-first LIFO cleanup remain intact.
- [ ] Repeated initialization, start, shutdown, or binding cannot duplicate any
  applicable owner, listener, sender, handler, limiter bucket, or dispatcher
  ledger.

### 3. Payload and response schemas

The common shape and bound rules apply to inbound C2S payloads and outbound S2C
payloads. Direction-specific bullets are mandatory only for that direction.

- [ ] One authenticated strict payload schema is linked from the record.
- [ ] For C2S, a response-required Request has one authenticated strict response
  schema; a no-response Request or Event has none.
- [ ] For S2C, the server validates the exact outbound Event envelope and
  payload against the authenticated schema before sending; there is no response
  schema or request ID.
- [ ] Every string, enumeration, array, record, number, and union has a
  feature-specific bound no wider than the fixed technical cap.
- [ ] Records use exact keys, arrays are dense, numbers and datatype components
  are finite, and coercion is not accepted.
- [ ] Existing typed ID families are used instead of untyped strings where a
  project ID already exists; cross-family values are rejected.
- [ ] Optional fields and unions are individually justified and do not create
  an ambiguous operation selector.
- [ ] Depth, node, field, item, and byte limits contain the complete composed
  payload, including speculative union work.
- [ ] Cycles, repeated aliases, sparse tables, hostile metatables, exotic keys,
  unexpected fields, NaN, positive/negative infinity, and wrong Roblox types
  fail with stable privacy-safe paths.
- [ ] For C2S, client-supplied Instances are rejected by default.
- [ ] If an inbound or outbound Instance is indispensable, the record names the
  exact class, subclass policy, server-owned ancestry, streaming/replication
  implications, and server-context proof. A C2S handler still derives authority
  independently; an S2C sender proves the Instance is intended to replicate to
  every recipient.
- [ ] Validation returns detached canonical table containers; an explicitly
  approved Instance policy may return the same authenticated server Instance.
  Neither validation nor any observable failure retains or echoes a rejected
  value.

### 4. C2S server-derived authorization and mutation safety

Every item in this section is mandatory for C2S. An S2C record marks the section
`N/A — ServerToClient` and instead completes the S2C audience requirements in
sections 5–7.

- [ ] Player identity comes only from the engine-supplied `Player` in the
  dispatcher context.
- [ ] Permissions, ownership, team, place role, prices, balances, inventory,
  roster membership, and other authoritative context are derived on the server.
- [ ] Client claims for those values are omitted from the schema or treated only
  as non-authoritative hints and checked against server state.
- [ ] The context-only authorizer is side-effect-free and sees no raw or
  canonical payload.
- [ ] The authorizer and handler complete synchronously and never yield, wait,
  spawn, defer, schedule, connect, or create unowned asynchronous work. A true
  asynchronous need has a separately reviewed bounded lifecycle-owned job
  protocol rather than weakening the dispatcher.
- [ ] Authorizer allow, deny, and throw paths have mutation-sentinel tests.
- [ ] If authorization genuinely needs canonical payload data, a separately
  reviewed post-validation/pre-handler guard and its pipeline position are
  recorded; the context authorizer is not bypassed.
- [ ] The handler performs every fallible read, calculation, and dependency call
  before one narrow atomic commit.
- [ ] Rejection and injected-failure tests prove zero partial mutation; success
  proves exactly the intended commit once.
- [ ] Caught handler failures and counterfeit outcomes become only allowlisted
  public failures and never escape as raw errors or traces.
- [ ] Handler-supplied public rejections contain no metadata. Only the
  dispatcher's strict payload-validation failure path may attach the bounded
  canonical `validationPath`.
- [ ] A client request ID is correlation only. It is not identity,
  authorization, freshness, transaction identity, idempotency, or proof that an
  earlier side effect occurred.
- [ ] Any value-granting or persistent mutation has its separately reviewed
  authoritative idempotency/transaction contract when that later phase exists.

### 5. Rate and resource bounds

The token-bucket bullets below are mandatory for C2S only. S2C endpoints do not
enter `ProductionRateLimits.luau`; they must complete the outbound bounds at the
end of this section.

- [ ] Every client-to-server definition has exactly one authenticated policy in
  `ProductionRateLimits.luau`.
- [ ] Capacity and refill are justified from expected legitimate bursts and the
  smallest acceptable sustained rate; the default is not accepted silently.
- [ ] The server uses its own monotonic clock and ignores client timestamps.
- [ ] Tests cover capacity, cap-plus-one, exact refill, fractional refill, long
  forward time, backwards/non-finite/throwing time, and recovery.
- [ ] Player and endpoint buckets are isolated, state growth is bounded, and a
  valid peer/action remains usable during another peer/action's abuse.
- [ ] `PlayerRemoving` and lifecycle shutdown clear exact limiter and
  correlation state without harming remaining Players.
- [ ] Abuse reporting is aggregate, saturating, interval-limited, and failure-
  isolated; it never logs each request or rejection.
- [ ] The endpoint introduces no automatic punishment, ban, persistence,
  analytics delivery, external sink, or hidden client throttle dependency.
- [ ] For S2C, a server-owned emission and fan-out policy records exact burst,
  sustained-frequency, recipient-count, payload-size, and queued-state bounds;
  it accepts no client timestamp, recipient, or broadcast selector.
- [ ] For S2C, disconnect and lifecycle shutdown remove any endpoint-owned
  recipient or queue state, and tests prove one recipient cannot cause unbounded
  work or disclosure to another.

### 6. Envelopes, public errors, and routing

Request-ID, response, and public-error bullets are mandatory for C2S Requests.
Every endpoint must use the exact direction-appropriate Event record when its
semantic kind is Event. S2C routing requirements follow the C2S bullets.

- [ ] For C2S Requests, Request, Success, and Rejected wire records use the exact
  shared envelope shapes with no extra arguments or fields.
- [ ] For every C2S or S2C Event, the Event wire record uses the exact shared
  envelope shape with no extra arguments or fields.
- [ ] For C2S Requests, client-generated request IDs satisfy the 8–48 byte fixed
  grammar and the client tracker bounds generation retries, Pending state, and
  terminal history.
- [ ] For C2S Requests, Pending duplicate, completed stale, malformed, and
  count-evicted ID
  behavior matches the documented correlation contract.
- [ ] For C2S Requests, cross-endpoint responses cannot terminate another endpoint's Pending
  request, and stale/malformed responses do not mutate valid client state.
- [ ] For C2S Requests, public errors use only the seven-code allowlist. Optional
  metadata is only the bounded canonical validation path for `INVALID_PAYLOAD`.
- [ ] For C2S Requests, responses never contain a caught error, traceback, payload echo, Player
  identity, private value, secret, catalog, or arbitrary server state.
- [ ] For C2S Requests, a response uses only the response leaf captured during server-owned tree
  creation and `FireClient(originatingPlayer, envelope)`.
- [ ] For C2S Requests, there is no caller-selected recipient, relay, or
  `FireAllClients` fallback for a private response.
- [ ] For S2C, the server derives every recipient from authoritative state; no
  client value selects, expands, or relays the audience.
- [ ] For S2C, `FireAllClients` is allowed only when the approval record proves
  the same payload is intentionally public to every active client in every
  enabled place role. Otherwise each `FireClient` target is server-derived.
- [ ] For S2C, the outbound payload contains no secret, server-only catalog,
  unauthorized Player data, caught error, trace, or state outside the approved
  recipient's visibility.

### 7. Client boundary and cleanup

Fixed lookup and connection ownership are universal. Tracker/Pending bullets
apply only to C2S Requests; S2C consumer requirements follow them.

- [ ] Client code resolves only the fixed canonical endpoint through
  `ClientRemoteLookup` with one bounded total deadline.
- [ ] The client never creates a missing remote, recursively searches for one,
  accepts a caller path, or substitutes a registry, role, parent, or wait source.
- [ ] For C2S Requests, request construction and response handling are registered
  against the same captured canonical definition and authenticated schemas.
- [ ] For C2S Requests, client UI state, if later implemented, consumes only canonical
  `Pending`, `Success`, and `Rejected` states; no UI is required by this gate.
- [ ] Every client and server connection is owned by the established `Cleanup`
  and lifecycle chain, and tracker state is explicitly cleared by its owner.
- [ ] For C2S Requests, lost response, cancellation, disconnect, shutdown, and
  lifecycle re-entry cannot leave unbounded Pending or server state.
- [ ] For S2C, the client parses and validates only the captured definition's
  exact Event envelope and payload schema before invoking its fixed consumer.
- [ ] For S2C, malformed or unexpected outbound data fails without client state
  mutation, payload echo, arbitrary dispatch, or an automatic client-to-server
  retry loop.

### 8. Required evidence

Universal and matching-direction evidence is mandatory; opposite-direction
cases are recorded as `N/A` with the direction reason.

- [ ] Positive direction-appropriate Request/Event behavior and the exact
  success response, where defined, are tested.
- [ ] Minimum, maximum, cap-plus-one, missing, extra, wrong-type, and coercion
  boundaries are tested for every field.
- [ ] Malformed envelopes, excessive nesting/size, cycles, hostile tables,
  NaN/infinity, and unexpected Instances are tested where applicable.
- [ ] For C2S Requests, malformed, oversized, duplicate, stale, cross-endpoint,
  and cross-family identifiers are tested.
- [ ] For C2S, burst, refill, multiple-Player, multiple-endpoint, cleanup, and
  time-anomaly behavior is tested deterministically with injected time.
- [ ] For C2S, unauthorized context and forged identity/ownership fields are
  tested.
- [ ] Unknown endpoint, arbitrary path, wrong direction, wrong kind, counterfeit
  definition/contract, duplicate binding, and lifecycle re-entry are tested.
- [ ] For C2S, handler throws, invalid outcomes, invalid responses, send
  failures, and reporter failures have safe contained results.
- [ ] Direct Luau suspension by a C2S authorizer or handler is detected, closed,
  translated safely, and cannot execute post-yield mutation; endpoint source
  contains no wait, spawn, defer, schedule, connection, or other engine-owned
  asynchronous work for which dispatcher cancellation is not claimed.
- [ ] S2C tests cover exact audience derivation, private-recipient isolation,
  broadcast prohibition or public-broadcast justification, outbound schema
  rejection before send, emission/fan-out bounds, and payload privacy.
- [ ] For C2S, mutation sentinels prove every pre-handler rejection and every
  designed handler failure has zero partial mutation.
- [ ] Recursive privacy assertions cover returned failures, responses, stats,
  aggregate reports, and captured development logs.
- [ ] Tests use deterministic test-only fixtures and do not populate lasting
  gameplay configuration.
- [ ] `stylua`, StyLua verification, Selene configuration validation, Selene,
  the canonical suite, and `git diff --check` pass.
- [ ] The four-project verifier proves exact source identity, intended
  bootstraps, Lobby/Match isolation, and absence of tests/test-only dependencies
  from Default, Lobby, and Match.
- [ ] Applicable real-engine behavior passes the current unsaved Studio
  procedure. If no engine-facing behavior changed, the record explains why the
  existing current evidence is sufficient; it may not cite historical evidence
  as a fresh run.
- [ ] Source, protocol-security, test-quality, and documentation reviews are
  linked and all P0, P1, and P2 findings are resolved.
- [ ] One genuine clean GitHub Actions run is linked to the exact implementation
  commit.

## Endpoint approval record template

Copy this section into the feature's authoritative protocol document. Do not
approve an endpoint with blank fields or informal evidence references.

```text
Endpoint approval record

Endpoint name:
Owning roadmap packet / feature:
Approval status: Proposed | Approved | Superseded
Approval date:
Implementation commit:
Clean CI run URL:

Fixed contract
- Registry definition source:
- Active place roles:
- Direction:
- Semantic kind:
- Response behavior:
- Transport:
- Why this is one narrow operation rather than a generic bus:

Data boundary
- Inbound C2S or outbound S2C payload schema and field/graph limits:
- C2S response schema source, or direction/response reason none is permitted:
- Typed ID families:
- Optional/union justification:
- Instance policy, or explicit default rejection:
- Public error codes and metadata this endpoint may return:

C2S server authority and mutation, or N/A — ServerToClient
- Context-only authorizer source and server-derived facts:
- Post-validation guard source/reason, or N/A with reviewer acceptance:
- Synchronous non-yielding handler source:
- Fallible-before-commit design:
- Mutation/idempotency design:
- Origin-only response route:
- Metadata-free handler rejection proof:

S2C audience and privacy, or N/A — ClientToServer
- Server-derived recipient/audience source:
- Private FireClient route or public FireAllClients justification:
- Outbound schema-validation call site:
- Recipient-isolation and payload-privacy design:

Abuse and lifecycle
- C2S rate-policy source, capacity, refill, and rationale, or direction N/A:
- S2C emission/fan-out policy and rationale, or direction N/A:
- Bounded per-Player/per-endpoint/recipient state:
- PlayerRemoving or recipient-disconnect cleanup:
- Lifecycle/Cleanup owners:
- Aggregate logging fields and cadence:

Client boundary
- Fixed lookup call site:
- C2S tracker/response-schema or S2C event-schema registration:
- Listener and Cleanup owner:
- Pending/Success/Rejected or fixed outbound-Event consumer:

Evidence
- Positive/boundary test cases:
- Adversarial/security test cases:
- Privacy and zero-mutation test cases:
- Role-isolation/build-exclusion evidence:
- Unsaved Studio evidence or accepted non-applicability reason:
- Source review:
- Protocol-security review:
- Test-quality review:
- Documentation review:
- Resolved findings:

Approvals
- Implementer:
- Source reviewer:
- Protocol-security reviewer:
- Test-quality reviewer:
- Documentation reviewer:
- Final approval statement:
```

## Phase 06 foundation record

Phase 06 establishes the reusable boundary but intentionally approves no
feature endpoint. Its test-only definitions and Studio fixture are evidence for
the foundation, not entries that may be copied into the production registry.
Packet 06.5's 200-case headless run and unsaved two-client engine regression are
recorded in `docs/NETWORK_PROTOCOL.md` and
`docs/NETWORK_SECURITY_STUDIO_REGRESSION.md`. The fresh Phase 06 exit audit
records the combined foundation evidence in `docs/PHASE_06_EXIT_AUDIT.md`; its
local combined state now passes, while current clean CI evidence and the
completion record remain open. The next
feature packet must still complete this checklist for each endpoint it
proposes; no test-only fixture is an approved production endpoint.
