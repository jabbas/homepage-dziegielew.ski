#!/usr/bin/env bash
# SPDX-License-Identifier: Apache-2.0
#
# Instaluje przypięte binaria na runnerze GitHub Actions linux/amd64:
#
#   bash .github/scripts/install-tools.sh yq
#   bash .github/scripts/install-tools.sh kubeconform actionlint
#
# Wzorzec z install-yq.sh i install-release-tools.sh z jabbas/secretspec-operator,
# w jednym pliku zamiast trzech kopii. Używany w ci.yml (testy: yq, kubeconform,
# actionlint) i w release.yml (helm-index: yq — skrypty indeksu parsują i
# przepisują wspólny indeks Helma, więc yq z obrazu runnera nie jest tym, któremu
# ufamy).
#
# Każde archiwum jest weryfikowane przez `sha256sum --check --strict` z SHA-256
# wziętym z pliku sum tego samego wydania upstreamu:
#   yq          plik `checksums`, kolumna SHA-256 (kolejność w `checksums_hashes_order`)
#   kubeconform plik `CHECKSUMS`
#   actionlint  plik `actionlint_<wersja>_checksums.txt`
# Wersję i sumę podbijamy razem. Renovate proponuje wersję (komentarze
# `# renovate:` czyta renovate.json), ale nie policzy sumy: podbicie samej wersji
# kończy się błędem weryfikacji, a komunikat wskazuje zmienną do poprawy.
# Skrypt tylko pobiera, weryfikuje i rozpakowuje; niczego nie uruchamia poza
# `--version`/`-version` na końcu. Działa wyłącznie na runnerze (RUNNER_TEMP,
# GITHUB_PATH); lokalnie wystarczy `shellcheck`.
set -euo pipefail

# renovate: datasource=github-releases depName=mikefarah/yq
YQ_VERSION=v4.54.1
YQ_SHA256=e68a456f90c577af3fe4960184b3a3cf5c461e0348407c10f107da3a5fec8972

# renovate: datasource=github-releases depName=yannh/kubeconform
KUBECONFORM_VERSION=v0.8.0
KUBECONFORM_SHA256=9bc2bffbf71f261128533edaf912153948b7ff238f9a531ae6d34466ec287883

# renovate: datasource=github-releases depName=rhysd/actionlint
ACTIONLINT_VERSION=v1.7.12
ACTIONLINT_SHA256=8aca8db96f1b94770f1b0d72b6dddcb1ebb8123cb3712530b08cc387b349a3d8

if [[ $# -eq 0 ]]; then
  echo "użycie: install-tools.sh <yq|kubeconform|actionlint>..." >&2
  exit 1
fi

# Nieznane narzędzie sprawdzamy przed pobraniem czegokolwiek.
for tool in "$@"; do
  case "$tool" in
    yq | kubeconform | actionlint) ;;
    *)
      printf '::error::install-tools.sh nie zna narzędzia %q (yq, kubeconform, actionlint)\n' "$tool" >&2
      exit 1
      ;;
  esac
done

temp="${RUNNER_TEMP:?RUNNER_TEMP is not set (this script is for Actions runners)}"
github_path="${GITHUB_PATH:?GITHUB_PATH is not set (this script is for Actions runners)}"
dir="$temp/tools/bin"
mkdir -p "$dir"

for tool in "$@"; do
  case "$tool" in
    yq)
      prefix=YQ
      version="$YQ_VERSION"
      checksum="$YQ_SHA256"
      archive="yq_linux_amd64.tar.gz"
      url="https://github.com/mikefarah/yq/releases/download/${version}/${archive}"
      member="./yq_linux_amd64"
      ;;
    kubeconform)
      prefix=KUBECONFORM
      version="$KUBECONFORM_VERSION"
      checksum="$KUBECONFORM_SHA256"
      archive="kubeconform-linux-amd64.tar.gz"
      url="https://github.com/yannh/kubeconform/releases/download/${version}/${archive}"
      member="kubeconform"
      ;;
    actionlint)
      prefix=ACTIONLINT
      version="$ACTIONLINT_VERSION"
      checksum="$ACTIONLINT_SHA256"
      archive="actionlint_${version#v}_linux_amd64.tar.gz"
      url="https://github.com/rhysd/actionlint/releases/download/${version}/${archive}"
      member="actionlint"
      ;;
  esac

  curl -fsSL --retry 3 -o "$temp/$archive" "$url"
  if ! echo "$checksum  $temp/$archive" | sha256sum --check --strict -; then
    echo "::error::$tool $version ($archive) nie zgadza się z przypiętą sumą; popraw razem ${prefix}_SHA256 i ${prefix}_VERSION w .github/scripts/install-tools.sh, według pliku sum tego wydania upstreamu" >&2
    exit 1
  fi
  tar -xzf "$temp/$archive" -C "$dir" "$member"
  # Archiwum yq zawiera plik yq_linux_amd64; reszta narzędzi ma gotową nazwę.
  if [[ "$tool" == yq ]]; then
    mv "$dir/yq_linux_amd64" "$dir/yq"
  fi
done

echo "$dir" >> "$github_path"

# Szybki dowód, że binaria się uruchamiają (a nie tylko zgadza się suma).
for tool in "$@"; do
  case "$tool" in
    yq) "$dir/yq" --version ;;
    kubeconform) "$dir/kubeconform" -v ;;
    actionlint) "$dir/actionlint" -version ;;
  esac
done
