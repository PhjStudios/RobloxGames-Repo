# Performance measurements and regression budgets

Version 1, 2026-09-04. These are local development measurements and provisional
regression thresholds for historical Phases 34–37. They do not establish phone,
tablet, console, published-client, or production capacity. Follow the bounded
Studio procedure in `docs/TEST_MATRIX.md` S-08 and the evidence definitions in
`docs/PLATFORM_HARDENING_DESIGN_LOCK.md`.

The scoped local measurement and implementation review are complete. The
milestone gate is recorded in H-17 with cumulative 1,601/1,601 headless coverage
and all four builds passed; Git delivery and external acceptance remain pending.

## Measurement environment and interpretation

The development machine has an AMD Ryzen 7 7800X3D, NVIDIA GeForce RTX 5080 and
33,903,378,432 bytes of physical memory (approximately 31.6 GiB). Studio is the
unsaved confirmed private staging experience: GameId 10764687717, group 35420107,
Lobby 140661668701496 and Match 104415140644510. Source synchronization does not
publish a version. Historical stored place versions are Lobby 18 and Match 15.

`tests/studio/PlatformProfile.luau` records RenderStepped client frame intervals,
server Heartbeat intervals, engine Stats, instance changes and received remote
counts. `tests/support/PerformanceWindow.luau` retains a bounded sample window,
labels the population used for percentiles and preserves the lifetime maximum.
Missing/rejected observations remain unavailable. The probe disconnects every
listener and retains aggregate counts/size estimates, never raw remote payloads.

Client frame intervals include pacing and scheduling. Server Heartbeat intervals
are scheduler cadence, not simulation CPU duration. MicroProfiler inclusive CPU
spans summed across threads are neither GPU timings nor critical-path frame
cost. Local headless `os.clock` timings are host execution observations around
the production runtime; they exclude Roblox rendering, replication and engine
memory. Studio process memory includes engine/editor overhead and, in solo
sessions, shared client/server process allocations.

Engine `DataSendKbps` and related properties are aggregate Stats observations.
The receive/physics properties reported zero in the initial sessions; zero does
not establish zero traffic or a working transport measurement. The separate
payload estimator counts JSON-like field names and values. Its bytes cannot be
converted into Roblox wire bytes or compared directly with the Stats property.

## Initial solo Studio checkpoint

The exact source is `docs/evidence/platform-initial-measurements.json`. These
captures preceded final localization/layout fixes and are an implementation
checkpoint. All samples below were retained without rejected frame samples.
Each probe reported zero remaining probe connections.

| Scenario | Seconds / frames | Frame interval mean / p95 / maximum, ms | Engine memory before → after, reported MB | Instances before → after |
| --- | --- | --- | --- | --- |
| Ready client | 12.20 / 731 | 16.67 / 17.99 / 18.87 | 2982.45 → 2983.09 | 5949 → 5949 |
| Ready server, Heartbeat cadence | 12.13 / 727 | 16.67 / 18.03 / 19.41 | 2983.24 → 2983.48 | 3385 → 3385 |
| Garden wave 6, no towers | 12.16 / 729 | 16.67 / 18.19 / 19.71 | 3123.30 → 3123.95 | 6236 → 6208 |
| Garden, four towers in combat | 12.18 / 730 | 16.67 / 18.38 / 19.51 | 3119.11 → 3119.13 | 6279 → 6246 |
| Results MicroProfiler | 128 captured frames | 16.66 / 17.53 / 18.09 | Not captured | Not captured |

The no-tower window changed from 20 to 18 enemies, with 140 instances added and
168 removed. Four-tower combat changed from 20 to 18 enemies and one to zero
attack-effect roots, with 406 instances added and 439 removed. Their presentation
descendant counts changed 284 → 256 and 326 → 293 respectively. These are short
combat windows, not equal-state repeated-match leak comparisons.

| Client observation | Full projections | Maximum / total estimated projection bytes | Attack events | Maximum / total estimated attack bytes |
| --- | ---: | --- | ---: | --- |
| Garden wave 6, no towers | 112 | 6183 / 670434 | 0 | 0 / 0 |
| Garden, four towers in combat | 112 | 7461 / 735913 | 42 | 276 / 11141 |

