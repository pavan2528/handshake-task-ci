#!/usr/bin/env bash
# Standalone, read-only Docker preflight for the private PCIe task checkout.
set -Eeuo pipefail

SOURCE_CHECKOUT="${1:?Usage: verify_pcie.sh <checked-out-source-directory>}"
TASK="${SOURCE_CHECKOUT}/tasks/pcie-reassembly"
REPORT="${GITHUB_STEP_SUMMARY:-/dev/null}"
AGENT_IMAGE="handshake-pcie-agent-ci:${GITHUB_RUN_ID:-local}"
VERIFIER_IMAGE="handshake-pcie-verifier-ci:${GITHUB_RUN_ID:-local}"

for path in \
  "${TASK}/task.toml" \
  "${TASK}/environment/Dockerfile" \
  "${TASK}/environment/app/rtl/pcie_reassembly.sv" \
  "${TASK}/tests/Dockerfile" \
  "${TASK}/tests/generate_traces.py" \
  "${TASK}/tests/trace_model.py" \
  "${TASK}/tests/tb.sv" \
  "${TASK}/tests/test_outputs.py" \
  "${TASK}/tests/test.sh" \
  "${TASK}/solution/pcie_reassembly.sv"; do
  if [[ ! -f "${path}" ]]; then
    echo "::error::Missing required task file: ${path#"${SOURCE_CHECKOUT}/"}"
    exit 1
  fi
done

python3 - "${TASK}/task.toml" <<'PY'
import pathlib, sys, tomllib
doc = tomllib.loads(pathlib.Path(sys.argv[1]).read_text())
assert "/app/rtl/pcie_reassembly.sv" in doc["artifacts"]
assert doc["verifier"]["environment_mode"] == "separate"
assert doc["task"]["name"] == "insight/pcie-reassembly"
print("Task schema and isolated verifier configuration: OK")
PY

trap 'docker image rm -f "${AGENT_IMAGE}" "${VERIFIER_IMAGE}" >/dev/null 2>&1 || true' EXIT

echo "::group::Build separate agent image"
docker build --quiet --tag "${AGENT_IMAGE}" "${TASK}/environment"
echo "::endgroup::"

echo "::group::Build isolated verifier and generate three deterministic traces"
docker build --quiet --tag "${VERIFIER_IMAGE}" "${TASK}/tests"
echo "::endgroup::"

echo "::group::Check agent image for reference/test leakage"
files="$(docker run --rm --network none --entrypoint /bin/sh "${AGENT_IMAGE}" -c 'find /app -type f | sort')"
if [[ "${files}" != "/app/rtl/pcie_reassembly.sv" ]]; then
  echo "::error::Unexpected files appear in the agent's /app image; isolation check failed."
  exit 1
fi
image_digest="$(docker run --rm --network none --entrypoint cat "${AGENT_IMAGE}" /app/rtl/pcie_reassembly.sv | sha256sum | cut -d' ' -f1)"
starter_digest="$(sha256sum "${TASK}/environment/app/rtl/pcie_reassembly.sv" | cut -d' ' -f1)"
if [[ "${image_digest}" != "${starter_digest}" ]]; then
  echo "::error::Agent image RTL does not match the starter; isolation check failed."
  exit 1
fi
echo "Agent image isolation: OK"
echo "::endgroup::"

{
  echo "### PCIe RTL Docker preflight"
  echo ""
  echo "Agent and verifier images built; agent contains only the starter RTL."
  echo ""
  echo "| Gate | Repetition | Expected reward | Actual reward |"
  echo "|---|---:|---:|---:|"
} >> "${REPORT}"

run_case() {
  local label="$1" round="$2" rtl="$3" expected="$4"
  local logs
  logs="$(mktemp -d "${RUNNER_TEMP:-/tmp}/pcie-ci-${label}-${round}-XXXXXX")"
  local actual="missing"
  local exit_code=0
  echo "::group::${label} repetition ${round}"
  # Never upload the private test traces, source, or raw output logs from this
  # public repo. The task's test.sh writes its reward under the bind-mounted
  # logs directory and intentionally returns zero even on a failing test.
  timeout --signal=TERM --kill-after=15s 420s \
    docker run --rm --network none --cpus 1 --memory 2048m --pids-limit 256 \
      --mount "type=bind,src=${rtl},dst=/app/rtl/pcie_reassembly.sv,readonly" \
      --mount "type=bind,src=${logs},dst=/logs/verifier" \
      --entrypoint /bin/bash "${VERIFIER_IMAGE}" /tests/test.sh || exit_code="$?"
  if [[ -r "${logs}/reward.txt" ]]; then
    actual="$(tr -d '\n\r\t ' < "${logs}/reward.txt")"
  fi
  echo "${label} trial ${round}: expected ${expected}, actual ${actual}, container exit ${exit_code}"
  printf '| %s | %s | %s | %s |\n' "${label}" "${round}" "${expected}" "${actual}" >> "${REPORT}"
  echo "::endgroup::"
  # Remove private verifier output after extracting the single reward bit.
  rm -rf -- "${logs}"
  if [[ "${exit_code}" != "0" || "${actual}" != "${expected}" ]]; then
    echo "::error::${label} trial ${round} did not produce its required reward."
    return 1
  fi
}

# Check twice, independently: this recompiles and reruns the hidden verifier
# for each input RTL, guarding against accidental one-off successes.
for round in 1 2; do
  run_case Oracle "${round}" "${TASK}/solution/pcie_reassembly.sv" 1
  run_case Nop "${round}" "${TASK}/environment/app/rtl/pcie_reassembly.sv" 0
done

{
  echo ""
  echo "**Result:** Oracle 2/2 passed; Nop 2/2 correctly failed; image isolation passed."
  echo ""
  echo "The official artificiality, rubric and pass@2/pass@5 difficulty evaluations are separate upstream gates."
} >> "${REPORT}"

echo "All standalone Docker preflight gates PASSED."
