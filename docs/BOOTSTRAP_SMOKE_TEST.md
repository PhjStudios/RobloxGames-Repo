# Bootstrap Cleanup and Studio Smoke Test

## Purpose

This document records the implementation and verification evidence for Packet
01.3 of `docs/DEVELOPMENT_PLAN.md`. The packet removes temporary scaffold
behavior and leaves only harmless client and server entry points for later
phases.

## Packet status

- Packet: 01.3
- Status: Complete
- Recorded: 2026-08-25
- Place tested: Ant Tower Defense, PlaceId `100561454756026`
- Studio version: `0.735.0.7351131`
- Gameplay systems added: none
- Studio-authored content changed: no
- Place saved or published by this packet: no

## Source changes

### Client bootstrap at Packet 01.3 completion

At that checkpoint, `src/client/common/bootstrap/Main.client.luau`:

- Obtains `RunService`.
- Emits one structured `ready` record only when `RunService:IsStudio()` is true.
- Creates no instances, connections, tasks, UI, input handling, or gameplay
  state.

### Server bootstrap at Packet 01.3 completion

At that checkpoint, `src/server/common/bootstrap/Main.server.luau`:

- Obtains `RunService`.
- Emits one structured `ready` record only when `RunService:IsStudio()` is true.
- Creates no parts, folders, tweens, loops, tasks, connections, or gameplay
  state.

### Removed example module

Before deletion, a source-scoped reference search for `Example`, `getMessage`,
and `Shared module is working` found matches only inside
`src/shared/Example.luau` itself. No client, server, or other shared source
required it, so the file was removed.

Post-change searches found no source or generated-build references to:

- `Example`
- `getMessage`
- `Shared module is working`
- `JumpingBricks`
- `runJumpLoop`
- `TweenService`

At Packet 01.3 completion, `src/shared` contained no Luau module and remained
mapped as `ReplicatedStorage.Shared`. Packet 02.3 later added the typed
`PlaceRoles` module and integrated it into both bootstraps; the removed example
behavior did not return.

### Current bootstrap behavior after Packet 03.2

Both common bootstraps now obtain `ReplicatedStorage` and `RunService`, validate
the shared place-role configuration, and resolve the project's declared role
against `game.PlaceId`. An invalid configuration or pairing produces a
structured error and stops that bootstrap. After successful role validation,
each bootstrap creates, initializes, and starts a context-specific lifecycle
runner with zero services. Packet 03.2 then creates a context-labelled cleanup
container and registers the runner's existing shutdown operation as its one
task. A valid Studio boot remains harmless and emits one ready record. See
`docs/PLACE_ROLES.md`, `docs/SERVICE_LIFECYCLE.md`, and `docs/CLEANUP.md` for the
current contracts.

## Bootstrap log contract

At Packet 01.3 completion, the two development records used this temporary,
directly readable format:

```text
[ATD][INFO][context=<client|server>][subsystem=bootstrap][event=ready][placeId=<safe ID>] <message>
```

The fields satisfy the existing logging decision by including severity,
execution context, subsystem, event, and a safe environment identifier. The
records are Studio-only, contain no player data or secrets, and occur once per
bootstrap rather than inside a loop.

Packet 01.3 deliberately does not add a shared logger or environment framework;
that belongs to Phase 03. Those direct strings are a minimal bridge that makes
startup failures visible without pulling later architecture forward.

Packet 02.3 extended successful records with `[role=<Development|Lobby|Match>]`
and added structured place-role rejection records. It still did not add the
Phase 03 logger or lifecycle framework.

Packet 03.1 subsequently extended successful records with
`[lifecycleState=Started][serviceCount=0]`. It added a focused lifecycle runner,
not the Packet 03.3 logging framework. Ready diagnostics remain direct,
Studio-only strings.

Packet 03.2 extended those records with
`[cleanupState=Active][cleanupTaskCount=1]`. It did not add a shutdown trigger;
Packet 03.4 still owns that behavior.

## Automated verification

