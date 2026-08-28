# Source Layers and Runnable Entrypoints

## Purpose

This document records the source-directory split and verification evidence for
Packet 02.1 of `docs/DEVELOPMENT_PLAN.md`. It defines common, lobby-only, and
match-only dependency boundaries. Packet 02.2 subsequently introduced the
place-isolated mappings recorded in `docs/ROJO_PROJECTS.md`.

## Packet status

- Packet: 02.1
- Status: Complete
- Recorded: 2026-08-25
- Current Rojo project definitions changed: no
- Gameplay services added: none
- Studio-authored content changed: no
- Place saved or published: no

Those fields record Packet 02.1. The current Phase 10 extension adds only
ModuleScripts beneath the established shared/server-Match/client-Match layers
and test-only mirrors/specs; it adds no runnable entrypoint. Focused and exact
Studio checks passed on 2026-08-28. Phase 11 remains unbegun.

## Current Phase 10-relevant source tree excerpt

```text
src/
  shared/
    config/
      AssetSchema.luau
      Assets.luau
      BannerSchema.luau
      Banners.luau
      ConfigurationValidator.luau
      DefaultSettings.luau
      Difficulties.luau
      DifficultySchema.luau
      Economy.luau
      EconomySchema.luau
      Enemies.luau
      EnemySchema.luau
      MapSchema.luau
      Maps.luau
      PlaceRoles.luau
      SchemaPrimitives.luau
      SettingsSchema.luau
      TowerSchema.luau
      Towers.luau
      WaveSchema.luau
      Waves.luau
    lifecycle/
      ServiceLifecycle.luau
    logging/
      EnvironmentContext.luau
      Log.luau
    match/
      BaseProtocol.luau
      EnemyProtocol.luau
      MatchProtocol.luau
    network/
      PayloadValidation.luau
      ProductionRemotes.luau
      RemoteRegistry.luau
      RequestProtocol.luau
    types/
      ConfigTypes.luau
    util/
      Cleanup.luau
      Ids.luau
      Result.luau
      Validation.luau
  server/
    common/
      bootstrap/
        Main.server.luau
        ServerBootstrap.luau
        Shutdown.luau
      networking/
        ProductionRateLimits.luau
        ServerRemoteRegistry.luau
        ServerRateLimiter.luau
        ServerRequestDispatcher.luau
    lobby/
      .gitkeep
    match/
      bootstrap/
        Main.server.luau
      base/
        BaseReplicationPublisher.luau
        BaseRuntime.luau
        BaseRuntimeService.luau
      enemies/
        EnemyPath.luau
        EnemyReplicationPublisher.luau
        EnemyRuntimeStore.luau
        EnemySimulationService.luau
      lifecycle/
        MatchLifecycleService.luau
        MatchStateMachine.luau
      maps/
        MapContract.luau
        MapLoader.luau
        MapValidator.luau
      ready/
        ReadyCheckCoordinator.luau
        SnapshotBroadcaster.luau
      roster/
        ParticipantRoster.luau
      .gitkeep
  client/
    common/
      bootstrap/
        ClientBootstrap.luau
        Main.client.luau
      networking/
        ClientRemoteLookup.luau
        ClientRequestTracker.luau
    lobby/
      .gitkeep
    match/
      bootstrap/
        Main.client.luau
      base/
        BaseController.luau
        BaseStateReducer.luau
        BaseViewModel.luau
        BaseWorldView.luau
      enemies/
        EnemyController.luau
        EnemyPresentation.luau
        EnemyRenderer.luau
        EnemyReplicationState.luau
      MatchReadyController.luau
      MatchReadyView.luau
      MatchReadyViewModel.luau
      .gitkeep
tests/
  fixtures/
    BaseFixtures.luau
    EnemyFixtures.luau
    MapFixtures.luau
    NetworkFixtures.luau
  negative/
  specs/
    BaseController.spec.luau
    BaseDefeatIntegration.spec.luau
    BaseProtocol.spec.luau
    BaseReplicationPublisher.spec.luau
    BaseRuntime.spec.luau
    BaseRuntimeService.spec.luau
    BaseStateReducer.spec.luau
    BaseViewModel.spec.luau
    BaseWorldView.spec.luau
    ClientRequestTracker.spec.luau
    EnemyController.spec.luau
    EnemyMovement.spec.luau
    EnemyPath.spec.luau
    EnemyPresentation.spec.luau
    EnemyProtocol.spec.luau
    EnemyRenderer.spec.luau
    EnemyReplicationPublisher.spec.luau
    EnemyReplicationState.spec.luau
    EnemyRuntimeStore.spec.luau
    EnemySimulationIntegration.spec.luau
    EnemySimulationService.spec.luau
    MapContract.spec.luau
    MapLoader.spec.luau
    MapValidator.spec.luau
    MatchLifecycleService.spec.luau
    MatchProtocol.spec.luau
    MatchReadyController.spec.luau
    MatchReadyView.spec.luau
    MatchReadyViewModel.spec.luau
    MatchStateMachine.spec.luau
    NetworkSecurity.spec.luau
    ParticipantRoster.spec.luau
    PayloadValidation.spec.luau
    ReadyCheckCoordinator.spec.luau
    RemoteRegistry.spec.luau
    RemoteRuntime.spec.luau
    RequestProtocol.spec.luau
    ServerRateLimiter.spec.luau
    ServerRequestDispatcher.spec.luau
    SnapshotBroadcaster.spec.luau
  studio/
    Phase06NetworkClient.client.luau
    Phase06NetworkServer.server.luau
    Phase07MapAuthoring.command.luau
    Phase07MapRegression.server.luau
  support/
```

