# Roblox project instructions

## Project

Roblox Luau project using Git, GitHub, Rojo, Team Create, Rokit, StyLua, and Selene.

## Source of truth

- `src/` is authoritative for scripts.
- Do not make lasting edits to Rojo-managed scripts inside Roblox Studio.
- Roblox Studio and Team Create are authoritative for maps, terrain, models, animations, and unmapped instances.
- Never use Roblox Script Sync on folders currently managed by Rojo.

## Structure

- `src/server`: server-only and authoritative game logic
- `src/shared`: modules shared between client and server
- `src/client`: client-only interface, camera, input, and visual code

## Commands

- Install tools: `rokit install`
- Development sync: `rojo serve`
- Format code and tests: `stylua src tests`
- Check formatting: `stylua --check --verify src tests`
- Lint code and tests: `selene src tests`
- Run headless tests: `lune run tests/run.luau`
- Verify all project builds: `lune run tests/verify-builds.luau`
- Build project: `rojo build -o build.rbxlx`

## Safety

- Never commit secrets, API keys, cookies, passwords, or `.env` files.
- Do not publish the game without explicit approval.
- Validate all client requests on the server.
- Do not trust values sent by a client.

## Before finishing a change

- Format and lint changed code.
- Build the Rojo project.
- Summarize changed files and required Roblox Studio testing.
