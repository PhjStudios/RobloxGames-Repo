# Phase 13 Tower Placement Contract

## Decision status and scope

This is the authoritative Phase 13 decision for Packets 13.1–13.5. Phase 13
adds an advisory cross-platform preview and one synchronous authoritative
placement transaction. It consumes the Phase 07 map snapshot and Phase 12
temporary loadout/TowerRuntime; it does not begin Phase 14 combat or Phase 15
Battle Cash.

Production Assets, Towers, Enemies, Maps, Difficulties, Waves, and
difficulty-specific Economy catalogs stay empty. The Phase 12 five-slot
loadout remains match-local development state and is not a persistent equipped
loadout.

## Placement-query ownership and revisions

`TowerPlacement` is one non-restartable Match service. It reads only current
detached MatchLifecycle/MapRuntime snapshots and narrow server-only
TowerRuntime placement views. It never retains a Player, accepts a client
definition, or obtains an Instance through a query record.

The client-safe contract version is `1`. A query revision starts at `1` after
all dependencies are available and increases once after each committed
placement. A `TowerPlacementRevision` event contains only the current MatchId
and revision and tells clients to coalesce one refresh. It is not placement
authority. Future revisions and revisions more than four commits behind are
rejected; a lag of at most four is admitted so up to four clients can submit
non-overlapping intents from the same snapshot. Every such intent is still
recomputed against current committed and reserved footprints. MatchId and
loadout revision must always match exactly.

`GetTowerPlacementQuery` has an exact empty payload. Its detached, deeply
frozen result contains only:

- contract version, MatchId, MapId, query revision, and the caller's temporary
  loadout revision;
- MapBounds;
- at most 32 placement zones with CFrame, Size, and surface category;
- at most 32 exclusion boxes;
- at most 128 existing footprints encoded as `Vector3(centerX, radius, centerZ)`;
- exactly five caller-owned slot records; and
- for occupied slots only the tower ID, bounded display/icon metadata, level-1
  range, authored footprint, placement cost, owned count/cap, affordability,
  and total-cap state needed to render the preview.

It contains no Instance, Player, UnitId, RuntimeTowerId, owner identity,
capability, canonical definition table, model identity, other-player loadout,
private diagnostic, mutable cache, or mutation handle. The limits fit the
shared depth-eight/512-node payload validator. An oversized authoritative map
or impossible source record makes placement unavailable rather than returning
a partial snapshot. Query state is discarded on cleanup; retained client
copies have no authority.

## Endpoints and wire shapes

All three endpoints are reliable, Match-only, registry-owned, and use the
existing request envelope, dispatcher, correlation ledger, validation,
authorization, response translation, aggregate logging, and cleanup.

| Endpoint | Direction | Exact purpose | Production rate policy |
| --- | --- | --- | --- |
| `GetTowerPlacementQuery` | C2S request | Read one caller-private bounded snapshot | capacity 4, refill 1/s |
| `SubmitTowerPlacement` | C2S request | Submit one bounded placement intent | capacity 3, refill 0.5/s |
| `TowerPlacementRevision` | S2C event | Announce only MatchId and current query revision | not inbound; no policy |

The placement payload is exactly:

```luau
{
    matchId: MatchId,
    observedQueryRevision: positive safe integer,
    loadoutRevision: positive safe integer,
    slot: integer 1..5,
    positionXZ: Vector2, -- each component within +/-100,000
    yawDegrees: number, -- finite and within -360..360
}
```

It cannot express Y, pitch, roll, CFrame, owner, TowerId, UnitId,
RuntimeTowerId, level, model, cost, cap, target mode, investment, cooldown, or
capability. Extra keys, multiple arguments, metatables, malformed tables,
oversized graphs, nonfinite values, and out-of-range values fail before the
handler. Yaw is normalized deterministically to `[0, 360)` with negative zero
canonicalized to zero. The server derives the placement Y and constructs an
upright CFrame, so pitch/roll injection has no accepted representation.