This excerpt shows every production source and the Phase 06–10 test areas
relevant to the network, map, lifecycle, roster, ready, enemy simulation,
defender-base, and client-presentation boundaries. It intentionally omits unrelated
test fixtures, negative controls, older specs, support modules, and runner
entrypoints; it is not a complete tracked-file inventory.

Any remaining `.gitkeep` markers preserve otherwise empty architecture
directories. They are not Luau modules or runnable scripts and create no Roblox
Instance. Match now contains the Phase 07 map modules, the Phase 08
server/client composition, the Phase 09 enemy modules, and the Phase 10 base
modules shown above.

`src/shared` remains the location for code that is safe and useful across both
execution contexts and both place roles. Packet 02.3 added the typed place-role
configuration described in `docs/PLACE_ROLES.md`. Packet 03.1 added the typed
service lifecycle contract described in `docs/SERVICE_LIFECYCLE.md`. Packet 03.2
added the ownership utility described in `docs/CLEANUP.md`. Packet 03.3 added
the context-bound diagnostic contract described in `docs/LOGGING.md`. Packet
03.4 added the server-only shutdown runner described in
`docs/GRACEFUL_SHUTDOWN.md`. Packet 04.1 added the pure shared ID and Result
contracts described in `docs/IDS_AND_RESULTS.md`. Packet 04.2 added the pure
tower, enemy, symbolic-asset, and validation contracts described in
`docs/TOWER_ENEMY_SCHEMAS.md`; at Packet 04.2 completion, none was required by a
bootstrap.
Packet 04.3 added the pure map, difficulty, and wave contracts described in
`docs/MAP_DIFFICULTY_WAVE_SCHEMAS.md`. Packet 04.4 added the economy, banner,
and default-settings contracts described in
`docs/ECONOMY_BANNER_SETTINGS_SCHEMAS.md`. Packet 04.5 added the one typed,
deterministic whole-configuration boundary described in
`docs/CONFIGURATION_VALIDATION.md` and integrated it into both common
bootstraps before lifecycle startup. It adds no place-specific or gameplay
service.

Packet 06.1 added the shared typed registry and
empty lasting production definition module, the server-common lifecycle owner,
and the client-common bounded lookup utility. Only the server bootstrap imports
the production registry and network owner. No lobby-only, match-only, gameplay,
or additional runnable entrypoint was added. The architecture and fixed path
contract are recorded in `docs/NETWORK_PROTOCOL.md`.

Packet 06.2 added only the pure shared `network/PayloadValidation.luau` contract
and its test-only spec. It reuses lower-level shared `Ids`, `Result`, and
`Validation` modules and is safe to replicate; neither bootstrap imported it at
that checkpoint because the production endpoint registry was empty. It adds no
server/client layer, lifecycle service, runnable entrypoint, gameplay schema, or
place-specific dependency.

