# Content balance

This file records the configured earn-only content, Battle Cash, acquisition,
and persistent-reward rules. It is not a commerce or monetization
specification. Values below describe content version 1 and result-policy version
2 at the verified Content and Onboarding checkpoint on 2026-09-04.

## Stable selection and compatibility

Backyard Garden (`map:backyard-garden-v1`) is the release map. Its release
difficulties are `difficulty:easy-v1`, `difficulty:normal-v1`,
`difficulty:hard-v1`, and `difficulty:endless-v1`. An authenticated ticket owns
that selection for a travelled Match; Lobby queues reject hidden or development
definitions and show configured display names instead of these IDs.

The existing `map:phase07-graybox` plus `difficulty:local` pair remains a
resolvable, hidden, non-rewarding server-owned fallback for direct development.
Existing tower/enemy IDs, `banner:starter` version 1, inventory records, pity
records, map/difficulty first-clear keys, tickets, and result version 1 retain
their meanings. New authoritative results use compatible version 2.

## Difficulty and Battle Cash rules

Damage income is Battle Cash awarded from eligible actual health removed, with
the listed divisor and floor rounding. Stipends are granted to each active
player for a standard, milestone, or final wave. Battle Cash is match-local and
never converts into Gold.

| Difficulty | Waves | Base health | Enemy health | Enemy speed | Start cash | Damage income | Stipends standard / milestone / final | Early-clear recovery |
| --- | ---: | ---: | ---: | ---: | ---: | ---: | ---: | ---: |
| Easy | 20 | 100 | 0.90× | 0.95× | 650 | 1 per 4 health | 90 / 140 / 220 | 6 s |
| Normal | 30 | 75 | 1.00× | 1.00× | 575 | 1 per 5 health | 75 / 125 / 200 | 5 s |
| Hard | 40 | 60 | 1.12× | 1.05× | 500 | 1 per 6 health | 60 / 105 / 175 | 4 s |
| Endless | no final wave | 75 | 1.04× base | 1.02× base | 550 | 1 per 6 health | 65 / 110 / 0 | 5 s |
| Local development | 5 | 30 | 1.00× | 1.00× | 500 | 1 per 4 health | 70 / 110 / 150 | 4 s |

Selling refunds 70% of total tower Battle Cash investment, rounded down. Easy
deliberately provides the strongest base, richest start, best damage income,
largest stipends, and longest recovery. Normal overlaps roles sooner with
tighter resources. Hard starts mixed, layers fast/swarm pressure behind durable
screens, and has the leanest economy. Difficulty is therefore not an enemy
health multiplier alone.

## Tower roster

All four towers support First, Last, Strongest, Weakest, and Closest targeting.
Upgrade cost is the incremental Battle Cash price for that level. Every listed
level has an attack; no service selects behavior by TowerId or display name.

| Tower | Job | Place cost | Footprint radius | Cap | Default | Level 1 | Level 2 | Level 3 |
| --- | --- | ---: | ---: | ---: | --- | --- | --- | --- |
| Dart Ant | balanced single target | 120 | 1.5 | 8 | First | range 24, damage 12, 0.80 s | +110, range 27, damage 22, 0.70 s | +190, range 30, damage 38, 0.62 s |
| Rapid Ant | fast and numerous targets | 165 | 1.4 | 6 | Closest | range 20, damage 5, 0.24 s | +135, range 22, damage 8, 0.20 s | +220, range 24, damage 13, 0.18 s |
| Guard Ant | durable enemies and bosses | 225 | 1.9 | 4 | Strongest | range 30, damage 42, 1.55 s | +180, range 34, damage 72, 1.40 s | +300, range 38, damage 125, 1.25 s |
| Bombardier Ant | clustered area damage | 195 | 1.8 | 5 | First | range 21, damage 20, 1.40 s, splash 5.5 | +145, range 23, damage 34, 1.25 s, splash 6.0 | +250, range 26, damage 58, 1.10 s, splash 6.5 |

