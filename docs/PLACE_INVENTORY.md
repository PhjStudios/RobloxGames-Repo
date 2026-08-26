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

The repository currently treats this as its only served place. Its Rojo project
name is `Ant Tower Defense`.

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

- Map terrain and environment geometry.
- Ant nest/enemy spawn markers.
- Ordered lane/path markers.
- Defender base and endpoint marker.
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

### Needed before Phase 03

- Create a separate private test experience under the same owner.
- Create Test Lobby and Test Match places.
- Record their universe and PlaceIds without credentials.

The separate test universe remains required before persistence and destructive
backend testing, but it does not block the code-only Phase 03 lifecycle work.

### Needed before Phase 07's graybox map gate

- Author the test map markers, placement areas, base, enemy spawn, and camera
  anchors in the Test Match place.

### Needed before Phase 26 teleport testing

- With explicit approval, publish the private test Lobby and Match places.
- Verify reserved-server and group teleport behavior in the Roblox client.

### Needed before Phase 29 production content

- Create/import the first production map, towers, enemies, animations, images,
  and audio under the confirmed owner with correct permissions.

## Current limitations and unresolved items

- Exact Roblox owner group name/ID is not locally or publicly available.
- Production root/start-place status cannot be verified without authenticated
  Creator Dashboard access.
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

The still-uncreated Match place and separate test environment are recorded
requirements, not invented identifiers. Their real IDs must be added here when
the approved Studio setup work occurs before the Phase 02 multi-place gate.