Packet 06.3 added the server-only `networking/ProductionRateLimits.luau` and
`networking/ServerRateLimiter.luau` modules under the existing common server
network owner, plus one test-only spec. It adds no lifecycle service or runnable
entrypoint. At that checkpoint the production rate-policy list and registry were
both frozen and empty; Phase 08 later added the Match-only definitions recorded
above.

Packet 06.4 adds the shared `network/RequestProtocol.luau`, server-common
`networking/ServerRequestDispatcher.luau`, and client-common
`networking/ClientRequestTracker.luau` modules. The server registry now accepts
only fixed request or event contracts through distinct secure registration APIs;
the former raw-handler binding surface is gone. The dispatcher owns validation,
rate-limit use, server-derived authorization context, bounded correlation,
protected handler outcomes, and origin-only response routing. The client tracker
builds only registered fixed request envelopes and bounds pending and terminal
correlation state. The client bootstrap does not import it, and no runnable
entrypoint, gameplay contract, or production endpoint was added.

Packet 06.5 adds one test-only integrated adversarial spec and two tracked
manual Studio harness sources under `tests/studio/`. No Rojo project maps the
manual harness directory. Its final independent review also hardens the existing
production `ServerRequestDispatcher` to close yielding authorizers/handlers and
forbid handler-supplied validation metadata. The production file inventory,
runnable entrypoints, empty lasting registry, and empty lasting rate-policy list
are unchanged.

At Phase 07 completion, exactly three server-only Match modules existed under
`match/maps`: `MapContract`, `MapValidator`, and `MapLoader`. That packet did
not import them from bootstrap or add a runnable entrypoint or lifecycle
service. Three focused
specs and `MapFixtures` are mapped only into Test. Both Phase 07 Studio tools
remain unmapped; the saved graybox is Studio-owned content outside `src/`.

Phase 08 adds one shared `match/MatchProtocol.luau`; two server lifecycle
modules; one UserId-keyed roster module; two ready modules; three Match client
modules; reusable common `ServerBootstrap` and `ClientBootstrap` composition
owners; and role-specific Match server/client entrypoint sources. The Match
project maps each role-specific entrypoint at the established common Main
DataModel path and excludes the corresponding common Main source, preserving
exactly one Script and one LocalScript. Default maps only the common Main files
and excludes both physical Match entrypoints. Lobby maps no server/client
Match-role source.

The Phase 08 Match server entrypoint binds exactly `GetMatchSnapshot`,
`SubmitReady`, and `MatchSnapshot`, then registers the dependent
`MatchLifecycle` service. The Match client entrypoint registers the one
`MatchReadyController`; its controller, view model, and programmatic view remain
under `src/client/match`. At Phase 08 completion, no Phase 09 enemy, wave,
combat, tower, placement, reward, persistence, teleport, or Lobby behavior had
begun.

Phase 09 adds exactly nine production modules: shared
`match/EnemyProtocol.luau`; server-Match `enemies/EnemyPath.luau`,
`EnemyReplicationPublisher.luau`, `EnemyRuntimeStore.luau`, and
`EnemySimulationService.luau`; and client-Match `enemies/EnemyController.luau`,
`EnemyPresentation.luau`, `EnemyRenderer.luau`, and
`EnemyReplicationState.luau`. The Match composition now registers the
server-owned enemy simulation after network and lifecycle initialization and the
client enemy controller after the Ready controller. `EnemyProtocol` follows the
normal shared mapping into every project. Default and Match map the eight
role-specific enemy modules, Lobby maps none of those eight, and no new Script
or LocalScript was added.

At Phase 09 completion the production registry contained exactly five reliable
Match-only endpoints: `GetMatchSnapshot`, `SubmitReady`, `MatchSnapshot`,
`GetEnemySnapshot`, and `EnemyReplication`. Exactly three production rate
policies cover the three client-to-server requests. The frozen production
`Enemies` and `Assets` catalogs remain empty, so enemy simulation is dormant
without test/Studio-only injected content. Packets 09.1–09.5, focused
executable coverage, Match Studio evidence, consolidated review, 467-case local
gate, and all four structural builds passed on 2026-08-27. Phase 09 is complete.
Phase 10 adds exactly eight production modules: shared `match/BaseProtocol.luau`;
server-Match `base/BaseRuntime.luau`, `BaseRuntimeService.luau`, and
`BaseReplicationPublisher.luau`; and client-Match `base/BaseController.luau`,
`BaseStateReducer.luau`, `BaseViewModel.luau`, and `BaseWorldView.luau`. The
existing Match entrypoints compose BaseRuntime between MatchLifecycle and
EnemySimulation and BaseController between MatchReadyController and
EnemyController; no Script or LocalScript is added. Two Match-only reliable
definitions and one request-rate policy are added. Production `Difficulties`,
`Maps`, `Waves`, `Enemies`, and `Assets` remain empty, so runtime initialization
is dormant outside Studio/test injection. Phase 11 remains unbegun.

