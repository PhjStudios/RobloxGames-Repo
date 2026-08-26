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
they still do not duplicate runtime PlaceIds.

## Project inventory

| Project | Purpose | Server layers | Client layers | Place binding |
| --- | --- | --- | --- | --- |
| `default.project.json` | Combined convenience project and documented `rojo serve` default | `common`, `lobby`, `match` | `common`, `lobby`, `match` | Existing development `servePlaceIds`; current role is `Development` |
| `lobby.project.json` | Role-isolated lobby source | `common`, `lobby` | `common`, `lobby` | No ID binding; current role is `Lobby` |
| `match.project.json` | Role-isolated match source | `common`, `match` | `common`, `match` | No ID binding; current role is `Match` |
| `test.project.json` | Headless contract/runtime-module test DataModel | No runnable layer; exact `common/networking` modules under `ServerStorage` | No runnable layer; exact `common/networking` modules under `ServerStorage` | Build-only; no role or `servePlaceIds` |

All four projects map `src/shared` to `ReplicatedStorage.Shared`. Only the test
project additionally maps `tests/specs`, `tests/fixtures`, `tests/support`, and
isolated negative controls under `ServerStorage`. Packet 06.1 also maps exactly
`src/server/common/networking` and `src/client/common/networking` beneath
`ServerStorage.AutomatedTests`; it still maps no bootstrap, shutdown module,
place-specific layer, or runnable Script/LocalScript.

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
and Packet 06.1 added the two narrow runtime
module mappings described above.

| Build | Server layers | Client layers | ModuleScripts | Scripts | LocalScripts |
| --- | --- | --- | ---: | ---: | ---: |
| Default | `common`, `lobby`, `match` | `common`, `lobby`, `match` | 34 | 1 | 1 |
| Lobby | `common`, `lobby` | `common`, `lobby` | 34 | 1 | 1 |
| Match | `common`, `match` | `common`, `match` | 34 | 1 | 1 |
| Test | No runnable layer; two selected runtime modules under `ServerStorage` | Same | 52 | 0 | 0 |

Additional assertions passed:

- Lobby JSON contains no server/client match source path.
- Match JSON contains no server/client lobby source path.
- Lobby build contains no match folder or source.
- Match build contains no lobby folder or source.
- Default, Lobby, and Match contain no test spec, fixture, support module,
  negative control, runner entrypoint, or test-only dependency.
- Every one of the 36 production Lua containers matches a fixed expected
  DataModel path, class, authoritative `src/` file, and exact source content.
- Test contains the same 31 shared ModuleScripts plus exactly
  `ServerRemoteRegistry` and `ClientRemoteLookup` under test-only
  `ServerStorage` paths, 19 test-owned spec/fixture/support/negative-control
  ModuleScripts, and no runnable Script or LocalScript.
- All builds contain `ReplicatedStorage.Shared`.
- `.gitkeep` files produce no Roblox instances.
- Both structured common bootstrap records are present in every production
  build; the Test build is intentionally bootstrap-free.
- Each role project has 12 verified unknown-instance-preservation boundaries.
- The new project files contain no `servePlaceIds`, known PlaceId, universe ID,
  or duplicated runtime PlaceId. Packet 02.3 later added only their role
  attributes.

The current production source inventory contains 31 shared ModuleScripts:
`PlaceRoles`,
`ServiceLifecycle`, `EnvironmentContext`, `Log`, `Cleanup`, `Ids`, `Result`,
`Validation`, `ConfigTypes`, `AssetSchema`, `Assets`, `BannerSchema`, `Banners`,
`ConfigurationValidator`, `DefaultSettings`, `Difficulties`, `DifficultySchema`, `Economy`,
`EconomySchema`, `Enemies`, `EnemySchema`, `MapSchema`, `Maps`,
`SchemaPrimitives`, `SettingsSchema`, `TowerSchema`, `Towers`, `WaveSchema`, and
`Waves`, plus `ProductionRemotes` and `RemoteRegistry`. The server-only common
`Shutdown` and `ServerRemoteRegistry` modules and client-only common
`ClientRemoteLookup` module bring each production build to 34 ModuleScripts,
alongside one Script and one LocalScript. The Default build contains both empty
role folders, the Lobby build contains no match folder, and the Match build
contains no lobby folder. Source-layer isolation remains unchanged. Packet 04.4
schema evidence is recorded in `docs/ECONOMY_BANNER_SETTINGS_SCHEMAS.md`; current
whole-catalog evidence is in `docs/CONFIGURATION_VALIDATION.md`, and the network
layout is in `docs/NETWORK_PROTOCOL.md`.

The inspected ignored build artifacts were removed. They can be recreated with
the commands above. `lune run tests/verify-builds.luau` rebuilds and checks all
four definitions across the complete DataModel and removes only its exact
generated outputs.

The structural verifier is the current headless production-shipping gate. Its
status and the separate Studio/published test boundaries are indexed in
`docs/TEST_MATRIX.md`.

At Packet 06.1 completion, the canonical runner passed 106
of 106 cases across ten suites and the four-project verifier passed the exact
counts above. The Test-only runtime mappings are source-identical copies used by
the headless adapter; they do not alter production mappings or make the test
project suitable for serving. Packet 06.1 is complete; Phase 06 and Gate A
remain open.

## Scope boundary and next gate

Packet 02.2 did not create the Match place, connect a role project to a real
place, run role-specific code, save Studio content, or publish. Packet 02.4 has
since passed the real Lobby-versus-Match Studio isolation gate; current evidence
is recorded in `docs/MULTI_PLACE_GATE.md`.
