# Phase 05 Exit-Gate Audit

## Purpose and current status

This document records the fresh combined-state audit for Phase 05 — Automated
Test and Continuous-Integration Foundation. It audits Packets 05.1 through 05.4
together after the test matrix and documentation reconciliation; it does not
merely repeat packet-level claims.

- **Audit date:** 2026-08-26
- **Branch:** `codex/phase-05-ci-verification`
- **Phase 04 baseline:** `ad16c4fdc8f5abadf50d648d143941bd9addc401`
- **Last pushed Phase 05 evidence commit:**
  `8de8d49c4e21bd136edfc9bb087f305f86654089`
- **Packets 05.1-05.4:** complete
- **Local combined-state audit:** passed
- **Independent exit reviews:** passed; final P0-P3 clearance recorded below
- **Final current-state GitHub run:** pending an explicitly authorized
  documentation commit/push
- **Phase 05 status:** not yet marked complete
- **Phase 06 status:** not begun

The final remote checkpoint is intentionally not inferred from Packet 05.3's
push authorization. Packet 05.3 authorized its own controlled commits and
pushes only. The current Packet 05.4 and exit-audit documentation remains local
until the user explicitly authorizes the final ordinary documentation commit(s)
and push(es).

## Audited repository state

At the audit start, local `HEAD`, upstream, and the remote branch all resolved to
`8de8d49c4e21bd136edfc9bb087f305f86654089`. The remote remained
`https://github.com/PhjStudios/RobloxGames-Repo.git`. The working tree contained
only the intended Packet 05.4 documentation/policy changes plus the new test
matrix; the only ignored file was the pre-existing `sourcemap.json`.

The complete Phase 05 path inventory from the Phase 04 baseline contains only:

- the pinned Lune entry in `rokit.toml`;
- `test.project.json`;
- repository-owned `tests/` runner, fixtures, controls, specs, support, and
  structural verifier;
- `.github/workflows/ci.yml`;
- repository instructions and documentation.

It contains no `src/` change. The current source tree still has 32 Luau files:
30 ModuleScripts plus the one common server Script and one common client
LocalScript. No remote, network implementation, gameplay service, persistence,
UI, map, runtime enemy, wave, tower, currency, reward, gacha, purchase, or other
Phase 06/later implementation entered the phase.

## Tool installation and version audit

`rokit install` completed successfully through a normal authorized host
invocation using the tracked `rokit.toml`. A first sandbox-confined invocation
could not write Rokit's user-level data directory; that environment restriction
did not alter the repository, and the authorized invocation immediately passed.

| Tool | Required pin | Fresh reported version | Result |
| --- | --- | --- | --- |
| Rokit | bootstrap `1.2.0` | `rokit 1.2.0` | Pass |
| Rojo | `rojo-rbx/rojo@7.7.0` | `Rojo 7.7.0` | Pass |
| StyLua | `JohnnyMorganz/StyLua@2.5.2` | `stylua 2.5.2` | Pass |
| Selene | `Kampfkarren/selene@0.31.0` | `selene 0.31.0` | Pass |
| Lune | `lune-org/lune@0.10.5` | `lune 0.10.5` | Pass |

No tool was upgraded. No package/install directory, lockfile-like output, or
temporary download entered the working tree.

## Formatting and lint audit

The restored combined state passed:

| Command | Result |
| --- | --- |
| `stylua src tests` | Exit 0; no production/test rewrite remained |
| `stylua --check --verify src tests` | Exit 0 |
| `selene validate-config` | Exit 0 |
| `selene src tests` | Exit 0; 0 errors, 0 warnings, 0 parse errors |

No Selene suppression, warning downgrade, or scope exclusion was introduced.

## Three-run determinism audit

Three consecutive fresh invocations of `lune run tests/run.luau` ran in one
sequential audit process. Every run discovered the same eight suites and 76
cases in the same canonical path and declaration order, returned exit 0, and
ended with:

```text
[ATD_TEST][SUMMARY][failed=0][passed=76][status=PASS][suites=8][tests=76]
```

Each raw captured stdout stream was 15,470 bytes with SHA-256
`e4a93d7e047dcebe509753b026c85068576c51048294247f1634782585325206`.
Removing only the process's final line-feed produced the previously documented
15,469-byte canonical content and SHA-256
`52bf494c37f3c47822b5a7c6ce372d8c8ea76ee807ebf28f3ea767cef8c93616`.
All three raw strings were byte-identical. The distinction is recorded so a
shell's treatment of the terminal newline cannot create a false reproducibility
claim or regression.

The deterministic order remained:

1. Cleanup — 14 cases
2. Configuration public contract edges — 16 cases
3. Configuration schema failures — 17 cases
4. Lasting and loaded configuration — 6 cases
5. Configuration privacy and malformed boundaries — 5 cases
6. Configuration schemas valid fixtures — 4 cases
7. Core ID, Result, and Validation contracts — 12 cases
8. Runner smoke — 2 cases

## Permanent runner failure audit