## Bootstrap move manifest

The Packet 01.3 bootstraps were moved as filesystem moves without rewriting
their contents:

| Previous path | Current path | SHA-256 after move |
| --- | --- | --- |
| `src/server/Main.server.luau` | `src/server/common/bootstrap/Main.server.luau` | `D32ABE9203C9737CE162BC92384A9A2BC8DF63F501DBB7D14C4880A5768A3365` |
| `src/client/Main.client.luau` | `src/client/common/bootstrap/Main.client.luau` | `D51AB371F486CC3A82A99EBD9F43A541637D921702A2BBCBC2CB7131D7105542` |

The same hashes were captured immediately before and after each move. This
provides traceability even while the previous packets remain together in the
working tree and Git rename presentation depends on similarity detection.

## Layer responsibilities

### Shared

`src/shared` may contain immutable definitions, types, network contracts, and
utilities that are safe for both client and server. Shared code must not import
from `src/server` or `src/client` and must not select lobby or match behavior.

### Server common

`src/server/common` contains server-authoritative infrastructure needed by both
place roles. It may depend on `src/shared` and other server-common modules. It
must not import lobby-only or match-only server code.

### Server lobby

`src/server/lobby` may depend on `src/shared` and `src/server/common`. It must not
import from `src/server/match` or any client directory.

### Server match

`src/server/match` may depend on `src/shared` and `src/server/common`. It must not
import from `src/server/lobby` or any client directory.

### Client common

`src/client/common` contains client infrastructure needed by both place roles.
It may depend on `src/shared` and other client-common modules. It must not import
lobby-only or match-only client code.

### Client lobby

`src/client/lobby` may depend on `src/shared` and `src/client/common`. It must not
import from `src/client/match` or any server directory.

### Client match

`src/client/match` may depend on `src/shared` and `src/client/common`. It must not
import from `src/client/lobby` or any server directory.

Place-specific layers may share behavior only by moving a genuinely reusable
module downward into the appropriate common or shared layer. They must never
solve duplication by importing across the lobby/match boundary.

## Runnable-entrypoint invariant

Roblox automatically runs files mapped as `Script` or `LocalScript`. Phase 08
adds physical Match entrypoint sources, so the shipping invariant is now
enforced by explicit project mappings rather than by a repository-wide filename
count:

1. Every production build contains exactly one Script and one LocalScript.
2. Default and Lobby map the common Main sources at the established common
   bootstrap paths and do not map either physical Match entrypoint.
3. Match replaces only those two mapped Main sources with
   `src/server/match/bootstrap/Main.server.luau` and
   `src/client/match/bootstrap/Main.client.luau` at the same DataModel paths.
4. The Match entrypoints call the reusable common bootstrap owners, require an
   exact Match role, and register services only after complete configuration
   validation.
5. Lobby contains no server/client Match-role source, Match contains no Lobby
   source, and the combined Default build remains inspection/development-only
   rather than evidence for Match role behavior.

The structural verifier authenticates each mapped Main by exact DataModel path,
class, authoritative source file, and byte-for-byte content. This prevents a
second runner or stale common Main from executing alongside the role-specific
composition. Phase 09 adds only ModuleScripts and leaves this invariant
unchanged.

## Dependency direction

| Layer | May depend on | Must not depend on |
| --- | --- | --- |
| `shared` | Other lower-level shared modules | Any client/server or place-specific layer |
| `server/common` | `shared`, `server/common` | `server/lobby`, `server/match`, all client layers |
| `server/lobby` | `shared`, `server/common`, `server/lobby` | `server/match`, all client layers |
| `server/match` | `shared`, `server/common`, `server/match` | `server/lobby`, all client layers |
| `client/common` | `shared`, `client/common` | `client/lobby`, `client/match`, all server layers |
| `client/lobby` | `shared`, `client/common`, `client/lobby` | `client/match`, all server layers |
| `client/match` | `shared`, `client/common`, `client/match` | `client/lobby`, all server layers |