The four-tower capture received approximately 9.19 full projections and 3.45
attack events per second. Full projections account for most of the measured
estimated envelope volume. This establishes an optimization candidate to profile,
not a finding that a delta protocol or unreliable attack transport is required.
Both endpoints retain their existing reliable transport and full-resync behavior.

The initial Results MicroProfiler captured frames 236–363 (absolute IDs
3670764–3670891). Its automatic labels reported mean inclusive CPU per captured
frame of 0.08375 ms for `physicsSteppedTotal`, 0.05642 ms for
`RunService.Heartbeat`, 0.03858 ms for `Script_Main`, and 0.01326 ms for
`RenderSteppedInternal`. These spans overlap and must not be added as an ATD
critical-path total. This capture preceded the named subsystem instrumentation
and cannot attribute target selection, UI work or presentation allocation cost.

## Four-client Studio campaign and replay

Sources: `docs/evidence/platform-four-client-measurements.json` and
`docs/evidence/platform-four-client-followup.json`. Four local Studio clients
played production Garden Easy with 12 towers: eight level-2 Dart Ants and four
level-1 Bombardier Ants. The campaign reached Victory at wave 20 with base health
100, then an actual R replay returned to Ready. These are unsaved non-rewarding
Studio observations on the development desktop with an iPhone 7 viewport. They
are not phone hardware or published-client evidence.

The 20-second probes were sequential, during waves before/between boss 10.
Active enemy counts were usually 0–3 because enemies died quickly. This is a
real four-player tower-load trace, distinct from the synthetic 20-enemy headless
density fixture. Do not claim saturated high-fire-rate/boss CPU acceptance from
this composition. Background window throttling affected client 2.

| Scenario | Seconds / frames | Mean / p95 / maximum frame interval, ms | Reported process memory before → after, MB | Instances before → after |
| --- | --- | --- | --- | --- |
| Client 1, foreground 60 Hz | 20.28 / 1216 | 16.67 / 18.05 / 19.60 | 1815.84 → 1811.09 | 6884 → 6874 |
| Client 2, background 15 Hz | 20.30 / 305 | 66.66 / 68.13 / 69.57 | 1753.58 → 1754.15 | 6874 → 6860 |
| Server, Heartbeat cadence | 20.26 / 1216 | 16.67 / 18.02 / 19.12 | 1635.04 → 1636.23 | 5225 → 5225 |
| Client Results, after boss 20 died | 12.20 / 731 | 16.67 / 17.65 / 18.79 | 1933.25 → 1933.25 | 6865 → 6865 |
| Client Ready, after actual replay | 12.18 / 730 | 16.67 / 17.75 / 18.64 | 1932.26 → 1932.26 | 6753 → 6753 |

Client 2's 15 Hz pacing is a recorded focus/throttling condition, not a failure
against the foreground budget. Client 1 memory ranged 1807.69–1826.14 MB within
its capture; endpoint differences alone would omit that allocation/GC variation.
The server's sampled `DataSendKbps` ranged 3.853873–63.994686, a functioning
nonzero aggregate engine property. Receive/physics counters still reported zero.
The send observations have no per-remote wire attribution and are not estimates
of phone or published-client bandwidth requirements.

| Sequential client window | Full projections, count / maximum / total estimated bytes | Attack events, count / maximum / total estimated bytes |
| --- | --- | --- |
| Client 1 | 87 / 6755 / 541414 | 34 / 262 / 8724 |
| Client 2, background | 118 / 6583 / 731646 | 44 / 261 / 11302 |

Both Results and replay-Ready windows recorded zero projection/attack events,
zero instance additions/removals and zero remaining probe connections. Replay
removed all prior towers, enemies and attack effects; the presentation root held
only its three empty owned folders. Ready retained four participants, three
Ready, wave zero and base health 100. This verifies the observed replay cleanup
and stable 12-second idle window. It does not prove a long-term memory slope or
complete three consecutive finite rematch/return cycles.

Across the bounded real-time sessions, the observed terminal paths were a solo
Garden defeat, a solo Endless defeat and the four-client Garden victory/replay.
These are finite observations with no known retained runtime objects in their
recorded cleanup checks. No claim of a long Endless memory/frame/network soak
or published return/travel acceptance follows.

