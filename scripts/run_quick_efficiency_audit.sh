#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_ROOT="$(cd "${SCRIPT_DIR}/.." && pwd)"
OUT_FILE="${PROJECT_ROOT}/docs/quick_efficiency_audit_latest.txt"

cd "${PROJECT_ROOT}"

{
  echo "=== quick_efficiency_audit ==="
  date
  echo
  echo "--- bulk_correction_quality_and_resource ---"
  /usr/bin/time -l swift test --filter BulkWordCorrectionEvaluationTests/testBulkTop1000HebrewAndEnglishEvaluation 2>&1
  echo
  echo "--- stage_cost_benchmarks ---"
  /usr/bin/time -l swift test --filter EfficiencyAuditBenchmarksTests/testEfficiencyBenchmarks 2>&1
} | tee "${OUT_FILE}"

echo
echo "Wrote audit output to ${OUT_FILE}"
