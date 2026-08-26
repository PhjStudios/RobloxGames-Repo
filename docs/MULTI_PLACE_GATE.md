# Studio Multi-Place Gate

Current headless versus Studio role/source-isolation coverage and all deferred
environment gates are indexed in `docs/TEST_MATRIX.md`.

## Purpose

This document records the implementation and live Studio evidence for Packet
02.4 of `docs/DEVELOPMENT_PLAN.md`. It proves that the Lobby and Match places
resolve their identities and boot only the source layers intended for their
roles.

## Packet status

- Packet: 02.4
- Status: Complete
- Recorded: 2026-08-25
- Experience owner: PHJGAMES, Group ID `35420107`
- Universe ID: `10757629094`
- Gameplay systems added: none
- External services enabled: none
- Rojo-synchronized places saved after testing: no
- Additional publishing authorized: no

## Approved place creation

The user explicitly approved creating and publishing one Match place inside the
existing PHJGAMES universe for this packet.

Roblox Studio's `AssetService:CreatePlaceAsync()` was evaluated first. An Edit
call was rejected because the API requires a server; a local server call was
then rejected because Studio API access is disabled. Both calls returned errors
and created nothing. Studio API access remained disabled.

The Match place was then created through Roblox's documented manual Studio
publish flow. Current production-place inventory is:

| Role | PlaceId | Current display name | Universe |
| --- | ---: | --- | ---: |
| Lobby/start | `100561454756026` | `Ant Tower Defense` | `10757629094` |
| Match | `136401514513678` | `fishytiger7's Place: 08252026_1` | `10757629094` |

Lobby-side `AssetService:GetGamePlacesAsync()` and the authenticated Creator
Dashboard both returned these two places in the target universe.

The manual workflow also created a separate PHJGAMES experience with universe
ID `10761692127` and place ID `113675721965291`, currently named
`Ant Tower Defense - Match`. It is not part of the Ant Tower Defense universe,
is not referenced by repository configuration, and must not be used for match
teleports. It was not deleted or otherwise changed because deletion was not
authorized.

The correct target Match place should eventually receive the intended display
name, and the unused standalone experience should be reviewed separately. These
administrative cleanups do not alter the verified PlaceId contract.

## Central configuration

`src/shared/config/PlaceRoles.luau` remains the only runtime location containing
place-role IDs. Packet 02.4 replaced only the Match role's safe unset sentinel
with the verified Match PlaceId.

The isolated Rojo project files still declare only their role attributes; they
do not duplicate raw PlaceIds:

- `lobby.project.json` declares `ATDPlaceRole = Lobby`.
- `match.project.json` declares `ATDPlaceRole = Match`.
- `default.project.json` remains the combined Studio-only development project.

## Automated and structural verification

The pure resolver passed eight focused Packet 02.4 cases in the connected Studio
Luau runtime:

1. Development in the known Lobby place succeeds in Studio.
2. Development in the Match place is rejected.
3. Lobby in the Lobby place succeeds.
4. Lobby in the Match place is rejected.
5. Match in the Match place succeeds.
6. Match in the Lobby place is rejected.
7. Development outside Studio is rejected.
8. A missing declared role is rejected.

Configuration validation passed, both PlaceIds were positive and distinct, and
all three Rojo projects built successfully.

| Build | Declared role | Server layers | Client layers | Result |
| --- | --- | --- | --- | --- |
| Combined | `Development` | common, lobby, match | common, lobby, match | Pass |
| Lobby | `Lobby` | common, lobby | common, lobby | Pass |
| Match | `Match` | common, match | common, match | Pass |

Every build contained one shared `ModuleScript`, one common server `Script`, and
one common client `LocalScript`. The Lobby build contained no match layer, and
the Match build contained no lobby layer.

## Live wrong-pairing rejection

Before the correct Match place was opened, the Match project was accidentally
connected to standalone place `113675721965291`. A local Play test produced
`PLACE_ID_MISMATCH` on both server and client, naming the configured and actual
PlaceIds. This confirms that a plausible but incorrect PHJGAMES place cannot
silently boot as the Ant Tower Defense Match role.

## Live Lobby gate

The Lobby project was connected to PlaceId `100561454756026` using its isolated
Rojo server.

- Edit-mode role attribute: `Lobby`.
- Universe: `10757629094`.
- Shared resolver present: yes.
- Common server scripts: 1.
- Common client scripts: 1.
- Lobby-specific runnable scripts: 0; none exist yet.
- Match-specific runnable scripts: 0.
- Server ready record: pass, `role=Lobby` and the expected PlaceId.
- Client ready record: pass, `role=Lobby` and the expected PlaceId.

Empty legacy `match` folders from the previous combined connection remained in
the Studio hierarchy because `$ignoreUnknownInstances` preserves unknown
instances. Read-only Edit and Play checks confirmed that they contained zero
runnable scripts. They did not start Match behavior.

## Live Match gate

The Match project was connected to PlaceId `136401514513678` using its isolated
Rojo server.

- Edit-mode role attribute: `Match`.
- Universe: `10757629094`.
- Shared resolver present: yes.
- Lobby source folders: absent.
- Common server scripts: 1.
- Common client scripts: 1.
- Match-specific runnable scripts: 0; none exist yet.
- Lobby-specific runnable scripts: 0.
- Server ready record: pass, `role=Match` and the expected PlaceId.
- Client ready record: pass, `role=Match` and the expected PlaceId.

Both Play sessions were stopped and both places returned to Edit mode. No
Rojo-synchronized place was saved or republished after testing.

## Phase 02 exit gate

Passed on 2026-08-25. Both isolated projects build and boot in the correct places
with only common plus their intended place layer. Wrong project/place pairing
fails closed. Packet 02.4 did not begin Phase 03 or add gameplay behavior.
