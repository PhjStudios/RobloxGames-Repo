# Roblox project instructions

## Ownership

- `src/` is authoritative for Rojo-managed scripts. Server-only authority lives
  under `src/server`, shared contracts under `src/shared`, and client interface,
  camera, input, and visuals under `src/client`.
- Roblox Studio and Team Create are authoritative for maps, terrain, models,
  animations, and other instances not mapped by Rojo.
- Never make lasting Studio edits to Rojo-managed scripts or enable Script Sync
  on folders managed by Rojo.
- `tests/` is test-only. Default, Lobby, and Match builds must remain free of
  test sources, fixtures, controls, and harnesses.

## Tool routing

- Use repository and CLI tools for source edits, formatting, linting, headless
  tests, builds, Git, and process management.
- Use Roblox Studio's built-in MCP tools first for DataModel inspection, Luau
  execution, play/stop, output, screenshots, navigation, and simulated input.
- Efficient Windows UI control is allowed when direct tools do not expose the
  exact action, including initial MCP/Rojo connection, Server & Clients,
  emulators, and engine-only windows. Perform the action, verify it, then return
  to direct tools.
- For Studio work, start one managed background `rojo serve` session for the
  correct project, check readiness, connect once, reuse the Studio instance ID,
  batch related assertions/logs/screenshots/cleanup, and terminate Rojo
  deliberately. Never wait on a foreground server.
- Keep reusable Studio harnesses under `tests/studio` or another test-only path;
  do not add phase-evidence machinery to production services.

## Verification ladder

- Fast iteration: run `stylua <changed .luau files>` and
  `selene <changed .luau files>`, then run selected nearby specs in one
  `lune run tests/run.luau` invocation using repeated `--spec` or `--group`
  selectors.
- Feature verification: run affected specs/integrations together, then build the
  affected project, for example
  `lune run tests/verify-builds.luau --builds-only --project Match`.
- Full milestone gate: run `stylua --check --verify src tests`,
  `selene validate-config`, `selene src tests`, then
  `lune run tests/verify-builds.luau`. The verifier runs the complete headless
  suite and builds Default, Lobby, Match, and Test once each.
- Do not repeat a passing gate unless a failure-affecting change requires it.
  See `docs/TEST_RUNNER.md` for selector details.

## Safety

- Preserve server authority, validate every client request, and never trust
  client-supplied values.
- Preserve lifecycle ownership, cleanup correctness, source isolation, and
  production/test separation.
- Never commit secrets, credentials, cookies, passwords, or `.env` files.
- Do not publish, migrate production data, purchase, merge, or rewrite history
  without explicit approval.
- Follow `ROADMAP.md`; historical phase packets are reference material, not
  mandatory delivery cycles.
