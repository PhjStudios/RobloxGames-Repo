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
2026-08-27. Packets 09.1–09.5, the exact Phase 09 Match Studio gate,
consolidated review, 467-case local gate, and all four current structural builds
passed on 2026-08-27. Phase 09 is complete. Phase 10 adds only the reviewed
shared/server-Match/client-Match base modules and Test-only mirrors/specs; its
focused and exact Studio checks, consolidated review, complete local gate, and
  all four structural builds passed on 2026-08-28. Phase 10 is complete. Phase
  11 adds only reviewed shared/server-Match/client-Match Wave modules and exact
  Test-only mirrors/specs; its Studio, consolidated-review, `742`-case local, and
  four-build gates pass. Exact-final-SHA CI is cited at handoff. Phase 11 is
  complete. Phase 12 adds only six server-Match Tower modules and their exact
  Test mirrors/fixture/specs; focused and exact unsaved Studio checks,
  consolidated review, the `840`-case/`64`-suite local gate, and all four
  structural builds pass. Phase 12 is complete; exact-final-SHA CI is recorded
  at handoff. The current Phase 13 mappings are recorded below.

## Project inventory

| Project | Purpose | Server layers | Client layers | Place binding |
| --- | --- | --- | --- | --- |
| `default.project.json` | Combined convenience project and documented `rojo serve` default | `common`, `lobby`, `match` | `common`, `lobby`, `match` | Existing development `servePlaceIds`; current role is `Development` |
| `lobby.project.json` | Role-isolated lobby source | `common`, `lobby` | `common`, `lobby` | No ID binding; current role is `Lobby` |
| `match.project.json` | Role-isolated match source | `common`, `match` | `common`, `match` | No ID binding; current role is `Match` |
| `test.project.json` | Headless contract/runtime-module test DataModel | No runnable layer; exact networking, map, lifecycle, roster, ready, base, enemy, Wave, Tower, and placement mirrors under `ServerStorage` | No runnable layer; exact networking, Match-ready, base, enemy, Wave, and placement mirrors under `ServerStorage` | Build-only; no role or `servePlaceIds` |

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

Phase 09 adds exactly these Test-only production mirrors:

- `ProductionServerEnemies`: `EnemyPath`, `EnemyReplicationPublisher`,
  `EnemyRuntimeStore`, and `EnemySimulationService`; and
- `ProductionClientEnemies`: `EnemyController`, `EnemyPresentation`,
  `EnemyRenderer`, and `EnemyReplicationState`.

`EnemyProtocol` remains in the normal authoritative shared mapping. The eleven
Phase 09 specs mapped under `ServerStorage.AutomatedTests.Specs` are
`EnemyProtocol`, `EnemyPath`, `EnemyRuntimeStore`, `EnemyMovement`,
`EnemyReplicationPublisher`, `EnemyReplicationState`, `EnemyPresentation`,
`EnemyRenderer`, `EnemySimulationService`, `EnemySimulationIntegration`, and
`EnemyController`; `EnemyFixtures` is the one new fixture. These suites contain
120 focused cases. The complete local run passes 39 suites and 467 cases. Test
still maps no bootstrap, shutdown module, role
entrypoint, or runnable Script/LocalScript.

Phase 10 adds exactly these Test-only production mirrors:

- `ProductionServerBase`: `BaseRuntime`, `BaseRuntimeService`, and
  `BaseReplicationPublisher`; and
- `ProductionClientBase`: `BaseController`, `BaseStateReducer`, `BaseViewModel`,
  and `BaseWorldView`.

`BaseProtocol` remains in the normal authoritative shared mapping. The nine Base
specs and `BaseFixtures` are Test-owned. No Studio runtime trigger is a tracked
harness file or separate mapping: the one fixed Studio-only trigger is created
by mapped production composition only while Studio is running and is destroyed
on shutdown.

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

