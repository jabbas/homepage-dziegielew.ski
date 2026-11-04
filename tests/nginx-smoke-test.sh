#!/usr/bin/env bash
# Test zachowania nginx w kontenerze: renderuje chart, wypakowuje obie
# ConfigMapy do katalogów tymczasowych, uruchamia obraz z values.yaml tak jak
# w klastrze (system plików tylko do odczytu, UID 101, bez uprawnień) i sprawdza
# odpowiedzi HTTP.
#
# Wymaga: helm, yq (mikefarah v4), curl, base64, sha256sum oraz podman albo
# docker (podman, jeśli jest w PATH). Uruchamiany bez argumentów:
#
#   bash tests/nginx-smoke-test.sh
#   bash tests/nginx-smoke-test.sh --serve   # kontener zostaje na 127.0.0.1:8080
#
# Kod wyjścia 0 = wszystkie testy PASS.
set -euo pipefail

cd "$(dirname "${BASH_SOURCE[0]}")/.."

serve=false
case "${1:-}" in
  "") ;;
  --serve) serve=true ;;
  *)
    echo "Użycie: $0 [--serve]" >&2
    exit 2
    ;;
esac

helm_binary="${HELM:-helm}"
chart=charts/homepage
release=homepage
namespace=homepage
canonical_host="$(yq '.canonicalHost' "$chart/values.yaml")"
redirect_host="$(yq '.redirectHosts[0]' "$chart/values.yaml")"

if command -v podman >/dev/null 2>&1; then
  engine=podman
else
  engine=docker
fi

work="$(mktemp -d)"
container_name="homepage-smoke-$$"
container_started=false

cleanup() {
  if [[ "$container_started" == true ]]; then
    # Sprzątanie nie może przesłonić wyniku testów: kontener mógł już zniknąć
    # (np. --serve przerwane Ctrl+C), a wtedy `rm` zwraca błąd.
    "$engine" rm --force "$container_name" >/dev/null 2>&1 || true
  fi
  rm -rf "$work"
}
trap cleanup EXIT

failures=0

pass() { echo "PASS: $*"; }

fail() {
  echo "FAIL: $*" >&2
  failures=$((failures + 1))
}

# expect_equal <nazwa> <oczekiwana wartość> <rzeczywista wartość>
expect_equal() {
  if [[ "$3" == "$2" ]]; then
    pass "$1"
    return
  fi
  fail "$1 (oczekiwano: $2, jest: $3)"
}

# expect_contains <nazwa> <fragment> <tekst>
expect_contains() {
  if [[ "$3" == *"$2"* ]]; then
    pass "$1"
    return
  fi
  fail "$1 (brak '$2' w: $3)"
}

# --- Przygotowanie: render chartu i wypakowanie ConfigMap --------------------

rendered="$work/rendered.yaml"
site_directory="$work/site"
conf_directory="$work/conf.d"
mkdir "$site_directory" "$conf_directory"

"$helm_binary" template "$release" "$chart" --namespace "$namespace" > "$rendered"

# extract_configmap <nazwa ConfigMapy> <katalog docelowy>: klucze z `data`
# jako tekst, klucze z `binaryData` przez base64 -d.
extract_configmap() {
  local name="$1" target="$2" key
  local configmap="select(.kind == \"ConfigMap\" and .metadata.name == \"$name\")"
  while IFS= read -r key; do
    [[ -n "$key" ]] || continue
    yq "$configmap | .data[\"$key\"]" "$rendered" > "$target/$key"
  done < <(yq "$configmap | .data // {} | keys | .[]" "$rendered")
  while IFS= read -r key; do
    [[ -n "$key" ]] || continue
    yq "$configmap | .binaryData[\"$key\"]" "$rendered" | base64 -d > "$target/$key"
  done < <(yq "$configmap | .binaryData // {} | keys | .[]" "$rendered")
}

extract_configmap "$release-site" "$site_directory"
extract_configmap "$release-nginx" "$conf_directory"

# Kontener działa jako UID 101, więc katalogi i pliki muszą być czytelne dla wszystkich.
chmod -R a+rX "$site_directory" "$conf_directory"
chmod a+rx "$work"

image="$(yq '.image.repository + ":" + .image.tag + "@" + .image.digest' "$chart/values.yaml")"
echo "silnik: $engine, obraz: $image"

