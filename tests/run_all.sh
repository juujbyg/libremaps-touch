#!/bin/sh
# Run every offline check in tests/ (no network, no phone). From the maps folder: sh tests/run_all.sh
# A suite fails if it exits non-zero or prints a FAIL line (some only print them).
cd "$(dirname "$0")/.." || exit 1
fail=0
for t in fuelprices_check official_alerts_check placeinfo_check netlimit_check alerts_security hostile_feeds; do
    out=$(python3 -I "tests/$t.py" 2>&1)
    code=$?
    printf '%-24s %s\n' "$t" "$(printf '%s\n' "$out" | tail -1)"
    if [ $code -ne 0 ] || printf '%s\n' "$out" | grep -qE "^FAIL|Traceback"; then
        fail=1
        printf '%s\n' "$out" | grep -E "^FAIL|Error" | head -5
    fi
done
[ $fail -eq 0 ] && echo "ALL PASSED" || echo "SOME FAILED"
exit $fail