Phase 09 adds the four server and four client enemy ModuleScripts to Default's
non-runnable Match folders. It adds no entrypoint: Default still runs only the
two common Main sources, while Match composes the enemy service/controller
through its existing role-specific Main sources.

Phase 10 similarly adds three server and four client base ModuleScripts to the
non-runnable Match folders in Default and to the role-specific Match build. It
adds no entrypoint; both builds retain their existing single Main Script and
LocalScript.

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
under the `match` folders. Lobby contains no server/client Match-role source,
and Match contains no Lobby source. Phase 09 extends those Match-only folders
with `enemies` on both runtime sides without changing either stable Main path or
runnable count. Lobby receives `EnemyProtocol` only through the normal shared
mapping. Phase 10 adds `base` on both Match runtime sides and shares only
`BaseProtocol` through the normal shared mapping; Lobby still receives no
server/client Match-role base source.

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

All four project JSON files parsed successfully and all four builds completed
with Rojo 7.7.0 at the completed checkpoints recorded below. The original
Packet 02.2 evidence covered only the three production definitions; Packet 05.1
added the Test definition and check, and Packets 06.1, 06.3, and 06.4 added the
six narrow networking module mappings described above.

### Historical Phase 08 build counts

At Phase 08 completion, the verified inventory was:

| Build | Server layers | Client layers | ModuleScripts | Scripts | LocalScripts |
| --- | --- | --- | ---: | ---: | ---: |
| Default | common Main plus non-runnable `lobby`/`match` modules | common Main plus non-runnable `lobby`/`match` modules | 54 | 1 | 1 |
| Lobby | `common`, `lobby` | `common`, `lobby` | 43 | 1 | 1 |
| Match | role Main at common path plus common modules and `match` | role Main at common path plus common modules and `match` | 54 | 1 | 1 |
| Test | No runnable layer; exact server production mirrors under `ServerStorage` | No runnable layer; exact client production mirrors under `ServerStorage` | 90 | 0 | 0 |

### Historical Phase 09 derived inventory

At Phase 09 completion, the project definitions and verifier derived these
counts:

| Build | Server layers | Client layers | ModuleScripts | Scripts | LocalScripts |
| --- | --- | --- | ---: | ---: | ---: |
| Default | common Main plus non-runnable `lobby`/`match` modules | common Main plus non-runnable `lobby`/`match` modules | 63 | 1 | 1 |
| Lobby | `common`, `lobby` | `common`, `lobby` | 44 | 1 | 1 |
| Match | role Main at common path plus common modules and `match` | role Main at common path plus common modules and `match` | 63 | 1 | 1 |
| Test | No runnable layer; 25 exact server/client production mirrors under `ServerStorage` | No runnable layer; authoritative shared tree plus Test-owned modules | 111 | 0 | 0 |

At Phase 08 completion, these additional assertions passed:

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

At Phase 08 completion, the production source inventory contained 34 shared
ModuleScripts: `PlaceRoles`,
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
`ClientRequestTracker` modules brought the common production inventory to 43
ModuleScripts. Default and Match added the eight server Match modules
(`MapContract`, `MapValidator`, `MapLoader`, `MatchLifecycleService`,
`MatchStateMachine`, `ParticipantRoster`, `ReadyCheckCoordinator`, and
`SnapshotBroadcaster`) and three client Match modules (`MatchReadyController`,
`MatchReadyView`, and `MatchReadyViewModel`) for 54 ModuleScripts. Lobby remained
at 43. Every production build retained one Script and one LocalScript. Default
contained both non-runnable role folders but excluded the physical Match Main
files; Lobby contained no server/client Match-role source; Match contained no
Lobby source.
Packet 04.4 schema evidence is recorded in
`docs/ECONOMY_BANNER_SETTINGS_SCHEMAS.md`; current whole-catalog
evidence is in `docs/CONFIGURATION_VALIDATION.md`, and the network layout is in
`docs/NETWORK_PROTOCOL.md`.