# Tak jak w klastrze: system plików tylko do odczytu, /tmp jako tmpfs,
# UID/GID 101, bez uprawnień, oba katalogi z ConfigMap tylko do odczytu.
security_arguments=(
  --read-only
  --tmpfs /tmp
  --user 101:101
  --cap-drop ALL
  --security-opt no-new-privileges
)
volume_arguments=(
  --volume "$site_directory:/usr/share/nginx/html:ro"
  --volume "$conf_directory:/etc/nginx/conf.d:ro"
)

publish_argument="127.0.0.1::8080"
if [[ "$serve" == true ]]; then
  publish_argument="127.0.0.1:8080:8080"
fi

"$engine" run --detach --name "$container_name" \
  "${security_arguments[@]}" "${volume_arguments[@]}" \
  --publish "$publish_argument" "$image" >/dev/null
container_started=true

if [[ "$serve" == true ]]; then
  echo "Strona pod http://127.0.0.1:8080 (Ctrl+C kończy)"
  # INT/TERM kończą skrypt, a cleanup usuwa kontener. Logi w tle + wait, bo
  # bash wykonuje pułapkę dopiero po zakończeniu polecenia na pierwszym planie.
  trap 'exit 130' INT TERM
  "$engine" logs --follow "$container_name" &
  wait $!
  exit 0
fi

port="$("$engine" port "$container_name" 8080/tcp | head -n 1 | sed 's/.*://')"
base_url="http://127.0.0.1:$port"

# --- Narzędzia do żądań ------------------------------------------------------

headers_file="$work/headers.txt"
body_file="$work/body.bin"
status=""

# request <Host> <ścieżka>: wynik w $status, $headers_file i $body_file.
request() {
  # `|| true`: brak połączenia (kod curl ≠ 0) nie ma przerywać skryptu przez
  # `set -e`; curl i tak wypisuje wtedy 000, więc asercje na statusie padną
  # z czytelnym komunikatem FAIL.
  status="$(curl --silent --output "$body_file" --dump-header "$headers_file" \
    --write-out '%{http_code}' --header "Host: $1" "$base_url$2" || true)"
}

# header_values <nazwa nagłówka>: wartości wszystkich wystąpień, po jednej w wierszu.
header_values() {
  # `|| true`: grep zwraca 1, gdy nagłówka nie ma — to poprawny wynik (pusta
  # wartość), na którym polegają testy „brak nagłówka” (np. no hsts).
  { grep -i "^$1:" "$headers_file" || true; } | tr -d '\r' | sed -E "s/^[^:]*:[[:space:]]*//"
}

body() { cat "$body_file"; }

# --- Testy -------------------------------------------------------------------

# Start = nginx odpowiada na HTTP w ≤ 10 s (kod 000 oznacza brak połączenia).
# Czy /healthz zwraca 200, sprawdzają osobne testy sond poniżej, żeby błąd
# konfiguracji nie przysłonił pozostałych wyników.
ready=false
for _ in $(seq 1 20); do
  # `|| true`: dopóki nginx nie nasłuchuje, curl kończy się błędem — to
  # oczekiwane przy oczekiwaniu na start, kolejna iteracja ponawia próbę.
  if [[ "$(curl --silent --output /dev/null --write-out '%{http_code}' --header 'Host: probe' "$base_url/healthz" || true)" != 000 ]]; then
    ready=true
    break
  fi
  sleep 0.5
done
# Bez `|| true`: jeśli nie da się odczytać logów, test „starts read-only”
# nie może po cichu przejść (brak logów = brak sprawdzenia `emerg`), więc
# `set -e` przerywa skrypt.
container_logs="$("$engine" logs "$container_name" 2>&1)"
if [[ "$ready" == true && "$container_logs" != *emerg* ]]; then
  pass "starts read-only"
else
  fail "starts read-only (gotowy: $ready)"
  echo "$container_logs" >&2
  if [[ "$ready" != true ]]; then
    echo "$failures test(ów) nie przeszło" >&2
    exit 1
  fi
fi

request "$canonical_host" /
expect_equal "home status" 200 "$status"
expect_contains "home content type" "text/html" "$(header_values Content-Type)"

request "$canonical_host" /cv
expect_equal "cv status" 200 "$status"
expect_contains "cv content" "Professional experience" "$(body)"

request "$canonical_host" /cv/
expect_equal "cv trailing slash status" 301 "$status"
expect_equal "cv trailing slash location" "/cv" "$(header_values Location)"

