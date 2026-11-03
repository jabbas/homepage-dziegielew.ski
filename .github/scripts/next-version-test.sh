#!/usr/bin/env bash
# SPDX-License-Identifier: Apache-2.0
#
# Testy next-version.sh (krok „Ustal wersję" joba version w ci.yml). Hermetyczne:
# skrypt czyta wyłącznie env, nic nie pobiera. Uruchamiany bez argumentów:
#
#   bash .github/scripts/next-version-test.sh
#
# Kod wyjścia 0 = wszystkie testy PASS.
set -euo pipefail

here="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
script="$here/next-version.sh"

failures=0

fail() {
  echo "FAIL: $*" >&2
  failures=$((failures + 1))
}
pass() { echo "PASS: $*"; }

# expect_version <nazwa> <oczekiwana linia> <RELEASE_TYPE> <PREVIOUS> <NEW>
#
# Skrypt ma wypisać na stdout dokładnie jedną linię i zakończyć się kodem 0.
expect_version() {
  local name="$1" expected="$2" release_type="$3" previous="$4" new="$5"
  local output code=0
  output="$(RELEASE_TYPE="$release_type" PREVIOUS="$previous" NEW="$new" bash "$script" 2> /dev/null)" || code=$?
  if [[ "$code" != 0 ]]; then
    fail "$name: kod wyjścia $code zamiast 0"
    return
  fi
  if [[ "$output" != "$expected" ]]; then
    fail "$name: wypisano '$output' zamiast '$expected'"
    return
  fi
  pass "$name"
}

# expect_failure <nazwa> <RELEASE_TYPE> <PREVIOUS> <NEW>
#
# Skrypt ma zakończyć się kodem 1 i nic nie wypisać na stdout.
expect_failure() {
  local name="$1" release_type="$2" previous="$3" new="$4"
  local output code=0
  output="$(RELEASE_TYPE="$release_type" PREVIOUS="$previous" NEW="$new" bash "$script" 2> /dev/null)" || code=$?
  if [[ "$code" != 1 ]]; then
    fail "$name: kod wyjścia $code zamiast 1"
    return
  fi
  if [[ -n "$output" ]]; then
    fail "$name: na stdout trafiło '$output'"
    return
  fi
  pass "$name"
}

expect_version "no release" "version=" "" "" ""
expect_version "no release ignores previous" "version=" "major" "abc" ""
expect_version "minor passes through" "version=0.2.0" minor 0.1.0 0.2.0
expect_version "patch passes through" "version=0.2.1" patch 0.2.0 0.2.1
expect_version "breaking before 1.0 is minor" "version=0.4.0" major 0.3.2 1.0.0
expect_version "breaking from nothing" "version=0.1.0" major 0.0.0 1.0.0
expect_version "breaking after 1.0 is major" "version=2.0.0" major 1.2.3 2.0.0
expect_version "minor after 1.0 passes through" "version=1.3.0" minor 1.2.3 1.3.0
expect_failure "malformed previous" major abc 1.0.0
expect_failure "empty previous" major "" 1.0.0
expect_failure "previous with a prerelease suffix" major 0.1.0-rc.1 1.0.0

if [[ $failures != 0 ]]; then
  echo "$failures test(ów) nie przeszło" >&2
  exit 1
fi
echo "wszystkie testy next-version przeszły"