### Historical Phase 09 source and Test boundary

At Phase 09 completion the production source inventory contained 35 shared
ModuleScripts: the 34-module Phase 08 shared inventory above plus
`EnemyProtocol`. The six
server-common and three client-common modules bring the common production
inventory to 44. Default and Match additionally contain 12 server-Match modules
(the prior eight plus `EnemyPath`, `EnemyReplicationPublisher`,
`EnemyRuntimeStore`, and `EnemySimulationService`) and seven client-Match
modules (the prior three plus `EnemyController`, `EnemyPresentation`,
`EnemyRenderer`, and `EnemyReplicationState`) for 63 ModuleScripts. Lobby
contains 44. Each production build still has exactly one authenticated Script
and one authenticated LocalScript.

At Phase 09 completion the Test inventory contained 35 authoritative shared
modules, 25 exact production mirrors, and 51 Test-owned modules. Those Test-owned modules are
exactly 39 specs, four fixtures, three support modules, and five negative
controls. The 25 mirrors comprise six common networking, three map, two
lifecycle, one roster, two ready, three Phase 08 client-Match, four server-enemy,
and four client-enemy modules. The resulting Test build has 111 ModuleScripts
and no runnable Script or LocalScript.

The Phase 09 verifier required Default/Lobby/Match to contain no test source,
Lobby to contain no server/client Match-role source, Match to contain no Lobby
source, every mapped Lua container to match its exact path/class/source bytes,
and all four tracked Studio tools to occur in no generated DataModel. It rejects
unlisted Test-owned source and Phase 10/11 production markers. At that
checkpoint the five production endpoints were reliable and Match-only, and
exactly the three inbound requests had rate policies. Production `Enemies` and
`Assets` remained frozen empty arrays.

The inspected ignored build artifacts were removed. They can be recreated with
the commands above. `lune run tests/verify-builds.luau` rebuilds and checks all
four definitions across the complete DataModel and removes only its exact
generated outputs.

### Phase 10 source and Test boundary (historical)

At Phase 10 completion, the project definitions mapped `BaseProtocol` through the authoritative
shared tree, the three server-base modules through `src/server/match/base`, and
the four client-base modules through `src/client/match/base`. Default and Match
contain those seven role-specific modules; Lobby contains none. Test maps exact
copies beneath `ProductionServerBase` and `ProductionClientBase`, plus the
Test-owned Base specs and fixture. No bootstrap, Studio harness, role entrypoint,
Script, or LocalScript is added to Test or mapped twice.

The Phase 10 verifier authenticated both mapping directions and every source
byte; keeps one Script and one LocalScript in each production build and zero
Test runnables; excludes tests, fixtures, and Studio-only evidence infrastructure
from production; preserves Lobby/Match isolation; and rejects generated output
or Phase 11 source. It also proves the seven Match-only reliable definitions,
four inbound rate policies, and empty production `Difficulties`, `Maps`, `Waves`,
`Enemies`, and `Assets`. The final Default/Lobby/Match/Test inventory is
`71/45/71/129` ModuleScripts, with Script/LocalScript counts `1/1`, `1/1`,
`1/1`, and `0/0` respectively.

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
policy list were empty. The historical Phase 08 counts and narrow mirrors are
preserved above; the historical Phase 09 counts, Match-only remotes, rate
policies, and enemy mirrors are recorded in the historical sections.