The client MicroProfiler capture around wave 14 retained 128 frames (absolute
IDs 13378–13505), frame p95 17.55 ms. Named inclusive CPU results were:

| Named scope | Spans | Mean per captured frame, ms | Maximum span, ms |
| --- | ---: | ---: | ---: |
| `ATD.Client.Presentation` | 128 | 0.05628 | 0.36357 |
| `ATD.Client.Aim` | 128 | 0.05005 | 0.18332 |
| `ATD.Client.UI` | 20 | 0.04954 | 0.39902 |
| `ATD.Client.World` | 20 | 0.04692 | 0.66351 |
| `ATD.Client.EffectCreate` | 8 | 0.01035 | 0.21780 |
| `ATD.Client.Effects` | 136 | 0.00490 | 0.17790 |

The server MicroProfiler summary covers 128 frames (absolute IDs 13226–13353),
frame p95 17.53 ms. `ATD.Service.Step` had mean inclusive CPU 0.12014 ms per
captured frame and maximum span 2.03924 ms; `ATD.Service.SnapshotPublish` had
0.08683 / 1.95800 ms; `ATD.Runtime.Step` had 0.02160 / 0.15418 ms. Snapshot
publication is the largest measured nested contributor in this short capture.
It remains a profiling candidate, with no demonstrated frame-budget failure or
evidence yet requiring a protocol rewrite. The summary does not report separate
target-candidate, selection, spawn or movement costs; their marker availability
is not an individual timing result.

These inclusive scopes overlap and cannot be summed. The Results probe started
after the final boss died; it is explicitly not a boss-combat CPU capture. This
checkpoint did not establish boss or saturated-density CPU attribution; the
later Garden Hard trace below records that distinct workload.

## Final-source dense Garden Hard and active Endless

`docs/evidence/platform-four-client-hard.json` records four actual local Studio
participants in Garden Hard, with eight Dart Ants and four Bombardier Ants, all
level 1. All 12 placements used accepted ordinary requests and the configured
starting Battle Cash; no health, wave, cash or outcome injection occurred.
Client 1 was foreground at actual 1919×1080 on the development desktop, with
default presentation/settings, Medium text and reduced motion off. This legal
load reached the 20-enemy cap. It differs from both the earlier Easy composition
and the synthetic headless fixture, and is not every possible upgraded-tower
combination or a representative phone/console workload.

| Garden Hard observation | Seconds / frames | Mean / p95 / maximum interval, ms | Process memory before → after, reported MB | Instances before → after |
| --- | --- | --- | --- | --- |
| Foreground client | 30.399 / 1823 | 16.67 / 19.21 / 21.41 | 1820.46 → 1820.96 | 7127 → 7247 |
| Server Heartbeat cadence | 30.431 / 1825 | 16.67 / 18.02 / 19.57 | 1711.78 → 1703.62 | 5227 → 5227 |

The client's second-samples stayed Playing, with 5–20 enemies and 0–3 optional
effect roots. The endpoint population changed from five enemies/three effects
to fourteen/two, with 1,859 instances created and 1,739 removed. This is combat
churn, not equal-state retained growth. The server had zero instance additions
or removals. Both probes ended with zero probe connections. The client received
279 full projections, maximum 10,302 and total 2,467,069 estimated bytes, plus
215 attack events, maximum 279 and total 57,630 estimated bytes. Server aggregate
`DataSendKbps` ranged from 76.565 to 97.729; it has no per-remote attribution and
is not interchangeable with those JSON-like estimates.

The client MicroProfiler retained 128 frames, absolute IDs 21630–21757, with
frame p95 18.0127 ms. Before/after UI observations had boss-health summaries
visible, twelve towers, waves 10 → 11 and enemies 6 → 14. The server capture
retained 128 frames, absolute IDs 22369–22496, p95 17.5502 ms; bracketing client
observations were wave 11, boss-health visible, enemies 20 → 17. These brackets
support boss-combat context; they are not per-frame authority-state logs.
Captures are sequential, not one simultaneous four-client distribution.