request "$canonical_host" /cv.html
expect_equal "cv html status" 301 "$status"
expect_equal "cv html location" "/cv" "$(header_values Location)"

request "$canonical_host" /nie-ma
expect_equal "not found status" 404 "$status"
expect_contains "not found content" "Page not found" "$(body)"

request "$canonical_host" /404.html
expect_equal "404 page not directly" 404 "$status"

request "$redirect_host" "/x?y=1"
expect_equal "www redirect status" 301 "$status"
expect_equal "www redirect location" "https://$canonical_host/x?y=1" "$(header_values Location)"

request jabbas.eu "/cv?x=1"
expect_equal "jabbas.eu redirect status" 301 "$status"
expect_equal "jabbas.eu redirect location" "https://$canonical_host/cv?x=1" "$(header_values Location)"

request www.jabbas.eu /
expect_equal "www.jabbas.eu redirect status" 301 "$status"
expect_equal "www.jabbas.eu redirect location" "https://$canonical_host/" "$(header_values Location)"

request 10.0.0.1 /healthz
expect_equal "probe by IP" 200 "$status"

request "$canonical_host" /healthz
expect_equal "probe on canonical" 200 "$status"

request "$canonical_host" /robots.txt
expect_equal "robots status" 200 "$status"
robots_content_type="$(header_values Content-Type)"
if [[ "$robots_content_type" == text/plain* ]]; then
  pass "robots content type"
else
  fail "robots content type (jest: $robots_content_type)"
fi

request "$canonical_host" /sitemap.xml
expect_equal "sitemap status" 200 "$status"
sitemap_content_type="$(header_values Content-Type)"
if [[ "$sitemap_content_type" == text/xml* || "$sitemap_content_type" == application/xml* ]]; then
  pass "sitemap content type"
else
  fail "sitemap content type (jest: $sitemap_content_type)"
fi

request jabbas.eu /robots.txt
expect_equal "jabbas.eu robots status" 301 "$status"
expect_equal "jabbas.eu robots location" "https://$canonical_host/robots.txt" "$(header_values Location)"

photo_expected="$(sha256sum "$chart/files/site/photo.jpg" | cut -d' ' -f1)"
request "$canonical_host" /photo.jpg
expect_equal "photo status" 200 "$status"
expect_equal "photo content type" "image/jpeg" "$(header_values Content-Type)"
expect_equal "photo checksum" "$photo_expected" "$(sha256sum < "$body_file" | cut -d' ' -f1)"

# Nagłówki bezpieczeństwa muszą być na każdej odpowiedzi: 200, 301 i 404
# (add_header w bloku location kasuje dziedziczenie z poziomu server).
expected_content_security_policy="default-src 'none'; style-src 'self'; img-src 'self'; base-uri 'none'; form-action 'none'; frame-ancestors 'none'"
expected_permissions_policy="camera=(), microphone=(), geolocation=(), payment=(), usb=()"
# check_security_headers <etykieta odpowiedzi>: wynik ostatniego request.
check_security_headers() {
  expect_equal "security headers: Content-Security-Policy on $1" "$expected_content_security_policy" "$(header_values Content-Security-Policy)"
  expect_equal "security headers: X-Content-Type-Options on $1" "nosniff" "$(header_values X-Content-Type-Options)"
  expect_equal "security headers: Referrer-Policy on $1" "strict-origin-when-cross-origin" "$(header_values Referrer-Policy)"
  expect_equal "security headers: Permissions-Policy on $1" "$expected_permissions_policy" "$(header_values Permissions-Policy)"
}

request "$canonical_host" /
check_security_headers "200 /"
request "$canonical_host" /cv/
check_security_headers "301 /cv/"
request "$canonical_host" /nie-ma
check_security_headers "404 /nie-ma"
request "$redirect_host" /
check_security_headers "301 www /"
request jabbas.eu /
check_security_headers "301 jabbas.eu /"

request "$canonical_host" /
expect_equal "cache home" "max-age=3600" "$(header_values Cache-Control)"
request "$canonical_host" /photo.jpg
expect_equal "cache photo" "max-age=3600" "$(header_values Cache-Control)"

request "$canonical_host" /
expect_equal "no version leak" "nginx" "$(header_values Server)"
expect_equal "no hsts" "" "$(header_values Strict-Transport-Security)"

if [[ "$failures" -gt 0 ]]; then
  echo "$failures test(ów) nie przeszło" >&2
  exit 1
fi
echo "Wszystkie testy przeszły"
