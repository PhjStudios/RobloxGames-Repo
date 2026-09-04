# Content and Onboarding Design Lock

Recorded: 2026-09-04  
Outcome: historical Phases 29–33, delivered as one milestone  
Baseline: `fe48b9fe2a9b597d6d169530877465654c8c4e96`

## Audit boundary

The repository and both private staging places were inspected before any lasting
edit. Live identity matched the configured staging deployment:

- GameId `10764687717`;
- Lobby PlaceId `140661668701496`, role `Lobby`;
- Match PlaceId `104415140644510`, role `Match`;
- owner `PHJGAMES`, Roblox Group `35420107`.

The Match inventory contained one 24-descendant `Map_phase07-graybox` tree and
the existing three tower/four enemy primitive models. The Lobby contained only
the existing `ATDSquadQueueZone` and its `ATDSquadQueueDisplay` attachment in
the authorized world scope. No runtime residue was present. The graybox was
confirmed as a sparse single bent lane with ample space but no release-quality
visual hierarchy.

After the identity lock, one guarded additive Team Create transaction authored
`Map_backyard-garden-v1` and the Bombardier, Broodling, and Royal Guard playable
templates in the authorized Match roots. A second default-deny transaction then
split the Garden's buildable area into four readable pockets and added one
visible rock exclusion. The final inventory is two map templates (237
descendants total) and ten playable templates (83 descendants total); the new
map has 212 descendants, contains no scripts, passes the live map validator and
placement probes, and left no `ATDRuntimeMap` or audit preview behind. The
legacy map and all seven legacy playable templates remained unchanged. The
Lobby needed no persistent world marker, so no Lobby Studio content was added.

## Locked product direction

### Visual direction and map contract

The release map is a bright, ant-scale backyard vegetable garden: warm soil and
stone define the lane, cool grass defines buildable ground, a readable nest is
the enemy entrance, and a seed store is the defended goal. Oversized leaves,
flowers, mushrooms, edging stones, and garden tools provide landmarks without
obscuring units. Two bends create obvious beginner choke points and broad
placement pockets. It uses original Studio-built primitive geometry, Roblox
materials, one ordered `main` lane, four player spawns, an overview camera, and
the unchanged map contract v1. Reduced-effects mode removes optional motion and
bursts, never navigation, warnings, or silhouettes.

### Stable identifiers and compatibility

Existing IDs retain their exact meaning: `map:phase07-graybox`,
`difficulty:local`, the three current tower IDs, four current enemy IDs,
`banner:starter` version 1, and `queue:backyard-squad`. The graybox/local pair
remains resolvable as an explicitly server-owned, hidden, non-rewarding direct
development fallback. Release content is additive and versioned:

- map `map:backyard-garden-v1`;
- difficulties `difficulty:easy-v1`, `difficulty:normal-v1`,
  `difficulty:hard-v1`, and `difficulty:endless-v1`;
- tower `tower:bombardier-ant`;
- enemies `enemy:broodling-ant` and `enemy:royal-guard-ant`;
- earn-only banner `banner:garden-v1` version 1;
- content version 1 for deterministic Endless generation and result records.

Saved inventories, pity, first-clear keys, old tickets, and version-1 result
records remain readable. New result records use a compatible version rather
than repurposing version 1.

### Tower and enemy roles

Dart Ant is the explicit balanced starter, Rapid Ant handles fast and numerous
targets, Guard Ant focuses durable enemies and bosses, and Bombardier Ant closes
the area-damage gap with a generic splash behavior. Every tower has a complete
three-level path and all normal targeting modes. No core service branches on a
tower ID or display name.

Worker, Scout, Soldier, and Garden Queen retain basic, fast, durable, and boss
roles. Broodling adds readable low-health swarm pressure; Royal Guard adds an
elite/miniboss bridge. No armor, stealth, flying, support aura, or economy/status
mechanic is added until gameplay evidence demonstrates a need. Boss and
miniboss meaning is configuration-driven and projected to clients.

### Campaign distinctions

Easy has exactly 20 waves, Normal 30, and Hard 40, with bosses on every tenth
wave. Easy introduces basic, fast, swarm, and durable pressure separately with
generous base health, Battle Cash, spacing, and stipends. Normal combines roles
earlier, uses controlled overlap, and tightens resources. Hard layers durable
screens with fast/swarm pressure, shorter recovery windows, and leaner economy;
it never assumes a rare tower. Health/speed modifiers remain secondary to
composition, timing, and economy. Exact combat numbers are accepted only after
deterministic schedule validation and the beginner-loadout balance simulation.

### Acquisition and rewards

