# Ant Tower Defense

Ant Tower Defense is a Roblox Luau tower-defense project built with Git, GitHub,
Rojo, Team Create, Rokit, StyLua, and Selene.

## Project status

The project is in structured pre-production. The complete game specification has
been converted into a long-horizon roadmap made of small, independently
verifiable work packets. Gameplay implementation should follow that roadmap in
order.

- [Detailed development roadmap](docs/DEVELOPMENT_PLAN.md)
- [Project instructions](AGENTS.md)

## Source of truth

- `src/` is authoritative for scripts.
- Roblox Studio and Team Create are authoritative for maps, terrain, models,
  animations, and instances that are not mapped by Rojo.
- Do not make lasting edits to Rojo-managed scripts in Roblox Studio.
- Never use Roblox Script Sync on folders managed by Rojo.

## Planned code layout

The repository is currently a minimal scaffold. The roadmap will gradually
separate shared, lobby-only, match-only, server, and client responsibilities:

    src/
      shared/
        config/
        network/
        types/
        util/
      server/
        common/
        lobby/
        match/
      client/
        common/
        lobby/
        match/
    tests/
    docs/

The lobby and match will ultimately be separate places in the same Roblox
experience, with separate Rojo project files and shared source modules.

## Initial setup

1. Install Git, GitHub Desktop, VS Code, Roblox Studio, and Rokit.
2. Clone the repository.
3. Open the repository in VS Code.
4. Run `rokit install`.
5. Run `rojo plugin install`.
6. Run `rojo serve`.
7. Open the development place in Roblox Studio.
8. Connect through the Rojo plugin.

## Development commands

- Install tools: `rokit install`
- Start Studio synchronization: `rojo serve`
- Format code: `stylua src`
- Check formatting: `stylua --check src`
- Lint code: `selene src`
- Build the project: `rojo build -o build.rbxlx`

Every implementation packet must format and lint changed Luau code, build its
applicable Rojo project, and describe any required Roblox Studio testing.