The current common client and server bootstraps both require
`ReplicatedStorage.Shared.config.PlaceRoles`,
`ReplicatedStorage.Shared.config.ConfigurationValidator`, and
`ReplicatedStorage.Shared.logging.EnvironmentContext`,
`ReplicatedStorage.Shared.logging.Log`,
`ReplicatedStorage.Shared.lifecycle.ServiceLifecycle`, and
`ReplicatedStorage.Shared.util.Cleanup`. All imports follow the allowed
common-to-shared dependency direction. Lifecycle and cleanup receive the same
genuine context-bound logger created by each bootstrap. No cross-role import
exists. Both bootstraps resolve their place role, validate the same nine-family
configuration graph, and only then create the lifecycle runner and cleanup
owner. Invalid configuration therefore starts no dependent service.

The common server bootstrap additionally requires
`ReplicatedStorage.Shared.network.ProductionRemotes`, its server-common siblings
`networking.ProductionRateLimits` and `networking.ServerRemoteRegistry`, and
`Shutdown.luau`. `ServerRemoteRegistry` owns its sibling `ServerRateLimiter` and
`ServerRequestDispatcher` dependencies. The bootstrap creates and registers the
one network service only after successful configuration validation. These
server-only modules are mapped into every production server build but are not
shared with clients and do not cross a place-role boundary.

`src/client/common/networking/ClientRemoteLookup.luau` depends only on shared
place-role, production-registry, registry, and Result contracts. It is not
imported by the bootstrap and cannot import or create server state. Its public
production API resolves only through the internally imported
`ProductionRemotes`; a dependency-injected seam exists only when the exact module
has the exact
`ServerStorage.AutomatedTests.ProductionClientNetworking.ClientRemoteLookup`
identity in the isolated Test build. Both runtime networking modules stay in
their appropriate common layer, and the shared production definition graph
stays safe for replication.

`src/client/common/networking/ClientRequestTracker.luau` depends only on shared
place-role, payload-validation, production-registry, registry, request-protocol,
and Result contracts plus fixed Roblox services used for production construction
and GUID generation. It neither selects a remote path nor sends a request. The
current Match Ready and enemy controllers pair its returned definition/envelope
with the fixed `ClientRemoteLookup` result and call `clear()` during cleanup.
The dependency-injected constructor is exposed only at the corresponding exact
non-replicated Test-project identity.

`src/shared/network/RequestProtocol.luau` depends only on shared
`PayloadValidation`, `Result`, and `Validation` contracts. It defines the exact
request, event, response, public-error, and correlation-state shapes without
importing either runtime side. Both the server dispatcher and client tracker
consume this one shared wire contract.

`src/shared/network/PayloadValidation.luau` depends only on the lower-level
shared `util/Ids`, `util/Result`, and `util/Validation` contracts. Its
authenticated validators, schemas, and Instance policies contain no client or
server import and do not select a place role. Live Instance acceptance is
checked at validation time and fails outside a running server; the isolated
headless seam is gated by the exact Test-project structure.

Phase 09 preserves the same one-way dependency graph. Shared `EnemyProtocol`
depends only on lower shared network, ID, Result, and validation contracts. The
four server enemy modules depend only on shared and server-Match modules; the
four client enemy modules depend only on shared, client-common networking, and
client-Match modules. Any dependency-injected Test seam remains gated by its
non-replicated `ServerStorage.AutomatedTests` identity. `EnemyProtocol` follows
the shared mapping into Lobby, but no place-specific enemy runtime module maps
there, imports a test module, or crosses the server/client boundary.

## Automated verification

| Check | Result |
| --- | --- |
| Pre/post move SHA-256 comparison | Pass; both bootstrap hashes unchanged |
| Place-specific runnable-file scan | Pass; 0 files |
| Total runnable-file scan | Pass; 1 server and 1 client bootstrap, both common |
| `stylua src` | Pass; no bootstrap content rewrite |
| `stylua --check src` | Pass |
| `stylua --check --verify src` | Pass |
| `selene src` | Pass; 0 errors, 0 warnings, 0 parse errors |
| `rojo build -o packet-02-1-smoke.rbxlx` | Pass |
| Built DataModel script count | Pass; exactly 1 Script and 1 LocalScript |
| Built place-specific folders | Pass; lobby and match folders contained no scripts |

