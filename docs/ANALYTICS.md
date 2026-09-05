# Analytics and operational logging

Contract version 1. Repository implementation and deterministic evidence cover
historical Phase 37.1–37.5. **External delivery and Packet 37.6 remain pending.**
There is no configured destination, dashboard, external emission, durable
analytics storage, or cross-place analytics identifier in this implementation.

## Event dictionary

`src/server/common/analytics/AnalyticsDictionary.luau` is the executable
allowlist. Every envelope includes dictionary version, content version, event
name, exact bounded fields, and an optional ephemeral correlation token. Unknown
names, omitted/extra fields, arbitrary strings, nested objects, nonfinite
numbers, and out-of-range values are rejected. A version change is required to
change existing meanings. Adding reviewed content IDs requires explicitly
updating the allowlist; display names are never dimensions.

| Event | Exact fields | Authoritative observation |
| --- | --- | --- |
| `onboarding.v1` | action: Initialized, Advanced, Skipped, Replayed, Completed; step: integer 0–16 | A newly applied, changed Tutorial profile transaction, after the service returns. Cached transaction receipts and unchanged observations do not emit. |
| `party.v1` | action: Created, InvitationChanged, MembershipChanged, Disbanded; members: 0–4 | Existing post-mutation party callback. Count means affected members in this change, not a roster. |
| `queue.v1` | action: Entered, Cancelled, Started, Failed; members: 0–4 | Confirmed changed join/leave/start receipts, successful physical entry/exit, or a handled queue-operation failure. |
| `travel.v1` | action: Requested, Admitted, Failed, Returned, Recovered; failureClass: None, Retryable, Terminal | Successful safe-teleport initialization; authenticated admission/rejoin; terminal rollback; authenticated Lobby return; handled start failure. Requested does not imply arrival. |
| `match.v1` | action: Ready, Started, Terminal, Returned; map and difficulty: explicit stable-content allowlists; outcome: None, Victory, Defeat; waveBucket: 0–20 | Accepted Ready and runtime state transitions. Five-wave buckets, saturated at 100+. Return completion currently uses `travel.v1/Returned`; `match.v1/Returned` is reserved. |
| `gold.v1` | direction: Source or Sink; reason: MatchReward or Chest; amountBucket: 0–100 | Durably Granted reward claim, or successful acquisition receipt. Amount is ceil(Gold / 100), saturated at 10,000+. |
| `acquisition.v1` | quantity: 0–10; newCount: 0–10; pityBucket: 0–20 | One aggregate per successful chest receipt, with five-pull pity milestones saturated at 100+. No per-unit event or inventory contents. |
| `operational.v1` | category: profile, ticket, teleport, configuration, match, reward, analytics, security; code: Unavailable, InvalidState, Rejected, TimedOut, Capacity, DeliveryFailed | An allowlisted operational failure category; no exception strings or arbitrary service return payloads. |

Profile/tutorial and acquisition events describe a successful authoritative
in-memory commit; they do not certify a later DataStore save. Reward source
events have the stronger existing `Granted` contract: profile flush and result
ledger acknowledgement have completed. Analytics never starts a save, issues a
reward, retries a gameplay operation, or enters a profile transaction callback.
The observer proxies preserve the original genuine service `self`, all return
values and object identities. A throwing or yielding observer is isolated after
the authoritative method returns.

## Privacy, limits, and failure behavior

- No player names, raw UserIds, chat, free text, profile snapshots, inventories,
  ticket/match/result IDs, access codes, teleport data, receipts, or secrets enter
  event envelopes. Server-internal IDs may identify a bounded deduplication entry
  but are never sent to a sink or log.
- Correlation is a random server nonce plus a local monotonic sequence. It is
  not derived from a user, account, match, ticket, or profile. At most 128 scope
  entries and 256 dedup entries are retained; entries expire logically after
  30 minutes and are evicted by capacity. Profile release forgets its scope;
  shutdown clears every cache. No token is persisted or carried through travel.
  If nonce generation is unavailable, correlation is omitted safely.
