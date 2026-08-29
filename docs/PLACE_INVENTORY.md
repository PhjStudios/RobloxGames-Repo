# Ant Tower Defense — Roblox Place and Test-Environment Inventory

## Purpose

This document records the verified Roblox place configuration, ownership
evidence, supported-platform target, test strategy, Studio-authored assets, and
safe DataStore testing approach for Packet 00.3 of
`docs/DEVELOPMENT_PLAN.md`.

It contains no credentials, authentication data, reserved-server codes, API
keys, cookies, or secrets.

## Inventory status

- Recorded: 2026-08-25
- Packet: 00.3
- Status: Complete
- Ownership confirmation: PHJGAMES, Roblox Group ID `35420107`
- Gameplay code changed: no
- Roblox Studio content changed: no
- Roblox publishing authorized: no

Those fields record Packet 00.3. The exact Match identity was reconfirmed for
the unsaved Phase 12 two-client primary and defeat gates on 2026-08-28. Only
mapped branch source and runtime-created evidence objects changed during Play;
Studio-authored content remained untouched and unsaved.

## Evidence sources

### Local repository

- `default.project.json`
- Git remote configuration
- Current repository file inventory
- `docs/GAME_DESIGN.md`
- `docs/DEVELOPMENT_PLAN.md`

### Roblox public metadata

- Place-to-universe endpoint:
  `https://apis.roblox.com/universes/v1/places/100561454756026/universe`
- Universe metadata endpoint:
  `https://games.roblox.com/v1/games?universeIds=10757629094`

The public metadata was checked on 2026-08-25. The experience is restricted, so
Roblox returned placeholder title/creator values rather than the exact group
identity. An unauthenticated Creator Dashboard session could not expose private
ownership details.

## Verified current Roblox identifiers

### Lobby/development PlaceId

- PlaceId: `100561454756026`
- Evidence: `default.project.json` under `servePlaceIds`
- Role-isolated Rojo project: `lobby.project.json`; it declares the `Lobby` role
  while the shared Packet 02.3 configuration owns the runtime PlaceId
- Public API verification: the PlaceId resolves to universe `10757629094`
- Intended role: Lobby/start place
- Confirmed as the universe root/start place: no; private dashboard verification
  is still required

This is the only PlaceId allowlisted by `servePlaceIds`, which exists only in the
combined development project. The isolated Lobby and Match project definitions
intentionally contain no place allowlist and are connected one at a time. The
combined Rojo project name is `Ant Tower Defense`.

### Universe/experience ID

- Universe ID: `10757629094`
- Evidence: Roblox public place-to-universe endpoint
- Public visibility: restricted/content-restricted
- Public creator type: Group
- Public creator name/ID: withheld as placeholder values; confirmed separately by
  the user below

### Match PlaceId

- Current configured Match PlaceId: `136401514513678`
- Current display name: `fishytiger7's Place: 08252026_1`
- Verified universe: `10757629094`
- Verified owner: PHJGAMES, Group ID `35420107`
- Matching Rojo project file: `match.project.json`; it declares the `Match` role
  while `src/shared/config/PlaceRoles.luau` owns the runtime PlaceId
- Live isolated Studio gate: passed in Packet 02.4; evidence:
  `docs/MULTI_PLACE_GATE.md`
- Phase 07 map gate identity reconfirmed: PlaceId `136401514513678`, GameId
  `10757629094`, PHJGAMES Group `35420107`, and resolved role `Match`.
- Phase 08 four-client gate identity reconfirmed on 2026-08-27: PlaceId
  `136401514513678`, GameId `10757629094`, CreatorType `Group`, CreatorId
  `35420107`, official Roblox group API name `PHJGAMES`, and resolved
  `ATDPlaceRole = Match`. Exact lifecycle/Ready evidence is in
  `docs/MATCH_LIFECYCLE_READY.md#studio-execution-evidence--2026-08-27`.
- Phase 09 two-client enemy gate identity reconfirmed on 2026-08-27: PlaceId
  `136401514513678`, GameId `10757629094`, CreatorType `Group`, CreatorId
  `35420107`, official Roblox group API name `PHJGAMES`, and resolved
  `ATDPlaceRole = Match`. Exact simulation, replication, renderer, stress, and
  cleanup evidence is in
  `docs/ENEMY_SIMULATION.md#executed-studio-evidence--2026-08-27`.