| Hard server scope | Spans | Mean inclusive CPU per captured frame, ms | Maximum span, ms |
| --- | ---: | ---: | ---: |
| `ATD.Service.Step` | 128 | 0.448744 | 3.136342 |
| `ATD.Service.SnapshotPublish` | 19 | 0.368058 | 3.010498 |
| `ATD.Runtime.Snapshot` | 76 | 0.165287 | 0.532246 |
| `ATD.Runtime.Step` | 128 | 0.059505 | 0.244988 |
| `ATD.Runtime.Attacks` | 42 | 0.053059 | 0.227875 |
| `ATD.Runtime.TargetSelect` | 228 | 0.038343 | 0.048503 |
| `ATD.Service.AttackPublish` | 15 | 0.011967 | 0.167560 |
| `ATD.Runtime.TargetCandidates` | 228 | 0.009962 | 0.018305 |
| `ATD.Runtime.Movement` | 42 | 0.002395 | 0.010450 |
| `ATD.Runtime.WaveResolve` | 42 | 0.000548 | 0.002194 |
| `ATD.Runtime.Spawn` | 42 | 0.000478 | 0.004348 |

| Hard client scope | Spans | Mean inclusive CPU per captured frame, ms | Maximum span, ms |
| --- | ---: | ---: | ---: |
| `ATD.Client.UI` | 19 | 0.108777 | 1.038545 |
| `ATD.Client.Presentation` | 128 | 0.099845 | 0.239338 |
| `ATD.Client.Aim` | 128 | 0.088388 | 0.151440 |
| `ATD.Client.World` | 19 | 0.084472 | 1.014270 |
| `ATD.Client.EffectCreate` | 17 | 0.021258 | 0.230646 |
| `ATD.Client.Effects` | 145 | 0.010220 | 0.131732 |

Parent and child scopes overlap and must not be summed as a frame total.
Snapshot construction/publication remains the largest measured contributor.
The heavier Hard load must not be judged against the earlier Easy normal-load
CPU thresholds. Its measured foreground frame cost does not justify a speculative
delta protocol, spatial index, pooling or authority rewrite. Retain these traces
as baselines for a future demonstrated regression.

SceneAnalysis was bracketed at wave 21 with twelve towers and twenty enemies:
181,255 triangles/143 draws including 91,177/61 shadow passes; excluding shadows,
90,078 triangles/82 draws (87,876/44 opaque and 2,202/38 UI). These are one rendered
viewpoint, not an asset-by-asset budget or GPU timing. Engine audio/animation totals
were 2,843,594/139,261 bytes and include character/Core assets. No persistent
geometry, collision, shadow, texture, animation or lighting optimization followed.

The follow-up in `docs/evidence/platform-four-client-hard-followup.json` retained
728 frames over 12.150 seconds, p95 19.4566 ms and maximum 21.7973 ms. Every sample
was Playing with a boss-health summary visible; endpoints had twelve towers and
twenty enemies. Memory changed 1935.953125 → 1936.0078125 MB, with 832 instance
additions/811 removals and zero remaining probe connections. It received 111
projections, maximum 10,482/total 1,140,877 estimated bytes, and 127 attack events,
maximum 280/total 34,236. This is another active-combat trace, not Results or
cleanup evidence, and does not erase earlier memory/frame outliers.

Later, a separate terminal observation reached Results at wave 34 with base
health zero. An accepted ordinary replay returned to Ready with zero towers,
enemies and effects and three presentation descendants. The probe's result-enum
lookup was not reliable; no captured enum outcome is claimed. All four temporary
clients were closed, the Match Edit emulator/camera restored, temporary test
attributes removed and ATD-owned template inventory unchanged, with zero ATD
runtime residue. This establishes that session's replay/cleanup result, not a
post-cleanup timing or memory distribution.

`docs/evidence/platform-endless-active.json` separately records a fresh solo
Garden Endless run, English/default preferences, no towers and actual enemy
leaks. Both 30-second windows were Playing in every recorded second-sample.

