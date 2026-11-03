# dziegielew.ski

Statyczna wizytówka i CV pod adresem <https://dziegielew.ski>, dostarczana jako
chart Helma `homepage`. Strona to dwa pliki HTML, jeden arkusz stylów i zdjęcie —
bez JavaScriptu i bez zasobów zewnętrznych. Chart umieszcza pliki w ConfigMapie
i serwuje je z nginx (`nginxinc/nginx-unprivileged`), bez własnego obrazu.

Każde scalenie do `main` to publiczne wdrożenie: workflow liczy wersję, tworzy
Release i dopisuje chart do wspólnego indeksu
<https://jabbas.github.io/helm-charts>, skąd pobiera go Flux.

Specyfikacja i plan: `docs/superpowers/specs/` i `docs/superpowers/plans/`.
Makiety z Google Stitch (tylko referencja): `docs/design/`.

## Układ katalogów

```
charts/homepage/
  Chart.yaml          # version i appVersion: 0.0.0 — zaślepki, nigdy nie podbijane ręcznie
  values.yaml         # wartości domyślne SĄ wartościami produkcyjnymi
  values.schema.json
  files/site/         # płaski katalog (klucze ConfigMapy nie mogą zawierać "/")
  files/nginx/default.conf
  templates/
tests/                # testy chartu, nginx i treści strony
.github/workflows/ci.yml
.github/scripts/      # wyliczanie wersji, indeks Helma, instalacja narzędzi
renovate.json
```

Prawdziwa wersja chartu powstaje dopiero z tagu: `helm package --version X --app-version X`.

## Uruchomienie lokalne

Wymagany `podman` albo `docker` (skrypt wybiera podmana, jeśli jest w `PATH`):

```bash
bash tests/nginx-smoke-test.sh --serve
```

Kontener zostaje uruchomiony na `127.0.0.1:8080`; stronę widać pod
<http://127.0.0.1:8080/>. Bez `--serve` skrypt tylko sprawdza konfigurację
i sprząta po sobie.

## Testy

Wszystkie skrypty uruchamia się bez argumentów; kod wyjścia 0 = wszystko PASS.
Potrzebne narzędzia: `helm`, `yq` (mikefarah v4), `kubeconform`, `shellcheck`,
`actionlint`, `jq`, `curl`, `python3` oraz `podman`/`docker`.

| Skrypt | Co sprawdza |
|---|---|
| `tests/render-test.sh` | `helm lint --strict`, schemat wartości, `kubeconform -strict`, asercje na manifestach, ConfigMapy < 900 KiB |
| `tests/content-test.sh` | brak zasobów zewnętrznych, kodu w HTML i danych prywatnych; treść, ciemny motyw, jasny wydruk CV |
| `tests/nginx-smoke-test.sh` | prawdziwy kontener nginx: przekierowania, nagłówki bezpieczeństwa na 200/301/404, `/healthz` |
| `.github/scripts/next-version-test.sh` | wyliczanie wersji (zmiana łamiąca → minor tylko przed 1.0.0) |
| `.github/scripts/helm-index-test.sh` | aktualizacja wspólnego indeksu Helma (lokalny zdalny git, bez sieci) |

Dodatkowo CI uruchamia `shellcheck .github/scripts/*.sh tests/*.sh` i `actionlint`.

## Konwencja commitów

Wersję wylicza `mathieudutour/github-tag-action` z Conventional Commits:

| Typ commitu | Efekt |
|---|---|
| `feat` | minor |
| `fix`, `perf`, `refactor` | patch |
| zmiana łamiąca, przed 1.0.0 | minor |
| `docs`, `chore`, `ci`, `test`, `style`, `build` | brak wydania |

- **Zmiany treści strony** (tekst, CV, wygląd) to `feat` albo `fix` — **nigdy `docs`**.
  Inaczej strona zmieni się na produkcji bez wydania. `docs` oznacza wyłącznie
  dokumentację repozytorium (np. ten plik).
- **`feat!:` nie działa.** Preset angular nie rozpoznaje wykrzyknika; zmianę
  łamiącą oznacza wyłącznie stopka `BREAKING CHANGE:` w treści commita.