Every permanent isolated control returned its documented nonzero class and
stable code. The audit also scanned complete stdout/stderr for the private
markers embedded in the controls; none appeared.

| Control | Expected/actual exit | Stable code observed | Private marker observed | Result |
| --- | ---: | --- | --- | --- |
| `assertion` | `1` / `1` | `ASSERT_EQUAL_FAILED` | no | Pass |
| `zero` | `2` / `2` | `ZERO_TESTS` | no | Pass |
| `module-load` | `2` / `2` | `MODULE_EXECUTION_FAILED` | no | Pass |
| `malformed` | `2` / `2` | `MISNAMED_SPEC` | no | Pass |
| `malformed-root` | `2` / `2` | `ROOT_WRONG_CLASS` | no | Pass |
| `runner-crash` | `3` / `3` | `RUNNER_CRASH` | no | Pass |

This proves the specifically required zero-discovery, assertion, module-load,
and runner-failure paths as well as both malformed-discovery boundaries.

## Local lint and broken-definition controls

The two stricter controls were reproduced through exact temporary edits and
restored with `apply_patch`; no reset, checkout, clean, or history rewrite was
used.

| Control | Preconditions | Intended failure | Result |
| --- | --- | --- | --- |
| Selene lint | Formatting check passed | `selene src tests` exited 1 with exactly one `unused_variable` warning, 0 errors, and 0 parse errors at `tests/specs/Smoke.spec.luau` | Pass |
| Broken definition | Formatting and Selene passed | Canonical tests exited 1 with `ASSERT_TRUE_FAILED` in the schema-entrypoint case and `failed=1`, `passed=75`, `tests=76` after a test-only Tower placement cost was set to `-1` | Pass |

After restoration, `git diff --exit-code -- tests`, Selene, and the complete
76-case suite all passed. Lasting authored configuration was never modified.

## Four-project build and shipping audit

`lune run tests/verify-builds.luau` passed after all controls were restored:

| Build | Fresh structural marker | Result |
| --- | --- | --- |
| Default | `MODULES_30_SCRIPTS_1_LOCALSCRIPTS_1` | Pass |
| Lobby | `MODULES_30_SCRIPTS_1_LOCALSCRIPTS_1` | Pass |
| Match | `MODULES_30_SCRIPTS_1_LOCALSCRIPTS_1` | Pass |
| Test | `SHARED_MODULES_29_RUNNABLE_SCRIPTS_0` | Pass |

The verifier freshly proved every production Lua container against the fixed
positive DataModel path, class, authoritative file, and byte-for-byte source
map. It also proved:

- no runner, spec, fixture, negative control, test support, or test-only marker
  exists in Default, Lobby, or Match;
- Lobby contains no Match source and Match contains no Lobby source;
- production retains exactly one common server bootstrap and one common client
  bootstrap;
- Test maps the 29 shared ModuleScripts, no client/server source, and no runnable
  Script/LocalScript;
- every exact generated build output was removed on success.

Separately, the canonical `ConfigurationLoaded` cases in
`lune run tests/run.luau` freshly proved that lasting tower, enemy, map,
difficulty, wave, asset, and banner catalogs remain empty and that Economy and
Settings remain policy-only. The structural verifier checks source identity and
shipping boundaries; it does not replace that semantic policy test.

## Workflow security audit

Fresh source inspection of `.github/workflows/ci.yml` passed every required
control:

- only `push`, `pull_request`, and `workflow_dispatch` trigger the workflow;
- `pull_request_target` is absent;
- top-level permissions are only `contents: read`;
- checkout is pinned to the full immutable v7.0.1 SHA
  `3d3c42e5aac5ba805825da76410c181273ba90b1` and does not persist credentials;
- Rokit 1.2.0 is downloaded under `runner.temp`, verified against SHA-256
  `f9ba1704014ff67d51e8005f605955c7c26d2429a5312a9419dc477fc310e96d`,
  layout-checked, and removed after installation;
- every tool version is checked exactly against the manifest;
- formatting, Selene configuration, lint, canonical tests, structural builds,
  and residue checks are distinct required steps;
- `continue-on-error`, cache actions/keys, artifact upload/download actions,
  secrets context, deployment, release, and Roblox publication are absent; and
- tracked, staged, nonignored untracked, and build-directory residue all fail
  the job.

The workflow retains no `.rbxl`/`.rbxlx`, cache, log bundle, or artifact.

## Genuine GitHub Actions evidence

A fresh read-only GitHub public Actions API check reconfirmed each control's
commit, run/job conclusion, and exact failed workflow step:

