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
| `Match` | Known Match PlaceId | Match-isolated project |

Packet 02.3 initially represented Match with the non-numeric sentinel `false`
inside the private configuration table. Public lookup converted it to `nil`.
Packet 02.4 replaced only that sentinel after the real Match PlaceId was created
and verified.

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
| `match.project.json` | `Match` | Actual PlaceId exactly matches the configured Match ID |

The projects declare roles, not duplicate IDs. The common client and server
bootstraps read the same attribute and call the same shared resolver. The
combined project remains useful for local inspection but cannot boot outside
Studio or in an unknown Studio place.

## Validation and failure contract

`validateConfiguration()` enforces these repository invariants before role
resolution:

- Development has no independent production PlaceId.
- Lobby has one positive, finite integer PlaceId.
- Match is one positive, finite integer PlaceId. The validator still permits the
  original unset sentinel so a future environment can fail closed during setup.

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

## Focused Packet 02.3 runtime validation

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

At the Packet 02.3 checkpoint, configuration validation passed, the configured
Lobby ID matched the connected place, and public Match lookup returned `nil`.
Packet 02.4 subsequently verified both configured IDs and both cross-place
rejection directions; see `docs/MULTI_PLACE_GATE.md`.

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

At the Packet 02.3 verification snapshot, every build contained exactly one
`ModuleScript`, one server `Script`, and one client `LocalScript`. Later packets
added shared and server-only modules without changing the place-role contract.
Generated `.rbxlx` artifacts were inspected and removed.

## Current Studio state after Packet 02.4

Packet 02.4 created and configured the real Match place, connected both isolated
projects, and passed Lobby and Match client/server Play tests. A deliberately
wrong Match connection also failed closed with `PLACE_ID_MISMATCH`. Full evidence
is recorded in `docs/MULTI_PLACE_GATE.md`.