| Active Endless window | Seconds / frames | Frame p95 / maximum, ms | Process memory before → after, reported MB | Projections: count / maximum / total estimate |
| --- | --- | --- | --- | --- |
| Initial spawning, zero → twenty enemies | 30.449 / 1826 | 18.22 / 23.41 | 2383.26 → 2376.25 | 231 / 6143 / 930627 bytes |
| Continuing capped enemy population | 30.431 / 1825 | 18.78 / 20.91 | 2375.41 → 2375.47 | 285 / 6224 / 1746483 bytes |

The second window showed a boss-health summary in 28 of 31 samples, with
nineteen/twenty enemies in its initial samples and twenty at its endpoint.
Both windows retained zero probe connections. This measures active Endless
rendering/replication, not thousands of real-time waves or tower-attack density.
The later attempted client MicroProfiler capture was already Results at wave 7,
with no boss-health display before or after; it remains Results evidence. Its
sequential server capture has no independent boss-state bracket. Neither is
claimed as an active Endless boss CPU trace. Play stopped after capture; long
Endless growth and physical/published-client acceptance remain separate gates.

## Three repeated finite-session checkpoints

`docs/evidence/platform-repeated-sessions.json` records three ordinary solo
Garden Easy Ready/Defeat/Replay cycles completed in 504.41 seconds, within the
600-second limit. The foreground Studio client used a 666×374 landscape viewport,
Largest preferred text, opaque panels, reduced motion and pseudo50. Each no-tower
run ended through actual leaks at wave 10, with eight waves completed and base
health zero. Seven production requests were accepted; the last replay remained
Ready without starting another match. These were finite defeats, not winning
campaigns or published rematch/return observations.

| Settled checkpoint | Elapsed seconds | Reported process memory, MB | Instances | Frame p95, ms |
| --- | ---: | ---: | ---: | ---: |
| Initial Ready | 2.15 | 2202.121 | 2706 | 18.09 |
| First Defeat | 167.39 | 2206.469 | 2707 | 17.92 |
| Second Ready | 169.56 | 2203.254 | 2707 | 18.04 |
| Second Defeat | 334.73 | 2256.363 | 2707 | 18.07 |
| Third Ready | 336.87 | 2256.383 | 2707 | 18.22 |
| Third Defeat | 502.19 | 2266.445 | 2707 | 17.69 |
| Final Ready | 504.41 | 2266.445 | 2707 | 17.54 |

All seven checkpoints had zero tower, enemy and effect roots and exactly three
empty presentation folders. Total instances increased once by one and then stayed
at 2,707; the runner retained zero probe connections. The frame distributions
cover only the two-second settled checkpoints, not continuous combat across all
504 seconds. The client received 4,409 full projections totaling 24,276,639
JSON-like estimated bytes, maximum 6,259; these remain estimates rather than
transport bandwidth measurements.

Ready-to-Ready process memory increased **64.324 MB**. Repeated-session entity
and presentation cleanup passed, but this did not pass memory-growth acceptance.
Rojo synchronized source edits during the trace while cached modules retained
their loaded implementation; the record also precedes final compact-occupancy
and localization fixes. Studio memory includes editor overhead. These confounders
prevent attribution of the increase and do not explain it away. This prompted
the unchanged-source follow-up below. The 12-second idle-window threshold is not
the same workload and must not be applied as though this were that measurement.

### Follow-up with unchanged source

`docs/evidence/platform-repeated-stable-source.json` records another three actual
Garden Easy no-tower Defeat/Replay cycles completed in **504.379 seconds**. Its
191-file source fingerprint remained unchanged:
`A0277C76FA61DE03F76ED8B0F9078E3D775F89DFC88494D2715E6D9B27A0D683`.
The latest source write was 2026-09-05 01:13:47 UTC, before the 01:20:25 UTC start.
This foreground run used the same development desktop with the 1366×768 laptop
emulator requested, English, Medium preferred text, authored transparency,
reduced motion off and saved UI scale 1. Its settings differ from the earlier
expanded-phone checkpoint; this is a controlled follow-up, not an exact repeated
device/preference workload or a before/after optimization comparison.