- Phase 10 two-client defender-base gate identity reconfirmed on 2026-08-28:
  PlaceId `136401514513678`, GameId `10757629094`, CreatorType `Group`, CreatorId
  `35420107`, official owner `PHJGAMES`, and `ATDPlaceRole = Match`. Exact base,
  world-presentation, defeat, and cleanup evidence is in
  `docs/BASE_RUNTIME.md#executed-studio-evidence--2026-08-28`.
- Phase 11 two-client authored-wave gate identity reconfirmed on 2026-08-28:
  PlaceId `136401514513678`, GameId `10757629094`, CreatorType `Group`, CreatorId
  `35420107`, official owner `PHJGAMES`, and `ATDPlaceRole = Match`. Exact
  scheduler, recovery, stress, completion, defeat, and cleanup evidence is in
  `docs/WAVE_RUNTIME.md#executed-studio-evidence--2026-08-28`.
- Phase 12 two-client tower-runtime primary and defeat gate identity
  reconfirmed on 2026-08-28 with the same PlaceId/GameId/Group/owner/role. Exact
  loadout, runtime/model, cap, tamper/recreation, defeat, inventory, and cleanup
  evidence is in
  `docs/TOWER_RUNTIME.md#executed-match-studio-evidence--2026-08-28`.
- Controlled Phase 07 Save To Cloud: succeeded at `2026-08-27T02:11:31Z` under
  the user's exact graybox authorization; it did not change visibility,
  settings, services, Lobby, or unrelated assets.
- Current Edit-mode map state: one exact 25-record
  `ServerStorage.ATDMapTemplates` catalog tree (the catalog folder plus its only
  `Map_phase07-graybox` subtree) and zero `Workspace.ATDRuntimeMap` roots.
  Studio remains in Edit mode.
- The final Phase 08 Edit-mode probe counted `54` ModuleScripts, one Script, one
  LocalScript, and `24` descendants below the map-catalog root. It confirmed the
  exact server/client common `Main` and `ServerBootstrap`/`ClientBootstrap`
  paths and found no runtime map, `ATDNetwork`, Ready GUI, `AutomatedTests`, or
  `TestRunner`. Device emulation was reset, no Server & Clients window remained,
  and no Save or publish occurred.
- The final Phase 09 Edit-mode probe counted the current `63` mapped
  ModuleScripts, one Script, one LocalScript, and the unchanged `24` descendants
  below the map-catalog root. It found no runtime map, enemy visual root,
  placeholder Part, production network root, runtime trigger, Ready GUI,
  automated-test root, timer, queue, snapshot, or cache residue. The task-owned
  Rojo server was stopped, emulation and profiling were reset, all simulated
  windows were closed, and Studio remained in Edit mode. No map, unmapped
  Instance, asset, setting, Lobby content, save, or publish changed.
- The Phase 10 final Edit-mode cleanup probe found the same persistent
  Studio-authored map catalog and no `Workspace.ATDRuntimeMap`, `ATDNetwork`,
  runtime trigger, enemy visual root, base GUI, listener/tween evidence object,
  request state, result seed, ledger, queue, or cache residue. All simulated
  windows were closed, the task-owned Rojo process was disconnected, emulation
  and profiling were reset, and no place was saved or published.

The Match place must:

- Belong to universe `10757629094` for production, or to the separate test
  universe for development testing.
- Not be the public start place.
- Run only common plus match-specific client/server code.
- Accept a maximum of four active match participants.
- Support reserved-server group teleports.
- Admit reward-bearing players only through a valid server-owned match ticket.
- Contain or load Studio-authored map assets.
- Preserve unmapped Studio instances when connected through Rojo.

The placeholder was replaced only after the real ID was verified from the Lobby
place enumeration and authenticated Creator Dashboard. The common bootstraps now
accept this exact pairing and reject other places.

### Unused standalone place

The manual creation workflow also produced a separate PHJGAMES experience:

