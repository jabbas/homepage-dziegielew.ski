#!/usr/bin/env bash
# Test treści strony: pliki w charts/homepage/files/site/ (HTML i CSS).
# Sprawdza zasady ze spec 2 i 7: zero zasobów zewnętrznych, zero kodu
# w HTML (wymóg CSP), brak danych prywatnych, poprawione literówki,
# wymagane znaczniki <head>, treść wizytówki i CV, ciemny motyw oraz
# jasny wydruk.
#
# Wymaga: bash, grep, awk. Uruchamiany bez argumentów:
#
#   bash tests/content-test.sh
#
# Kod wyjścia 0 = wszystkie testy PASS.
#
# Uwaga: test NIE zawiera prywatnych wartości (adres, data urodzenia,
# numer telefonu) — repozytorium jest publiczne. Brak danych prywatnych
# sprawdzamy po etykietach ("Date of birth", "Phone:"), nigdy po wartościach.
set -euo pipefail

cd "$(dirname "${BASH_SOURCE[0]}")/.."

site=charts/homepage/files/site
stylesheet="$site/style.css"
html_files=("$site"/*.html)
head_files=("$site/index.html" "$site/cv.html")

failures=0

pass() { echo "PASS: $*"; }

fail() {
  echo "FAIL: $*" >&2
  failures=$((failures + 1))
}

# flat <plik>: zawartość pliku w jednej linii (znaczniki rozbite na wiele
# linii nadal pasują do wyrażeń regularnych). Wynik przekazujemy do grep
# przez here-string, nie przez potok: `grep -q` kończy się po pierwszym
# dopasowaniu, a przy `pipefail` SIGPIPE w `tr` (kod 141) odwróciłby wynik.
flat() {
  tr '\n' ' ' <"$1"
}

# expect_absent <nazwa> <wyrażenie ERE> <plik...>: wyrażenie nie może pasować
# do żadnego z plików (każdy plik sprawdzany jako jedna linia).
expect_absent() {
  local name="$1" pattern="$2"
  shift 2
  local file bad=0
  for file in "$@"; do
    if [[ ! -f "$file" ]]; then
      fail "$name ($file: brak pliku)"
      bad=1
    elif grep -Eqi -- "$pattern" <<<"$(flat "$file")"; then
      fail "$name ($file pasuje do: $pattern)"
      bad=1
    fi
  done
  if [[ $bad -eq 0 ]]; then
    pass "$name"
  fi
}

# expect_present <nazwa> <wyrażenie ERE> <plik...>: wyrażenie musi pasować
# do każdego z plików.
expect_present() {
  local name="$1" pattern="$2"
  shift 2
  local file bad=0
  for file in "$@"; do
    if [[ ! -f "$file" ]]; then
      fail "$name ($file: brak pliku)"
      bad=1
    elif ! grep -Eq -- "$pattern" <<<"$(flat "$file")"; then
      fail "$name ($file nie pasuje do: $pattern)"
      bad=1
    fi
  done
  if [[ $bad -eq 0 ]]; then
    pass "$name"
  fi
}

# expect_contains_text <nazwa> <dosłowny tekst> <plik>: tekst dosłowny (bez regex).
expect_contains_text() {
  local name="$1" text="$2" file="$3"
  if [[ ! -f "$file" ]]; then
    fail "$name ($file: brak pliku)"
  elif grep -Fq -- "$text" <<<"$(flat "$file")"; then
    pass "$name"
  else
    fail "$name ($file nie zawiera: $text)"
  fi
}

# print_block: pierwszy blok @media print z arkusza stylów (liczy nawiasy
# klamrowe, więc działa też z zagnieżdżonymi regułami).
print_block() {
  awk '
    /^@media print/ { inside = 1 }
    inside {
      print
      opened += gsub(/\{/, "{")
      closed += gsub(/\}/, "}")
      if (opened > 0 && opened == closed) exit
    }
  ' "$stylesheet"
}

all_files=("${html_files[@]}" "$stylesheet")

# 1. Zasoby zewnętrzne: src=, <link href>, url(, @import wskazujące na http:,
# https: lub // (<a href> jest dozwolone). @import odrzucamy w całości — strona
# go nie potrzebuje. Dodatkowo odrzucamy data: (CSP: img-src 'self').
expect_absent "no external resources" \
  'src="?(https?:)?//|<link[^>]*href="?(https?:)?//|url\(\s*["'\'']?(https?:)?//|@import' \
  "${all_files[@]}"
expect_absent "no data uris" \
  'src="?data:|url\(\s*["'\'']?data:' \
  "${all_files[@]}"

# 2. Kod i style w HTML (CSP: style-src 'self', default-src 'none').
expect_absent "no inline code or style" '<script|<style| style=' "${html_files[@]}"

# 3. Dane prywatne (spec 2, anty-cele): link tel: w żadnym pliku,
# w HTML brak etykiet sekcji prywatnych i klauzuli RODO.
expect_absent "no phone link" 'tel:' "${all_files[@]}"
expect_absent "no private sections" \
  'Date of birth|Phone:|Wyrażam zgodę|Online version' \
  "${html_files[@]}"

# 4. Literówki ze spec 7.4 poprawione, brak osieroconych znaczników <i>.
expect_absent "typos fixed" 'technican|Labolatory|Spectometry' "$site/cv.html"
if [[ -f "$site/cv.html" ]]; then
  # grep bez dopasowań kończy się kodem 1, a pipefail przerwałby test.
  opening=$({ grep -o '<i[ >]' "$site/cv.html" || true; } | wc -l)
  closing=$({ grep -o '</i>' "$site/cv.html" || true; } | wc -l)
  if [[ "$opening" -eq "$closing" ]]; then
    pass "italic tags balanced"
  else
    fail "italic tags balanced (otwarte: $opening, zamknięte: $closing)"
  fi
else
  fail "italic tags balanced ($site/cv.html: brak pliku)"
fi

# 4b. Lata w osi czasu: gdy początek == koniec, jeden rok ("2024", nie "2024 – 2024").
expect_absent "single year not repeated" \
  '<dt>([0-9]{4})[[:space:]]*[–—-][[:space:]]*\1</dt>' "$site/cv.html"

# 4c. Martwe lub przekierowujące na obce strony firmy/projekty bez linku (decyzja
# koordynatora): tylko nazwa jako zwykły tekst.
expect_absent "dead links removed" \
  'href="[^"]*(hurra\.com|parasoft-magnat\.pl|klik\.kr\.pl|denise\.pl)' "$site/cv.html"

# 5. Język dokumentu.
expect_present "lang" '<html lang="en">' "${html_files[@]}"

# 6. Sekcja <head> stron głównych (spec 7.2).
expect_present "head: title" '<title>[^<]+</title>' "${head_files[@]}"
expect_present "head: description" '<meta name="description" content="[^"]+"' "${head_files[@]}"
expect_present "head: viewport" '<meta name="viewport"' "${head_files[@]}"
expect_present "head: favicon" '<link[^>]*rel="icon"[^>]*href="/favicon.svg"' "${head_files[@]}"
expect_present "head: og:title" 'property="og:title"' "${head_files[@]}"
expect_present "head: og:description" 'property="og:description"' "${head_files[@]}"
expect_present "head: og:image" \
  'property="og:image"[^>]*content="https://dziegielew.ski/photo.jpg"' \
  "${head_files[@]}"
expect_present "head: og:url" 'property="og:url"' "${head_files[@]}"
if [[ -f "$site/favicon.svg" ]]; then
  pass "favicon file exists"
else
  fail "favicon file exists ($site/favicon.svg)"
fi

# 7. Arkusz stylów podpięty na każdej stronie (łącznie z 404).
expect_present "stylesheet" '<link[^>]*rel="stylesheet"[^>]*href="/style.css"' "${html_files[@]}"

# 8. Treść wizytówki (spec 2, 7.3). Tekst „o mnie" dosłownie ze spec.
about_text="Linux user since 1995 — from running a neighbourhood network in the late '90s, through Akamai and Sabre, to leading Kubernetes platform work at Novomatic Technologies today. I like systems that are simple enough to explain and boring enough to trust."
home="$site/index.html"
for required in \
  'Grzegorz Dzięgielewski' \
  'Tech Lead DevOps/Kubernetes Engineer' \
  'Kraków, Poland' \
  'mailto:jabbas@jabbas.eu' \
  'https://github.com/jabbas' \
  'https://linkedin.com/in/jabbas' \
  'href="/cv"'; do
  expect_contains_text "home content: $required" "$required" "$home"
done
expect_contains_text "home content: about text" "$about_text" "$home"

# 9. Sekcje CV (spec 7.4).
for heading in \
  'Professional experience' \
  'Education' \
  'Additional experience' \
  'Knowledge' \
  'Language skills' \
  'Hobbies and interests'; do
  expect_present "cv section: $heading" "<h2[^>]*>[[:space:]]*${heading}[[:space:]]*</h2>" "$site/cv.html"
done

# 10. Strona 404: ten sam styl i link powrotny do strony głównej.
expect_contains_text "404 text" 'Page not found' "$site/404.html"
expect_present "404 home link" '<a href="/"' "$site/404.html"

# 11. Ciemny motyw i wydruk (patrz "Na co patrzeć przy przeglądzie" nr 4).
expect_present "dark mode" '@media \(prefers-color-scheme: dark\)' "$stylesheet"

if [[ -f "$stylesheet" ]]; then
  block="$(print_block)"
  # Wydruk zawsze jasny: blok @media print nadpisuje zmienne kolorów na
  # białe tło i czarny tekst (zmienne są używane w całym arkuszu).
  if grep -Eq -- '--color-background:[[:space:]]*(#fff|#ffffff|white)[[:space:];]' <<<"$block" &&
    grep -Eq -- '--color-text:[[:space:]]*(#000|#000000|black)[[:space:];]' <<<"$block"; then
    pass "print light"
  else
    fail "print light (blok @media print nie ustawia białego tła i czarnego tekstu)"
  fi

  # Wydruk nie wymusza przerzucania całych sekcji na następną stronę (puste
  # pół strony przed "Knowledge"); unikamy łamania tylko wewnątrz wpisów.
  if grep -Eq -- '\.cv-section[[:space:]]*\{[^}]*break-inside' <<<"$(tr '\n' ' ' <<<"$block")"; then
    fail "print sections may break (reguła .cv-section w @media print ustawia break-inside)"
  else
    pass "print sections may break"
  fi

  # Blok @media print musi leżeć PO bloku ciemnego motywu — przy równej
  # specyficzności selektorów (:root) wygrywa późniejsza reguła, inaczej
  # system w trybie ciemnym drukowałby jasny tekst na białym.
  # Szukamy tylko reguł zaczynających linię (komentarze w arkuszu nie liczą się).
  dark_line=$({ grep -n '^@media (prefers-color-scheme: dark)' "$stylesheet" || true; } | head -n 1 | cut -d: -f1)
  print_line=$({ grep -n '^@media print' "$stylesheet" || true; } | head -n 1 | cut -d: -f1)
  if [[ -n "$dark_line" && -n "$print_line" && "$print_line" -gt "$dark_line" ]]; then
    pass "print block after dark block"
  else
    fail "print block after dark block (dark: ${dark_line:-brak}, print: ${print_line:-brak})"
  fi
else
  fail "print light ($stylesheet: brak pliku)"
  fail "print block after dark block ($stylesheet: brak pliku)"
fi

if [[ $failures -ne 0 ]]; then
  echo "$failures test(ów) nie przeszło" >&2
  exit 1
fi
echo "Wszystkie testy treści przeszły"
