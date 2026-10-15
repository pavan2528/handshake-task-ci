# Handshake Task CI

An independent GitHub Actions runner for **pavan2528/hardware-rtl-eded247b-089251a8d3fb**. This repository is not a fork, and the workflow **never writes to the source repository**.

## What is tested

- Build the actual agent Docker image and the separate verifier Docker image.
- Check agent-image isolation: only the task starter RTL appears inside /app.
- Run the submitted reference/Oracle RTL **twice** under the separate verifier and require reward **1** both times.
- Run the inert starter/Nop RTL **twice** and require reward **0** both times.
- Verify the task's TOML metadata and the trace generator are in the source checkout.
- Fail the GitHub Actions job on a Docker build failure, unexpected reward, or a missing expected artifact.

These checks exercise real Icarus Verilog and the task's existing cycle-by-cycle verifier. They are **not** the official Handshake artificiality, implementation-rubric, or pass@2/pass@5 difficulty trials. Those require the upstream Handshake evaluation system and its agent infrastructure.

## One-time setup: private source access

The source repository is private, while this standalone CI repository is public. A workflow token scoped to this CI repository cannot read the private source.

1. In GitHub, create a **fine-grained personal access token** whose repository access is limited to `pavan2528/hardware-rtl-eded247b-089251a8d3fb`. Grant only **Contents: Read-only** (metadata read is implicit).
2. In **this CI repository**, open **Settings → Secrets and variables → Actions → New repository secret**.
3. Name the secret `SOURCE_REPO_TOKEN` and paste the token.
4. Open **Actions → PCIe RTL Docker Validation → Run workflow**. Optionally enter a commit SHA or branch for the source ref (default `submission`).

The secret is only supplied to the private-source checkout step, with `persist-credentials: false`. Do not paste tokens into issues, actions logs, or workflow dispatch inputs.

## When it runs

- Manually using **Run workflow**; choose the source branch or exact SHA.
- Automatically every six hours against the latest `submission` branch.
- Whenever the standalone CI workflow or its scripts change on `main`.
- Via `repository_dispatch` event `validate-rtl`, if you configure an external source-repository trigger later.

**No private RTL, reference solution, test fixtures, expected traces, or raw verification logs are uploaded as artifacts.** Only the checked source SHA and Oracle/Nop pass/fail results are reported in the Actions summary. Keep the CI repo private if you need to preserve even those results.

## Security and limitations

This repository is public. GitHub Actions workflow definitions and summaries are visible publicly. The task RTL and hidden tests are checked out and executed only on the ephemeral GitHub-hosted runner. The verifier runs with `--network none`, and the existing task verifier drops compiler and simulator subprocesses to an unprivileged user.

The workflow does not automatically receive the official upstream evaluation results and cannot prove that frontier agents fail pass@2 or pass@5. The CI job remains the local reproducible preflight gate; the official Handshake review is the difficulty gate.

## Source task

`tasks/pcie-reassembly` in the private source repository; source branch `submission`.
