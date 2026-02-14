#!/usr/bin/env bash
#
# Test runner for gh-review.nvim.
# Runs each test/test_*.lua file in headless Neovim, tallies results.

set -euo pipefail

cd "$(dirname "$0")/.."

total_pass=0
total_fail=0
failed_suites=()

for test_file in test/test_*.lua; do
  name=$(basename "$test_file" .lua)
  results_file="/tmp/gh_review_${name}.txt"
  rm -f "$results_file"

  printf "%-30s" "$name..."

  # Run test in headless Neovim
  if ! nvim --clean --headless --cmd "set rtp^=$(pwd)" -c "luafile $test_file" 2>/dev/null; then
    echo "CRASH"
    total_fail=$((total_fail + 1))
    failed_suites+=("$name (crashed)")
    continue
  fi

  if [[ ! -f "$results_file" ]]; then
    echo "NO OUTPUT"
    total_fail=$((total_fail + 1))
    failed_suites+=("$name (no output)")
    continue
  fi

  pass=0
  fail=0
  while IFS= read -r line; do
    if [[ "$line" == PASS:* ]]; then
      pass=$((pass + 1))
    elif [[ "$line" == FAIL:* ]]; then
      fail=$((fail + 1))
      echo ""
      echo "  $line"
    fi
  done < "$results_file"

  total_pass=$((total_pass + pass))
  total_fail=$((total_fail + fail))

  if [[ $fail -gt 0 ]]; then
    echo "${pass} passed, ${fail} FAILED"
    failed_suites+=("$name")
  else
    echo "${pass} passed"
  fi
done

echo ""
echo "=== Summary ==="
echo "Passed: $total_pass"
echo "Failed: $total_fail"

if [[ $total_fail -gt 0 ]]; then
  echo ""
  echo "Failed suites:"
  for s in "${failed_suites[@]}"; do
    echo "  - $s"
  done
  exit 1
fi

exit 0