| Evidence | Commit | Run/job | Fresh API result |
| --- | --- | --- | --- |
| Formatting control | `02dfbe833743961d93820017c8a5e82399f11054` | [run 32970475786](https://github.com/PhjStudios/RobloxGames-Repo/actions/runs/32970475786), [job 98182761351](https://github.com/PhjStudios/RobloxGames-Repo/actions/runs/32970475786/job/98182761351) | failure; only `Check Luau formatting` failed |
| Broken expectation | `60a0aae4e61fee31f4c5a37e8b1deef9b4711b1e` | [run 32970860256](https://github.com/PhjStudios/RobloxGames-Repo/actions/runs/32970860256), [job 98184011544](https://github.com/PhjStudios/RobloxGames-Repo/actions/runs/32970860256/job/98184011544) | failure; only `Run deterministic unit tests` failed |
| Selene lint control | `9c8b2609929374731934f4488d8407145a6425ba` | [run 32972023099](https://github.com/PhjStudios/RobloxGames-Repo/actions/runs/32972023099), [job 98187762689](https://github.com/PhjStudios/RobloxGames-Repo/actions/runs/32972023099/job/98187762689) | failure; only `Lint Luau` failed |
| Broken definition | `d6dd2e2a51cb312b27a99007a001ce1013871107` | [run 32972524397](https://github.com/PhjStudios/RobloxGames-Repo/actions/runs/32972524397), [job 98189368945](https://github.com/PhjStudios/RobloxGames-Repo/actions/runs/32972524397/job/98189368945) | failure; only `Run deterministic unit tests` failed |
| Clean evidence state | `8de8d49c4e21bd136edfc9bb087f305f86654089` | [run 32973295687](https://github.com/PhjStudios/RobloxGames-Repo/actions/runs/32973295687), [job 98191841968](https://github.com/PhjStudios/RobloxGames-Repo/actions/runs/32973295687/job/98191841968) | success; every required step passed |

The final listed clean run was triggered by `push`, ran the `Windows
verification` job, and its public artifact API returned `total_count = 0`.
Browser inspection independently showed `Status: Success`, the correct branch
and commit, job success, and no artifacts. Packet 05.3's detailed failure
messages, runner image, reported permissions, and restoration commits remain in
[Continuous integration](CONTINUOUS_INTEGRATION.md).

Run `32973295687` proves the last pushed executable Phase 05 state. A new genuine
clean run of the final documentation/audit commit is still required before this
audit marks Phase 05 complete.

## Link, privacy, artifact, and scope audit

The complete README/documentation set passed a generated local-link and
GitHub-style heading-anchor audit. The first external-link pass found 56 of 58
links healthy and two Roblox HTML API-reference routes returning repeated 502
responses. Those two references were corrected to Roblox's official `.md`
API-reference endpoints. A new complete pass then returned HTTP 2xx for all 58
unique external links.

A high-confidence secret scan found zero GitHub token, Roblox security-cookie,
AWS access-key, private-key, or similar credential pattern. No `.env`, log,
place build, package/install directory, temporary file, or retained workflow
artifact exists. The only ignored file remains the pre-existing generated
`sourcemap.json`.

Observable negative-control output contained no private marker. Documentation
contains no raw profile, catalog payload, reserved-server code, cookie, API key,
arbitrary caught error, or rejected private value.

The authoritative [test matrix](TEST_MATRIX.md) has 37 uniquely identified test
records across all six required categories. A machine check confirmed every
record contains all 12 required fields. Future gameplay, multi-client,
published-client, device/accessibility, persistence, purchase, and destructive
tests are marked deferred, unavailable, historical-only, or prohibited with an
exact prerequisite; none is mislabeled as passing current automation.

## Studio regression decision

Phase 05 changed no production `src/`, place-role declaration, Rojo production
mapping, bootstrap behavior, or Studio-authored instance. Under the approved
scope, no Phase 05 Studio rerun was necessary or authorized. Historical Studio
evidence remains labeled historical, and the current safe procedures remain in
the test matrix. Neither Roblox place was saved or published, and no external
Roblox service was enabled.

## Independent review status

Three independent read-only combined-state reviews inspected the final local
source/tests, workflow security and remote evidence, and documentation/matrix
state. Their initial findings were corrected without changing production source:

- the source/test review reassigned lasting-catalog policy evidence from the
  structural verifier to the canonical `ConfigurationLoaded` cases and removed
  unsupported current headless-serialization claims;
- the workflow-security review narrowed the residue wording to the workflow's
  exact nonignored-untracked check; and
- the documentation review reconciled all current regression procedures,
  player-count requirements, status vocabulary, and external-service boundaries.

Each reviewer then inspected the corrected current tree. Final P0, P1, P2, and
P3 status is clear in all three review areas. The matrix independently retains
37 unique records, every record retains all 12 required fields, all 49 local
Markdown targets and anchors resolve, and `git diff --check` passes.

## Remaining exit condition

All local technical and documentation gates are green. The sole remaining
condition is a genuine clean GitHub Actions run for the final intended Phase 05
documentation/audit state.

Completing that condition requires explicit authorization to create and push the
ordinary final documentation commit(s) on
`codex/phase-05-ci-verification`. No force-push, merge, pull request, branch/tag
deletion, repository-setting change, secret, deployment, Roblox publication, or
Phase 06 work is required or authorized.

Until that authorization and clean run exist:

- Phase 05 remains in its exit audit;
- `docs/DEVELOPMENT_PLAN.md` must not mark the Phase 05 exit gate passed; and
- Packet 06.1 is identified only as the next future packet, not begun.
