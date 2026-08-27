# Rojo Project Definitions

## Purpose

This document records the multi-project Rojo structure and verification evidence
for Packet 02.2 of `docs/DEVELOPMENT_PLAN.md`. It distinguishes the combined
development project from the role-isolated lobby and match projects without
assigning PlaceIds. Packet 02.3 subsequently added the centralized runtime role
configuration recorded in `docs/PLACE_ROLES.md`; Packet 05.1 added one isolated,
build-only automated-test project.

## Packet status

- Packet: 02.2
- Status: Complete
- Recorded: 2026-08-25
- Project definitions added: `lobby.project.json`, `match.project.json`
- `default.project.json` changed: no
- PlaceId-role configuration added: no
- Gameplay code changed: no
- Studio-authored content changed: no
- Place saved or published: no

The fields above describe Packet 02.2 at completion. The current project files
now also declare their Packet 02.3 roles as `Development`, `Lobby`, and `Match`;
they still do not duplicate runtime PlaceIds. Phase 08 and its four-client
Studio, consolidated-review, and complete-local-gate evidence passed on
2026-08-27. Phase 09 is next but has not begun.

## Project inventory

| Project | Purpose | Server layers | Client layers | Place binding |
| --- | --- | --- | --- | --- |
| `default.project.json` | Combined convenience project and documented `rojo serve` default | `common`, `lobby`, `match` | `common`, `lobby`, `match` | Existing development `servePlaceIds`; current role is `Development` |
| `lobby.project.json` | Role-isolated lobby source | `common`, `lobby` | `common`, `lobby` | No ID binding; current role is `Lobby` |
| `match.project.json` | Role-isolated match source | `common`, `match` | `common`, `match` | No ID binding; current role is `Match` |
| `test.project.json` | Headless contract/runtime-module test DataModel | No runnable layer; exact networking, map, lifecycle, roster, and ready mirrors under `ServerStorage` | No runnable layer; exact networking and Match-ready client mirrors under `ServerStorage` | Build-only; no role or `servePlaceIds` |

All four projects map `src/shared` to `ReplicatedStorage.Shared`. Only the test
project additionally maps `tests/specs`, `tests/fixtures`, `tests/support`, and
isolated negative controls under `ServerStorage`. Packets 06.1, 06.3, and 06.4
also map exactly six common networking modules beneath
`ServerStorage.AutomatedTests`: `ProductionRateLimits`,
`ServerRemoteRegistry`, `ServerRateLimiter`, `ServerRequestDispatcher`,
`ClientRemoteLookup`, and `ClientRequestTracker`. Test still maps no bootstrap,
shutdown module, role entrypoint, or runnable Script/LocalScript.
The tracked `tests/studio/Phase06NetworkServer.server.luau` and
`tests/studio/Phase06NetworkClient.client.luau` manual harness sources are
mapped by none of the four projects.

Phase 07 additionally maps the exact production `MapContract`, `MapValidator`,
and `MapLoader` modules beneath the Test-only
`ServerStorage.AutomatedTests.ProductionServerMaps` folder. `MapFixtures` and
the three map specs are Test-owned. `Phase07MapRegression.server.luau` and
`Phase07MapAuthoring.command.luau` remain unmapped, as does the lasting
Studio-owned `ServerStorage.ATDMapTemplates` content.

Phase 08 adds only the exact Test-only production mirrors required by its
headless suites:

- `ProductionServerMatchLifecycle`: `MatchLifecycleService` and
  `MatchStateMachine`;
- `ProductionServerMatchRoster`: `ParticipantRoster`;
- `ProductionServerMatchReady`: `ReadyCheckCoordinator` and
  `SnapshotBroadcaster`; and
- `ProductionClientMatch`: `MatchReadyController`, `MatchReadyView`, and
  `MatchReadyViewModel`.

`MatchProtocol` remains in the normal shared mapping. The nine Phase 08 specs
mapped under `ServerStorage.AutomatedTests.Specs` are `MatchProtocol`,
`MatchStateMachine`, `MatchLifecycleService`, `ParticipantRoster`,
`ReadyCheckCoordinator`, `SnapshotBroadcaster`, `MatchReadyViewModel`,
`MatchReadyView`, and `MatchReadyController`. Neither Phase 08 role bootstrap is
mapped into Test, and no Studio harness is mapped into Test or any production
project.

The role projects intentionally omit `servePlaceIds`, raw PlaceIds, universe
IDs, and conditional role selection. Their only identity declaration is the
`ATDPlaceRole` string attribute. Packet 02.3 owns the single shared role
configuration and wrong-place detection. No placeholder Match PlaceId is
invented.

## Combined development project

`default.project.json` remains byte-for-byte unchanged by Packet 02.2 and remains
the project selected by plain `rojo serve` and `rojo build` commands.

Packet 02.3 later added only the `Development` role attribute to this file; it
did not change its source mappings or existing `servePlaceIds` entry.

