# Map Runtime Contract

## Purpose and boundary

This document is the authoritative Phase 07 decision for the Studio-authored
map interface, deterministic validation, and graybox runtime loader. It records
the decision before executable Phase 07 source is implemented.

Phase 07 owns only map metadata, validation, loading, immutable geometry
queries, cleanup, and one primitive graybox battlefield. It does not start the
match lifecycle or add readiness, enemies, waves, towers, combat, placement
gameplay, UI, persistence, matchmaking, monetization, or networking.

The lasting `Maps`, `Difficulties`, and `Waves` catalogs remain frozen and
empty. Phase 07 uses the already established `Ids.MapId`, `Result`,
`Validation`, `Cleanup`, lifecycle, logging/privacy, configuration, and
structural-build contracts without turning the graybox into a production map
catalog entry or an automatically started service.

## Authoritative ownership

- `src/` is authoritative for every script and ModuleScript.
- Studio and Team Create are authoritative for the unmapped map-template
  folder, map models, primitive graybox geometry, markers, tags, and attributes.
- Rojo's Match project remains connected only to the Match place and preserves
  unknown instances at its mapped boundaries.
- A Studio author must never edit a Rojo-managed script, place a lasting script
  in the map template, or use Roblox Script Sync on a Rojo-managed folder.
- The runtime loader is server-only Match source. No client chooses a map ID,
  Instance, tag, template path, catalog root, or mutable object.

## Engine facts that constrain the decision

Roblox tags and attributes are serialized with place content. Tags replicate
as one collection, attributes replicate, and neither is an authorization
boundary. CollectionService's global tagged lookup excludes detached instances
and does not provide root isolation. Instance child/descendant enumeration is
not ordered. Therefore the validator performs a bounded traversal starting at
the one selected root, reads tags on each visited Instance, and explicitly
sorts every traversal input and output. It never calls global `GetTagged()` for
candidate discovery.

`Instance:Clone()` returns a detached root, can return `nil` for a
non-Archivable root, and omits non-Archivable descendants. The loader therefore
preflights the original selected template read-only, requires every visited
Instance to be Archivable, clones it, and independently validates the detached
clone. The runtime root receives its one DataModel parent assignment only after
all validation and immutable query derivation succeed.

A Model's implicit pivot and computed bounding box are not authored region
contracts. Map bounds and placement regions are explicit anchored Parts with
validated CFrames and Sizes. The validator reads but never moves or pivots the
candidate.

Relevant primary documentation:

