#!/usr/bin/env bash
set -euo pipefail
root=$(cd -- "$(dirname -- "$0")/.." && pwd)
for test in "$root"/tests/test_*.sh; do
    echo "-- ${test##*/}"
    bash "$test"
done
for test in "$root"/tests/test_*.py; do
    echo "-- ${test##*/}"
    python3 "$test"
done