New profiles receive Dart Ant and Bombardier Ant exactly once and begin with
both equipped. This deterministic pair is the intended onboarding loadout and
closes the area-damage gap without requiring a chest pull.

## Enemy roster

| Enemy | Teaching role | Threat class | Health | Speed | Leak damage |
| --- | --- | --- | ---: | ---: | ---: |
| Worker Ant | basic | Standard | 45 | 5.5 | 1 |
| Scout Ant | fast | Standard | 28 | 9.0 | 1 |
| Soldier Ant | durable | Elite | 145 | 3.8 | 4 |
| Broodling Ant | swarm | Standard | 16 | 6.6 | 1 |
| Royal Guard Ant | durable miniboss | MiniBoss | 420 | 3.2 | 12 |
| Garden Queen | boss | Boss | 650 | 2.7 | 30 |

Boss and miniboss status is configured and projected to clients for warnings
and health presentation. “Heavy shell” is flavor for Royal Guard durability;
content version 1 does not add a separate armor, stealth, flying, aura, economy,
slow, or status subsystem.

## Authored finite campaigns

Easy, Normal, and Hard contain exactly 20, 30, and 40 authored waves. A Garden
Queen boss wave occurs at every tenth wave; explicit Royal Guard miniboss waves
teach focused damage between those milestones. Authored finite waves schedule
at most 20 enemies each.

Easy introduces basic, swarm, fast, and durable roles before combining them and
allows the deterministic Dart/Bombardier starter pair to learn placement and
upgrading. Normal combines roles earlier with denser spacing. Hard uses mixed
opening waves, controlled overlap, durable screens, shorter spacing, and leaner
income without assuming a rare tower.

The deterministic test-only balance driver advances the actual production
`PlayableMatchRuntime` on a virtual clock using the same 168–169 stud Garden
path, four disjoint build pockets, one visible exclusion, and placements first
accepted by `PlacementGeometry`. It does not reimplement movement, combat,
splash, economy, upgrades, waves, or leaks. It verifies that Dart/Bombardier
and multiple two-role alternatives complete Easy with base health remaining.
That deterministic runtime evidence was paired with bounded private-staging
Studio acceptance: a solo iPhone 17 Pro landscape session exercised touch
placement, selection, upgrade, camera bounds, and defeat, while a four-client
session exercised distinct owned placements, an upgrade, shared wave state, and
boss-overlap presentation. It does not claim broader physical-device balance or
an uninstructed newcomer observation.

## Endless generation and resource bounds

Endless uses the existing authoritative Match runtime and has no configured
victory or final wave. Its first ten waves are authored; later waves are lazily
and statelessly generated from `(contentVersion, seed, waveNumber, drawIndex)`
using `wave-generator.garden-v1`. Seeds are positive integers no greater than
2,147,483,647. Every tenth wave is a boss wave; generated non-boss multiples of
five from wave 15 may be miniboss waves.

Difficulty scaling saturates instead of overflowing: generator progression is
clamped at wave 10,000, health scaling at 30×, speed scaling at 1.6×, groups at
6, and scheduled spawns at 72 per generated wave. The runtime additionally caps
the accepted wave queue at 96 spawns, live enemies at 20, live towers at 12,
overlapping wave origins at 4, spawns per simulation step at 8, attacks per step
at 64, enemy health at 1,000,000, enemy speed at 24, Battle Cash at
2,147,483,647, and result/wave counters at 1,000,000,000,000. Only current work
is retained; the absence of a terminal wave does not imply unbounded memory,
network projection, or per-step work.

Deterministic coverage generates and repeats 10,000 waves within every bound,
checks different-seed variation, and probes wave 1,000,000,000,000 after growth
has saturated. It does not wait through those waves in real time.

## Garden Tower Chest

The release `banner:garden-v1` version 1 chest uses earned Gold only:

- one pull costs 250 Gold; ten pulls cost 2,250 Gold;
- Dart Ant: 40%;
- Rapid Ant: 30%;
- Bombardier Ant: 20%;
- Guard Ant: 10%; and
- hard pity at ten guarantees Guard Ant.