For Packet 06.5, `lobby.project.json` was connected only to Lobby and
`match.project.json` only to Match, one at a time. Three unsaved cycles passed in
each role, followed by the final two-client networking regression. Both places
were left in Edit mode without saving or publishing. Packet 06.5 and the fresh
Phase 06/Gate A audit pass, including clean workflow run `33022784985`. Phase 06
is complete and Gate A passed. Phase 07 implementation, exact Match Studio
authoring, consolidated review, 241-case local suite, and all four structural
builds pass. Phase 07 is complete. Packets 08.1–08.5, the four-client Match
Studio gate, consolidated final review, 347-case local suite, and all four
then-current structural builds pass. Phase 08 is complete; Phase 09 was next but
had not begun at that historical checkpoint. Packets 09.1–09.5, their 11 focused
suites with 120 cases, and the exact two-client Match Studio gate passed on
2026-08-27. The complete local run passes 39 repository suites and 467 cases;
the consolidated review and all four current structural builds also pass.
Phase 09 is complete. Phase 10 focused and exact Studio checks, consolidated
review, `593`-case local gate, and all four current structural builds passed on
2026-08-28. Phase 10 is complete. Phase 11 remained unbegun at that historical
checkpoint; the current Phase 11 boundary is recorded below. Exact-final-SHA CI
evidence is cited at each handoff.

## Scope boundary and next gate

Packet 02.2 did not create the Match place, connect a role project to a real
place, run role-specific code, save Studio content, or publish. Packet 02.4 has
since passed the real Lobby-versus-Match Studio isolation gate; current evidence
is recorded in `docs/MULTI_PLACE_GATE.md`.

## Current Phase 12 mapping boundary

Default and Match map the authoritative shared Wave protocol, three server Wave
modules, and two client Wave modules through their existing trees. Lobby maps
only shared protocol/configuration and contains no server/client Match Wave
runtime. Test maps exact Wave production mirrors under `ServerStorage` alongside
the Phase 11 fixtures/specs; it remains build-only with zero Script and
LocalScript. No project maps `tests/studio`, and no source is mapped twice.

Default and Match additionally map the six authoritative server-Match Tower
modules under `ServerScriptService.Server.match.towers`. Lobby maps none of
those six. Test maps exact byte-identical copies under
`ServerStorage.AutomatedTests.ProductionServerTowers`, plus Test-owned
`TowerFixtures` and eight Tower specs. There is no client Tower mapping, shared
Tower protocol, production test fixture, manually mapped Studio harness, or
second runnable entrypoint. The Studio-only graybox/runtime evidence seam is
inside the reviewed production Tower service and remains
`RunService:IsStudio()`-gated and dormant outside its one-shot transaction.

The completed Phase 12 structural inventory is `83/46/83/159`
ModuleScripts for
Default/Lobby/Match/Test. Each production build retains exactly one Script and
one LocalScript; Test retains zero. The current verifier also proves ten
Match-only reliable definitions, six inbound rate policies, 79 exact Test-owned
modules, every shared and production-mirror path/class/source byte,
generated-output absence, Lobby/Match isolation, and zero production
test/fixture/manual-Studio-harness content. Production `Assets`, `Towers`,
`Enemies`, `Maps`, `Difficulties`, `Waves`, and difficulty-specific `Economy`
rules remain frozen empty. Exact Tower source/public-method allowlists reject
any Phase 13 placement/query/preview/hotbar source or behavior at the
historical Phase 12 checkpoint.

## Current Phase 13 mapping boundary

Default and Match map the two authoritative shared placement modules, two
server placement modules, and four client placement modules through their
existing shared/server/client trees. Lobby maps only the shared contracts and
contains no Match server/client placement runtime. Test maps exact mirrors
under `ProductionSharedMatch`, `ProductionServerPlacement`, and
`ProductionClientPlacement`, plus nine Test-owned placement specs. No project
maps `tests/studio`, a fixture into production, a second Script/LocalScript, or
the Studio evidence BindableFunctions as persistent instances.

The structural verifier now authenticates both mapping directions and exact
source bytes, one Script/one LocalScript per production build and zero in Test,
thirteen reliable Match-only endpoint definitions, eight inbound policies,
Lobby/Match isolation, empty production catalogs, and absence of Phase 14
source. Final Default/Lobby/Match/Test module and Test-owned counts are recorded
after the complete Phase 13 gate.
