#!/usr/bin/env bash
# SPDX-License-Identifier: Apache-2.0
#
# Krok „Ustal wersję" joba version w ci.yml: z wyjść github-tag-action (tryb
# dry_run) wylicza wersję do wydania. Logika z ~/Projects/homebudget/.github/
# workflows/ci.yml, z jedną różnicą (spec 8.3): zamiana zmiany łamiącej na
# następny minor działa tylko przed 1.0.0, czyli gdy major PREVIOUS to 0. Od
# 1.0.0 zmiana łamiąca podbija major (semver.org).
#
# Wejście wyłącznie przez zmienne środowiskowe (żeby skrypt dało się uruchomić
# lokalnie i przetestować):
#   RELEASE_TYPE  release_type z akcji (major, minor, patch)
#   PREVIOUS      previous_version z akcji
#   NEW           new_version z akcji; pusty = żaden commit nie wydaje
#
# Na stdout trafia dokładnie jedna linia: `version=<X.Y.Z>` albo `version=`
# (brak wydania); w workflow: `bash .github/scripts/next-version.sh >> "$GITHUB_OUTPUT"`.
# Komunikaty idą na stderr. Kod 1, gdy PREVIOUS jest potrzebny i niepoprawny.
set -euo pipefail

release_type="${RELEASE_TYPE:-}"
previous="${PREVIOUS:-}"
new="${NEW:-}"

if [[ -z "$new" ]]; then
  echo "Brak commitów wydających (feat/fix/perf/refactor) — bez wydania." >&2
  echo "version="
  exit 0
fi

if [[ "$release_type" != major ]]; then
  echo "version=$new"
  exit 0
fi

# PREVIOUS jest potrzebny dopiero tutaj: decyduje, czy major to jeszcze 0.
semver_pattern='^([0-9]+)\.([0-9]+)\.[0-9]+$'
if [[ ! "$previous" =~ $semver_pattern ]]; then
  printf 'Nieoczekiwana poprzednia wersja: %q\n' "$previous" >&2
  exit 1
fi
previous_major="${BASH_REMATCH[1]}"
previous_minor="${BASH_REMATCH[2]}"

# 10# wymusza zapis dziesiętny (bez ósemkowej interpretacji zer wiodących).
if [[ "$((10#$previous_major))" != 0 ]]; then
  echo "version=$new"
  exit 0
fi

version="0.$((10#$previous_minor + 1)).0"
echo "Zmiana łamiąca przed 1.0.0 → minor; 1.0.0 tylko ręcznym tagiem ($previous → $version zamiast $new)." >&2
echo "version=$version"