The ignored smoke-build artifact was inspected and removed. It can be recreated
with the build command above.

### Historical Phase 08 source layout

At Phase 08 completion, the structural contract expected 54 ModuleScripts in
Default and Match, 43 in Lobby, and exactly one Script plus one LocalScript in
every production build. The common inventory contained 34 shared modules; six
server-only common modules (`Shutdown`, `ServerBootstrap`, and the four
networking modules); and three client-only common modules (`ClientBootstrap`
and the two networking modules). Default and Match added eight server-only Match
modules and three client-only Match modules. Default deliberately excluded both
physical Match entrypoint sources; Match mapped those sources in place of the
common Main files.

At that checkpoint, the Test build contained exactly 90 ModuleScripts and zero
runnable Script or LocalScript instances: 34 shared modules, six common
networking mirrors, three map mirrors, two lifecycle mirrors, one roster mirror,
two ready mirrors, three client-Match mirrors, and 39 test-owned modules. Its
Phase 08 production mirrors are exact and Test-only:

- `ProductionServerMatchLifecycle`: `MatchLifecycleService` and
  `MatchStateMachine`;
- `ProductionServerMatchRoster`: `ParticipantRoster`;
- `ProductionServerMatchReady`: `ReadyCheckCoordinator` and
  `SnapshotBroadcaster`; and
- `ProductionClientMatch`: `MatchReadyController`, `MatchReadyView`, and
  `MatchReadyViewModel`.

`MatchProtocol` is mapped once through the normal 34-module shared tree. The
exact Phase 08 Test-owned specs are `MatchProtocol`, `MatchStateMachine`,
`MatchLifecycleService`, `ParticipantRoster`, `ReadyCheckCoordinator`,
`SnapshotBroadcaster`, `MatchReadyViewModel`, `MatchReadyView`, and
`MatchReadyController`. The verifier authenticates every production mirror and
test-owned module by exact DataModel path, class, authoritative file, and
byte-for-byte source; unlisted Test-owned source fails.

Lobby contains no server/client Match-role source, Match contains no Lobby
source, and tests and Studio tools occur in no production build. Packets
08.1–08.5, the four-client Studio gate, consolidated final review, and complete
local exit gate passed.
Phase 08 is complete; at that historical checkpoint, Phase 09 was next and had
not begun.

### Historical Phase 09 source layout

The Phase 09 structural contract expected 63 ModuleScripts in Default and Match,
44 in Lobby, and exactly one Script plus one LocalScript in every production
build. The common production inventory contains 35 shared modules, six
server-only common modules, and three client-only common modules, for 44
ModuleScripts. Default and Match add 12 server-Match modules and seven
client-Match modules for 63. The 12 are the three map, two lifecycle, one
roster, two ready, and four enemy modules; the seven are the three Ready client
modules and four enemy client modules. Default still excludes both physical
Match entrypoints, Match substitutes them at the stable common Main paths, and
Lobby maps no server/client Match-role source. Lobby still receives
`EnemyProtocol` through the authoritative shared tree.

The Test build contains exactly 111 ModuleScripts and zero runnable Script or
LocalScript instances: 35 authoritative shared modules, 25 exact production
mirrors, and 51 test-owned modules. The 25 mirrors are the six common networking
modules, three map modules, two lifecycle modules, one roster module, two ready
modules, three Phase 08 client-Match modules, four server enemy modules, and four
client enemy modules. The 51 Test-owned modules are exactly 39 specs, four
fixtures, three support modules, and five negative controls.

The Phase 09 Test-only mirrors are:

- `ProductionServerEnemies`: `EnemyPath`, `EnemyReplicationPublisher`,
  `EnemyRuntimeStore`, and `EnemySimulationService`; and
- `ProductionClientEnemies`: `EnemyController`, `EnemyPresentation`,
  `EnemyRenderer`, and `EnemyReplicationState`.