The following checks passed after the source cleanup:

| Check | Result |
| --- | --- |
| `stylua src` | Pass; formatted source with no unrelated rewrite |
| `stylua --check src` | Pass |
| `stylua --check --verify src` | Pass; formatted AST verified |
| `selene src` | Pass; 0 errors, 0 warnings, 0 parse errors |
| `rojo build -o packet-01-3-smoke.rbxlx` | Pass; project `Ant Tower Defense` built successfully |
| Generated-build temporary-content search | Pass; no example, brick, loop, or TweenService content |
| Generated-build bootstrap search | Pass; both structured bootstrap records present |

The ignored smoke-build artifact was removed after inspection. It can be
regenerated with the command above and is not authoritative content.

## Current Roblox Studio smoke-test procedure

Use this procedure for Packet 01.3 regression checks:

1. From the repository root, restart `rojo serve` if it was already running when
   a project definition changed.
2. Open the development place with PlaceId `100561454756026` in Roblox Studio.
3. Connect the Rojo plugin to the repository server.
4. In Edit mode, confirm:
   - `ReplicatedStorage` has `ATDPlaceRole = Development`.
   - Both common `Main` bootstraps contain shared place-role validation and
     zero-service lifecycle startup.
   - `ReplicatedStorage.Shared.config.PlaceRoles` exists.
   - `ReplicatedStorage.Shared.lifecycle.ServiceLifecycle` exists.
   - `ReplicatedStorage.Shared.util.Cleanup` exists.
   - `ReplicatedStorage.Shared.Example` does not exist.
5. Open Output and clear old messages if verifying manually.
6. Start a local Play test.
7. Confirm Output contains one server record and one client record:

   ```text
   [ATD][INFO][context=server][subsystem=bootstrap][event=ready][role=Development][placeId=100561454756026][lifecycleState=Started][serviceCount=0][cleanupState=Active][cleanupTaskCount=1] Server bootstrap ready
   [ATD][INFO][context=client][subsystem=bootstrap][event=ready][role=Development][placeId=100561454756026][lifecycleState=Started][serviceCount=0][cleanupState=Active][cleanupTaskCount=1] Client bootstrap ready
   ```

8. Confirm there is no script error or warning from either bootstrap.
9. In both the Server and Client DataModels, confirm:
   - `Workspace.JumpingBricks` does not exist.
   - `ReplicatedStorage.Shared.Example` does not exist.
   - The applicable client or server `Main` bootstrap exists.
10. Stop the Play test.
11. Confirm Studio returns to Edit mode and `Workspace.JumpingBricks` still does
    not exist.
12. Do not save or publish merely to complete this smoke test.

## Historical Packet 01.3 Studio result

The original Packet 01.3 procedure was executed through the connected Studio
control endpoint on 2026-08-25. The role-aware procedure above supersedes it for
future regression runs.

### Before Play

- Studio state: Edit.
- Rojo-synchronized server and client script contents matched the filesystem.
- `ReplicatedStorage.Shared` existed with no `Example` child.
- Studio script search returned no `JumpingBricks` match.

### During Play

- Studio state: Play with Client and Server DataModels available.
- Output captured both expected records with PlaceId `100561454756026`.
- No application script error or warning appeared in the captured smoke-test
  Output.
- Server assertions:
  - `isStudio = true`
  - `hasServerMain = true`
  - `hasExample = false`
  - `hasJumpingBricks = false`
- Client assertions:
  - `isStudio = true`
  - `hasClientMain = true`
  - `hasExample = false`
  - `hasJumpingBricks = false`

### After Play

- The Play session was stopped.
- Studio returned to Edit mode.
- No `JumpingBricks` instance existed in the Edit DataModel.
- No Studio instance was authored, moved, renamed, or deleted manually.
- No save, DataStore access, external service mutation, or publish occurred.

This satisfies the Phase 01 exit gate: client and server boot cleanly, formatting,
linting, and build checks pass, and no temporary gameplay behavior remains.
