#!/usr/bin/env bash
# Stage-only Harbor verification. Uses ONLY the candidate under this checkout.
set -Eeuo pipefail

TASK_REL="${1:?Usage: verify_harbor.sh tasks/<name>}"
if [[ ! "${TASK_REL}" =~ ^tasks/[A-Za-z0-9][A-Za-z0-9._-]*$ ]]; then
  echo "::error::Task must be a direct child of tasks/ (example tasks/pcie-reassembly)"
  exit 1
fi

ROOT="$(git rev-parse --show-toplevel)"
TASK="${ROOT}/${TASK_REL}"
if [[ ! -f "${TASK}/task.toml" ||
      ! -f "${TASK}/instruction.md" ||
      ! -f "${TASK}/solution/solve.sh" ||
      ! -f "${TASK}/tests/test.sh" ]]; then
  echo "::error::Complete task not staged in ${TASK_REL}"
  exit 1
fi

if ! command -v docker >/dev/null || ! docker info >/dev/null 2>&1; then
  echo "::error::Docker engine is not available"
  exit 1
fi
if ! command -v harbor >/dev/null; then
  echo "::error::Harbor evaluation CLI is not installed"
  exit 1
fi

# Keep verifier source/traces/results in ephemeral runner storage, not in the
# public GitHub status or uploads. The GitHub repo MUST be private before use.
JOBS_ROOT="$(mktemp -d "${RUNNER_TEMP:-/tmp}/harbor-stage-XXXXXXXX")"
trap 'rm -rf -- "${JOBS_ROOT}"' EXIT

REPORT="${GITHUB_STEP_SUMMARY:-/dev/null}"
{
  echo '### Staged Harbor evaluation (Docker)'
  echo ''
  echo "| Agent | Trial | Expected reward | Actual reward |"
  echo "|---|---:|---:|---:|"
} >> "${REPORT}"

run_trial() {
  local agent="$1" round="$2" expected="$3"
  local job="stage-${agent}-${round}"
  echo "::group::Harbor ${agent}, repeat ${round}"

  # This command builds and runs the staged task with Harbor's native Oracle
  # or Nop agent in Docker, including the separate verifier container.
  # A nonzero CLI status is an infrastructure failure, not a Nop success.
  if ! harbor run --path "${TASK}" --agent "${agent}" --env docker \
    --jobs-dir "${JOBS_ROOT}" --job-name "${job}" --n-concurrent 1; then
    echo "::error::Harbor invocation failed for ${agent} trial ${round}"
    return 1
  fi

  python3 - "${JOBS_ROOT}/${job}" "${agent}" "${round}" "${expected}" "${REPORT}" <<'PY'
import json
from pathlib import Path
import sys

job, agent, round_no, expected, report = sys.argv[1:]
job = Path(job)
results = []
for item in job.glob("*/result.json"):
    obj = json.loads(item.read_text())
    if obj.get("exception_info"):
        raise SystemExit(f"{agent} trial {round_no}: trial error {obj['exception_info'].get('exception_type', 'unknown')}")
    verifier = obj.get("verifier_result") or {}
    rewards = verifier.get("rewards") or {}
    if len(rewards) != 1:
        raise SystemExit(f"{agent} trial {round_no}: missing or ambiguous verifier reward")
    value = float(next(iter(rewards.values())))
    results.append(value)
if len(results) != 1:
    raise SystemExit(f"{agent} trial {round_no}: expected one trial result, found {len(results)}")
actual = results[0]
with open(report, "a") as f:
    f.write(f"| {agent} | {round_no} | {expected} | {actual:g} |\n")
print(f"Harbor {agent} repetition {round_no}: reward {actual:g} (expected {expected})")
if actual != float(expected):
    raise SystemExit(f"{agent} trial {round_no}: wrong reward")
PY
  echo "::endgroup::"
}

for round in 1 2; do
  run_trial oracle "${round}" 1
  run_trial nop "${round}" 0
done

echo 'Harbor Oracle 2/2 and Nop 2/2 checks passed.'
