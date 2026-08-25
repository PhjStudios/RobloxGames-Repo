# Toolchain Baseline

## Purpose

This document records the reproducible toolchain and command evidence for
Packet 01.1 of `docs/DEVELOPMENT_PLAN.md`. It describes the minimal scaffold as
verified on 2026-08-25; it does not authorize dependency updates, gameplay
changes, Studio content edits, or publishing.

## Baseline status

- Packet: 01.1
- Status: Complete
- Recorded: 2026-08-25
- Host used for verification: Windows x64
- Gameplay behavior changed: no
- `src/` changed by verification: no
- Studio-authored content changed: no
- Experience published: no

## Managed tools

`rokit.toml` is the project tool manifest. `rokit install` completed successfully
and every pinned executable reports the same version as its manifest entry.

| Tool | Manifest entry | Reported version | Role |
| --- | --- | --- | --- |
| Rokit | User-level bootstrap; not pinned by `rokit.toml` | `1.2.0` | Installs and selects project tools |
| Rojo | `rojo-rbx/rojo@7.7.0` | `7.7.0` | Filesystem-to-Studio project sync and place builds |
| StyLua | `JohnnyMorganz/StyLua@2.5.2` | `2.5.2` | Luau formatting |
| Selene | `Kampfkarren/selene@0.31.0` | `0.31.0` | Luau static linting with `std = "roblox"` |

Rokit resolves Rojo, StyLua, and Selene from its user-level binary directory.
The repository must continue to use the manifest-selected executables rather
than unrelated global copies.

## Luau and Roblox Studio baseline

The repository does not currently pin or expose a standalone `luau`,
`luau-analyze`, `luau-lsp`, Lune, Darklua, Wally, or Luau test-runner executable.
No version is invented for an absent tool, and Packet 01.1 does not add one.

Luau execution is currently provided by Roblox Studio and the Roblox runtime.
The running Studio installation observed during verification reported product
version `0.735.0.7351131` from installation directory
`version-dcbeee682ce74ee0`. This is an observed local version, not a repository
pin: Roblox updates Studio and its embedded Luau runtime independently. StyLua
and Selene are the only repository-pinned Luau-processing tools at this stage.

If a later packet needs a standalone analyzer, language server, package manager,
or test runner, it must add and pin that dependency explicitly instead of
assuming it exists on contributor machines.

## Command verification

All commands documented in `README.md` and `AGENTS.md` were exercised against
the minimal scaffold.

| Command | Result | Evidence and notes |
| --- | --- | --- |
| `rokit install` | Pass | Exit code 0; all manifest-pinned tools were available afterward. |
| `rojo plugin install` | Pass | Exit code 0; the documented Studio plugin setup command completed successfully. |
| `rojo serve` | Pass, existing session | Port 34872 already had a Rojo 7.7.0 listener with an established Roblox Studio connection. A duplicate invocation correctly reported that the address was in use; the existing user session was not terminated. |
| `rojo serve --port 34873` | Pass, smoke check | A separate server reached `Rojo server listening` on localhost:34873. Only this verification process was then stopped. This proves a fresh server can load and serve the current project. |
| `stylua src` | Pass | Exit code 0 and no `src/` diff; formatting the scaffold was a no-op. |
| `stylua --check src` | Pass | Exit code 0. |
| `selene src` | Pass | Exit code 0; 0 errors, 0 warnings, and 0 parse errors. |
| `rojo build -o build.rbxlx` | Pass | Rojo built project `Ant Tower Defense`; Packet 01.2 subsequently classified this generated output as untracked. |

The occupied default Rojo port is expected while a sync session is already
running. When this occurs, inspect the listener before starting another server;
do not kill a user's active Rojo or Studio process merely to make a second
invocation bind the default port.

## Verified project inputs

- `rokit.toml` pins Rojo, StyLua, and Selene.
- `selene.toml` selects the Roblox standard library.
- `default.project.json` was the sole Rojo project during Packet 01.1. Packet
  02.2 later added `lobby.project.json` and `match.project.json`; all continue to
  use the pinned Rojo toolchain.
- `build.rbxlx` was tracked during this verification but is a reproducible local
  artifact; Packet 01.2 removed it from source control under
  `docs/CODE_STYLE.md`.
- Packet 01.3 subsequently replaced the temporary example behavior with minimal
  Studio-only client and server bootstraps.

## Reproduction checklist

From the repository root:

1. Run `rokit install`.
2. Confirm `rokit --version`, `rojo --version`, `stylua --version`, and
   `selene --version` against the table above.
3. Run `stylua src` and verify that expected source changes, if any, are reviewed.
4. Run `stylua --check src`.
5. Run `selene src`.
6. Run `rojo build -o build.rbxlx`.
7. Run `rojo serve`; if port 34872 is already occupied, confirm it is an intended
   Rojo session or use an explicitly chosen free port for a smoke check.
8. Connect Roblox Studio through the Rojo plugin only when Studio testing is in
   the active packet's scope.

Packet 01.1 required no manual place mutation or gameplay test in Studio. The
existing Rojo-to-Studio connection was observed but not used to edit or publish
the place.
