# Handshake Task Staging CI

**Private, standalone testing workspace** for developing Handshake tasks before committing them to their corresponding source forks.

This repository is intentionally **not a fork**. The `submission` branches in the source repositories are never modified by the validation workflow.

## Important: turn this repository PRIVATE before using it

This repository was originally created **public**. A Handshake task can contain a private reference solution, hidden tests, and grading traces. **Do not upload these into a public repository.**

First open [repository visibility settings](https://github.com/pavan2528/handshake-task-ci/settings) and change the repository to **Private**. The workflow has a safety gate that refuses to run while this repository is public.

Neither a `SOURCE_REPO_TOKEN` nor checkout access to the source fork is required by this staging workflow. Staged task code is checked out from **this** repository only.

## Intended workflow

1. Develop and adjust a candidate task independently of the Handshake submission fork.
2. Copy the **complete** candidate task into `tasks/<task-name>/` **in this private CI repository**. Keep its exact files and relative structure: `task.toml`, `instruction.md`, `environment/`, `solution/`, and `tests/`.
3. Push/commit to `main` here; that automatically runs **Candidate Task Docker + Harbor Validation**. Alternatively dispatch it manually by giving `tasks/<task-name>`, or change `ci/request.txt` to rerun an existing stage.
4. GitHub Actions builds/runs the task with Docker and installs the Harbor framework CLI. It checks:
   - Required task files and TOML parsing.
   - For `tasks/pcie-reassembly`, the existing agent/verifier Docker image builds, isolation, Oracle twice expecting reward 1, and Nop twice expecting reward 0.
   - Through `harbor run --path <staged-task> --agent oracle/nop --env docker`, **Oracle twice**, expecting reward **1**, and **Nop twice**, expecting reward **0**.
   - The workflow fails if any run has a missing result, unexpected reward, simulation error, Docker/Harbor failure, or incorrect stage isolation.
5. Inspect GitHub Actions and the commit's `task-staging/docker-harbor` status. If any check fails, fix the **staged candidate here**, commit, and repeat. Do **not** update the source fork yet.
6. Once all checks are green, confirm the stage commit SHA and task **tree SHA** in the summary. Copy **the same task files** (not CI scripts) into the target fork's `submission` branch, then confirm the corresponding Git tree matches.
7. Push only the verified submission and review the **official Handshake** artificiality, rubric, and difficulty evaluations. The upstream pass@2/pass@5 agent trials are not reproducible merely by running Oracle/Nop in Docker.

If any post-promotion changes are required, start another staged validation before pushing those changes to submission.

## How to trigger

**On commit:** A change to `tasks/**`, `scripts/**`, `ci/request.txt`, or the workflow on the CI repo's `main` branch starts validation.

**Manually:** [Actions → Candidate Task Docker + Harbor Validation](https://github.com/pavan2528/handshake-task-ci/actions/workflows/rtl-ci.yml) → Run workflow → `task_path=tasks/pcie-reassembly` (or another staged task).

**Rerun from connected GitHub tools:** Update `ci/request.txt` with `task_path=tasks/<name>` and a new `request_id`. This triggers Actions without writing to the Handshake fork.

## What the pipeline does NOT do

- It does not download or write the private Handshake source fork.
- It does not modify the source fork automatically; promotion happens only after the results have been inspected.
- It does not claim the official Handshake pass@2/pass@5 model-difficulty evaluation has passed.
- It does not upload the hidden verifier, reference solution, traces or raw Harbor logs as artifacts. Those stay on the ephemeral runner.

## Repo structure

```text
.github/workflows/rtl-ci.yml
scripts/verify_pcie.sh       # PCIe-specific direct Docker preflight
scripts/verify_harbor.sh      # Harbor Oracle/Nop double gate for staged tasks
ci/request.txt               # rerun an already-staged task
tasks/<task-name>/            # populated only AFTER setting repo private
```

The dedicated staging CI uses GitHub-hosted Ubuntu runners, Docker Engine, Icarus Verilog from the task's verifier image, and the **Harbor agent benchmark framework** installed through `uv tool install harbor`. It is distinct from the Harbor container registry.