| Ready checkpoint | Elapsed seconds | Reported process memory, MB | Instances | Frame p95, ms |
| --- | ---: | ---: | ---: | ---: |
| Initial Ready | 2.18 | 2356.219 | 2692 | 17.60 |
| Second Ready | 169.64 | 2346.031 | 2694 | 17.56 |
| Third Ready | 337.00 | 2348.586 | 2694 | 17.92 |
| Final Ready | 504.38 | 2348.422 | 2694 | 18.00 |

All seven Ready/terminal checkpoints again had zero tower/enemy/effect roots
and three empty presentation folders; completion left zero probe connections. Instances
rose once by two and then stayed at 2,694. Initial-to-final Ready process memory
decreased **7.796875 MB**, from 2356.21875 to 2348.421875. The client received
4,381 projections totaling 24,127,748 estimated bytes, maximum 6,259, and made
seven accepted production requests. All three outcomes were natural wave-10
defeats, with eight completed waves and base health zero.

A separate warmed Final Ready probe retained all 732 frames over 12.199 seconds:
p95 17.9634 ms, maximum 23.9034 ms, memory 2348.484375 → 2348.496094 MB. Its
6,513-instance population stayed flat with zero additions/removals; owned runtime
entities/effects and probe connections were zero. Compare total instance counts
within each probe; the separate probe populations must not be spliced into a
single instance-growth series.

The earlier 64.324 MB increase was **not reproduced**, but its cause remains
unexplained. This bounded run found no known retained owned-object growth or
monotonic process-memory rise. It does not establish long-duration memory
behavior, absolute hardware budgets, saturated combat or published return.
One unchanged-source follow-up does not calibrate a repeated-session memory
slope threshold; the existing zero-owned-residue rule and matching idle-window
investigation thresholds remain in force.

## Deterministic workload evidence

`PerformanceScenarios` uses the production PlayableMatchRuntime, configuration,
protocol validation and existing ContentBalanceSimulation. The stress fixture
explicitly overrides worker health/speed and its first wave and uses a synthetic
loop lane. It retains production tower attacks, costs, authority and entity caps.
It is distinct from the real Garden four-client scenario.

| Dense fixture, 10 virtual seconds | Observed |
| --- | --- |
| Participants / maximum towers / maximum enemies | 4 / 12 / 20 |
| Accounted full projections at virtual 10 Hz | 400 recipient envelopes |
| Projection size, maximum / mean / total estimate | 11067 / 8083.5875 / 3233435 bytes |
| Attacks, logical / recipient envelopes | 244 / 976 |
| Attack size, maximum / mean / total recipient estimate | 254 / 247.0205 / 241092 bytes |
| Combined estimated rate, all recipients / each recipient | 347452.7 / 86863.175 bytes per virtual second |
| Local headless step p95, initial and later focused runs | Approximately 0.5214 and 0.5298 ms |

Timing differences between those runs are ordinary host observations, not a
before/after optimization result. The virtual schedule is explicit accounting;
actual sender cadence is established separately by Studio observations.

Repeated finite coverage ran 48 terminal fixture sessions, with 3432 fixed steps
per 24-cycle run, maximum two enemies and zero retained runtime entities,
participants and wave origins after cleanup. Two runs of Easy, Normal and Hard
production Garden campaigns reproduced terminal waves 20/30/40, attack counts
567/1079/1959 and Battle Cash 1600/4595/9773. Two runs of 2000 generated Endless
descriptions produced checksum 1186923905, at most six groups and 72 spawns.
Generated descriptions and empty deterministic collections do not establish
real-time engine memory, connection, frame or network soak acceptance.

## Provisional local regression thresholds

The following thresholds use the observations above with explicit headroom.
They are review thresholds for repeating the same fixture, hardware, foreground
state, warmup, engine settings and duration. They are not advertised-platform
exit criteria. A warning calls for a matching capture; a failure requires an
explanation or fix before accepting that local scenario. A background-throttled
window or a different workload is a different measurement environment, not a
pass or failure against the foreground row.

