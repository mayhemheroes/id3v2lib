#!/usr/bin/env bash
#
# mayhem/test.sh — RUN id3v2lib's own functional suite (built by build.sh) and emit CTRF.
# The suite (test/main_test) is a behavioral oracle: it parses fixture mp3s and assert()s exact
# parsed values (artist/album/title/genre/comment/... and edited-file round-trips), then prints a
# "<SUITE>: OK" marker AFTER its asserts hold. Built Debug so asserts are live.
#
# We assert on the OUTPUT MARKERS, not just exit status: a PATCH that neuters the program to exit(0)
# (functional collapse) produces rc=0 but emits NO markers, and a wrong parsed value aborts the suite
# before its marker prints. Requiring all 5 markers (+ rc 0) makes the oracle non-reward-hackable.
set -uo pipefail
[ -n "${SOURCE_DATE_EPOCH:-}" ] || unset SOURCE_DATE_EPOCH
cd "$SRC"

emit_ctrf() {
  local tool="$1" passed="$2" failed="$3" skipped="${4:-0}" pending="${5:-0}" other="${6:-0}"
  local tests=$(( passed + failed + skipped + pending + other ))
  cat > "${CTRF_REPORT:-$SRC/ctrf-report.json}" <<JSON
{
  "results": {
    "tool": { "name": "$tool" },
    "summary": {
      "tests": $tests,
      "passed": $passed,
      "failed": $failed,
      "pending": $pending,
      "skipped": $skipped,
      "other": $other
    }
  }
}
JSON
  printf 'CTRF {"results":{"tool":{"name":"%s"},"summary":{"tests":%d,"passed":%d,"failed":%d,"pending":%d,"skipped":%d,"other":%d}}}\n' \
    "$tool" "$tests" "$passed" "$failed" "$pending" "$skipped" "$other"
  [ "$failed" -eq 0 ]
}

# The 5 behavioral markers the suite prints, one per assert-guarded sub-suite.
EXPECTED=5
RUNDIR="$SRC/build-tests/test"
if [ ! -x "$RUNDIR/main_test" ]; then
  echo "main_test not found in $RUNDIR — build.sh did not build the suite" >&2
  emit_ctrf "id3v2lib" 0 "$EXPECTED"
  exit 1
fi

# main_test reads/writes fixtures relative to cwd (extra/file.mp3, extra/file_edited.mp3) which CMake
# copies next to the binary in build-tests/test/.
cd "$RUNDIR"
out="$(./main_test 2>&1)"; rc=$?
printf '%s\n' "$out"
passed="$(printf '%s\n' "$out" | grep -c ': OK' || true)"
if [ "$rc" -eq 0 ] && [ "$passed" -eq "$EXPECTED" ]; then
  emit_ctrf "id3v2lib-main_test" "$EXPECTED" 0
else
  failed=$(( EXPECTED - passed )); [ "$failed" -lt 1 ] && failed=1
  emit_ctrf "id3v2lib-main_test" "$passed" "$failed"
fi