It maps the common source plus non-runnable Lobby and Match modules for
repository-wide inspection and transitional local work. Phase 08 explicitly
excludes both physical Match entrypoint files from Default, so only the common
Main Script and LocalScript run there. Role testing must use
`lobby.project.json` or `match.project.json`; the combined project is not proof
of place-role isolation or Match lifecycle behavior.

Keeping the combined project does not weaken the dependency rules in
`docs/SOURCE_LAYOUT.md`. Lobby and match source still may not import each other.

## Role-isolated hierarchy

Both role projects create the same predictable common hierarchy:

```text
ReplicatedStorage
  Shared
ServerScriptService
  Server
    common
    <lobby or match>
StarterPlayer
  StarterPlayerScripts
    Client
      common
      <lobby or match>
```

The common bootstrap paths therefore remain stable across both projects:

- `ServerScriptService.Server.common.bootstrap.Main`
- `StarterPlayer.StarterPlayerScripts.Client.common.bootstrap.Main`

Lobby continues to use the common Main sources. Phase 08 Match maps its
role-specific server and client Main sources at those same stable DataModel
paths and maps the reusable common bootstrap owners beside them. It therefore
retains exactly one Script and one LocalScript while adding Match-only modules
under the `match` folders. Lobby contains no Match source, and Match contains no
Lobby source.

## Unknown-instance preservation

The lobby and match definitions explicitly set `$ignoreUnknownInstances` to
`true` at every mapped ownership boundary:

1. DataModel root.
2. `ReplicatedStorage`.
3. `ReplicatedStorage.Shared`.
4. `ServerScriptService`.
5. `ServerScriptService.Server`.
6. Server `common`.
7. Server role folder.
8. `StarterPlayer`.
9. `StarterPlayer.StarterPlayerScripts`.
10. Client root folder.
11. Client `common`.
12. Client role folder.

This tells Rojo not to remove unmapped children under those containers during
sync. Studio and Team Create remain authoritative for maps, terrain, models,
animations, and all other unmapped instances. It does not authorize storing
Studio-authored content in Rojo folders or using Roblox Script Sync.

## Commands

### Serve

- Combined default: `rojo serve` or `rojo serve default.project.json`
- Lobby source only: `rojo serve lobby.project.json`
- Match source only: `rojo serve match.project.json`

`test.project.json` is never served or connected to a Roblox place. It has no
`servePlaceIds` and exists only for deterministic local/CI builds.

Only one Rojo project should be connected to a given Studio place at a time.
Packet 02.4 owns the manual gate that connects the correct isolated project to
each real place.

### Build

- Combined: `rojo build default.project.json -o default.rbxlx`
- Lobby: `rojo build lobby.project.json -o lobby.rbxlx`
- Match: `rojo build match.project.json -o match.rbxlx`
- Isolated tests: `rojo build test.project.json -o test.rbxlx`

Root `*.rbxl` and `*.rbxlx` outputs are ignored under `docs/CODE_STYLE.md`. Build
artifacts are local verification products, not authoritative Studio content.

## Structural verification

All four current project JSON files parsed successfully and all four builds
completed with Rojo 7.7.0. The original Packet 02.2 evidence covered only the
three production definitions; Packet 05.1 added the Test definition and check,
and Packets 06.1, 06.3, and 06.4 added the six narrow networking module mappings
described above.

| Build | Server layers | Client layers | ModuleScripts | Scripts | LocalScripts |
| --- | --- | --- | ---: | ---: | ---: |
| Default | common Main plus non-runnable `lobby`/`match` modules | common Main plus non-runnable `lobby`/`match` modules | 54 | 1 | 1 |
| Lobby | `common`, `lobby` | `common`, `lobby` | 43 | 1 | 1 |
| Match | role Main at common path plus common modules and `match` | role Main at common path plus common modules and `match` | 54 | 1 | 1 |
| Test | No runnable layer; exact server production mirrors under `ServerStorage` | No runnable layer; exact client production mirrors under `ServerStorage` | 90 | 0 | 0 |

Additional assertions passed:

- Lobby JSON contains no server/client match source path.
- Match JSON contains no server/client lobby source path.
- Lobby build contains no match folder or source.
- Match build contains no lobby folder or source.
- Default, Lobby, and Match contain no test spec, fixture, support module,
  negative control, runner entrypoint, or test-only dependency.
- Every production Lua container matches a fixed expected
  DataModel path, class, authoritative `src/` file, and exact source content.
- Test contains the same 34 shared ModuleScripts plus exactly
  `ProductionRateLimits`, `ServerRemoteRegistry`, `ServerRateLimiter`,
  `ServerRequestDispatcher`, `ClientRemoteLookup`, and `ClientRequestTracker`
  under test-only `ServerStorage` paths; the three map modules; the two
  lifecycle modules; the roster module; the two ready modules; and the three
  Match-ready client modules. Its test-owned
  spec/fixture/support/negative-control set contains 39 ModuleScripts, each
  authenticated against an exact DataModel path, class, authoritative test
  file, and byte-for-byte source. Unlisted Test-owned source fails the
  verifier. The complete Test build therefore contains 90 ModuleScripts and no
  runnable Script or LocalScript.