- [CollectionService](https://create.roblox.com/docs/reference/engine/classes/CollectionService)
- [Instance](https://create.roblox.com/docs/reference/engine/classes/Instance)
- [Model](https://create.roblox.com/docs/reference/engine/classes/Model)
- [PVInstance](https://create.roblox.com/docs/reference/engine/classes/PVInstance)
- [Attributes](https://create.roblox.com/docs/scripting/attributes)
- [Studio Properties and attribute types](https://create.roblox.com/docs/studio/properties)
- [Place files](https://create.roblox.com/docs/projects/place-files)
- [Collaboration and Team Create](https://create.roblox.com/docs/projects/collaboration)
- [Studio testing modes](https://create.roblox.com/docs/studio/testing-modes)

## Fixed roots and names

The only production lookup roots are fixed server constants:

| Purpose | Exact location and class | Ownership |
| --- | --- | --- |
| Trusted templates | `ServerStorage.ATDMapTemplates` (`Folder`) | Studio/Team Create content selected only by server code |
| Active runtime | `Workspace.ATDRuntimeMap` (`Model`) | Created and destroyed only by the server loader |

`ATDMapTemplates` contains at most 32 direct-child map Models and no other
direct children. Selection scans that bounded folder and matches the canonical
`ATD_MapId` attribute; it never selects by child name or a client value. There
must be exactly one catalog root and at most one template with a selected ID.
A missing, duplicate, malformed, or conflicting root or template fails closed.

A template root with MapId `map:<body>` is named exactly `Map_<body>`. Its only
direct children are the exact folders `Geometry` and `Markers`.
`Geometry` contains the Studio-owned primitive map. `Markers` has this exact
hierarchy:

```text
Markers
  EnemySpawns
  PathNodes
  DefenderBase
  PlacementZones
  NoPlacementZones
  MapBounds
  CameraAnchors
  PlayerSpawns
```

The six plural names are Folders. `DefenderBase` and `MapBounds` are Parts.
Every collection member is an immediate child of its role Folder. The same
name may not occur twice under one parent. Names are contractual, ASCII, and at
most 100 bytes:

| Role | Exact name |
| --- | --- |
| Enemy spawn | `EnemySpawn_<LaneId>` |
| Path node | `PathNode_<LaneId>_<NodeOrder>` |
| Placement zone | `PlacementZone_<ZoneId>` |
| No-placement zone | `NoPlacementZone_<ZoneId>` |
| Camera anchor | `CameraAnchor_<AnchorId>` |
| Player spawn | `PlayerSpawn_<SpawnId>` |

`LaneId`, `ZoneId`, `AnchorId`, and `SpawnId` use
`Validation.isSymbolicKey`: 1–64 bytes of lowercase ASCII letters or digits,
with only single internal `.`, `-`, or `_` separators. Identity comes from the
typed attribute, not from `FindFirstChild()` or `GetFullName()`; the exact name
is an independently validated authoring guard.

## Fixed tags and attributes

All Phase 07 metadata uses the reserved `ATD_` prefix. An unknown `ATD_` tag or
attribute anywhere under the selected map root is invalid. An Instance may
carry at most one semantic map tag. Known tags on an unapproved Instance,
under the wrong role folder, or combined with another semantic tag are invalid.
Duplicate tag entries are invalid even when their strings match. Every tag is
1–100 bytes and matches `^[A-Za-z][A-Za-z0-9_.-]*$`; malformed tag strings are
rejected. Non-`ATD_` metadata belongs to other Studio systems and is ignored
after its bounded name/type inventory is checked.

| Role | Exact tag | Exact allowed `ATD_` attributes | Exact class |
| --- | --- | --- | --- |
| Map root | `ATD_MapRoot_v1` | `ATD_MapId: string`, `ATD_MapContractVersion: number` | `Model` |
| Enemy spawn | `ATD_EnemySpawn_v1` | `ATD_LaneId: string` | `Part` |
| Path node | `ATD_PathNode_v1` | `ATD_LaneId: string`, `ATD_NodeOrder: number` | `Part` |
| Defender base | `ATD_DefenderBase_v1` | none | `Part` |
| Placement zone | `ATD_PlacementZone_v1` | `ATD_ZoneId: string` | `Part` |
| No-placement zone | `ATD_NoPlacementZone_v1` | `ATD_ZoneId: string` | `Part` |
| Map bounds | `ATD_MapBounds_v1` | none | `Part` |
| Camera anchor | `ATD_CameraAnchor_v1` | `ATD_AnchorId: string` | `Part` |
| Player spawn | `ATD_PlayerSpawn_v1` | `ATD_SpawnId: string` | `SpawnLocation` |

`ATD_MapId` must pass `Ids.validateMapId` and equal the server-selected MapId.
`ATD_MapContractVersion` is the finite safe integer `1` exactly.
`ATD_NodeOrder` is a finite integer from 1 through 256. String IDs follow the
symbolic-key rule above. Booleans encoded as numbers, numeric strings,
unsupported attribute datatypes, NaN, infinities, and fractional node orders
are rejected rather than coerced.

The template root carries only its root semantic tag. Each marker carries only
its own semantic tag. Contract folders and `Geometry` carry no semantic map
tag and no reserved attribute.

## Classes, safety, and ancestry

All visited Instances must be Archivable so cloning cannot silently drop
content. Map templates contain no `LuaSourceContainer`, RemoteEvent,
RemoteFunction, BindableEvent, BindableFunction, executable code, or other
runtime dispatch surface. Phase 07 `Geometry` is deliberately primitive: its
descendants may be only Folder, Model, Part, WedgePart, CornerWedgePart,
TrussPart, MeshPart, UnionOperation, Decal, Texture, or SurfaceAppearance.
Expanding that allowlist for production art is a future reviewed contract
change, not an authoring exception.

Every marker has exactly the class and immediate ancestry in the tables above.
Every marker is a leaf with zero children. Each contract Folder contains only
the exact child kinds assigned to it: the root contains only `Geometry` and
`Markers`, `Markers` contains only its six exact collection Folders and two
singleton Parts, and each collection Folder contains only its exact marker
class. Every Instance outside `Geometry` is therefore one of the explicitly
listed root, Folder, or marker definitions; every other class or descendant is
rejected. A Geometry Model `PrimaryPart`, when set, must point inside the
selected root; external Instance references are invalid. The allowlist
otherwise contains no reference-bearing constraint or value objects,
preventing a staged clone from retaining writable links to the template or
unrelated content.

The lasting Phase 07 graybox uses the stricter `Folder`, `Model`, and `Part`
subset under `Geometry`. Meshes, unions, decals, textures, surface appearances,
terrain, effects, and production-art assets are not allowed through the 07.4
Studio gate even though a later reviewed map can use the wider runtime
allowlist.

## Cardinality and work limits

Limits are technical safety ceilings, not balance or production-content
targets:

| Scope | Required range |
| --- | ---: |
| Catalog templates | 0–32 |
| Selected-root descendants | 10–2,048 |
| Traversal depth below selected root | 0–32 |
| Immediate children of one visited Instance | 0–512 |
| Tags on one Instance / across selected root | 0–8 / 0–4,096 |
| Attributes on one Instance / across selected root | 0–16 / 0–8,192 |
| Validator issues returned | 0–256 |
| Lanes / enemy spawns | 1–32, exactly one spawn per LaneId |
| Path nodes per lane | 1–256, contiguous orders starting at 1 |
| Path nodes across the map | 1–1,024 |
| Defender base | exactly 1 |
| Map bounds | exactly 1 |
| Placement zones | 1–64 |
| No-placement zones | 1–64 |
| Camera anchors | 1–16 |
| Player spawns | 1–4 |

Lane, zone, anchor, and player-spawn IDs are unique in their own domains.
Every node LaneId must resolve to one enemy spawn. Duplicate attributes,
duplicate names, duplicate NodeOrders, missing orders, unknown lanes, and
excess collections are rejected.

Traversal is an explicit bounded walk, not an unrestricted `GetDescendants()`
followed by a late count. Every tag string and attribute name is additionally
limited to 100 bytes. Only the fixed reserved string values are copied;
unreserved attribute values are ignored after their key and `typeof` are
counted. Exceeding a per-Instance, map-total, byte, traversal, depth, or child
limit returns one deterministic root issue and suppresses dependent checks.

After a bounded unordered collection pass, validation sorts snapshots before
creating ordinary issues. The exact member key is: fixed role rank; valid
semantic ID or empty string; valid NodeOrder or zero; safe contractual Name or
empty string; ClassName; sorted reserved tag strings; sorted reserved attribute
`name/typeof/value` tuples; then the validation-relevant CFrame, Size, and
boolean property tuple. Number keys use the exact tokens `nan`, `-inf`, `+inf`,
or a 17-significant-digit finite representation. Strings are length-prefixed.
No Instance identity, debug string, hash-table order, or full DataModel path is
used. Marker leaves that tie on every validation-relevant field deliberately
share one canonical malformed path; swapping them cannot change the issue
multiset. Geometry diagnostics use their safe root-relative name/class path,
and duplicate indistinguishable paths likewise share a path rather than receive
engine-order ordinals.

## Geometry contract

Every BasePart under the selected root must have a finite CFrame, an absolute
position component no greater than 100,000 studs, and a finite, strictly
positive Size whose component is at most 4,096 studs. All BaseParts are
anchored. Semantic point markers have Size components from 0.1 through 64
studs. Semantic markers other than player spawns have `CanCollide`, `CanTouch`,
and `CanQuery` false. Player spawns are enabled, neutral, anchored
SpawnLocations. Positions are always derived from the validated
`BasePart.CFrame.Position`, never from a separately read or authored `Position`
property. The root Model pivot is not a contract input and is neither moved nor
queried. The validator does not call `GetPivot()`, `GetBoundingBox()`, or infer
bounds from a Model pivot.

The explicit `MapBounds`, placement-zone, and no-placement-zone Parts accept
only identity world rotation: each element of their CFrame rotation matrix must
be within `1e-6` of the corresponding identity-matrix element. The other 23
axis-aligned rotations are not accepted. Each region size component is from
0.1 through 4,096 studs; the map-bounds components are each at least 1 stud.
Point markers—the enemy spawns, path nodes, base, camera anchors, and player
spawns—must lie inside or on MapBounds. Every Geometry BasePart and every
placement/no-placement box must be wholly inside or on MapBounds. Containment
uses all eight corners transformed into the containing Part's object space with
the scale-aware tolerance `max(1, halfExtent) * 1e-6` per axis.

Placement zones may not overlap other placement zones. No-placement zones may
not overlap other no-placement zones and must be wholly contained by exactly
one placement zone. For overlap on one axis, positive overlap must exceed
`max(1, leftHalfExtent, rightHalfExtent) * 1e-6`; all three axes must have
positive overlap. Boundary contact within that tolerance is allowed and is not
positive-volume overlap.

For each lane, the route is:

```text
enemy spawn -> NodeOrder 1 -> ... -> NodeOrder N -> defender base
```

Every segment uses the Euclidean distance between finite positions. Its length
must be at least 0.01 studs and at most 512 studs. A shorter segment is
zero-length for this contract; a longer segment is disconnected. Total lane
length must be finite, positive, and at most 32,768 studs. Loader cumulative
distances begin at 0 for the enemy spawn and increase through every node to the
base. Lane order is lexical LaneId order and node order is numeric NodeOrder.
The Phase 07 graybox additionally proves at least one genuine non-collinear
bend. For consecutive normalized segment vectors, the cross-product magnitude
must be at least `sin(5 degrees)`; later map validation does not require every
lane to bend.

## Deterministic validator result

Validation never mutates the candidate. It copies tag lists, attribute keys,
child lists, marker values, and geometry into detached records. Success returns
a frozen `Result.ok` containing only canonical MapId, immutable Roblox value
types, numbers, strings, and deeply frozen arrays/records—never an Instance.
Failure returns a frozen `Result.err` report containing a deeply frozen issue
array built with the shared `Validation.Issue` shape.

Diagnostics use fixed root-relative paths such as
`Map.Markers.PathNodes[2].ATD_NodeOrder`; they never contain a DataModel path,
raw unsafe Instance name, attribute value, caught error, template object, or
client value. Roles are ordered by the contract-definition table. Members are
ordered by validated ID/order and then a bounded structural key. Final issues
are stable-sorted by canonical path, fixed code rank, related path, and fixed
message. Equivalent input produces byte-identical issue order regardless of
engine enumeration.

Invalid definitions are reported comprehensively where safe. A structural
failure suppresses dependent geometry checks for that Instance so one malformed
field does not cause unordered cascades. All discovery and issue counts are
bounded. Validation generates issues only after the bounded snapshots are in
canonical order. If more than 256 would be produced, the returned list contains
the first 255 in canonical order plus a fixed final `OUT_OF_RANGE` issue at
`Map.issues`; no engine enumeration can affect truncation.

### Exact detached snapshot types

The validator success value has this conceptual strict type; every record,
array, and lookup is copied and frozen:

```luau
type PointSnapshot = { cframe: CFrame, position: Vector3 }
type NodeSnapshot = { order: number, cframe: CFrame, position: Vector3 }
type RegionSnapshot = { id: string, cframe: CFrame, size: Vector3 }
type NamedPointSnapshot = { id: string, cframe: CFrame, position: Vector3 }
type LaneSnapshot = {
    id: string,
    spawn: PointSnapshot,
    nodes: { NodeSnapshot },
}
type ValidatedMapSnapshot = {
    mapId: Ids.MapId,
    base: PointSnapshot,
    bounds: { cframe: CFrame, size: Vector3 },
    lanes: { LaneSnapshot },
    placementZones: { RegionSnapshot },
    noPlacementZones: { RegionSnapshot },
    cameraAnchors: { NamedPointSnapshot },
    playerSpawns: { NamedPointSnapshot },
}
```

The validator returns
`Result.Result<ValidatedMapSnapshot, MapValidationReport>`, where the report is
`{ issues: { Validation.Issue } }`. It exposes no Instance-bearing alternate
view.

## Loader state, staging, and cleanup

One frozen public loader handle is backed by private weak-key state. Its states
are `Idle`, `Loading`, `Loaded`, `Unloading`, `Cleaned`, and terminal `Failed`.
Public operations are synchronous and do not yield.

`load(mapId)` performs this exact transaction:

1. require `Idle` and validate the typed `Ids.MapId`;
2. resolve exactly one `ServerStorage.ATDMapTemplates` Folder;
3. bounded-scan its direct children and select exactly one matching authenticated
   template by `ATD_MapId`;
4. read-only validate the original template, including Archivable coverage;
5. reject any existing direct `Workspace.ATDRuntimeMap` child without modifying it;
6. clone the template detached and immediately register the clone in a fresh
   Cleanup container;
7. independently validate the detached clone and derive the detached cumulative
   lane snapshot;
8. rename only the staged clone to `ATDRuntimeMap` and repeat the destination
   conflict check; and
9. publish with the clone's one final `Parent = Workspace` assignment, then
   enter `Loaded`.

Every failure before publication destroys the staged clone through Cleanup,
clears the per-load snapshot and all template/staged references, and returns to
`Idle`. A rollback failure is terminal `Failed`. Rejected loads publish no
Instance or query state. Existing conflicting roots are never destroyed.

`unload()` is idempotent in `Idle`; in `Loaded` it clears public query state,
runs the per-load Cleanup container, clears all retained references, and returns
to `Idle`. `cleanup()` performs the same release when needed and then enters
terminal `Cleaned`; repeated cleanup is idempotent. Load after cleanup,
duplicate load, and any operation observed during `Loading` or `Unloading` are
rejected with a frozen privacy-safe error and no mutation. Load/unload/reload
creates a fresh clone, snapshot, and Cleanup container each time.

The public query API returns the deeply frozen detached snapshot or one lane by
typed LaneId. It never returns the catalog root, template, runtime Model,
markers, mutable caches, Cleanup container, or connections. A caller may retain
an old detached snapshot after unload, but it has no Instance reference and
cannot affect a later load.

The runtime query shapes are exact:

```luau
type RoutePointKind = "EnemySpawn" | "PathNode" | "DefenderBase"
type RoutePointSnapshot = {
    kind: RoutePointKind,
    nodeOrder: number?,
    cframe: CFrame,
    position: Vector3,
    distance: number,
}
type RuntimeLaneSnapshot = {
    id: string,
    totalDistance: number,
    points: { RoutePointSnapshot },
}
type RuntimeMapSnapshot = {
    mapId: Ids.MapId,
    base: PointSnapshot,
    bounds: { cframe: CFrame, size: Vector3 },
    lanes: { RuntimeLaneSnapshot },
    placementZones: { RegionSnapshot },
    noPlacementZones: { RegionSnapshot },
    cameraAnchors: { NamedPointSnapshot },
    playerSpawns: { NamedPointSnapshot },
}
```

`load(mapId: unknown)` returns `Result<RuntimeMapSnapshot, LoaderError>`;
`getSnapshot()` returns the same Result type; `getLane(laneId: unknown)` returns
`Result<RuntimeLaneSnapshot, LoaderError>`; `unload()` returns
`Result<boolean, LoaderError>` (`true` when one map was removed and `false` for
an already-Idle loader); `cleanup()` returns `Result<boolean, LoaderError>` and
is idempotent; and `getState()` returns the fixed loader state. All are
synchronous.

`LoaderError` is a deeply frozen `{ code, operation, state, validationReport? }`
record with a fixed code from `INVALID_MAP_ID`, `INVALID_LANE_ID`,
`INVALID_STATE`, `NOT_LOADED`, `CATALOG_ROOT_MISSING`,
`CATALOG_ROOT_CONFLICT`, `CATALOG_LIMIT_EXCEEDED`, `TEMPLATE_NOT_FOUND`,
`TEMPLATE_DUPLICATE`, `TEMPLATE_INVALID`, `RUNTIME_ROOT_CONFLICT`,
`CLONE_FAILED`, `LANE_NOT_FOUND`, `CLEANUP_FAILED`, or `ROLLBACK_FAILED`.
It contains no authored value, raw Instance name/path, or caught error. Unknown
LaneIds and queries while Idle return `LANE_NOT_FOUND` and `NOT_LOADED`
respectively. Except repeated `cleanup`, operations after `Cleaned` and all
operations during transitional or `Failed` states return `INVALID_STATE`.

## Studio persistence gate

The exact authorized place is the restricted Match place, PlaceId
`136401514513678`, owned by Roblox group PHJGAMES (`CreatorId 35420107`). Only
`match.project.json` may be connected during Packet 07.4.

Team Create can save Edit-mode changes automatically, so "unsaved" verification
must not begin by authoring lasting Edit-mode content. Before the persistent
step, Studio must prove that save persistence is manual and controllable for the
focused session. If Team Create auto-persistence is active or its state cannot
be verified without changing experience settings, stop and ask; Phase 07 does
not authorize changing that setting. The required order is:

1. confirm `game.PlaceId == 136401514513678`, group CreatorType and CreatorId,
   the visible PHJGAMES owner, Edit mode, and the Match-only Rojo connection;
2. capture a bounded before inventory and source hashes for the Rojo-managed
   script containers;
3. in Studio Test/Run mode, construct the Phase 07 fixture under the trusted
   root, run validate/load/query/unload/reload/cleanup, and Stop so the candidate
   is discarded;
4. confirm the Edit-mode inventory and Rojo-managed sources are unchanged;
5. construct the complete lasting subtree detached from the DataModel, validate
   it read-only, and compare its canonical inventory to the proposed exact
   after delta;
6. only in the verified manually controlled session, publish the complete
   detached subtree with one parent-last Edit-mode assignment, immediately
   capture the actual after inventory, and verify the delta contains only
   `ServerStorage.ATDMapTemplates.Map_phase07-graybox`, its contract children,
   and the required SpawnLocation; if it differs, remove only the just-added
   unsaved subtree and stop;
7. validate the lasting content read-only, then use the user's one controlled
   save/publish authorization for this exact place; and
8. reopen/confirm the saved subtree, rerun the focused read-only/load cleanup
   smoke check if persistence changed representation, disconnect/stop the Rojo
   session, and leave Studio in Edit mode.

If identity, ownership, isolation, before/after inventory, collaborator state,
or save scope is uncertain, do not make the Edit-mode change and do not save.
The authorization does not make the experience public or permit settings,
services, Lobby content, or unrelated assets to change.

## Future map authoring procedure

1. Start from the exact hierarchy, tags, attributes, names, classes, and limits
   in this document; do not copy scripts into a template.
2. Assign a new canonical server-owned MapId. Do not accept the ID or an
   Instance from a client and do not select by model name.
3. Author only under the fixed trusted Match-place folder. Keep all contract
   markers anchored, finite, bounded, and root-scoped.
4. Run the deterministic validator while detached or in Test mode. Resolve all
   issues in canonical order.
5. Exercise load, immutable queries, unload, reload, rollback, and cleanup with
   no partial `Workspace.ATDRuntimeMap` residue.
6. Compare exact before/after inventories and Rojo source hashes. Obtain fresh
   authorization for any persistent Studio edit or save not already covered.
7. Add a production catalog/config binding only in the later roadmap packet
   that owns that content; Phase 07's graybox does not pre-authorize one.

## Review and evidence status

- Architecture decision recorded: 2026-08-26, before Phase 07 source work.
- Single targeted architecture review: completed 2026-08-26; all two P1 and
  four P2 material findings resolved in this record before source work.
- Packet 07.1 implementation/tests: pending.
- Packet 07.2 validator/tests: pending.
- Packet 07.3 loader/tests: pending.
- Packet 07.4 Match Studio gate and controlled persistence: pending.
- Consolidated review and Phase 07 exit gate: pending.
