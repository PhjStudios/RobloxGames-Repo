# Continuous integration

## Packet status

- Packet: 05.3
- Status: Complete — 2026-08-26
- Research date: 2026-08-26
- Target runner: GitHub-hosted Windows Server 2025 x64 (`windows-2025`)
- Workflow: `.github/workflows/ci.yml`, `Repository Verification`
- Required job: `Windows verification`
- Phase 05 evidence branch: `codex/phase-05-ci-verification`
- Current Phase 06 evidence branch: `codex/phase-06-network-security`
- Workflow authority: verification only; no deployment, release, package, or
  Roblox publication authority

The dependency decision and executable supply chain were recorded before the
workflow was added. This final record also contains the genuine GitHub Actions
negative controls and clean runs required by Packet 05.3; local inspection or a
simulated command run was not used as a substitute.

This workflow is the automated-CI row in `docs/TEST_MATRIX.md`; it does not claim
Studio, multi-client, published-client, device, or production-sensitive coverage.

## Dependency and action decision

The workflow uses one action and no cache or artifact action:

| Component | Immutable pin | License | Purpose and policy |
| --- | --- | --- | --- |
| `actions/checkout` | `3d3c42e5aac5ba805825da76410c181273ba90b1` (`v7.0.1`) | MIT | Checkout only; `persist-credentials: false`; update only after a separately reviewed full-SHA change. |
| Rokit | `1.2.0`; tag commit `3b803035635c29c752f6ea1d2befc1473b96c51a` | MIT | Direct official Windows x64 release download; bootstrap is verified before execution. |
| Rokit Windows archive | `rokit-1.2.0-windows-x86_64.zip`; SHA-256 `f9ba1704014ff67d51e8005f605955c7c26d2429a5312a9419dc477fc310e96d` | MIT | The official 3,638,436-byte archive contains only `rokit.exe`; any digest or layout mismatch fails. |
| Project tools | Exact versions in `rokit.toml` | See each official tool | Rokit uses the job's built-in read-only token for release-asset requests, removes that authentication immediately after installation, and installs Rojo 7.7.0, StyLua 2.5.2, Selene 0.31.0, and Lune 0.10.5 into the ephemeral runner directory. |

The checkout tag and Rokit tag were independently resolved from their official
repositories. The Rokit digest was read from the official GitHub Releases API
and independently reproduced from the downloaded archive. The workflow does
not execute a remote installer script, mutable branch, mutable action tag, or
unverified archive.

Checkout v7.0.1 was released on 2026-07-20 and uses Node 24. Its documented
runtime requirement is Actions Runner 2.327.1 or newer; current GitHub-hosted
runners meet it. `windows-2025` is the current generally available Windows
family and avoids following the moving `windows-latest` alias. The older
`windows-2022` family is also technically compatible, but selecting the current
family avoids beginning this foundation on the older image line. GitHub still
updates hosted images within a named family, so every retained run must record
the actual image version from its job log.

No dependency cache is justified at this foundation scale. Omitting one avoids
another executable action and cache-poisoning boundary. GitHub-hosted job
storage and the isolated Rokit root are ephemeral and are naturally discarded
after the job.

Rokit release discovery and tool downloads use GitHub's API. The workflow
passes the job's automatically generated, read-only `github.token` to Rokit's
documented authentication command to avoid the shared unauthenticated API
limit, then removes both the Rokit authentication entry and the step environment
variable before verification begins. No repository-configured secret or
persistent credential is used.

## Official primary sources