- All four tracked `tests/studio` tools occur in no generated DataModel: the
  three runtime-regression harness sources and the default-deny Phase 07
  Edit-mode authoring command are absent even from the Test build.
- All builds contain `ReplicatedStorage.Shared`.
- `.gitkeep` files produce no Roblox instances.
- Each production build contains exactly one authenticated server Main and one
  authenticated client Main. Default and Lobby use the common sources; Match
  uses its role sources at the same DataModel paths. Test is bootstrap-free.
- Each role project has 12 verified unknown-instance-preservation boundaries.
- The new project files contain no `servePlaceIds`, known PlaceId, universe ID,
  or duplicated runtime PlaceId. Packet 02.3 later added only their role
  attributes.

The current production source inventory contains 34 shared ModuleScripts:
`PlaceRoles`,
`ServiceLifecycle`, `EnvironmentContext`, `Log`, `Cleanup`, `Ids`, `Result`,
`Validation`, `ConfigTypes`, `AssetSchema`, `Assets`, `BannerSchema`, `Banners`,
`ConfigurationValidator`, `DefaultSettings`, `Difficulties`, `DifficultySchema`, `Economy`,
`EconomySchema`, `Enemies`, `EnemySchema`, `MapSchema`, `Maps`,
`SchemaPrimitives`, `SettingsSchema`, `TowerSchema`, `Towers`, `WaveSchema`, and
`Waves`, plus `PayloadValidation`, `ProductionRemotes`, `RemoteRegistry`, and
`RequestProtocol`, and `MatchProtocol`.
The server-only common `Shutdown`, `ServerBootstrap`, `ProductionRateLimits`,
`ServerRemoteRegistry`, `ServerRateLimiter`, and `ServerRequestDispatcher`
modules and client-only common `ClientBootstrap`, `ClientRemoteLookup`, and
`ClientRequestTracker` modules bring the common production inventory to 43
ModuleScripts. Default and Match add the eight server Match modules
(`MapContract`, `MapValidator`, `MapLoader`, `MatchLifecycleService`,
`MatchStateMachine`, `ParticipantRoster`, `ReadyCheckCoordinator`, and
`SnapshotBroadcaster`) and three client Match modules (`MatchReadyController`,
`MatchReadyView`, and `MatchReadyViewModel`) for 54 ModuleScripts. Lobby remains
at 43. Every production build retains one Script and one LocalScript. Default
contains both non-runnable role folders but excludes the physical Match Main
files; Lobby contains no Match source; Match contains no Lobby source.
Packet 04.4 schema evidence is recorded in
`docs/ECONOMY_BANNER_SETTINGS_SCHEMAS.md`; current whole-catalog
evidence is in `docs/CONFIGURATION_VALIDATION.md`, and the network layout is in
`docs/NETWORK_PROTOCOL.md`.

The inspected ignored build artifacts were removed. They can be recreated with
the commands above. `lune run tests/verify-builds.luau` rebuilds and checks all
four definitions across the complete DataModel and removes only its exact
generated outputs.

The structural verifier is the current headless production-shipping gate. Its
status and the separate Studio/published test boundaries are indexed in
`docs/TEST_MATRIX.md`.

Packet 06.4 added only the shared request protocol, the server dispatcher, the
client tracker, their focused specs, and narrow Test mappings reflected above.
Packet 06.5 adds one Test-only integrated adversarial spec and two unmapped
manual Studio harness sources. The Test-only networking copies remain
source-identical and do not make the test project suitable for serving. At that
historical Phase 06 checkpoint, Default, Lobby, and Match each had 40
ModuleScripts, one Script, and one LocalScript, and the production registry and
policy list were empty. The current Phase 08 counts, Match-only remotes, and
narrow test mirrors are recorded above.

For Packet 06.5, `lobby.project.json` was connected only to Lobby and
`match.project.json` only to Match, one at a time. Three unsaved cycles passed in
each role, followed by the final two-client networking regression. Both places
were left in Edit mode without saving or publishing. Packet 06.5 and the fresh
Phase 06/Gate A audit pass, including clean workflow run `33022784985`. Phase 06
is complete and Gate A passed. Phase 07 implementation, exact Match Studio
authoring, consolidated review, 241-case local suite, and all four structural
builds pass. Phase 07 is complete. Packets 08.1–08.5, the four-client Match
Studio gate, consolidated final review, 347-case local suite, and all four
current structural builds pass. Phase 08 is complete; Phase 09 is next but has
not begun.

## Scope boundary and next gate

Packet 02.2 did not create the Match place, connect a role project to a real
place, run role-specific code, save Studio content, or publish. Packet 02.4 has
since passed the real Lobby-versus-Match Studio isolation gate; current evidence
is recorded in `docs/MULTI_PLACE_GATE.md`.
