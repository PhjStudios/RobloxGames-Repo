# Continuous integration

## Packet status

- Packet: 05.3
- Status: In progress; local workflow design recorded, genuine GitHub evidence
  not yet obtained
- Research date: 2026-08-26
- Target runner: GitHub-hosted Windows Server 2025 x64 (`windows-2025`)
- Workflow: `.github/workflows/ci.yml`, `Phase 05 Verification`
- Required job: `Windows verification`
- Workflow authority: verification only; no deployment, release, package, or
  Roblox publication authority

This record was written before the workflow was added. It documents the exact
executable supply chain and the evidence that Packet 05.3 must obtain. A local
workflow inspection or simulated command run is not a substitute for genuine
GitHub Actions runs.

## Dependency and action decision

The workflow uses one action and no cache or artifact action:

| Component | Immutable pin | License | Purpose and policy |
| --- | --- | --- | --- |
| `actions/checkout` | `3d3c42e5aac5ba805825da76410c181273ba90b1` (`v7.0.1`) | MIT | Checkout only; `persist-credentials: false`; update only after a separately reviewed full-SHA change. |
| Rokit | `1.2.0`; tag commit `3b803035635c29c752f6ea1d2befc1473b96c51a` | MIT | Direct official Windows x64 release download; bootstrap is verified before execution. |
| Rokit Windows archive | `rokit-1.2.0-windows-x86_64.zip`; SHA-256 `f9ba1704014ff67d51e8005f605955c7c26d2429a5312a9419dc477fc310e96d` | MIT | The official 3,638,436-byte archive contains only `rokit.exe`; any digest or layout mismatch fails. |
| Project tools | Exact versions in `rokit.toml` | See each official tool | `rokit install --no-trust-check` installs Rojo 7.7.0, StyLua 2.5.2, Selene 0.31.0, and Lune 0.10.5 into the ephemeral runner directory. |

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
- [Rokit isolated-root behavior](https://github.com/rojo-rbx/rokit/blob/v1.2.0/lib/storage/home.rs)
- [Official Rokit release metadata and asset digest](https://api.github.com/repos/rojo-rbx/rokit/releases/tags/v1.2.0)

## Workflow contract

The workflow must:

1. trigger on `push`, `pull_request`, and `workflow_dispatch`, never
   `pull_request_target`;
2. declare only `permissions: contents: read`;
3. check out the event-selected commit without persisting Git credentials;
4. download the exact Rokit archive, verify SHA-256 and archive layout before
   execution, and keep Rokit plus all installed tools under `runner.temp`;
5. install only the versions pinned by `rokit.toml` and verify every reported
   version;
6. run formatting, Selene configuration validation, Selene linting, the
   canonical tests, and the four-project structural verifier as distinct
   required steps;
7. fail on any nonzero command, zero tests, test failure, module-load or runner
   failure, formatting or lint failure, build failure, production test leak, or
   generated-output residue;
8. retain no place build, package output, cache, log bundle, or workflow
   artifact; and
9. reference no repository secret, Roblox credential, cookie, API key,
   publishing credential, release permission, or deployment command.

The workflow must not use `continue-on-error` on a required check. Commands
remain the same repository-owned commands used locally; CI does not maintain a
parallel test or build implementation.

## Required negative and clean evidence

Packet 05.3 is not complete until the following genuine GitHub evidence is
recorded. Each negative control must be an ordinary pushed commit and must be
followed by an ordinary restoring commit; history must not be rewritten.

| Evidence | Required result | Current status |
| --- | --- | --- |
| Deliberate formatting or Selene violation | The intended formatting/lint step fails before later checks. | Not run |
| Restored formatting/lint state plus deliberately broken definition or expectation | Formatting and lint pass; the automated-test step fails for the intended stable assertion/definition reason. | Not run |
| Final restoring commit | Every required step passes in one complete workflow run. | Not run |

The final evidence must record branch, commits, workflow/run/job names, URLs,
conclusions, restoring commits, actual runner image, permissions, absence of
retained artifacts, and the final clean repository state. If authentication,
write permission, or Actions availability prevents those runs, Packet 05.3 is
blocked rather than simulated.
