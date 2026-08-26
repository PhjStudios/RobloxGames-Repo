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
      PlaceRoles.luau
    lifecycle/
      ServiceLifecycle.luau
    util/
      Cleanup.luau
  server/
    common/
      bootstrap/
        Main.server.luau
    lobby/
      .gitkeep
    match/
      .gitkeep
  client/
    common/
      bootstrap/
        Main.client.luau
    lobby/
      .gitkeep
    match/
      .gitkeep
```

The remaining `.gitkeep` files preserve the four empty place-specific
architecture directories until packet-approved source replaces them. They are
not Luau modules or runnable scripts. Rojo represents the directories as empty
folders and does not create instances for the `.gitkeep` files themselves.

`src/shared` remains the location for code that is safe and useful across both
execution contexts and both place roles. Packet 02.3 added the typed place-role
configuration described in `docs/PLACE_ROLES.md`. Packet 03.1 added the typed
service lifecycle contract described in `docs/SERVICE_LIFECYCLE.md`. Packet 03.2
added the ownership utility described in `docs/CLEANUP.md`.

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
   diagnostics, and start no lobby or match service.
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

The current common client and server bootstraps require only
`ReplicatedStorage.Shared.config.PlaceRoles` and
`ReplicatedStorage.Shared.lifecycle.ServiceLifecycle`, plus
`ReplicatedStorage.Shared.util.Cleanup`. All imports follow the allowed
common-to-shared dependency direction. No cross-role import exists.

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