- Universe ID: `10761692127`
- PlaceId: `113675721965291`
- Display name: `Ant Tower Defense - Match`
- Relationship to Ant Tower Defense: none; it is not in universe `10757629094`
- Repository references: none

Its appealing display name must not be treated as identity evidence. The runtime
resolver correctly rejected this place with `PLACE_ID_MISMATCH`. Deleting or
repurposing it requires separate approval.

## Ownership inventory

### Roblox experience ownership

- Verified owner type: Group
- Exact Roblox group name: `PHJGAMES`
- Exact Roblox group ID: `35420107`
- Group page supplied by the user:
  `https://www.roblox.com/share/g/35420107`
- Confidence: user-confirmed name and ID, consistent with Roblox's public creator
  type of Group; the restricted public experience response still replaces its
  creator ID/name with placeholder values

### GitHub repository ownership

- Remote: `https://github.com/PhjStudios/RobloxGames-Repo.git`
- GitHub organization/account: `PhjStudios`

The GitHub remote is evidence of repository ownership only. It must not be
treated as proof that the Roblox owner group has the same name or identity.

### Ownership requirements

The confirmed Roblox owner/group should own or receive explicit access to:

- Lobby and Match places.
- Test-universe Lobby and Match places.
- Tower and enemy models.
- Map models and environment assets.
- Images and thumbnails.
- Animations.
- Audio.
- Future badges and monetization products.

Assets owned by an individual collaborator should be transferred or explicitly
granted to the experience where Roblox supports it. Asset provenance and
permissions are reviewed again before closed alpha.

## Supported-platform target

The following are development targets from `docs/GAME_DESIGN.md`. They are not
claims that the current Roblox experience settings already enable or pass these
platforms.

### Core supported targets

- Desktop with mouse and keyboard.
- Mobile phone with touch.
- Tablet with touch.
- Gamepad/controller with console-style navigation.

### Deferred

- VR.

### Platform verification requirements

Before a platform is advertised:

- Its Roblox experience setting must be enabled intentionally.
- The complete first-session and match flows must pass the test matrix.
- UI safe areas, text, navigation, camera, placement, tower management, and
  settings must work on that input family.
- Performance must meet the later documented budget on representative hardware.

## Test-environment strategy

### Required topology

Create a separate private Roblox test experience owned by the same confirmed
Roblox group as production.

The test experience should contain:

- Test Lobby place.
- Test Match place.
- The same common/lobby/match Rojo project structure as production.
- Test-only DataStore names/scopes.
- Test-only MemoryStore names.
- No production monetization products.
- No public discovery or unrestricted audience.

### Why a separate universe is required

DataStores and other universe-scoped services are isolated naturally when the
test environment uses a different universe. This reduces the chance that Studio,
development commands, migrations, or failure-injection tests can damage
production player data.

A private place inside the production universe is not sufficient isolation for
profile testing because universe-scoped DataStores are still shared.

### Environment identifiers

When environment configuration is introduced:

- Store public identifiers such as universe and PlaceIds in one server/shared
  configuration location appropriate to their use.
- Do not scatter raw IDs across services.
- Use explicit environment names such as `Development`, `Test`, and `Production`.
- Fail closed when a required environment identifier is missing.
- Never infer production from the client.
- Never store credentials in the repository.

### Testing stages

1. **Pure automated tests**
   - Use deterministic fixtures and in-memory adapters.
   - Do not call Roblox DataStore or MemoryStore services.
2. **Studio gameplay tests without persistence**
   - Use server-owned in-memory profiles.
   - Exercise match and UI behavior without backend writes.
3. **Studio persistence tests in the test universe**
   - Enable Studio API access only for the private test universe.
   - Use explicit test store names and designated test accounts.
4. **Published private test-universe tests**
   - Required for real TeleportService, reserved servers, party travel, reconnect,
     and staggered arrival.
   - Publishing still requires explicit user approval.
5. **Production validation**
   - Occurs only at a later release gate.
   - Never includes destructive profile experiments.

## Safe DataStore testing policy

### Approved strategy