Success is an `Accepted` receipt with the server-assigned RuntimeTowerId,
canonical placement CFrame, and new query revision. Expected domain rejection
is a bounded `Rejected` receipt with the current revision and one fixed reason:
`NotEligible`, `Stale`, `InvalidSlot`, `InvalidPosition`, `InvalidSurface`,
`OutsideZone`, `Excluded`, `Occupied`, `Capped`, `Unaffordable`, or
`Unavailable`. Dispatcher-level invalid, replay, duplicate, rate, authorization,
and internal failures keep the existing public error vocabulary. Neither form
includes another player, hidden count, definition, or diagnostic.

## Shared footprint, zone, surface, and height rule

`PlacementGeometry` is one pure shared module used by preview and server. An
authored `footprintRadiusStuds` is the only tower footprint; model bounds are
never read or inferred. Positions and regions must be finite and bounded.

Placement regions are horizontal boxes. The pure rule supports an upright
yaw-oriented CFrame; pitch, roll, shear, or a malformed rotation is rejected.
The current Phase 07 authoring contract remains compatible with its existing
identity rotations. MapBounds remains explicit. For a candidate circle:

1. its complete circle must be inside MapBounds;
2. it must be wholly inside exactly one placement zone in that zone's object
   XZ space;
3. that zone's top face determines the trusted ground height;
4. the surface category must be approved;
5. it must have no positive-area intersection with an exclusion box; and
6. it must have no positive penetration with a committed or reserved circle.

Boundary contact is allowed for bounds and full-zone containment. Exact
tangency to exclusions or another footprint is also allowed; positive
penetration beyond the scale-aware `1e-6` tolerance is invalid. This policy is
identical in preview and admission, but the client result is advisory.

Placement zones carry the narrow `ATD_SurfaceCategory` contract with the closed
values `Land`, `Elevated`, and `Water`. Existing version-1 authored zones that
lack the new optional attribute normalize to `Land`; current deterministic
fixtures author it explicitly. `Land` and `Elevated` are approved in Phase 13.
`Water` is parsed and replicated as a future category but remains inert and
invalid for every current tower. No tower schema or production content is
expanded.

## Client preview and input-family state machines

The client owns presentation only: a five-slot temporary hotbar, at most one
selected slot, one candidate, one translucent ghost, one flat range indicator,
and bounded UI. The ghost is a generic projection from server-safe radius/range
metadata; it is not the canonical tower model. Preview parts are anchored,
non-colliding, non-touching, non-queryable, and local-only.

One reducer owns `Idle -> Selected -> Positioned -> Submitting` and the
orthogonal preferred-device state. Slot switching replaces metadata without
duplicating bindings. Cancel clears the preview; terminal or stale responses
return to a safe selected/idle state and request one refresh. Valid, blocked,
unaffordable, and capped states use text/icon/shape feedback as well as color.

- Desktop uses the mouse position, one explicit include-filter raycast against
  `Workspace.ATDRuntimeMap`, deliberate rotate, click/confirm, cancel, and
  number-slot actions.
- Phone and tablet use a completed single-touch tap only to position. A
  separate on-screen Confirm action is the sole touch confirmation. Drag,
  pinch, multi-touch, camera gestures, and UI navigation never dispatch it.
- Gamepad owns a bounded deterministic virtual reticle moved by the thumbstick,
  explicit confirm/cancel/rotate, slot cycling, and selectable focus.
- Preferred-device changes update hints only; they do not recreate bindings,
  discard selection, or confirm.

At most one raycast is performed per rendered update, no preview has more than
two world parts, and controller connections/bindings are constant. Revision
events and responses coalesce refresh work. Shutdown cancels tracked requests,
unbinds every action, disconnects every connection, destroys all UI/world
preview Instances, clears snapshots/state, and makes captured callbacks inert.

## Authoritative validation and atomic admission