`EnemyProtocol` is mapped once through the normal 35-module authoritative
shared tree. The exact Phase 09 specs are `EnemyProtocol`, `EnemyPath`,
`EnemyRuntimeStore`, `EnemyMovement`, `EnemyReplicationPublisher`,
`EnemyReplicationState`, `EnemyPresentation`, `EnemyRenderer`,
`EnemySimulationService`, `EnemySimulationIntegration`, and `EnemyController`;
`EnemyFixtures` is the one new Test-owned fixture. These 11 suites contain 120
focused cases. The complete local run passes 39 suites and 467 cases in total.

At Phase 09 completion the production network catalog contained five reliable
Match-only endpoints and the production rate catalog contained three policies.
Production `Enemies` and `Assets` remained frozen empty arrays. Tests, fixtures, support,
negative controls, and Studio tools occur in no production build. Packets
09.1–09.5, the exact Match Studio gate, consolidated review, complete local
gate, and exact structural inventory passed on 2026-08-27. Phase 09 is complete;
that dated inventory remains historical. The current Phase 10 extension follows.

### Current Phase 10 source and Test boundary

`BaseProtocol` is mapped once through the normal authoritative shared tree.
Default and Match map the three `src/server/match/base` modules and four
`src/client/match/base` modules; Lobby maps none of those seven role-specific
modules. Match still substitutes only its two existing role entrypoints at the
stable common Main paths, so no new runnable source is introduced.

Test mirrors the exact three server modules beneath `ProductionServerBase` and
the exact four client modules beneath `ProductionClientBase`. `BaseFixtures` and
the nine Base specs shown in the source excerpt are Test-owned. No bootstrap,
Studio trigger/harness source, role entrypoint, Script, or LocalScript is mapped
into Test, and no test source is mapped into a production project.

The verifier authenticates every Phase 10 path, class, authoritative file, and
source byte; checks Lobby/Match isolation; keeps exactly one Script and one
LocalScript in each production build and zero Test runnables; rejects generated
output and Phase 11 markers; and proves production `Difficulties`, `Maps`,
`Waves`, `Enemies`, and `Assets` remain empty. The current registry has exactly
seven reliable Match-only endpoints and four inbound request-rate policies. The
complete gate passed `593` cases across `48` suites; Default/Lobby/Match/Test
contain `71/45/71/129` ModuleScripts and Script/LocalScript counts `1/1`, `1/1`,
`1/1`, and `0/0` respectively.

Phase 10 focused and exact Match Studio checks, consolidated review, complete
local gate, and all four structural builds passed on 2026-08-28. Phase 10 is
complete; exact-final-SHA CI is cited at handoff. Phase 11 is next and remains
unbegun.

## Historical Packet 02 Roblox Studio verification

The connected Ant Tower Defense place, PlaceId `100561454756026`, was verified
without manually editing or saving any Studio instance.

### Edit-mode hierarchy

- `ServerScriptService.Server.common.bootstrap.Main` was the only server Script.
- `StarterPlayer.StarterPlayerScripts.Client.common.bootstrap.Main` was the only
  client LocalScript template.
- Server and client `lobby` and `match` folders existed and were empty.
- `ReplicatedStorage.Shared` remained present.
- The synchronized bootstrap source matched the filesystem.

### Play-mode assertions

One local Play session produced the existing structured server and client
bootstrap logs. Read-only checks returned:

| Assertion | Server | Client |
| --- | ---: | ---: |
| Total runnable scripts under the mapped root | 1 | 1 |
| Runnable scripts under `common` | 1 | 1 |
| Runnable scripts under `lobby` | 0 | 0 |
| Runnable scripts under `match` | 0 | 0 |
| Old root-level `Main` exists | false | false |
| `ReplicatedStorage.Shared` exists | true | true |

The Play session was stopped and Studio returned to Edit mode. No Studio-authored
content, DataStore, external service, save operation, or publish operation was
used.

### Packet 06.5 unsaved networking regression

The later Packet 06.5 engine regression used Studio `0.735.0.7351131` from
installation directory `version-dcbeee682ce74ee0`. With
`lobby.project.json` connected only to Lobby and
`match.project.json` connected only to Match, one project at a time, three
unsaved Lobby cycles and three unsaved Match cycles passed. The final authorized
two-client networking regression also passed. Both places were left in Edit
mode, and neither was saved or published.

The reusable source for that manual check is
`tests/studio/Phase06NetworkServer.server.luau` and
`tests/studio/Phase06NetworkClient.client.luau`. These tracked files are mapped
by no Rojo project and do not change either production bootstrap count.