New profiles receive Dart Ant and Bombardier Ant exactly once and begin with a
valid pre-equipped loadout; tutorial progress never depends on a roll. The
Garden Tower Chest costs earned Gold only: 250 for one or 2,250 for ten, with
40% Dart, 30% Rapid, 20% Bombardier, 10% Guard, and hard pity at ten for Guard.
Duplicates remain disclosed unique unit records; there is no conversion or paid
currency. The legacy starter banner remains compatible but is not the release
entry point.

Finite rewards are difficulty-specific and exactly-once: Easy awards 50 Gold
participation, 150 victory, and 150 first-clear; Normal 65/235/225; Hard
85/365/325. The local fallback awards zero. Endless grants nothing before five
completed waves, then one terminal award of 25 Gold plus 25 per ten completed
waves, capped at 300 Gold. Time connected cannot increase it. All rewards reuse
the durable result receipt and never grant Gold per wave.

### Endless contract

Endless uses the existing playable runtime. It has an authored opening and then
lazy, stateless generation from `(contentVersion, seed, waveNumber, drawIndex)`.
It generates only current/next work, never accumulates an unbounded schedule,
preserves bosses every ten waves, and clamps per-wave spawns, active enemies,
spawn work, health, speed, cash, counters, and network projection. It has no
victory or fake final wave. Defeat, deliberate departure, all-participants-gone,
shutdown, or technical termination produces one authoritative result containing
the highest completed wave, elapsed time, map, difficulty, seed, content
version, and termination reason. No global leaderboard is introduced.

### Tutorial state graph

Profile schema v6 keeps the legacy tutorial fields and adds version, attempt,
skip, and tracked-match metadata. The authoritative numeric states are:

0. initialize starter inventory and a safe loadout;
1. learn persistent Gold, match-only Battle Cash, and disclosed chest odds;
2. confirm a server-validated starter loadout;
3. enter a singleton PartyOnly Easy queue on the release map;
4. arrive through its authenticated travel ticket;
5. place a tower through an accepted server action;
6. upgrade an owned tower through an accepted server action;
7. finish the tracked match through its durable terminal result;
8. return to Lobby with the matching transfer/result continuity;
9. complete.

Skip becomes available only after state 0 is safely committed. Replay increments
a bounded attempt and returns guidance to state 1 without duplicating owned
starters. Legacy profiles missing a starter are repaired deterministically when
capacity permits; saturated inventories preserve every unit and use a
server-validated owned attacking loadout. Rejected, out-of-order, public, squad,
foreign-match, or spectator actions cannot advance the graph. Solo tutorial
assistance is derived from the authenticated singleton ticket and never changes
public or squad sessions. Guidance is concise and contextual; Help can replay it
after completion.

## Completion evidence

The implementation on `codex/content-onboarding` was based on
`fe48b9fe2a9b597d6d169530877465654c8c4e96` and passed a consolidated review
after all material findings were resolved. The milestone gate was run once:
StyLua check/verify passed, Selene configuration and `src`/`tests` lint passed,
and Default, Lobby, Match, and Test all built. The initial complete headless run
passed `1,484/1,486`; its only failures were two stale fixture expectations.
After correcting those expectations, only `AuthenticatedTowerFixtures` and
`PersistentMatchLoadoutIntegration` were rerun (`15/15`) and the affected Test
build passed. Cumulative coverage for the resulting tree is therefore
`1,486/1,486`. Earlier implementation checkpoints included a `383/383`
changed-spec bundle and a final `52/52` Match travel-host run.

The final authorized Studio inventories were:

- `ServerStorage.ATDMapTemplates`: two children and 237 descendants, including
  the 212-descendant Garden;
- `ReplicatedStorage.ATDPlayableTemplates`: ten children and 83 descendants;
- Lobby `ATDSquadQueueZone`: one child and one descendant, unchanged; and
- zero scripts, direct-development attributes, runtime maps, presentation
  fixtures, or test residue in those bounded scopes.

Live identity remained GameId `10764687717`, Lobby PlaceId
`140661668701496`, Match PlaceId `104415140644510`, and creator group
`35420107`. In Match Studio, iPhone 17 Pro landscape emulation verified touch
placement, selection, a level-two upgrade, authored camera framing/bounds, and
the safe defeat path. The consolidated four-client Server & Clients session
brought all players to Ready, accepted one independently owned Dart placement
per client, accepted one upgrade, and converged at wave 12 with base health
`93/100`, 20 enemies, and the surviving Garden Queen boss panel at `573/585`
health. Client scene analysis measured 76,971 triangles/79 draws including
shadows, or 52,386 creator-adjusted triangles/44 draws; the server contained
1,290 instances, and no unparented ATD instance was found. Reduced-effects
communication is verified by deterministic projection/view coverage rather
than claimed as a live Studio toggle.

Production was untouched. No new staging place version was published and no
uninstructed first-time-player test was performed; either remains a separate
acceptance gate if later desired or required. Phase 34 has not begun.