- Do not use universe `10757629094` for routine Studio DataStore tests.
- Keep Studio API access disabled for the production universe.
- Enable Studio API access only in the separate private test universe.
- Use different DataStore names for test and production even though universes
  already isolate them.
- Include schema versioning in stored profiles.
- Use only designated test UserIds for destructive migration/failure tests.
- Prefer in-memory adapters until Phase 19 introduces ProfileService.

Recommended logical names when persistence is implemented:

- Test profiles: `ATD_Profile_Test_v1`
- Production profiles: `ATD_Profile_Prod_v1`

These are provisional names, not DataStores created by this packet.

### Prohibited actions

- Never enable Studio API access on production merely for convenience.
- Never test profile wipes against production.
- Never use a blank writable fallback when profile loading fails.
- Never place a broad wipe command in ordinary production server code.
- Never copy raw production profiles into documentation, logs, or fixtures.
- Never treat client-provided environment, profile, or store names as trusted.

### Future safe tooling requirements

Any test-data reset or migration tool must:

- Be restricted to Studio or the explicitly configured test universe.
- Require an exact DataStore name and exact test UserId.
- Display/log the resolved environment and target before mutation.
- Reject production identifiers.
- Avoid globs, ranges, or all-player operations.
- Receive its own review before use.

## Studio-authored asset inventory

The following assets remain authoritative in Roblox Studio/Team Create and are
not created by Rojo-managed scripts.

### Lobby place

- Terrain and environment geometry.
- Player spawn locations.
- Physical queue squares/elevators and their visible models.
- World-space queue display anchors.
- Inventory, chest, tutorial, and other interaction-station models.
- Lobby camera anchors and cinematic viewpoints.
- Lighting, atmosphere, and non-scripted decorative effects.
- Unmapped NPC, prop, and decoration instances.

### Match place and maps

- Phase 07 currently owns one primitive graybox template under the fixed
  `ServerStorage.ATDMapTemplates` folder. It contains one genuinely bent lane,
  enemy spawn, ordered nodes, defender base, placement/no-placement regions,
  bounds, camera anchor, player SpawnLocation, and primitive geometry.
- Map terrain and environment geometry.
- Ant nest/enemy spawn markers.
- Ordered lane/path markers.
- Defender base and endpoint marker.
- Phase 10 uses the existing real `DefenderBase` Part read-only as a BillboardGui
  Adornee. The GUI, bar, numeric text, `LOW` label, and damage pulse are
  client-created repository-owned presentation and are never saved beneath the
  runtime map.
- Tower placement and no-placement regions.
- Map bounds.
- Player spawn/spectator locations.
- Match camera anchors.
- Lighting and environment presentation.
- Map-specific decoration and collision geometry.

### Towers and enemies

- Tower models and upgrade visual variants.
- Tower pivots, aiming parts, muzzle/effect attachment markers, and footprints.
- Enemy models, rigs, pivots, scale, and health-bar attachment markers.
- Boss models and presentation anchors.
- Animations uploaded with appropriate ownership/permissions.

Those bullets describe future Studio/Team Create authority, not current
production content. Phase 12 created only runtime-owned graybox Models from
fresh authenticated Studio/test fixtures. They were never saved, published, or
placed under `ServerStorage.ATDMapTemplates`; production `Assets` and `Towers`
remain empty and no uploaded model, mesh, image, animation, sound, or asset ID
was introduced.

### Media and presentation assets

- Images, icons, portraits, thumbnails, and decals.
- Audio and music.
- Animation assets.
- Particle textures and other imported visual assets.

The repository records IDs and metadata when code needs them, but the uploaded
assets remain under Roblox ownership/permission controls.

## Rojo-authored source inventory

The following remain authoritative in the repository:

- Server and client scripts.
- Shared types and immutable content definitions.
- Remote names and network contracts.
- Configuration validation.
- UI behavior and code-created UI components.
- Profile, inventory, queue, match, wave, enemy, tower, combat, economy, reward,
  and analytics logic.
- Development logging and diagnostics.
- Automated tests and fixtures.

Lasting edits to Rojo-managed scripts must never be made in Studio. Roblox Script
Sync must never be used on Rojo-managed folders.

## Manual Roblox tasks and timing

