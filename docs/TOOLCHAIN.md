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
| Lune | `lune-org/lune@0.10.5` | `0.10.5` | Headless Luau test runtime and structural build inspection |

Rokit resolves Rojo, StyLua, Selene, and Lune from its user-level binary directory.
The repository must continue to use the manifest-selected executables rather
than unrelated global copies.

## Luau and Roblox Studio baseline

Packet 05.1 added Lune 0.10.5 as the repository's pinned headless Luau test
runtime. The runner decision, license, embedded Luau 0.709 version, and update
policy are recorded in `docs/TEST_RUNNER.md`. The repository still does not pin
or expose a separate `luau`, `luau-analyze`, `luau-lsp`, Darklua, Wally, or
third-party assertion framework. Packet 01.1 itself did not add any of these.

Roblox engine execution and integration remain provided by Roblox Studio and
the Roblox runtime. The running Studio installation observed during verification reported product
version `0.735.0.7351131` from installation directory
`version-dcbeee682ce74ee0`. This is an observed local version, not a repository
pin: Roblox updates Studio and its embedded Luau runtime independently. Lune,
StyLua, and Selene are the repository-pinned Luau runtime/processing tools;
Lune's headless scope remains limited as described below.

If a later packet needs another standalone analyzer, language server, package
manager, or test framework, it must add and pin that dependency explicitly
instead of assuming it exists on contributor machines.

Lune is not an engine replacement. The canonical `lune run tests/run.luau`
command executes pure shared contracts from an isolated Rojo build; Roblox
Studio remains authoritative for engine integration.

The current command/environment boundary and deferred Studio, device, published,
and destructive tests are indexed in `docs/TEST_MATRIX.md`. GitHub execution and
supply-chain policy are recorded in `docs/CONTINUOUS_INTEGRATION.md`.

## Command verification

The source-only rows below preserve the Packet 01.1 scaffold evidence. The Lune
rows record later Phase 05 evidence; current canonical commands are the
reproduction checklist, not the historical source-only spellings.

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
| `lune run tests/run.luau` | Pass | Packet 05.2 discovered eight suites and 76 ordered cases. Three consecutive runs returned exit 0 with byte-identical output. |
| `lune run tests/verify-builds.luau` | Pass | Packet 05.2 rebuilt Default, Lobby, Match, and Test, matched all 32 production Lua containers to their exact path, class, and authoritative source, and removed its exact ignored outputs. |

### Packet 06.5 current verification

The table above preserves the packet-specific historical evidence named in each
row. With the same pinned tools, Packet 06.5 produced the following current
evidence on Windows x64:

- `lune run tests/run.luau` passed all 200 tests in 16 deterministic suites.
  The new `NetworkSecurity.spec.luau` suite contributes nine integrated
  adversarial cases.
- `lune run tests/verify-builds.luau` passed with the unchanged 40
  ModuleScripts, one Script, and one LocalScript in each production build. Test
  contains 65 ModuleScripts—33 shared, six mapped common networking, and 26
  test-owned—and zero runnable scripts.
- The two tracked manual sources under `tests/studio/` are mapped by no Rojo
  project and are absent from all four generated DataModels.
- Roblox Studio `0.735.0.7351131` was observed from installation directory
  `version-dcbeee682ce74ee0`. Three unsaved Lobby cycles, three unsaved Match
  cycles, and the final two-client networking regression passed. Both places
  were left in Edit mode without saving or publishing.
- No tool version, manifest pin, production file/build inventory, lasting
  gameplay catalog, remote definition, or rate policy changed for Packet 06.5.
  The existing dispatcher alone gained review-driven non-yielding callback and
  validation-metadata hardening. Phase 07 has not begun.

This is Packet 06.5 evidence, not the Phase 06/Gate A exit record. The fresh
exit audit and genuine CI evidence remain open.

The occupied default Rojo port is expected while a sync session is already
running. When this occurs, inspect the listener before starting another server;
do not kill a user's active Rojo or Studio process merely to make a second
invocation bind the default port.

## Verified project inputs

- `rokit.toml` pins Rojo, StyLua, Selene, and Lune.
- `selene.toml` selects the Roblox standard library.
- `default.project.json` was the sole Rojo project during Packet 01.1. Packet
  02.2 later added `lobby.project.json` and `match.project.json`; Packet 05.1
  added the build-only `test.project.json`. All use the pinned Rojo toolchain.
- `build.rbxlx` was tracked during this verification but is a reproducible local
  artifact; Packet 01.2 removed it from source control under
  `docs/CODE_STYLE.md`.
- Packet 01.3 subsequently replaced the temporary example behavior with minimal
  Studio-only client and server bootstraps.

## Reproduction checklist

From the repository root:

1. Run `rokit install`.
2. Confirm `rokit --version`, `rojo --version`, `stylua --version`,
   `selene --version`, and `lune --version` against the table above.
3. Run `stylua src tests` and review expected changes.
4. Run `stylua --check --verify src tests`.
5. Run `selene validate-config`.
6. Run `selene src tests`.
7. Run `lune run tests/run.luau`.
8. Run `lune run tests/verify-builds.luau`.
9. Run `rojo serve`; if port 34872 is already occupied, confirm it is an intended
    Rojo session or use an explicitly chosen free port for a smoke check.
10. Connect Roblox Studio through the Rojo plugin only when Studio testing is in
    the active packet's scope.

Packet 01.1 required no manual place mutation or gameplay test in Studio. The
existing Rojo-to-Studio connection was observed but not used to edit or publish
the place.
