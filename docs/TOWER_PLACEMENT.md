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
authority. A valid first revision observed before any snapshot is an explicit
bootstrap signal: the reducer marks refresh required and the controller issues
one authenticated query. Later advanced revisions received while that query is
pending set one queued refresh, so an early rejected query cannot strand the
client and a burst cannot create unbounded requests. Future revisions and
revisions more than four commits behind are
rejected; a lag of at most four is admitted so up to four clients can submit
non-overlapping intents from the same snapshot. Every such intent is still
recomputed against current committed and reserved footprints. MatchId and
loadout revision must always match exactly.

The Match composition wraps its existing authenticated lifecycle snapshot
sender. After a canonical `PreWave` or `WaveActive` snapshot is delivered to one
recipient, the wrapper delivers the current placement revision to that same
recipient through the registered reliable event. `Loading` and `ReadyCheck`
snapshots do not emit a placement revision. This production lifecycle transition
is the source of initial recovery; the Studio-only `Refresh` evidence operation
is diagnostic and is neither required nor called by the production path.

`GetTowerPlacementQuery` has an exact empty payload. Its detached, deeply
frozen result contains only:

- contract version, MatchId, MapId, query revision, and the caller's temporary
  loadout revision;
- MapBounds;
- at most 24 placement zones with CFrame, Size, and surface category;
- at most 24 exclusion boxes;
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
- The bottom panel respects Roblox GUI insets, keeps 12-pixel horizontal margins,
  caps at 700 pixels, and scales every horizontal child proportionally. Its
  five slot targets remain at least 44 pixels wide at the supported 375-pixel
  phone viewport, while the tablet and desktop layouts retain the capped width.
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
Technical ceilings are four active participants, five slots, 24 query zones,
24 exclusions, 128 committed footprints, 32 active towers per owner, four
accepted stale-revision distance, one operation/reservation per synchronous
admission, and bounded linear validation work over those collections.

Disconnect, spectator state, Results/Closing, defeat, dependency fault, cleanup,
late response, and re-entry close admission. Cleanup revokes reservations and
placeholder tokens, clears revisions/caches/metrics, disconnects publication
ownership through the normal network lifecycle, and rejects late work. Client
cleanup additionally leaves no hotbar, hint, confirmation UI, ghost, range
indicator, binding, connection, pending request, cache, or preview folder.

Two lifecycle-owned evidence triggers exist only when `RunService:IsStudio()`:
the server trigger can publish one current revision or return bounded placement
metrics, while the client trigger accepts only diagnostics and the exact
gamepad operations `CycleNext`, `CyclePrevious`, `Axis`, `Rotate`, `Confirm`,
and `Cancel`. Axis components are finite and limited to `[-1, 1]`; extra fields
and every other operation fail closed. The triggers expose no production
remote, authority, arbitrary callback, or source mutation. Server and client
shutdown detach and destroy them before clearing owned placement state.

## Executed Studio evidence — 2026-08-30

All scenarios used the exact unsaved Match place named
`fishytiger7's Place: 08252026_1`: PlaceId `136401514513678`, GameId
`10757629094`, Group CreatorId `35420107`. The separately open place at
PlaceId `100561454756026` was untouched. Studio/MCP connection IDs are
transient; the stable place, universe, creator, role, and byte-identical Rojo
source determined the target.

- Desktop/exploit session MatchId
  `match:bf10b8c2-3e1a-4c26-a788-e1a9a862e926` activated the Primary fixture
  in `0.0040514s`; the bounded Studio evidence operation then explicitly
  refreshed query revision `1` in `0.0001231s`. Actual hotbar, pointer, `R`,
  `Q`, and click input proved valid, exclusion-blocked, unaffordable, capped,
  `15°` rotation, cancel, and placement presentation. This session proves the
  interaction scenarios; the final-source run below separately proves that
  production bootstrap recovery does not depend on that Studio operation.
- The same-position race at `(-20, 35)` used request IDs
  `p13e-race-n2-0001` and `p13e-race-n1-0001`: RuntimeTowerId `2` committed in
  `0.0507238s`, while the peer received `Occupied` at revision `3` in
  `0.0495762s`. Independent simultaneous requests both committed, followed by
  a fifth valid tower. Both clients converged on five models/126 descendants;
  prepare/commit were exactly `5/5`, abort/outstanding/reservations were zero,
  and publication was `6/0` success/failure.
