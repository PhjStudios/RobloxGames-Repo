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

## Current source tree

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
        Shutdown.luau
      networking/
        ProductionRateLimits.luau
        ServerRemoteRegistry.luau
        ServerRateLimiter.luau
        ServerRequestDispatcher.luau
    lobby/
      .gitkeep
    match/
      .gitkeep
  client/
    common/
      bootstrap/
        Main.client.luau
      networking/
        ClientRemoteLookup.luau
        ClientRequestTracker.luau
    lobby/
      .gitkeep
    match/
      .gitkeep
tests/
  fixtures/
    NetworkFixtures.luau
  negative/
  specs/
    ClientRequestTracker.spec.luau
    PayloadValidation.spec.luau
    RemoteRegistry.spec.luau
    RemoteRuntime.spec.luau
    RequestProtocol.spec.luau
    ServerRateLimiter.spec.luau
    ServerRequestDispatcher.spec.luau
  support/
```

The remaining `.gitkeep` files preserve the four empty place-specific
architecture directories until packet-approved source replaces them. They are
not Luau modules or runnable scripts. Rojo represents the directories as empty
folders and does not create instances for the `.gitkeep` files themselves.

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
`Validation` modules and is safe to replicate; neither bootstrap imports it yet
because the lasting production endpoint registry remains empty. It adds no
server/client layer, lifecycle service, runnable entrypoint, gameplay schema, or
place-specific dependency.

Packet 06.3 added the server-only `networking/ProductionRateLimits.luau` and
`networking/ServerRateLimiter.luau` modules under the existing common server
network owner, plus one test-only spec. It adds no lifecycle service or runnable
entrypoint. The lasting production rate-policy list is frozen and empty because
the lasting production registry is empty.

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

Roblox automatically runs files mapped as `Script` or `LocalScript`. Under the
current unsplit `default.project.json`, all descendants of `src/server` and
`src/client` are mapped into the same development place. Therefore Packet 02.1
enforces:

1. The only `*.server.luau` file is
   `src/server/common/bootstrap/Main.server.luau`.
2. The only `*.client.luau` file is
   `src/client/common/bootstrap/Main.client.luau`.
3. Lobby and match directories contain no runnable BaseScript.
4. The common bootstraps validate the declared role, emit development
   diagnostics, and start no lobby or match service. The common server now
   registers one foundation-only `NetworkRegistry` service, whose internal
   dispatcher and limiter remain owned children rather than additional lifecycle
   services; the client remains at zero services.
5. Any future lobby or match entrypoint must be tested through its isolated
   Packet 02.2 project, never through the combined project as evidence of role
   isolation.

This is how the default development place avoids starting both roles. Packet
02.1 did not infer a role from PlaceId or add conditional place loading. Packet
02.3 subsequently added centralized boot validation without adding either
place's services.

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
and GUID generation. It neither selects a remote path nor sends a request. A
future client owner must pair its returned definition/envelope with the fixed
`ClientRemoteLookup` result and must call `clear()` during that owner's cleanup.
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

### Current Packet 06.4 source layout

The four-project structural contract now expects 40 ModuleScripts, one Script,
and one LocalScript in every production build. That is 42 exact production Lua
source containers: 33 shared modules; the server-only `Shutdown`,
`ProductionRateLimits`, `ServerRemoteRegistry`, `ServerRateLimiter`, and
`ServerRequestDispatcher` modules; the client-only `ClientRemoteLookup` and
`ClientRequestTracker` modules; and the two common bootstraps.

The Test build's production source subset contains all 33 shared modules and
exactly six common networking modules copied under test-only `ServerStorage`
paths. It maps four server modules (`ProductionRateLimits`,
`ServerRemoteRegistry`, `ServerRateLimiter`, and `ServerRequestDispatcher`) and
two client modules (`ClientRemoteLookup` and `ClientRequestTracker`). Test-owned
specs, fixtures, support, and negative controls remain separate, and the build
has zero runnable scripts. Lobby contains no Match source, Match contains no
Lobby source, and lasting production remote definitions and rate policies
remain empty. Packet 06.4 implementation is present; Packet 06.5 and the fresh
Phase 06 exit audit remain open.

## Roblox Studio verification

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
The Test project maps neither bootstrap, the shutdown hook, nor any
place-specific layer. Production code must never import a test module. Fixtures
and intentional negative controls stay under test-only
directories; lasting authored catalogs under `src/shared/config` and lasting
remote definitions under `src/shared/network/ProductionRemotes.luau` remain
empty or policy-only.

`test.project.json` creates no runnable Script or LocalScript. Conversely,
Default, Lobby, and Match map no test directory.
`lune run tests/verify-builds.luau` enforces both directions across the complete
generated DataModels, including an exact positive path/class/source map for all
42 current production Lua containers and exact source identity for the six
test-mapped networking modules.

This headless boundary and every environment-specific follow-up are indexed in
`docs/TEST_MATRIX.md`; passing it does not substitute for a deferred Studio,
multi-client, published-client, or device gate.