## Manual regression procedure

1. Run `rojo serve` from the repository root and connect the development place.
2. Confirm the Edit-mode hierarchy listed above.
3. Search both lobby and match folders for `BaseScript` descendants; expect 0.
4. Start a local Play test.
5. Confirm exactly the structured common server-ready and client-ready messages
   appear for the test session, with no application error or warning.
6. Confirm both runtime roots contain one common runnable bootstrap and no lobby
   or match runnable script.
7. Stop Play and confirm Studio returns to Edit mode.
8. Do not save or publish merely to complete this regression test.

Packet 02.2 added isolated Rojo project definitions without weakening these
dependency rules. Packet 02.3 added centralized place identity checks and no
cross-role import. Packet 02.4 owns isolated Studio connections.

## Automated-test boundary

Packet 05.1 added repository-owned Luau under `tests/`. It is not production
source and initially depended only on exact shared ModuleScripts in the isolated
Rojo test build. Packets 06.1, 06.3, and 06.4 narrowly add exact mappings of six
common networking modules under `ServerStorage.AutomatedTests`:
`ProductionRateLimits`, `ServerRemoteRegistry`, `ServerRateLimiter`,
`ServerRequestDispatcher`, `ClientRemoteLookup`, and `ClientRequestTracker`.
At those Phase 06 checkpoints, the Test project mapped neither bootstrap, the
shutdown hook, nor any place-specific layer. Packet 06.5 added the integrated
adversarial spec to the Test-only spec root; its two `tests/studio` networking
harness sources remain mapped nowhere. Phase 07 added three exact production
map mirrors, one fixture, three specs, one runtime map harness, and one
default-deny Edit authoring command; the two Phase 07 Studio tools also remain
mapped nowhere. Phase 08 added the exact lifecycle, roster, ready, and
Match-ready client mirrors listed in its historical section above.

Phase 09 adds only eight exact place-specific production mirrors under
`ServerStorage.AutomatedTests`: four beneath `ProductionServerEnemies` and four
beneath `ProductionClientEnemies`. Its eleven specs and `EnemyFixtures` remain
Test-owned. Phase 10 adds the exact three `ProductionServerBase` and four
`ProductionClientBase` mirrors; its nine specs and `BaseFixtures` remain
Test-owned. The Test project still maps no bootstrap, shutdown hook, role
entrypoint, Script, or LocalScript. Production code must never import a test
module, and fixtures and intentional negative controls stay under test-only
directories. The frozen production `src/shared/config/Enemies.luau` and
`src/shared/config/Assets.luau` catalogs remain empty, as do `Difficulties`,
`Maps`, and `Waves`. The production remote registry contains only the seven
reliable Match endpoints, and only its four client-to-server requests have
production rate policies.

`test.project.json` creates no runnable Script or LocalScript. Conversely,
Default, Lobby, and Match map no test directory.
At Phase 07 completion, `lune run tests/verify-builds.luau` enforced exact
positive path/class/source maps for all 45 Default/Match and 42 Lobby production
Lua containers, exact source identity for the six test-mapped networking
modules and three production map modules, and an exact positive
path/class/source map for all 30 Test-owned ModuleScripts. Those counts are
historical.

The current Phase 10 verifier enforces both mapping directions across the
complete generated DataModels and its exact allowlists of authoritative shared,
production-mirror, and Test-owned modules. It authenticates DataModel path,
class, authoritative file, and byte-for-byte source, rejects unlisted Test-owned
source, proves zero Test runnables, excludes all tests and Studio tools from
production, and rejects Phase 11 source or behavior. The final Phase 10
inventory is `71/45/71/129` ModuleScripts across Default/Lobby/Match/Test, with
no Test runnable source.

This headless boundary and every environment-specific follow-up are indexed in
`docs/TEST_MATRIX.md`; passing it does not substitute for published-client or
device evidence. Packet 06.5's specific unsaved Studio and two-client regression
is recorded above. Phase 09's exact two-client Match Studio evidence,
consolidated review, 467-case local gate, and four current structural builds
passed on 2026-08-27 and are recorded in `docs/ENEMY_SIMULATION.md`. Phase 10's
focused and exact Studio evidence is recorded in `docs/BASE_RUNTIME.md`. The
exact-final-SHA CI evidence is cited at handoff.