- Stale, future-revision, capped, unaffordable, outside-bounds, partial-zone,
  exclusion, wrong-Match, and empty-slot domain attempts rejected safely.
  Extra-key, NaN, infinity, oversized, and pitch/roll payloads failed exact
  validation; duplicate `p13e-replay-n1-0001` returned `STALE_REQUEST`. Each
  client's eight-request burst produced exactly three domain receipts and five
  `RATE_LIMITED` responses. After the late post-cleanup request, accepted/
  rejected placement counts were `5/18`; query counts were `15/2` accepted/
  rejected before cleanup.
- iPad Pro M5 (13-inch), `1375x1032`, LandscapeLeft proved a camera drag did
  not position or submit; a separate tap positioned, Rotate reached `15°`,
  Cancel cleared, and a new tap plus the visible Confirm button placed one
  Support tower at `(44.9873, 0, 40.0126)`. Both clients replicated one model,
  with prepare/commit `1/1` and zero rejection/reservation/outstanding state.
- Xbox One, `1919x1079`, showed the gamepad hint and centered bottom layout
  without clipping. The bounded Studio-only input evidence path exercised the
  same controller actions used by Gamepad1: slot cycling, axis-driven reticle
  movement from `(1, 1)` to a valid `(877, 552)`, explicit `15°` rotate,
  cancel with no placement, reselection, confirm, and successful placement.
  MatchId `match:af96c9ce-1900-47ea-b2bc-1bc82456fece` assigned
  RuntimeTowerId `1` at `(12.0139, 0, 38.3514)`; both clients replicated one
  28-instance tower tree. Each controller retained eight connections and one
  Studio trigger; server prepare/commit were `1/1`, with zero abort,
  reservation, rejection, or publication failure.
- Final-source natural-bootstrap MatchId
  `match:e6120c59-0ade-4498-91cf-7ae4f927eabb` used two iPhone 17 Pro
  LandscapeLeft clients. Before activation, the server recorded zero accepted
  and two rejected placement queries at revision `1`. The authoritative
  `PreWave` lifecycle publication delivered one placement-revision event to
  each client without invoking `Refresh`; both clients issued exactly one
  bounded retry and populated their loadouts. Final counts were two accepted/
  two rejected queries, two requests and one revision event per client,
  `studioRefreshCount=0`, and zero placement-publication failures. The runtime
  ScreenGui reported `CoreUISafeInsets`, clipping enabled,
  `SafeAreaCompatibility.None`, a `750x303` safe canvas, a centered `700x154`
  panel at `(25, 131)`, and `90x90` slots; no control or text crossed the
  Dynamic Island or bottom safe boundary.
- Explicit Tower cleanup returned all-zero runtime/loadout/model/capability/
  observer/connection residue in `0.0015286s` for the desktop session and
  `0.0006657s` for Xbox; the final natural-bootstrap recheck also returned all
  eleven residue counts as zero. The desktop late request rejected
  `Unavailable`. Accepted sessions had no console errors; clients had no
  warnings, and the server emitted only bounded expected bootstrap/protocol
  aggregates. All clients/servers stopped, emulation reset through
  `StopSimulationAsync()` to device `default` and `LandscapeLeft`, and the
  final Edit probe found eight persistent Workspace descendants with no
  runtime map, tower root, preview, or evidence trigger. Nothing was saved or
  published.

## Consolidated review — 2026-08-30

The single bounded independent reviewer found no Phase 14 scope expansion and
identified four completion gaps. The production client could remain stranded
after its pre-activation query, the structural TowerRuntime allowlist omitted
`getPlacementView`, the reducer's revision-apply type omitted `Bootstrap`, and
the map document confused the 24-record query ceiling with the 64-record
authoring ceiling. The fixes add lifecycle-authenticated initial revision
delivery, authenticate the thirteenth TowerRuntime method in every structural
build, complete the reducer type, and state both map bounds accurately. The
same closure pass also added a bounded responsive phone layout and explicit
safe-area properties. Focused controller, view, reducer, placement-service,
and structural-source checks pass after the fixes; the complete exit gate is
recorded only after it runs.

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
