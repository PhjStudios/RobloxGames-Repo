# Rojo Project Definitions

## Purpose

This document records the multi-project Rojo structure and verification evidence
for Packet 02.2 of `docs/DEVELOPMENT_PLAN.md`. It distinguishes the combined
development project from the role-isolated lobby and match projects without
assigning PlaceIds. Packet 02.3 subsequently added the centralized runtime role
configuration recorded in `docs/PLACE_ROLES.md`.

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
they still do not duplicate runtime PlaceIds.

## Project inventory

| Project | Purpose | Server layers | Client layers | Place binding |
| --- | --- | --- | --- | --- |
| `default.project.json` | Combined convenience project and documented `rojo serve` default | `common`, `lobby`, `match` | `common`, `lobby`, `match` | Existing development `servePlaceIds`; current role is `Development` |
| `lobby.project.json` | Role-isolated lobby source | `common`, `lobby` | `common`, `lobby` | No ID binding; current role is `Lobby` |
| `match.project.json` | Role-isolated match source | `common`, `match` | `common`, `match` | No ID binding; current role is `Match` |

All projects map `src/shared` to `ReplicatedStorage.Shared`.

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

It maps all source layers for repository-wide inspection and transitional local
work. At the current scaffold stage it is safe to Play because lobby and match
contain no runnable scripts. Once role-specific entrypoints exist, role testing
must use `lobby.project.json` or `match.project.json`; the combined project must
not be treated as proof of place-role isolation.

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

Role-specific source will appear only under its corresponding `lobby` or `match`
folder when later packets add it.

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

Only one Rojo project should be connected to a given Studio place at a time.
Packet 02.4 owns the manual gate that connects the correct isolated project to
each real place.

### Build

- Combined: `rojo build default.project.json -o default.rbxlx`
- Lobby: `rojo build lobby.project.json -o lobby.rbxlx`
- Match: `rojo build match.project.json -o match.rbxlx`

Root `*.rbxl` and `*.rbxlx` outputs are ignored under `docs/CODE_STYLE.md`. Build
artifacts are local verification products, not authoritative Studio content.

## Structural verification

All three project JSON files parsed successfully and all three builds completed
with Rojo 7.7.0.

| Build | Server layers | Client layers | Script count | LocalScript count |
| --- | --- | --- | ---: | ---: |
| Default | `common`, `lobby`, `match` | `common`, `lobby`, `match` | 1 | 1 |
| Lobby | `common`, `lobby` | `common`, `lobby` | 1 | 1 |
| Match | `common`, `match` | `common`, `match` | 1 | 1 |

Additional assertions passed:

- Lobby JSON contains no server/client match source path.
- Match JSON contains no server/client lobby source path.
- Lobby build contains no match folder or source.
- Match build contains no lobby folder or source.
- All builds contain `ReplicatedStorage.Shared`.
- `.gitkeep` files produce no Roblox instances.
- Both structured common bootstrap records are present in every build.
- Each role project has 12 verified unknown-instance-preservation boundaries.
- The new project files contain no `servePlaceIds`, known PlaceId, universe ID,
  or duplicated runtime PlaceId. Packet 02.3 later added only their role
  attributes.

Current Packet 03.4 builds contain the five shared ModuleScripts `PlaceRoles`,
`ServiceLifecycle`, `EnvironmentContext`, `Log`, and `Cleanup`, plus the
server-only common `Shutdown` ModuleScript. Each build therefore contains six
ModuleScripts, one Script, and one LocalScript. The Default build contains both
empty role folders, the Lobby build contains no match folder, and the Match
build contains no lobby folder. Source-layer isolation remains unchanged.

The inspected ignored build artifacts were removed. They can be recreated with
the commands above.

## Scope boundary and next gate

Packet 02.2 did not create the Match place, connect a role project to a real
place, run role-specific code, save Studio content, or publish. Packet 02.4 has
since passed the real Lobby-versus-Match Studio isolation gate; current evidence
is recorded in `docs/MULTI_PLACE_GATE.md`.
