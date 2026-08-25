# Place Role Configuration

## Purpose

This document records the implementation contract and verification evidence for
Packet 02.3 of `docs/DEVELOPMENT_PLAN.md`. The shared configuration prevents a
Lobby project, Match project, or combined development project from silently
booting in the wrong Roblox place.

## Packet status

- Packet: 02.3
- Status: Complete
- Recorded: 2026-08-25
- Gameplay systems added: none
- Match place created or identified: no
- Studio-authored content changed: no
- External services enabled: no
- Place saved or published: no

## Single runtime source of truth

`src/shared/config/PlaceRoles.luau` is the only Luau location that stores or
resolves place-role identifiers. It exports typed roles, typed success/failure
results, configuration validation, and a deterministic resolver.

| Role | Runtime PlaceId state | Intended use |
| --- | --- | --- |
| `Development` | No independent production ID | Combined project in Studio, paired only with the known Lobby place |
| `Lobby` | Known Lobby PlaceId | Lobby-isolated project |
| `Match` | Unset | Match-isolated project after Packet 02.4 provides a real ID |

The unset Match value is the non-numeric sentinel `false` inside the private
configuration table. Public lookup converts it to `nil`. This is safer than `0`
or a fabricated number because it cannot accidentally be supplied as a PlaceId
to a Roblox API.

The known Lobby PlaceId appears once in runtime Luau. Its other required project
occurrence is the existing `servePlaceIds` allow-list in
`default.project.json`; that is Rojo connection metadata, not runtime role
logic. Neither isolated project contains a raw PlaceId or universe ID.

## Project declarations

Each Rojo definition supplies one `ReplicatedStorage` string attribute named
`ATDPlaceRole`:

| Project | Declared role | Safe boot requirement |
| --- | --- | --- |
| `default.project.json` | `Development` | Studio only, in the configured Lobby place |
| `lobby.project.json` | `Lobby` | Actual PlaceId exactly matches the configured Lobby ID |
| `match.project.json` | `Match` | Rejected until the real Match PlaceId is configured |

The projects declare roles, not duplicate IDs. The common client and server
bootstraps read the same attribute and call the same shared resolver. The
combined project remains useful for local inspection but cannot boot outside
Studio or in an unknown Studio place.

## Validation and failure contract

`validateConfiguration()` enforces these repository invariants before role
resolution:

- Development has no independent production PlaceId.
- Lobby has one positive, finite integer PlaceId.
- Match is either the unset sentinel or one positive, finite integer PlaceId.

`resolve(declaredRole, actualPlaceId, isStudio)` is pure and deterministic. It
returns a tagged result and never reads Roblox services itself.

| Failure code | Meaning |
| --- | --- |
| `INVALID_DECLARED_ROLE` | The project attribute is missing, mistyped, or unknown |
| `DEVELOPMENT_ROLE_OUTSIDE_STUDIO` | The combined project was used outside Studio |
| `PLACE_ID_UNCONFIGURED` | The declared production role has no configured ID |
| `INVALID_ACTUAL_PLACE_ID` | A role requiring a published place received a non-positive or non-integer ID |
| `PLACE_ID_MISMATCH` | The actual place does not match the declared role |

Both bootstraps fail closed with structured `[ATD][ERROR]` records that include
context, subsystem, event, and error code. Successful Studio boot records retain
the existing structured format and now include the resolved role. No lobby or
match gameplay service is started by this packet.

## Focused runtime validation

The repository does not add a test runner early; test-runner selection remains
Packet 05.1. For Packet 02.3, the pure resolver was exercised through the
connected Studio Luau runtime against a temporary clone of the synchronized
module. The clone was immediately destroyed and no place was saved.

All 10 cases passed:

1. Development in the known Lobby place while in Studio.
2. Development outside Studio is rejected.
3. Development in an unknown Studio place is rejected.
4. Development with an invalid actual PlaceId is rejected.
5. Lobby in its configured place.
6. Lobby in a mismatched place is rejected.
7. Lobby with an invalid actual PlaceId is rejected.
8. Match remains rejected while its ID is unset.
9. A missing role is rejected.
10. An unknown role is rejected.

Configuration validation passed, the configured Lobby ID matched the connected
place, and public Match lookup returned `nil`.

## Build and static verification

The following checks passed with the pinned toolchain:

| Check | Result |
| --- | --- |
| `stylua src` | Pass |
| `stylua --check --verify src` | Pass |
| `selene src` | Pass; 0 errors, 0 warnings, 0 parse errors |
| Combined Rojo build | Pass; `Development` attribute, shared resolver, common client/server bootstraps |
| Lobby Rojo build | Pass; `Lobby` attribute and no match source layer |
| Match Rojo build | Pass; `Match` attribute and no lobby source layer |

Every build contains exactly one `ModuleScript`, one server `Script`, and one
client `LocalScript`. Generated `.rbxlx` artifacts were inspected and removed.

## Studio boundary and next gate

The already-connected Rojo server was started before the project attribute was
added. Source hot-sync delivered the module and bootstrap revisions, while the
new project-level attribute requires reconnecting the project definition. This
packet deliberately did not reconnect isolated projects, author place content,
save, or publish: those operations belong to Packet 02.4.

Packet 02.4 must first create or identify the real Match place, replace only the
unset Match entry in the shared configuration, then connect each isolated
project to its correct place and verify successful and rejected boots. Until
then, the Match project is intentionally non-bootable.