- [actions/checkout v7.0.1 release](https://github.com/actions/checkout/releases/tag/v7.0.1)
- [Pinned checkout commit](https://github.com/actions/checkout/commit/3d3c42e5aac5ba805825da76410c181273ba90b1)
- [Checkout action metadata](https://github.com/actions/checkout/blob/v7.0.1/action.yml)
- [Checkout permissions and runtime documentation](https://github.com/actions/checkout/blob/v7.0.1/README.md)
- [Checkout MIT license](https://github.com/actions/checkout/blob/v7.0.1/LICENSE)
- [GitHub secure-use guidance](https://docs.github.com/en/actions/reference/security/secure-use)
- [GitHub workflow syntax and permissions](https://docs.github.com/en/actions/reference/workflows-and-actions/workflow-syntax)
- [GitHub workflow-event behavior](https://docs.github.com/en/actions/reference/workflows-and-actions/events-that-trigger-workflows)
- [GitHub-hosted runner reference](https://docs.github.com/en/actions/reference/runners/github-hosted-runners)
- [Official runner-image labels](https://github.com/actions/runner-images)
- [Rokit 1.2.0 release](https://github.com/rojo-rbx/rokit/releases/tag/v1.2.0)
- [Rokit installation documentation](https://github.com/rojo-rbx/rokit/blob/v1.2.0/README.md)
- [Rokit MIT license](https://github.com/rojo-rbx/rokit/blob/v1.2.0/LICENSE.txt)
- [Rokit CI trust-check behavior](https://github.com/rojo-rbx/rokit/blob/v1.2.0/src/cli/install.rs)
- [Rokit authentication command](https://github.com/rojo-rbx/rokit/blob/v1.2.0/src/cli/authenticate.rs)
- [Rokit isolated-root behavior](https://github.com/rojo-rbx/rokit/blob/v1.2.0/lib/storage/home.rs)
- [Official Rokit release metadata and asset digest](https://api.github.com/repos/rojo-rbx/rokit/releases/tags/v1.2.0)
- [GitHub automatic workflow-token contract](https://docs.github.com/en/actions/concepts/security/github_token)

## Workflow contract

The workflow must:

1. trigger on `push`, `pull_request`, and `workflow_dispatch`, never
   `pull_request_target`;
2. declare only `permissions: contents: read`;
3. check out the event-selected commit without persisting Git credentials;
4. download the exact Rokit archive, verify SHA-256 and archive layout before
   execution, and keep Rokit plus all installed tools under `runner.temp`;
5. authenticate Rokit's GitHub release requests only with the job's automatic
   read-only token, remove that authentication immediately after installation,
   install only the versions pinned by `rokit.toml`, and verify every reported
   version;
6. run formatting, Selene configuration validation, Selene linting, the
   canonical tests, and the four-project structural verifier as distinct
   required steps;
7. fail on any nonzero command, zero tests, test failure, module-load or runner
   failure, formatting or lint failure, build failure, production test leak, or
   generated-output residue;
8. retain no place build, package output, cache, log bundle, or workflow
   artifact; and
9. reference no repository-configured secret, Roblox credential, cookie,
   persistent API key, publishing credential, release permission, or deployment
   command.

The workflow must not use `continue-on-error` on a required check. Commands
remain the same repository-owned commands used locally; CI does not maintain a
parallel test or build implementation.

## Genuine negative and clean evidence

All evidence below came from ordinary commits pushed to
`codex/phase-05-ci-verification`. Each deliberate failure was followed by an
ordinary restoring commit. No force-push, history rewrite, pull request,
deployment, publication, repository-setting change, repository-configured
secret, external credential, or Roblox credential was introduced or referenced
by the workflow. Checkout used only GitHub's implicit least-privilege token.

| Evidence | Commit and genuine run | Result |
| --- | --- | --- |
| Initial live run / bootstrap defect | Foundation commit `95c13801fa11f92eca33b342e75461f5fee32f75`; [run 1](https://github.com/PhjStudios/RobloxGames-Repo/actions/runs/32969869700), [job 98180817628](https://github.com/PhjStudios/RobloxGames-Repo/actions/runs/32969869700/job/98180817628) | Failed before checks at `Install pinned Rokit toolchain`. The log identified a PowerShell parser error caused by leading continuation-line `-or` tokens. This was an implementation defect, not a required negative control. |
| Corrected clean baseline | Parser-fix commit `cf1d79b7f6722eff9c53b238ed9c113ac64ed29f`; [run 2](https://github.com/PhjStudios/RobloxGames-Repo/actions/runs/32970317159), [job 98182245919](https://github.com/PhjStudios/RobloxGames-Repo/actions/runs/32970317159/job/98182245919) | Passed every required step. |
| Formatting negative control | `02dfbe833743961d93820017c8a5e82399f11054` (`test(ci): prove formatting failure`); [run 3](https://github.com/PhjStudios/RobloxGames-Repo/actions/runs/32970475786), [job 98182761351](https://github.com/PhjStudios/RobloxGames-Repo/actions/runs/32970475786/job/98182761351) | Setup and pinned-version checks passed. `Check Luau formatting` failed with exit 1 and named `tests/specs/Smoke.spec.luau`; all later required checks were skipped. |
| Formatting restoration | `2c5f8592ad987963609ab361a731b111509e91d0` (`test(ci): restore formatting control`); [run 4](https://github.com/PhjStudios/RobloxGames-Repo/actions/runs/32970674430), [job 98183409900](https://github.com/PhjStudios/RobloxGames-Repo/actions/runs/32970674430/job/98183409900) | Complete clean pass before the next control. |
| Expectation negative control | `60a0aae4e61fee31f4c5a37e8b1deef9b4711b1e` (`test(ci): prove automated test failure`); [run 5](https://github.com/PhjStudios/RobloxGames-Repo/actions/runs/32970860256), [job 98184011544](https://github.com/PhjStudios/RobloxGames-Repo/actions/runs/32970860256/job/98184011544) | Formatting, Selene configuration, and lint all passed. `Run deterministic unit tests` then failed with `ASSERT_EQUAL_FAILED`, suite `runner smoke`, case and path context, and summary `failed=1`, `passed=75`, `tests=76`. |
| Expectation restoration | `d946c8f888488b1c4780baf8b7a704344ae6403d` (`test(ci): restore automated test control`); [run 6](https://github.com/PhjStudios/RobloxGames-Repo/actions/runs/32971057779), [job 98184643132](https://github.com/PhjStudios/RobloxGames-Repo/actions/runs/32971057779/job/98184643132) | Complete clean pass before the stricter exit-gate controls. |
| Selene-lint negative control | `9c8b2609929374731934f4488d8407145a6425ba` (`test(ci): prove Selene lint failure`); [run 7](https://github.com/PhjStudios/RobloxGames-Repo/actions/runs/32972023099), [job 98187762689](https://github.com/PhjStudios/RobloxGames-Repo/actions/runs/32972023099/job/98187762689) | Setup, pinned versions, formatting, and Selene configuration validation passed. `Lint Luau` failed with exit 1 on exactly one `unused_variable` warning and no errors or parse errors. |
| Selene-lint restoration | `ae4d39440ece57a038b8ed673402ecd423711f12` (`test(ci): restore Selene lint control`); [run 8](https://github.com/PhjStudios/RobloxGames-Repo/actions/runs/32972218109), [job 98188400918](https://github.com/PhjStudios/RobloxGames-Repo/actions/runs/32972218109/job/98188400918) | Complete clean pass before the broken-definition control. |
| Broken-definition negative control | `d6dd2e2a51cb312b27a99007a001ce1013871107` (`test(ci): prove broken definition failure`); [run 9](https://github.com/PhjStudios/RobloxGames-Repo/actions/runs/32972524397), [job 98189368945](https://github.com/PhjStudios/RobloxGames-Repo/actions/runs/32972524397/job/98189368945) | A test-only Tower definition used a negative placement cost. Formatting and lint passed; the test step failed with `ASSERT_TRUE_FAILED`, exact schema suite/case/path context, and summary `failed=1`, `passed=75`, `tests=76`. Lasting authored catalogs were unchanged. |
| Final restoration | `877b5f71c0446bccfd73df565931aa34985857d6` (`test(ci): restore broken definition control`); [run 10](https://github.com/PhjStudios/RobloxGames-Repo/actions/runs/32972680148), [job 98189867916](https://github.com/PhjStudios/RobloxGames-Repo/actions/runs/32972680148/job/98189867916) | Complete clean pass. Every required workflow step succeeded. |

The final successful job used Actions Runner `2.336.0`, image
`windows-2025-vs2026` version `20260818.207.1`, and reported only
`Contents: read` plus GitHub's implicit `Metadata: read`. It verified Rokit
1.2.0, Rojo 7.7.0, StyLua 2.5.2, Selene 0.31.0, and Lune 0.10.5; reported zero
Selene errors, warnings, and parse errors; passed all 76 tests in eight suites;
and emitted all four structural build markers:

- Default, Lobby, and Match: `MODULES_30_SCRIPTS_1_LOCALSCRIPTS_1`
- Test: `SHARED_MODULES_29_RUNNABLE_SCRIPTS_0`

GitHub's run-artifact API returned an empty artifact list for inspected clean
runs 2, 6, and 10. At the restoration evidence checkpoint, the local branch
matched its remote with no tracked or untracked residue and only the
pre-existing ignored `sourcemap.json`. Packet 05.3 therefore satisfies its
genuine negative-control and clean-run gate.

The subsequent evidence-documentation commit
`8de8d49c4e21bd136edfc9bb087f305f86654089` also passed every required step in
[run 11](https://github.com/PhjStudios/RobloxGames-Repo/actions/runs/32973295687)
([job 98191841968](https://github.com/PhjStudios/RobloxGames-Repo/actions/runs/32973295687/job/98191841968))
and retained no artifacts. This did not add a new control or broaden workflow
authority.

The final Packet 05.4 test-matrix and combined exit-audit commit
`884999482091f4a7276a1d20c9ebdb6c029c159b` passed every required step in
[run 12](https://github.com/PhjStudios/RobloxGames-Repo/actions/runs/32978442021)
([job 98208817947](https://github.com/PhjStudios/RobloxGames-Repo/actions/runs/32978442021/job/98208817947)).
The public API confirmed the exact commit, `push` event, successful `Windows
verification` job and every required step, and `total_count = 0` retained
artifacts. This completed the genuine remote condition for the Phase 05 exit
gate without changing workflow authority.

## Phase 06 evidence status

The workflow's phase-specific display name was replaced with the stable
`Repository Verification` name during the Phase 06 exit audit. No trigger,
permission, action, digest, tool pin, command, residue condition, or workflow
authority changed.

Packet 06.5 commit `6c690fee71761165f24f7bd279bd0b3310ea2509`
passed every required step in
[run 33014884391](https://github.com/PhjStudios/RobloxGames-Repo/actions/runs/33014884391)
([job 98330403303](https://github.com/PhjStudios/RobloxGames-Repo/actions/runs/33014884391/job/98330403303)).
That packet run is clean evidence for its exact commit but does not substitute
for the fresh combined Gate A state.

The fresh Phase 06/Gate A audit passes. Audit-content commit
`7ada807586164c8ab0c940c749393c243d4fe9e3` passed genuine clean
`Repository Verification`
[run 33022784985](https://github.com/PhjStudios/RobloxGames-Repo/actions/runs/33022784985),
[job 98356927817](https://github.com/PhjStudios/RobloxGames-Repo/actions/runs/33022784985/job/98356927817),
on a `push` event at the exact head SHA. Run attempt one reported success for setup,
checkout, pinned Rokit installation and version verification, formatting,
Selene configuration, lint, deterministic unit tests, all-project structural
verification, and generated-output residue checks. The requested runner label
was `windows-2025`, the public job record named runner
`GitHub Actions 1000000023`, and the artifact API returned zero retained
artifacts. The unauthenticated job-log archive endpoint returned HTTP 403, so
this record does not infer an image version from the numeric API runner name.
Phase 06 is complete and Gate A passed; Phase 05's intentional negative-control
commits were not recreated for Phase 06.