### Needed before Phase 02's Studio gate

- Complete — owner, Lobby, and Match identities are verified.
- Complete — the correct isolated project was connected to each place.
- Complete — both places passed client/server boot and source-isolation checks.

### Needed before persistence and published-service testing

- Create a separate private test experience under the same owner.
- Create Test Lobby and Test Match places.
- Record their universe and PlaceIds without credentials.

The separate test universe remains unavailable. It is required before Phase 19
persistence/destructive backend testing and before the Phase 26 published-client
teleport gate, but none of the completed Phases 03-05 required that private
Roblox environment.

### Phase 07 graybox map gate

- Complete in the existing restricted Match place under the specific user
  authorization. The exact added-only inventory was 25 records; no unrelated
  or Rojo-managed Instance changed, and no runtime clone remains.
- This Studio-owned template is not a `Maps.luau` production catalog entry and
  does not substitute for the still-unavailable separate private test universe.

### Phase 09 enemy simulation gate

- Complete in the exact restricted Match place on 2026-08-27 under the user's
  active Team Create and Rojo authorization for mapped current-branch source.
- The real saved Phase 07 five-point bent lane was consumed read-only through the
  detached runtime snapshot. No additional lane, map marker, model, production
  enemy content, asset ID, or Studio-authored enemy was created or saved.