- Tag nie ma prefiksu `v` (`0.1.0`, nie `v0.1.0`). Pierwsze wydanie to `0.1.0`,
  z pierwszego commitu `feat`.

## Wydania

Wszystko dzieje się w jednym przebiegu `ci.yml` (tag utworzony przez
`GITHUB_TOKEN` nie uruchamia kolejnego workflow): `test` → `version` →
`release` → `helm-index`.

- **Automatycznie:** push do `main` po zielonych testach. Jeśli commity wydają
  wersję, powstaje tag, GitHub Release (paczka `homepage-X.Y.Z.tgz` i `SHA256SUMS`)
  oraz wpis w indeksie `jabbas/helm-charts`.
- **Ręcznie:** wypchnięcie tagu semver (`X.Y.Z`) uruchamia testy i wydanie dla
  tego tagu. Tak wydaje się `1.0.0` i wydania awaryjne.
- **Wersja 1.0.0 i każdy kolejny major** wymaga zmiany zakresu wersji w
  HelmRelease, zanim Flux ją wdroży. Przed 1.0.0 `next-version.sh` zamienia zmianę
  łamiącą na minor; po 1.0.0 zmiana łamiąca daje następny major (semver.org).
- **Job `helm-index` jest idempotentny.** Jeśli padł (np. brak sekretu), można go
  ponowić samodzielnie. Gdy Pages buduje się powoli, job tylko ostrzega — indeks
  jest już wypchnięty. Inna suma SHA-256 dla tej samej wersji kończy job błędem.

### Sekret `HELM_CHARTS_TOKEN`

Job `helm-index` działa w środowisku `helm-charts` i potrzebuje w nim sekretu
`HELM_CHARTS_TOKEN`: fine-grained PAT z prawem *Contents: read and write*
wyłącznie do `jabbas/helm-charts`. Środowisko i sekret ustawia się w ustawieniach
repozytorium (Settings → Environments). Bez sekretu job kończy się czytelnym błędem.

## Aktualizacja narzędzi i zależności

Renovate (`renovate.json`) proponuje aktualizacje; wszystkie scala się ręcznie
(każde scalenie do `main` to publiczne wdrożenie).

- Obraz nginx (`values.yaml`): `fix(deps)` — poprawki bezpieczeństwa muszą wydać
  nową wersję chartu. Tag i skrót (`digest`) są osobnymi polami, więc obraz
  czyta wyrażenie regularne, nie menedżer `helm-values`.
- Akcje GitHuba i narzędzia z `install-tools.sh` (`yq`, `kubeconform`,
  `actionlint`): `ci(deps)` — bez wydania.
- **Narzędzia mają przypięte sumy SHA-256.** Renovate podbije wersję, ale nie
  policzy sumy, więc taki PR padnie w CI na weryfikacji. Trzeba ręcznie poprawić
  razem `*_VERSION` i `*_SHA256` w `.github/scripts/install-tools.sh`, według pliku
  sum tego wydania upstreamu.

## Dług i świadome pominięcia

- **Brak weryfikacji podpisu chartu.** Flux i Helm nie sprawdzają podpisów dla
  repozytoriów HTTP; kto ma token z prawem zapisu do `jabbas/helm-charts` albo do
  Release tego repozytorium, może podmienić wdrażany chart. Złagodzenie:
  restrykcyjny namespace, brak tokena konta serwisowego, kontrola SHA-256 w
  pipeline. Spłata: kanał OCI z cosign i `OCIRepository.verify`.
- **Dwie kopie `helm-index.sh`** (tu i w `jabbas/secretspec-operator`). Spłata przy
  trzecim charcie: workflow wielokrotnego użytku w `jabbas/helm-charts`.
- **Brak automatycznych testów wizualnych i dostępności.** Sprawdzenie ręczne
  przy akceptacji.
- **Brak ochrony tagów** (darmowy plan GitHuba, jeden właściciel). Każdy z
  prawem push może wyzwolić wydanie.