All four towers therefore have a free acquisition path. Odds and the earn-only
policy are disclosed before a pull. Duplicates remain separate persistent unit
records and are not converted. The compatible `banner:starter` v1 definition
retains its historical 60% Dart / 30% Rapid / 10% Guard distribution and
ten-pull Guard pity, but it is not the release onboarding entry point.

## Current version 2 persistent rewards

Only an authenticated, server-owned ticketed Match marked rewarding can award
persistent Gold. Direct local, development, non-ticketed, spectator, and
unexpected-arrival sessions award zero.

| Difficulty | Participation | Victory bonus | First Victory clear | Eligible defeat | Repeat victory | First victory |
| --- | ---: | ---: | ---: | ---: | ---: | ---: |
| Easy | 50 | 150 | 150 | 50 | 200 | 350 |
| Normal | 65 | 235 | 225 | 65 | 300 | 525 |
| Hard | 85 | 365 | 325 | 85 | 450 | 775 |
| Local development | 0 | 0 | 0 | 0 | 0 | 0 |

Finite first clears are keyed by the stable map-and-difficulty pair and apply
only to Victory. For Endless, no reward is available below five completed
participant waves. At five or more, one terminal award is:

    min(300, 25 + floor(rewardedWave / 10) × 25) Gold

where `rewardedWave` is the lesser of the participant's completed waves and the
authoritative run high-water mark. Connected time cannot increase the award;
Endless has no Victory or first-clear bonus.

Common eligibility requires all of the following authoritative evidence:

1. admission as a participant through the expected roster of a valid ticket;
2. successful Ready submission;
3. at least one authoritative tower placement; and
4. either connection through Results or participation through at least two
   completed waves.

The Endless five-wave minimum is stricter than item 4. Spectators always receive
zero. Results may display persistent Gold as `Granted` only after the profile
mutation has been durably saved; otherwise the status is `Pending`,
`Ineligible`, or `Failed`. One server-owned result ID records Gold, first-clear
state, and the result receipt in the same profile mutation, so retries cannot
grant twice.

Version-2 results also record mode kind, highest completed wave, elapsed seconds,
map, difficulty, seed, content version, and termination reason. Endless ends
only through base defeat, deliberate player end/departure,
all-participants-gone, shutdown, or technical termination.

## Legacy result version 1 policy

Version-1 records remain readable and retain the Squad Travel policy rather
than being reinterpreted with version-2 difficulty values:

- eligible participation: 50 Gold;
- Victory: an additional 200 Gold; and
- first Victory clear: an additional one-time 250 Gold.

Thus a legacy eligible Defeat is 50 Gold, repeat Victory is 250 Gold, and first
Victory is 500 Gold. The common authoritative participation rules still apply.

The source constants are `src/shared/config/MatchRewards.luau`,
`src/shared/config/Economy.luau`, and the validated content catalogs. Reward
evaluation and durable claims remain server-owned.

## Reproducible platform-hardening report

Run `lune run tests/balance-report.luau` to write
`build/content-balance-report.md`. The read-only test tool records report/content
version 1, seed 1, the Garden build policy and starter pair. It reports tower
investment and nominal primary-target DPS curves, role tags, difficulty economy
pressure, all authored finite-wave health/speed/spawn budgets, generated Endless
checkpoints through wave 10,000, and exported runtime caps. Nominal DPS excludes
splash multiplicity, fixed-step quantization, target downtime, buffs and overkill.

Campaign results come from the existing `ContentBalanceSimulation` advancing
the production `PlayableMatchRuntime`, rather than a second simulator. The
recorded one-participant starter-pair run reached Easy/Normal/Hard Victory at
20/30/40 waves, with base health 100/75/60 and virtual durations
249.90/376.80/501.35 seconds. These are deterministic balance observations; they
do not measure real-time performance or prove newcomer/device acceptance.

`ContentBalanceReport` tests verify byte-stable configuration reporting and the
existing runtime's campaign outcome. Generation reads validated configuration
without editing it, creates no live profile or reward writes, and retains only
the generated Markdown under ignored `build/`.