- Runtime-only server triggers and measurement objects were discarded with the
  session. The delayed-bootstrap recovery, two-client convergence, endpoint,
  visual recreation, `1/32/64/128` stress ladder, constant connection counts,
  profiling, and residue checks are recorded in
  [Enemy Simulation and Replication](ENEMY_SIMULATION.md#executed-studio-evidence--2026-08-27).

### Phase 10 defender-base gate

- Complete in the restricted Match place on 2026-08-28. Focused and exact
  unsaved Studio evidence, consolidated review, the `593`-case local gate, and
  all four structural builds pass; exact-final-SHA CI is cited at handoff.
- Runtime-only validated difficulty/enemy fixtures initialized the otherwise
  dormant base service and drove only the evidence-only PreWave -> WaveActive
  seam. No production catalog, difficulty selection, wave, cadence, boss
  metadata, model, asset, marker, or balance content was created.
- Both clients converged on the authenticated world marker and base state;
  zero/ordinary/low/exact/overkill/high leaks, recovery, UI/marker recreation,
  one defeat/Results transition, spawn closure, ordered enemy cleanup, timing,
  constant connections, and residue checks passed as recorded in
  [Defender Base Runtime and Replication](BASE_RUNTIME.md#executed-studio-evidence--2026-08-28).
- A true late-client add terminates the local multiplayer server on the tested
  Studio build, so the established delayed-bootstrap active-session fallback was
  used and explicitly measured. This limitation does not substitute for later
  published-client/rejoin testing.

### Phase 11 authored-wave gate

- Complete in the restricted Match place on 2026-08-28. Twelve exact unsaved
  two-client Studio scenario records, the one consolidated review, the
  `742`-case/`56`-suite local gate, and all four structural builds pass;
  exact-final-SHA CI is cited at handoff.
- One runtime-only full-root fixture transaction authenticated the otherwise
  empty production catalogs and ran the real finite scheduler over the saved
  Phase 07 lane. No lasting catalog, wave, difficulty, enemy, economy, map,
  marker, model, asset, or Studio-authored content was created or changed.
- Exact-time ordering, empty waves, five-second intermission, allowed overlap,
  skip/disconnect quorum, production-transport recovery, the `1/32/64/128`
  due-spawn ladder, healthy finite completion without Results, and lethal defeat
  preemption passed as recorded in
  [Authored Wave Runtime and Difficulty Scheduler](WAVE_RUNTIME.md#executed-studio-evidence--2026-08-28).
- Both clients retained constant Wave ownership and converged within the declared
  bound. Accepted sessions had zero console errors, stopped without runtime
  residue, left Studio in Edit mode, and performed no save or publication.

### Phase 12 tower-runtime and temporary-loadout gate

- The exact connected Match place was reconfirmed as PlaceId
  `136401514513678`, GameId `10757629094`, CreatorType `Group`, CreatorId
  `35420107`, owner `PHJGAMES`, and `ATDPlaceRole = Match`. The unrelated
  standalone Ant Tower Defense place was not synchronized or tested.
- Before Phase 12 synchronization, the bounded persistent roots contained six
  Workspace descendants (Camera, Baseplate, SpawnLocation and its Decal,
  Terrain, Baseplate Texture), five Lighting descendants (Atmosphere, Bloom,
  DepthOfField, Sky, SunRays), and zero SoundService, Teams, StarterGui, or
  StarterPack descendants. The mapped Phase 11 Match source inventory was `77`
  ModuleScripts, one Script, and one LocalScript.
- Synchronizing only reviewed `match.project.json` source produced the expected
  Phase 12 mapped inventory of `83` ModuleScripts, one Script, and one
  LocalScript: the difference is exactly the six server-Match Tower modules.
  The persistent Workspace/Lighting/other-root inventory remained byte-for-byte
  and identity-for-identity unchanged.
- Fresh exact two-client primary and defeat sessions exercised the one
  authenticated runtime-only fixture transaction, distinct five-slot temporary
  loadouts, trusted graybox creation/caps/tamper/recreation, healthy Wave
  coexistence, unchanged lethal defeat, and explicit Tower cleanup. All Models,
  templates, records, loadouts, UnitIds, capabilities, roots, observers,
  boundaries, and caches were runtime-only. Accepted server/client consoles had
  zero errors; only the expected early base-snapshot bootstrap warning appeared
  on the server.
- Final cleanup found no `Workspace.ATDTowerRuntime`, runtime map, enemy visual
  root, `ReplicatedStorage.ATDNetwork`, Phase 11 trigger, Tower object, or client
  Tower object. The exact persistent inventory remained Workspace `6`, Lighting
  `5`, SoundService/Teams/StarterGui/StarterPack `0`, and mapped source
  ModuleScript/Script/LocalScript `83/1/1`. The final Edit-mode source audit
  measured `1,843,901` mapped source bytes, including the reviewed
  `83,729`-byte `TowerRuntimeService` with both consolidated-review fixes.
- Every server/client stopped, the task-owned Rojo process disconnected and
  exited, port `34872` had zero listeners, emulation/profiling state was reset,
  and the exact Match place was left in Edit mode. No Studio-owned instance was
  edited, no lasting Script.Source change was made in Studio, and nothing was
  saved, published, uploaded, or tested in Lobby.

### Needed before Phase 26 teleport testing

- With explicit approval, publish the private test Lobby and Match places.
- Verify reserved-server and group teleport behavior in the Roblox client.

### Needed before Phase 29 production content

- Create/import the first production map, towers, enemies, animations, images,
  and audio under the confirmed owner with correct permissions.

## Current limitations and unresolved items

- The user confirmed PHJGAMES, Group ID `35420107`, as owner. That ownership was
  not independently derivable from the original local scaffold alone.
- Production root/start-place status remains dependent on authenticated Creator
  Dashboard evidence rather than public metadata alone.
- The correct Match place still has a default-generated display name.
- An unused standalone PHJGAMES experience/place was created during the manual
  workflow and awaits separate cleanup approval.
- Separate test universe and places do not appear in repository configuration.
- Current enabled platform settings are not visible locally.
- Current Studio API-access setting is not treated as verified because restricted
  public metadata returned placeholder experience values.

These limitations do not justify guessing identifiers or enabling services. They
are resolved through user confirmation and later explicitly approved Studio
work.

## Packet 00.3 completion requirement

Complete on 2026-08-25. All locally discoverable facts and recommended
strategies are recorded, and the user confirmed the exact Roblox owner as
PHJGAMES, Group ID `35420107`.

At the Packet 00.3 snapshot, the Match place and separate test environment were
still uncreated requirements. Packet 02.4 subsequently created and verified the
Match place at PlaceId `136401514513678` inside the production experience. The
separate private test universe remains uncreated and must receive real verified
identifiers only through later explicitly approved setup work. Current test
availability and authorization boundaries are indexed in `docs/TEST_MATRIX.md`.
