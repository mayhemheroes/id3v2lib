#!/usr/bin/env bash
#
# mayhem/build.sh — build the id3v2lib fuzz harness (+ standalone reproducer) and the test suite.
# id3v2lib is a self-contained C library (no third-party deps), so the build is fully offline and
# idempotent: re-running on an already-built tree just re-configures the existing cmake dirs.
set -euo pipefail

# clang rejects an empty SOURCE_DATE_EPOCH — unset rather than pass "".
[ -n "${SOURCE_DATE_EPOCH:-}" ] || unset SOURCE_DATE_EPOCH

# Build contract from the base image (override-able). SANITIZER_FLAGS uses `=` so an explicit empty
# value (the sanitizer off-switch) is honored; DEBUG_FLAGS carries DWARF<4 independently.
: "${SANITIZER_FLAGS=-fsanitize=address,undefined -fno-sanitize-recover=all -fno-omit-frame-pointer}"
: "${DEBUG_FLAGS:=-g -gdwarf-3}"
: "${CC:=clang}" ; : "${CXX:=clang++}" ; : "${LIB_FUZZING_ENGINE:=-fsanitize=fuzzer}"
: "${STANDALONE_FUZZ_MAIN:=/opt/mayhem/StandaloneFuzzTargetMain.c}"
# SanitizerCoverage for the LIBRARY so libFuzzer is coverage-guided on the parser itself (ASan/UBSan
# alone add NO coverage). -fsanitize=fuzzer-no-link instruments without pulling in the libFuzzer main,
# so the static lib links into both the fuzzer (with the engine) and the standalone reproducer (without).
: "${FUZZ_COV:=-fsanitize=fuzzer-no-link}"
: "${MAYHEM_JOBS:=$(nproc)}"
: "${COVERAGE_FLAGS=}"
export SANITIZER_FLAGS DEBUG_FLAGS CC CXX LIB_FUZZING_ENGINE STANDALONE_FUZZ_MAIN FUZZ_COV MAYHEM_JOBS COVERAGE_FLAGS

cd "$SRC"

# 1) Build libid3v2lib.a INSTRUMENTED (ASan+UBSan + DWARF<4) so the fuzzed library code itself is
#    sanitized. Static archive → the harness links one self-contained binary. $DEBUG_FLAGS comes
#    AFTER $SANITIZER_FLAGS so its -gdwarf-3 wins over the base's plain -g (which would be DWARF-5).
cmake -B build-fuzz \
      -DCMAKE_C_COMPILER="$CC" -DCMAKE_CXX_COMPILER="$CXX" \
      -DBUILD_SHARED_LIBS=OFF \
      -DCMAKE_C_FLAGS="$SANITIZER_FLAGS $FUZZ_COV $DEBUG_FLAGS" \
      -DCMAKE_CXX_FLAGS="$SANITIZER_FLAGS $FUZZ_COV $DEBUG_FLAGS"
cmake --build build-fuzz -j"$MAYHEM_JOBS" --target id3v2lib
LIB="$SRC/build-fuzz/src/libid3v2lib.a"

# 2) Compile the harness TWICE: once with the libFuzzer engine (the fuzz binary), once with the
#    standalone run-once driver (a non-fuzzer reproducer). Both are C → no linkage mangling concerns.
$CC $SANITIZER_FLAGS $DEBUG_FLAGS $LIB_FUZZING_ENGINE \
    "$SRC/mayhem/id3v2lib-fuzz.c" -I"$SRC/include" "$LIB" \
    -o /mayhem/id3v2lib-fuzz

$CC $SANITIZER_FLAGS $DEBUG_FLAGS \
    "$STANDALONE_FUZZ_MAIN" "$SRC/mayhem/id3v2lib-fuzz.c" -I"$SRC/include" "$LIB" \
    -o /mayhem/id3v2lib-fuzz-standalone

# 3) Build the test suite with NORMAL flags (clean, independent of the sanitized build) so test.sh
#    only RUNS it. Build type Debug — NOT Release: the suite asserts via assert(), and Release defines
#    NDEBUG which compiles every assert() out, silently turning the functional oracle into a no-op.
cmake -B build-tests \
      -DCMAKE_BUILD_TYPE=Debug \
      -DCMAKE_C_FLAGS="$COVERAGE_FLAGS" -DCMAKE_CXX_FLAGS="$COVERAGE_FLAGS"
cmake --build build-tests -j"$MAYHEM_JOBS" --target main_test
