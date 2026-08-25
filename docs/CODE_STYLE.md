# Formatting, Linting, and Generated Outputs

## Purpose

This document records the repository policy established by Packet 01.2 of
`docs/DEVELOPMENT_PLAN.md`. It applies to future implementation packets but does
not itself change gameplay behavior or remove the temporary scaffold examples.

## Policy status

- Packet: 01.2
- Status: Complete
- Recorded: 2026-08-25
- Applies to: Roblox Luau source, repository text, lint configuration, and local
  generated outputs
- Gameplay behavior changed: no
- Studio-authored content changed: no
- Experience published: no

## StyLua formatting policy

`.stylua.toml` is authoritative for Luau formatting:

| Setting | Value | Reason |
| --- | --- | --- |
| `syntax` | `Luau` | Parse Roblox Luau syntax and types correctly. |
| `column_width` | `120` | Keep ordinary code readable without forcing excessive wrapping. |
| `line_endings` | `Unix` | Produce deterministic LF output on every contributor platform. |
| `indent_type` | `Tabs` | Preserve the repository's existing indentation convention. |
| `indent_width` | `4` | Make continuation and displayed tab width deterministic. |
| `quote_style` | `AutoPreferDouble` | Prefer double quotes while avoiding needless escape churn. |

StyLua defaults remain in effect for options that the project has no reason to
override. In particular, Packet 01.2 does not enable automatic require sorting
or aggressive statement collapsing.

Use these commands from the repository root:

- `stylua src` formats authoritative Luau source.
- `stylua --check src` verifies formatting without writing files.

Format files touched by the active packet. Do not use a formatting packet as a
reason to rewrite unrelated user work. If formatting an existing file creates a
large diff, separate functional changes from mechanical formatting so the result
can be reviewed safely.

`.gitattributes` normalizes repository text to LF, matching StyLua. Binary
Roblox `.rbxl` and `.rbxm` files are explicitly protected from line-ending
conversion if a future, approved policy ever versions one.

## Selene lint policy

`selene.toml` selects `std = "roblox"`. This provides Roblox globals, classes,
datatypes, and APIs while retaining Selene's normal correctness rules.

No custom rule suppression, directory exclusion, or warning downgrade is needed
for the current scaffold. This is intentional:

- New warnings and errors must be reviewed instead of globally hidden.
- Normal verification uses `selene src` without `--allow-warnings`.
- A narrow suppression may be added later only when the code is valid, the rule
  cannot model it accurately, and the reason is documented beside the smallest
  practical scope.
- Generated dependencies are outside `src/` and must not be linted as project
  source.
- Selene complements server-side validation and tests; it does not prove network
  security or runtime correctness.

Run `selene validate-config` after editing `selene.toml`, then run `selene src`.
A passing baseline reports 0 errors, 0 warnings, and 0 parse errors.

## Tracked source-of-truth files

The following categories belong in Git:

- Luau source under `src/` and, when introduced, repository-owned tests.
- Rojo project definitions such as `default.project.json`.
- Tool manifests and configuration: `rokit.toml`, `.stylua.toml`,
  `selene.toml`, `.gitattributes`, and `.gitignore`.
- Reviewed editor recommendations and settings under `.vscode/`.
- Documentation and intentionally authored configuration/data definitions.
- Future dependency manifests and lockfiles, while installed package folders
  remain generated.

Roblox Studio and Team Create remain authoritative for maps, terrain, models,
animations, and unmapped instances. They are not converted into generated Rojo
build files and committed opportunistically.

## Untracked generated and local files

The following outputs are reproducible or machine-local and must remain
untracked:

| Output | Producer | Policy |
| --- | --- | --- |
| `/build.rbxl` and `/build.rbxlx` | `rojo build` | Local verification output; regenerate when needed. |
| Other root `*.rbxl` or `*.rbxlx` files | Explicit Rojo build commands | Local build output unless a later architecture decision names a narrow exception. |
| `/build/` | Future multi-place build commands | Local/generated build directory. |
| `/sourcemap*.json` | Rojo or the VS Code Luau-LSP integration | Editor/analyzer aid regenerated from Rojo projects. |
| `/Packages/`, `/ServerPackages/`, `/DevPackages/` | Future package installation | Installed dependencies; track manifests and lockfiles instead. |
| `*.log` and `/logs/` | Local diagnostics | Runtime or tool output; summarize useful evidence in documentation instead. |
| `.env` and `.env.*` | Local configuration | Never commit secrets; only `.env.example` may be tracked. |

Before Packet 01.2, `build.rbxlx` was still tracked even though `.gitignore`
already described it as generated. Packet 01.2 removes that historical build
from source control. `sourcemap.json` was already ignored and untracked; its
regeneration was verified before the local copy was cleaned up. Both outputs can
be regenerated, and neither is authoritative game content.

An intentionally versioned Roblox place snapshot would require an explicit
architecture decision, a specific non-generated filename, and a narrow ignore
exception. It must never be confused with the Studio/Team Create source of truth.

## Required verification order

For a normal implementation packet:

1. Format only changed Luau with `stylua`.
2. Run `stylua --check src`.
3. Run `selene src`.
4. Run focused automated tests when available.
5. Build every affected Rojo project to an ignored output path.
6. Inspect `git status` and the diff to ensure generated files, secrets, and
   unrelated changes are absent.
7. Report any required Studio testing separately; never publish without explicit
   approval.

Packet 01.2 validation also runs `selene validate-config` and verifies that a
Rojo build succeeds before its generated output is removed from the working
tree.