The network owner performs exact envelope/payload validation, rate limiting,
context authentication, and correlation before the service handler. The
service then validates, without yielding, in this fail-closed order:

1. live authenticated sender UserId and current Active participant;
2. current MatchId and `PreWave` or `WaveActive` lifecycle;
3. exact caller loadout revision and occupied temporary slot;
4. server-derived UnitId/TowerId/canonical-definition relationship;
5. query-revision policy and current authenticated MapRuntime identity;
6. finite bounded XZ/yaw and server-derived upright transform;
7. MapBounds, full-zone containment, approved surface, and ground height;
8. exclusion and current committed/reserved footprint overlap;
9. owner, per-TowerId placement cap, per-owner total cap 32, and global
   TowerRuntime cap;
10. server-owned affordability placeholder;
11. a private atomic footprint reservation;
12. a private placeholder-charge reservation;
13. a fresh Phase 12 occupied-slot capability;
14. capability consumption and RuntimeTower/model creation;
15. placeholder reservation commit, committed-footprint reconciliation, query
    revision increment, and bounded revision publication.

The operation guard and reservation ledger serialize mutation. Re-entry,
cleanup, disconnect, lifecycle change, map identity change, or dependency fault
before commit aborts the charge placeholder, removes the footprint reservation,
and consumes/revokes any capability. Failure after tower creation invokes the
trusted TowerRuntime remove path before returning; an impossible rollback
faults placement closed and leaves lifecycle cleanup as the final owner.
Committed footprints are always re-derived from current TowerRuntime records,
so Workspace models and client previews never become collision truth.

## Affordability boundary

Phase 13 has no wallet. The production-dormant default and Studio fixture use a
server-owned static placeholder: canonical placement costs up to `150` are
`Affordable`; larger costs are `Unaffordable`. Its prepare/commit/abort tokens
and counts exist only to prove ordering, exact-once behavior, and rollback.
They never store or mutate a balance, spend or refund currency, grant starting
cash or income, persist data, or affect Gold. Deterministic tests may inject a
bounded spy with the same synchronous contract. Phase 15 must replace this
boundary with its own reviewed atomic Battle Cash transaction.

## Lifecycle, work bounds, and cleanup

The service depends on NetworkRegistry, MatchLifecycle, WaveRuntime, and
TowerRuntime and shuts down before TowerRuntime. It retains no per-player task,
timer, loop, Heartbeat, Player, model, preview, or canonical client table.
Technical ceilings are four active participants, five slots, 32 query zones,
32 exclusions, 128 committed footprints, 32 active towers per owner, four
accepted stale-revision distance, one operation/reservation per synchronous
admission, and bounded linear validation work over those collections.

Disconnect, spectator state, Results/Closing, defeat, dependency fault, cleanup,
late response, and re-entry close admission. Cleanup revokes reservations and
placeholder tokens, clears revisions/caches/metrics, disconnects publication
ownership through the normal network lifecycle, and rejects late work. Client
cleanup additionally leaves no hotbar, hint, confirmation UI, ghost, range
indicator, binding, connection, pending request, cache, or preview folder.

## Verification and exclusions

Headless acceptance covers surface/geometry/tangency, snapshots and schemas,
rate policies, reducers/input adapters, authoritative validation order,
optimistic revision admission, overlapping/non-overlapping races, replay/spam,
fault injection at every reservation/create boundary, privacy, integration, and
cleanup. Exact unsaved Match Studio acceptance covers desktop, touch/tablet,
gamepad, two-client races/replication, malformed/stale/capped/unaffordable
rejections, coexistence, and zero residue.

Phase 13 does not add target queries, attacks, cooldown stepping, damage,
splash/support/status execution, upgrades, selling, target-mode transactions,
Battle Cash mutation, persistence, matchmaking, rewards, production tower
content, uploaded assets/animations, or lasting Studio content. Phase 14 remains
unbegun.
