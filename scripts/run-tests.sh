#!/usr/bin/env bash
# Compiles and runs the Foundation-only test harness used by Tests/run-tests.ps1.
# Both runners build the same sources and execute the same checks.
set -euo pipefail

root="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
swiftc_bin="${SWIFTC:-swiftc}"
work="$(mktemp -d "${TMPDIR:-/tmp}/velora-tests.XXXXXX")"
trap 'rm -rf "$work"' EXIT

if ! command -v "$swiftc_bin" >/dev/null 2>&1; then
    echo "error: swiftc was not found. Set SWIFTC to the compiler path." >&2
    exit 1
fi

sources=(
    "$root/App/Design/AccessibilityText.swift"
    "$root/App/Models/SpeedUnit.swift"
    "$root/App/Services/GPSStatus.swift"
    "$root/App/Services/Engine/MotionMath.swift"
    "$root/App/Services/Demo/DemoDrive.swift"
    "$root/App/Services/Demo/DemoSession.swift"
    "$root/App/Services/Engine/TripRecorder.swift"
    "$root/App/Services/Engine/SpeedEngine.swift"
    "$root/Tests/SpeedEngineTests.swift"
)

echo "Compiling ${#sources[@]} files with $("$swiftc_bin" --version | head -n 1)"

set +e
"$swiftc_bin" -o "$work/SpeedEngineTests" "${sources[@]}" >"$work/build.log" 2>&1
compile_status=$?
set -e

if [ "$compile_status" -ne 0 ]; then
    cat "$work/build.log" >&2
    echo "error: compilation failed (swiftc exit $compile_status)" >&2
    exit "$compile_status"
fi

set +e
output="$("$work/SpeedEngineTests" 2>&1)"
test_status=$?
set -e

printf '%s\n' "$output"

if [[ "$output" =~ ([0-9]+)\ checks,\ ([0-9]+)\ failures ]]; then
    checks="${BASH_REMATCH[1]}"
    failures="${BASH_REMATCH[2]}"
else
    echo "error: the test runner did not print a summary line" >&2
    exit 1
fi

echo
echo "Summary: $checks checks, $failures failures"

if [ "$test_status" -ne 0 ]; then
    echo "error: the test runner exited with code $test_status" >&2
    exit "$test_status"
fi

if [ "$failures" -ne 0 ]; then
    echo "error: $failures failing checks" >&2
    exit 1
fi