| Metric and matching environment | Target | Warning above | Failure above |
| --- | ---: | ---: | ---: |
| Foreground solo client frame p95, 12-second Ready/Garden windows | 20 ms | 22 ms | 25 ms |
| Foreground solo client worst frame, same windows | 25 ms | 33.3 ms | 50 ms |
| Headless dense fixture runtime-step p95, 200 steps | 0.75 ms | 1 ms | 1.5 ms |
| Four-client normal-load service step mean inclusive CPU per captured frame, matching 128-frame capture | 0.15 ms | 0.2 ms | 0.3 ms |
| Four-client normal-load service step maximum span, same capture | 2.5 ms | 3 ms | 4 ms |
| Four-client normal-load runtime-step maximum span, same capture | 0.25 ms | 0.5 ms | 1 ms |
| Four-client Garden Hard foreground client frame p95, matching 30-second scene | 22 ms | 25 ms | 33.3 ms |
| Four-client Garden Hard service step mean inclusive CPU per frame, matching 128-frame scene | 0.55 ms | 0.75 ms | 1 ms |
| Four-client Garden Hard service step maximum span, same capture | 3.5 ms | 4.5 ms | 6 ms |
| Four-client Garden Hard runtime-step maximum span, same capture | 0.3 ms | 0.5 ms | 1 ms |
| Dense fixture maximum projection estimate | 12000 bytes | 14000 bytes | 16384 bytes |
| Dense fixture maximum attack estimate | 300 bytes | 400 bytes | 512 bytes |
| Dense fixture combined per-recipient estimated rate, virtual 10 Hz | 90000 bytes/s | 100000 bytes/s | 125000 bytes/s |
| Ready solo process-memory endpoint increase, warmed identical 12-second idle window | 2 reported MB | 5 reported MB | 20 reported MB |

The Hard rows are provisional rounded review headroom above the observed
19.21 ms client p95, 0.448744 ms service mean, 3.136342 ms service maximum and
0.244988 ms runtime maximum. They are not statistically calibrated device limits,
and they do not replace the lighter Easy scenario's thresholds. No new absolute
memory or wire-bandwidth ceiling is inferred from a single combat window.

The memory row is an investigation threshold, not a leak diagnosis. It applies
only to repeated equal-state idle windows with recorded allocation/GC behavior;
combat endpoints, a newly loaded Studio session, additional local clients and
different process composition are not comparable. Absolute client/server memory
ceilings and repeated-match slope budgets remain uncalibrated. Any unexplained
retained ATD root or probe connection after cleanup fails cleanup regardless of
the memory delta. Deterministic cleanup requires exactly zero owned entities,
participants and wave origins and idempotent cleanup.

The existing automated payload safety guards are deliberately wider: projection
maximum below 32768 estimated bytes and attack maximum below 1024. Those guards
catch envelope explosions; they do not automatically enforce the tighter manual
review thresholds above. No flaky host timing assertion is installed in headless
CI. `PerformanceWindow.classify` distinguishes unavailable, target, above-target,
warning and failure measurements without treating missing values as success.

Runtime safety caps remain 12 towers, 20 enemies and 64 attacks per fixed step.
Client admission limits are 32 concurrent optional effects, four new effects per
frame, reduced to eight/one under low detail and zero under reduced motion.
Particles remain zero; sound admission is at most 12 concurrent sounds, one music
voice and two UI voices. These are bounded policy limits. They are not measured
sound-quality, hardware or frame budgets, especially while the approved audio
manifest contains no playable owned assets. Persistent health/range/navigation/
ownership/warnings bypass optional-effect suppression.

## Subsystem profiling and optimization decision

The shared `ProfileScope` adapter adds static labels without recording samples
or exposing diagnostics. Missing or failing engine profiler APIs cannot change
the operation result. Scope closure covers normal return and thrown errors.

- Runtime: `ATD.Runtime.Step`, `WaveStart`, `Spawn`, `Movement`,
  `TargetCandidates`, `TargetSelect`, `Attacks`, `WaveResolve`, `Snapshot`.
- Service: `ATD.Service.Step`, `SnapshotPublish`, `AttackPublish`.
- Client: `ATD.Client.UI`, `World`, `Aim`, `Effects`, `EffectCreate`,
  `Presentation`.

Use the appropriate full prefix for each label. Capture nested timings without
adding inclusive parent/child costs, record sample counts, and separate world
synchronization, UI updates, aiming and transient creation. A static marker is
instrumentation availability, not proof a subsystem was measured. Named traces
must identify the actual scene and capture duration before making that claim.