- At most 120 accepted events per server per minute, 128 buffered records, and
  32 processed records per drain. Ingestion stops at the cap; no per-enemy,
  per-attack, damage, frame, or performance-value event exists. This is bounded
  best-effort telemetry, not an exact accounting ledger or a complete funnel
  under overload. A reviewed destination may require future sampling analysis.
- Production uses the disabled sink: validated events are counted then
  discarded immediately, with no buffer or external work. Injected mock sinks
  exercise delivery. A sink must return without yielding; failure permits one
  retry only, then drops. Records expire after 30 seconds. Reentrant drains are
  rejected. Shutdown discards pending records without delaying gameplay.
- Deduplication is local and bounded, not durable exactly-once delivery. A
  replay after eviction, expiry, or a server restart may emit again. Analytics
  does not change existing persistent reward or transaction idempotency.

## Operational logging

`Log` retains context-bound structured logging and fatal bootstrap errors.
Additional subsystem names cover profile, ticket, teleport, match, reward,
analytics, and security. Existing configuration/bootstrap and aggregated
network/security diagnostics remain their owners; no duplicate global reporter
is installed. Runtime simulation failure logs once when the service stops.

`OutcomeObserver.failure` is a nonfatal rate-limited recorder: one fixed
category/code every 30 seconds and at most 16 records per minute per server.
Profile load/flush failures or a failed profile state, rejected ticket admission,
failed safe teleport, failed reward claim and ledger acknowledgement blockage
are actionable recorded seams. Ordinary pending rewards are not warnings.
Unknown categories/codes are discarded. Log event names are capped at 64 bytes,
messages at 512, ordinary string fields at 128, validation paths at 512, and
correlation tokens at 48. Sensitive field-name tokens and control/injection
characters remain rejected. There is no raw exception forwarding.

## Safe development commands

`tests/support/SafeDevelopmentCommands.luau` is absent from Default, Lobby and
Match builds. Construction and every execution require the exact
`ServerStorage.AutomatedTests.Support.SafeDevelopmentCommands` test module
location. There is no automatic startup, production remote, chat command,
configuration attribute, or enabled production command authority.

The server-owned environment must identify staging GameId 10764687717, Lobby
140661668701496 or Match 104415140644510 with the matching role, Group owner
35420107, server execution and runtime-only fixtures. Studio is allowed only
inside that confirmed identity. Non-Studio additionally requires an explicitly
confirmed private test server and exact UserId allowlist membership. No
published adapter or allowlist is configured. Missing/ambiguous fields deny.

Commands are StartWave (next test wave), GrantBattleCash (0–10,000 per call and
50,000 total reserved before dispatch), Inspect (eight bounded counters),
ValidateMap (valid flag and bounded issue count), and PresentationScenario
(Idle, Normal, Boss, Dense, Results, Cleanup). Mutations require an isolated
Match test-runtime adapter. All commands share a 30/minute limit; adapters must
not yield. Cleanup disables the dispatcher and releases adapter references.
No Gold, inventory, pity, profile, receipt, DataStore, MemoryStore, teleport,
purchase, or production mutation command exists.

The framework accepts explicit test-only capability adapters; it does not
grant arbitrary access to the live PlayableMatchRuntime internals. Battle Cash
fixtures can use the existing production BattleCashLedger, while runtime
scenarios use the existing simulation and legal actions. Binding commands to
any further Studio fixture requires that fixture's own recorded procedure and
cleanup; dispatcher unit tests are not evidence of a live command session.

## External dashboard acceptance gate

The following must be reviewed together before any destination is enabled:
the private experience and published place versions, provider and exact event
subset, designated test accounts, expected write count and duration, access
controls, retention/deletion boundary, correlation policy, failure/abort
conditions, and cleanup. A requested retention target must be enforced and
verified at the provider; no provider retention behavior is claimed here.

Only after that approval can a bounded private published session establish
arrival, dimensional usefulness, duplicate/drop visibility, retention behavior,
and dashboard usefulness. Deterministic mock records establish none of those
external-service claims. No Packet 37.6 completion is asserted.