The recorded evidence does not justify spatial indexing, delta replication,
unreliable transport, pooling or a gameplay simulation rewrite. Current bounds,
authority, reconnect/full-snapshot recovery and cleanup are preserved. Short-lived
effect allocation is visible in instance counts, but no isolated allocation/GC
trace yet demonstrates that pooling would improve frame cost. Do not pool
authoritative entities or weaken gameplay communication to satisfy these numbers.

## Assets, joining and external budgets

The later Lobby Settings checkpoint is recorded in
`docs/evidence/platform-lobby-measurements.json`: 730 frames over 12.18 seconds,
p95 18.03 ms and maximum 23.58 ms, 5,704 instances at both endpoints, 121 created
and removed, and zero remaining probe connections. This was phone emulation on
the developer desktop with Largest text, pseudo50 and saved scale 0.75, before
the final physical-scale text-measurement fix. The protected profiler harness
also completed and restored its recorded toggles/frame limit. Its 107 eligible
frames are reported as 107, not a requested 128-frame population.

SceneAnalysis at that Lobby viewpoint reported 38,969 triangles/37 draws:
7,488/7 opaque, 1,492/1 UI, and 29,989/29 shadow passes. Excluding shadows gives
8,980 triangles/eight draws. Engine audio/animation totals were 2,843,594 and
139,261 bytes; these include character/Core assets and do not establish owned
ATD audio availability. Script-memory query was unavailable. The 13 reported
unparented instances were attributed to engine PlayerModule/character animation,
with none attributed to ATD at this checkpoint. No persistent optimization was
made from these single-view observations.

Profiler limitation: the initial audit did not record the original frame-limit
window, and LibMP exposes no getter. Later captures require explicit recorded
restore options. Cleanup restores disabled capture/profiler and the documented
256-frame default; this must not be described as proof of the unknown initial
frame-limit value. Native arrays from FindTimerIds have no Dispose operation;
owned sessions and iterators are disposed.

The bounded Studio audit counted 208 parts in ATD map templates, including 31
shadow-casting and 21 collidable parts, and 73 parts in playable templates with
zero shadow/collision flags. The roots have no scripts. This is source-template
inventory, not rendered runtime draw calls. No persistent asset edits were made.
Streaming is enabled; enabled status does not establish stream-in timing,
collision availability or camera/path behavior on constrained hardware.

The following remain unavailable until their named evidence exists:

- Cold/warm join and first-interactive latency: measure process join, authenticated
  profile readiness, initial projection receipt and enabled critical controls
  separately in a private published client. Local source boot time does not
  represent network join or travel latency.
- Device-class client frame and absolute memory budgets: calibrate a named phone,
  tablet, desktop controller client and any claimed console in a published
  session with actual hardware, resolution, graphics quality and thermal state.
- Roblox-hosted server simulation/update capacity and other worst-case tower
  combinations: the local Hard boss/density trace now has named runtime/service
  measurements, but it does not establish hosted or all-composition capacity.
- Reliable/unreliable wire rates, packet/bandwidth limits and resync cost: record
  a functioning engine/published transport trace with sender/receiver attribution;
  neither JSON estimates nor zero receive Stats establish this acceptance.
- Asset camera sweeps, texture memory/size, light/shadow GPU cost, animation
  metadata and streaming behavior: the Lobby and dense Match viewpoint counts
  above do not establish these wider budgets. Record before/after inventory for
  any separately approved persistent change.
- Long-duration memory and real-time Endless growth: the unchanged-source
  three-cycle repeat found no retained owned-object growth and did not reproduce
  the earlier 64.324 MB process increase; that earlier cause remains unexplained.
  Longer equal-state allocation/GC, memory, connection and network observations
  and published return remain separate gates. The two active Endless windows
  above supply bounded real-time evidence, not a long-duration growth result.
  Deterministic descriptions cannot close those longer gates.

Window focus and background throttling remain attached to each four-client
observation. Sequential clients are not one simultaneous frame distribution.
The completed captures establish the specific scene and cleanup facts above;
device, hosted/all-composition capacity, long-duration memory and external gates
remain open.
