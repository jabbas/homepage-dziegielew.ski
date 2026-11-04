# Strona-wizytówka dziegielew.ski — projekt

- Data: 2026-11-03
- Status: zaakceptowana przez właściciela 2026-11-03
- Plan implementacji: `docs/superpowers/plans/2026-11-03-homepage-dziegielewski.md`
- Odbiorca: inżynier, który zaplanuje implementację bez rozmowy z właścicielem

Oznaczenia decyzji:

- „(decyzja właściciela)" — ustalone przez właściciela, nie do zmiany bez jego zgody.
- „(decyzja architekta)" — ustalone w projekcie; zmiana wymaga uzasadnienia w planie.

Skróty używane w dokumencie (rozwinięte raz, tutaj):

- CI (Continuous Integration) — ciągła integracja, tu: GitHub Actions.
- CSP (Content-Security-Policy) — nagłówek HTTP ograniczający źródła zasobów strony.
- HSTS (HTTP Strict Transport Security) — nagłówek wymuszający HTTPS w przeglądarce.
- TLS (Transport Layer Security) — szyfrowanie połączenia HTTPS.
- DNS (Domain Name System) — system nazw domen.
- CDN (Content Delivery Network) — zewnętrzna sieć serwująca pliki (np. biblioteki, fonty).
- LXC (Linux Containers) — kontener systemowy na hoście Proxmox.
- OCI (Open Container Initiative) — format rejestrów obrazów; tu: rejestr chartów Helma.
- PAT (Personal Access Token) — token dostępowy GitHuba.
- PDB (PodDisruptionBudget) — zasób Kubernetes ograniczający jednoczesne wyłączenia podów.
- UID/GID (User ID / Group ID) — identyfikator użytkownika i grupy w systemie.
- SHA-256 — funkcja skrótu kryptograficznego.
- RODO — Rozporządzenie o ochronie danych osobowych (GDPR).

## 1. Cel i powód

Właściciel, Grzegorz Dzięgielewski (Tech Lead, DevOps/Kubernetes Engineer), kupił domenę `dziegielew.ski`.
Chce prostej, statycznej, zawodowej wizytówki.
Rekruter lub ktoś z branży ma w kilka sekund wiedzieć, kim jest właściciel, i znaleźć kontakt.
Pod stałym adresem `/cv` ma być aktualne CV do wklejania w aplikacjach o pracę.

Strona ma być wdrażana jak reszta homelabu: chart Helma plus Flux (GitOps).
Każda zmiana na `main` ma się sama wydać i wdrożyć.

## 2. Cele, nie-cele, anty-cele

### Cele

- `/` — wizytówka (decyzja właściciela: wariant „wizytówka + CV pod /cv"). Zawiera:
  - zdjęcie,
  - imię i nazwisko,
  - stanowisko,
  - lokalizację „Kraków, Poland",
  - 2–3 zdania o właścicielu,
  - linki: e-mail `jabbas@jabbas.eu`, GitHub `https://github.com/jabbas`, LinkedIn `https://linkedin.com/in/jabbas`,
  - wyraźny link do CV.
- `/cv` — odświeżona treść CV z `/Users/jabbas/Projects/cv/index.html`, drukowalna (zapis do PDF z przeglądarki). (decyzja właściciela)
- Tylko język angielski. (decyzja właściciela)
- Wygląd (decyzja właściciela):
  - minimalistyczny,
  - jasny lub ciemny zależnie od ustawień systemu (`prefers-color-scheme`),
  - systemowe fonty,
  - okrągłe zdjęcie,
  - jeden kolor akcentu,
  - dopuszczalny drobny akcent „terminalowy" w detalu (np. w stopce).
- Przekierowanie 301 z `www.dziegielew.ski` na `https://dziegielew.ski`, realizowane w charcie przez nginx. (decyzja właściciela)
- Automatyczne wydanie (tag semver i publikacja chartu) po każdym push lub merge do `main`, który zawiera commity kwalifikujące się do wydania. (decyzja właściciela)

### Nie-cele

- wersja polska,
- blog,
- formularz kontaktowy,
- analityka,
- JavaScript,
- generator stron statycznych lub system zarządzania treścią (CMS, Content Management System),
- własny obraz kontenera,
- cert-manager,
- kanał OCI dla chartu,
- generowanie PDF w pipeline — zastępuje je styl druku; stary `wkhtmltopdf` odpada.

### Anty-cele (porażka, nawet jeśli strona działa)

- Publikacja danych prywatnych:
  - adresu domowego,
  - daty urodzenia,
  - numeru telefonu (także linku `tel:`),
  - polskiej klauzuli zgody RODO z dołu CV.
  - Usuwamy też link „Online version of this CV" (`jabbas.eu/cv`).
- Jakikolwiek zasób ładowany z zewnątrz: CDN, Google Fonts, Bootstrap, jQuery, skrypty śledzące. Zasadę egzekwują CSP i test w CI.
- Strona, która przez błąd może zaszkodzić klastrowi, np. przez brak limitów zasobów albo uprawnienia roota.

## 3. Kontekst i ograniczenia

Stan zastany, sprawdzony w repozytoriach.

- **Ruch publiczny:** Internet → Cloudflare (terminuje TLS, działa jako proxy) → tunel `cloudflared` (kontener LXC 1000, repozytorium `~/Projects/container-cloudflared`) → `traefik-external` (`10.1.200.0:80`) → Ingress.
  - Plik `cloudflared.vars.yaml` ma już reguły `dziegielew.ski` i `*.dziegielew.ski` → `traefik-external`. Nic tam nie zmieniamy.
- **Brak cert-managera w klastrze.** Publiczne Ingressy mają klasę `traefik-external` i celowo NIE mają `spec.tls` (wzorzec: tekton, ibakery, httpbin).
  - Uwaga: każdy Ingress w tej klasie jest natychmiast publiczny.
- **GitOps:** repozytorium `jabbas/flux-homeapps` (lokalnie `~/Projects/flux-homeapps`), katalog `applications/`, lista aplikacji w `applications/kustomization.yaml`.
- **Repozytorium chartów HTTP:** `https://jabbas.github.io/helm-charts` (repozytorium `jabbas/helm-charts`).
  - Zawiera tylko wspólny `index.yaml`. Paczki leżą jako załączniki GitHub Release repozytoriów źródłowych.
  - Istniejąca logika aktualizacji indeksu: `secretspec-operator/.github/scripts/helm-index.sh` (z testem `helm-index-test.sh`) i job `helm-index` w `release.yml` tamtego repozytorium.
- **Limit ConfigMapy:** 1 MiB. Zdjęcie `/Users/jabbas/Projects/cv/photo.jpg` ma około 75 KB.
- **Repozytorium strony:** `jabbas/homepage-dziegielew.ski` na GitHubie. MUSI być publiczne, bo Flux pobiera paczkę z GitHub Release bez uwierzytelnienia. (decyzja właściciela: GitHub; publiczność to wymóg techniczny)

## 4. Architektura

### 4.1. Ścieżka ruchu i zasoby w klastrze

```d2
direction: right
internet: Przeglądarka {shape: person}
cloudflare: Cloudflare {
  tls: TLS + proxy
  dns: "DNS: dziegielew.ski, www (CNAME → tunel)"
}
lxc: "LXC 1000: cloudflared" {
  rule: "dziegielew.ski, *.dziegielew.ski → 10.1.200.0:80"
}
cluster: "Klaster Talos" {
  traefik: "traefik-external (10.1.200.0)"
  ns: "namespace homepage (Pod Security: restricted)" {
    ingress: "Ingress (bez spec.tls)\nhosty: dziegielew.ski, www"
    svc: "Service :80 → :8080"
    pods: "Deployment ×2\nnginx-unprivileged (read-only)"
    cm_site: "ConfigMap: pliki strony"
    cm_nginx: "ConfigMap: konfiguracja nginx"
    pdb: "PodDisruptionBudget minAvailable 1"
    ingress -> svc -> pods
    cm_site -> pods: montowana
    cm_nginx -> pods: montowana
  }
  flux: "Flux: HelmRepository + HelmRelease"
  traefik -> ns.ingress
  flux -> ns: helm upgrade
}
internet -> cloudflare.tls: HTTPS
cloudflare.tls -> lxc: tunel
lxc -> cluster.traefik: HTTP
```

Przeglądarka łączy się po HTTPS z Cloudflare.
Cloudflare kończy TLS i przekazuje żądanie tunelem do `cloudflared` w LXC 1000.
`cloudflared` wysyła zwykłe HTTP do `traefik-external` w klastrze.
Traefik dopasowuje host (`dziegielew.ski` lub `www.dziegielew.ski`) do Ingressu w namespace `homepage`.
Ingress kieruje ruch do Service (port 80), a ten do dwóch podów nginx (port 8080).
Pody serwują pliki z ConfigMapy strony i działają według konfiguracji z drugiej ConfigMapy.
Flux instaluje i aktualizuje całość przez `helm upgrade`.

### 4.2. Wydanie i wdrożenie

```d2
shape: sequence_diagram
dev: Właściciel
gh: "GitHub Actions (ci.yml)"
rel: "GitHub Release (homepage-dziegielew.ski)"
idx: "jabbas/helm-charts (Pages)"
flux: Flux
dev -> gh: "push / merge do main"
gh -> gh: "test: lint, render, kubeconform, limity, test indeksu"
gh -> gh: "github-tag-action: wersja z conventional commits"
gh -> rel: "helm package --version X; .tgz + SHA256SUMS"
gh -> idx: "helm-index.sh: wpis X w index.yaml"
gh -> idx: "czekanie aż Pages serwuje X"
flux -> idx: "co 10 min: nowa wersja w zakresie >=0.1.0 <1.0.0?"
flux -> rel: "pobranie .tgz"
flux -> flux: "helm upgrade → rolling update podów"
```

Właściciel wypycha zmianę do `main` (bezpośrednio albo przez merge).
Workflow `ci.yml` uruchamia testy.
Potem liczy wersję z komunikatów commitów (Conventional Commits).
Jeśli żaden commit nie kwalifikuje się do wydania, przebieg się kończy.
W przeciwnym razie powstaje tag `X`, paczka chartu w wersji `X` i GitHub Release z paczką oraz plikiem `SHA256SUMS`.
Następnie skrypt `helm-index.sh` dopisuje wersję `X` do wspólnego `index.yaml` w `jabbas/helm-charts` i czeka, aż GitHub Pages zacznie ją serwować.
Flux co 10 minut sprawdza indeks.
Gdy znajdzie nowszą wersję w zakresie `>=0.1.0 <1.0.0`, pobiera paczkę z GitHub Release i robi `helm upgrade`.
Zmiana treści zmienia sumy kontrolne ConfigMap, więc pody przechodzą rolling update.

## 5. Układ repozytorium

(decyzja architekta)

```
charts/homepage/
  Chart.yaml            # version: 0.0.0 i appVersion: 0.0.0 — zaślepki; prawdziwa wersja tylko z tagu
  values.yaml
  values.schema.json
  files/site/           # PŁASKI katalog — klucze ConfigMapy nie mogą zawierać "/"
    index.html
    cv.html
    404.html
    style.css
    photo.jpg
    favicon.svg
  files/nginx/default.conf
  templates/
    _helpers.tpl
    configmap-site.yaml
    configmap-nginx.yaml
    deployment.yaml
    service.yaml
    ingress.yaml
    poddisruptionbudget.yaml
    NOTES.txt
.github/workflows/ci.yml
.github/scripts/helm-index.sh
.github/scripts/helm-index-test.sh
renovate.json
README.md
docs/design/stitch/      # makiety z Google Stitch — tylko referencja
docs/superpowers/specs/
```

## 6. Chart `homepage`

### 6.1. ConfigMapy

- ConfigMapa strony zawiera wszystkie pliki z `files/site/*`, zebrane przez `.Files.Glob`.
  - Pliki tekstowe trafiają do `data`.
  - Pliki binarne (jpg, png, webp, ico) trafiają do `binaryData` (przez `b64enc`).
- Konfiguracja nginx leży w osobnej ConfigMapie.

### 6.2. Adresy URL

(decyzja architekta)

| Żądanie | Odpowiedź |
|---|---|
| `/` | `index.html` |
| `/cv` | `cv.html` (przez `try_files` lub `location =`) |
| `/cv/` | 301 na `/cv` |
| `/cv.html` | 301 na `/cv` |
| nieistniejąca ścieżka | `404.html` z kodem 404 |

### 6.3. Obraz

- Oficjalny `nginxinc/nginx-unprivileged` w wariancie alpine. (decyzja właściciela: brak własnego obrazu)
- Przypięty tagiem i skrótem `@sha256` w `values.yaml`.
- Aktualizowany przez Renovate.
- Bez obrazów Bitnami.

### 6.4. Konfiguracja nginx

(decyzje architekta)

- Nasłuch na porcie 8080.
- `server_tokens off`.
- Serwer dla `www.dziegielew.ski` zwraca `301 https://dziegielew.ski$request_uri`.
- `location = /healthz` zwraca 200 bez wpisu w logu (dla sond).
- Nagłówki na wszystkich odpowiedziach (z `always`):
  - `Content-Security-Policy: default-src 'none'; style-src 'self'; img-src 'self'; base-uri 'none'; form-action 'none'; frame-ancestors 'none'`
  - `X-Content-Type-Options: nosniff`
  - `Referrer-Policy: strict-origin-when-cross-origin`
  - `Permissions-Policy: camera=(), microphone=(), geolocation=(), payment=(), usb=()` — strona nie używa żadnego API przeglądarki, więc wszystkie wyłączone (decyzja architekta; `interest-cohort` dotyczył wycofanego FLoC i nic nie robi)
- `Cache-Control` krótki (np. 1 godzina) dla wszystkich plików, bo nazwy plików nie mają odcisków treści.
- Bez HSTS na serwerze źródłowym. HSTS i przekierowanie HTTP→HTTPS to zadanie Cloudflare.

### 6.5. Deployment

(decyzje architekta)

- 2 repliki.
- Miękkie `topologySpreadConstraints` po `kubernetes.io/hostname`.
- `securityContext`:
  - `runAsNonRoot: true`, UID i GID 101,
  - `readOnlyRootFilesystem: true`,
  - `allowPrivilegeEscalation: false`,
  - `capabilities.drop: [ALL]`,
  - `seccompProfile: RuntimeDefault`.
- `automountServiceAccountToken: false`.
- `emptyDir` zamontowany w `/tmp` — tam nginx-unprivileged trzyma plik pid i pliki tymczasowe.
- Montowanie całych katalogów, nie `subPath`:
  - ConfigMapa strony → `/usr/share/nginx/html`,
  - ConfigMapa nginx → `/etc/nginx/conf.d`.
- Sondy readiness i liveness na `/healthz`.
- Zasoby:
  - requests: cpu `10m`, memory `16Mi`,
  - limits: cpu `100m`, memory `64Mi`.
- Adnotacje `checksum/site` i `checksum/nginx` (SHA-256 z wyrenderowanych ConfigMap). Zmiana treści wywołuje rolling update.

### 6.6. Service, PodDisruptionBudget, Ingress

- Service typu ClusterIP, port 80 → 8080.
- PodDisruptionBudget z `minAvailable: 1`.
- Ingress:
  - `ingressClassName: traefik-external`,
  - hosty `dziegielew.ski` i `www.dziegielew.ski`,
  - ścieżka `/`, typ `Prefix`,
  - bez `spec.tls`.

### 6.7. Wartości i schemat

(decyzja architekta)

- Domyślne wartości w `values.yaml` SĄ wartościami produkcyjnymi tej strony. Chart ma jednego użytkownika.
- Klucze co najmniej:
  - `image.repository`, `image.tag`, `image.digest`,
  - `replicaCount`,
  - `resources`,
  - `ingress.className`,
  - `canonicalHost` (`dziegielew.ski`),
  - `redirectHosts` (`[www.dziegielew.ski]`).
- `values.schema.json` waliduje je ściśle (`additionalProperties: false`).
- HelmRelease nie musi niczego nadpisywać.

## 7. Treść strony

### 7.1. HTML i CSS

- Ręcznie pisany, semantyczny HTML5 z `lang="en"`.
- Jeden plik `style.css`, który zawiera:
  - zmienne kolorów,
  - wariant `@media (prefers-color-scheme: dark)`,
  - reguły `@media print`: CV czytelne na A4, bez teł, linki z widocznym adresem tam, gdzie to ma sens.
- Zero JavaScriptu.
- Zero atrybutów `style=` i elementów `<style>` w HTML — wymóg CSP `style-src 'self'`.

### 7.2. Sekcja `<head>`

(decyzje architekta)

- `title`, `meta description`, `meta viewport`.
- Link do `favicon.svg`.
- Znaczniki Open Graph dla podglądu linku na LinkedInie:
  - `og:title`,
  - `og:description`,
  - `og:image` z adresem absolutnym `https://dziegielew.ski/photo.jpg`,
  - `og:url`.
- Indeksowanie przez wyszukiwarki dozwolone.

### 7.3. Strona główna

- Tekst „o mnie" — napisany przez architekta, zaakceptowany przez właściciela 2026-11-03:

  > Linux user since 1995 — from running a neighbourhood network in the late '90s, through Akamai and Sabre, to leading Kubernetes platform work at Novomatic Technologies today. I like systems that are simple enough to explain and boring enough to trust.

- Lokalizacja „Kraków, Poland" — samo miasto, bez adresu. (zaakceptowane przez właściciela 2026-11-03)

### 7.4. CV (`cv.html`)

- Sekcje jak w starym CV:
  - Professional experience (oś czasu),
  - Education,
  - Additional experience,
  - Knowledge,
  - Language skills,
  - Hobbies and interests.
- Nagłówek: imię i nazwisko, stanowisko, e-mail, GitHub, LinkedIn, zdjęcie.
- Usunąć:
  - datę urodzenia,
  - adres,
  - telefon,
  - link „Online version",
  - klauzulę RODO.
- Poprawić:
  - „technican" → „technician",
  - „an technican" → „a technician",
  - „Labolatory" → „Laboratory",
  - „Spectometry" → „Spectrometry",
  - niedomknięty lub nieotwarty znacznik `<i>` przy „Computer Repairer",
  - linki do firm `http://` → `https://` tam, gdzie działają (implementator sprawdza każdy).
- Merytorycznie treści nie zmieniamy.

### 7.5. Zdjęcie

- ~~Kopia `/Users/jabbas/Projects/cv/photo.jpg` bez zmian.~~ Zmiana 2026-11-04 (decyzja właściciela): portret z CV był zbyt ciasno kadrowany (twarz na całą szerokość), więc żaden `object-position` nie mieścił całej głowy z brodą. `photo.jpg` to teraz awatar GitHuba właściciela (`https://avatars.githubusercontent.com/jabbas`, 460×460, przekonwertowany do JPEG), kadr `object-position: 50% 50%`.

### 7.6. Makiety

- Makiety z Google Stitch leżą w `docs/design/stitch/` (zrzuty PNG, pliki HTML, README z paletą). Są referencją wizualną.
- HTML ze Stitcha NIE trafia do chartu. Zwykle używa Tailwind z CDN, co łamie CSP i anty-cel.
- Implementator przepisuje paletę i odstępy do własnego `style.css`.
- Wzorzec wizualny: `home-desktop.png` i `cv-desktop.png` (paleta: tło `#FAFAF9`, tekst `#1C1917`, akcent teal `#0F766E`; ciemny motyw wg `docs/design/stitch/README.md`). `home-mobile.png` ma inny font i tło — niespójność Stitcha, nie wzorzec; wersja mobilna = ta sama kolumna co desktop, zwężona.
- Portret na makietach jest wygenerowany przez AI — na stronie wyłącznie prawdziwe `photo.jpg`.
- Teksty na makiecie CV Stitch skrócił i przeredagował. Źródłem treści jest stare CV (z poprawkami z sekcji 7.4), nie makieta. Układ (oś czasu w dwóch kolumnach, „Knowledge" w dwóch kolumnach z poziomem jako dopiskiem) — z makiety.
- Nagłówki sekcji CV na makiecie (`#A8A29E` na jasnym tle) mają za słaby kontrast — implementator dobiera kolor spełniający WCAG AA (kontrast ≥ 4.5:1).
- Fonty: systemowe stosy z README (`system-ui`…, `ui-monospace`…), nie fonty z makiet.
- Jeśli makiet zabraknie w chwili implementacji, obowiązuje opis wyglądu z sekcji 2.

## 8. CI i wydawanie

Jeden workflow: `.github/workflows/ci.yml`.

### 8.1. Zasady ogólne

- Wyzwalacze:
  - `pull_request` do `main`,
  - `push` do `main`,
  - `push` tagów pasujących do `[0-9]+.[0-9]+.[0-9]+`.
- Wszystkie akcje przypięte pełnym SHA z komentarzem wersji (jak w secretspec-operator).
- Uprawnienia minimalne, ustawiane na poziomie jobów.

### 8.2. Job `test`

Uruchamiany zawsze. Kroki:

1. `helm lint --strict`.
2. `helm template` → `kubeconform -strict`. Plik `values.schema.json` sprawdza sam Helm przy `lint` i `template`.
3. Każda wyrenderowana ConfigMapa ma mniej niż 900 KiB (zapas do limitu 1 MiB).
4. Test „brak zasobów zewnętrznych": w `files/site/*.html` i `style.css` nie ma `src=`, `<link href=`, `url(` ani `@import` wskazującego na `http://`, `https://` lub `//`. Linki `<a href>` są dozwolone.
5. Test „brak `tel:`".
6. `shellcheck` skryptów.
7. `bash .github/scripts/helm-index-test.sh`.

UWAGA: repozytorium jest publiczne. Testy NIE mogą zawierać danych prywatnych (numeru telefonu, adresu) jako wzorców do wyszukania.

### 8.3. Job `version`

- Warunki: tylko `push` do `main`; `needs: test`.
- `permissions: contents: write`.
- `concurrency: release` bez anulowania trwającego przebiegu.
- Akcja `mathieudutour/github-tag-action` w tej samej wersji i konfiguracji co w `~/Projects/homebudget/.github/workflows/ci.yml`:
  - `tag_prefix: ""`,
  - `default_bump: "false"`,
  - `release_branches: main`,
  - `custom_release_rules: refactor:patch`.
- Polityka wersji (decyzja właściciela, identyczna z homebudget D2):

  | Typ commitu | Efekt |
  |---|---|
  | `feat` | minor |
  | `fix`, `perf`, `refactor` | patch |
  | zmiana łamiąca, przed 1.0.0 | minor |
  | `docs`, `chore`, `ci`, `test`, `style`, `build` | brak wydania |

- Implementator sprawdza, czy konfiguracja daje „zmiana łamiąca → minor przed 1.0.0" tak jak w homebudget. Jeśli nie, zgłasza to.
  - Stan sprawdzony w homebudget: sama akcja tego nie robi. Homebudget używa trzech kroków: akcja z `dry_run: "true"` i `fetch_all_tags: "true"` liczy wersję, krok powłoki zamienia `major` na następny minor, a drugie wywołanie akcji z `custom_tag` tworzy tag. „Ta sama konfiguracja" oznacza przeniesienie tego wzorca.
  - Różnica względem homebudget (decyzja architekta): zamiana `major` → minor działa TYLKO, gdy bieżąca wersja ma major `0`. Wzorzec z homebudget zamienia zawsze, co po 1.0.0 łamałoby semver.org (zmiana łamiąca musi podbić major). Po ręcznym 1.0.0 zmiana łamiąca daje 2.0.0 — i wymaga zmiany zakresu w HelmRelease, zanim Flux ją wdroży.
- Brak nowego tagu kończy przebieg.
- Tag bez prefiksu „v" (zgodnie z semver.org i decyzją właściciela z homebudget).

### 8.4. Job `release`

- Uruchamiany po `version`, gdy ten utworzył nowy tag, ALBO po ręcznym pushu tagu semver.
- `permissions: contents: write`.
- Kroki:
  1. Wersja = nazwa tagu.
  2. `helm package charts/homepage --version X --app-version X`.
  3. Plik `SHA256SUMS`.
  4. `gh release create X` z plikiem `.tgz`, plikiem `SHA256SUMS` i automatycznie generowanymi notatkami.
- Wszystko dzieje się w jednym przebiegu workflow. Tag utworzony przez `GITHUB_TOKEN` nie uruchamia kolejnego workflow.

### 8.5. Job `helm-index`

- Uruchamiany po `release`.
- `environment: helm-charts`.
- Sekret `HELM_CHARTS_TOKEN`: fine-grained PAT z prawem Contents read/write wyłącznie do `jabbas/helm-charts`.
- Kroki:
  1. Sprawdzenie, że sekret istnieje.
  2. Pobranie załącznika z GitHub Release i porównanie jego SHA-256 z `SHA256SUMS`.
  3. `publish_index` ze skopiowanego `helm-index.sh`.
  4. `wait_for_pages`.
- Job jest idempotentny — można go ponowić samodzielnie.
- Bez kroku OCI i cosign z oryginału.

### 8.6. Skrypty indeksu

(decyzja właściciela)

- `helm-index.sh` i `helm-index-test.sh` to kopie z secretspec-operator.
- `CHART_NAME` staje się parametrem (zmienną środowiskową lub argumentem) zamiast stałej.
- Reszta logiki bez zmian.

### 8.7. Konwencja commitów

(decyzja architekta)

- Zmiany treści strony (tekst, CV, wygląd) to `feat` lub `fix`, NIGDY `docs`.
- `docs` oznacza wyłącznie dokumentację repozytorium.
- Konwencję opisuje README.

### 8.8. Wydania ręczne i pierwsze wydanie

- Ręczny tag semver to dozwolony sposób wydania, np. dla 1.0.0 albo wydania awaryjnego.
- Wersja 1.0.0 i każdy kolejny major wymaga zmiany zakresu wersji w HelmRelease.
- Pierwsze wydanie: 0.1.0, z pierwszego commitu `feat`.
  - Zastrzeżenie (z przeglądu końcowego): przy repozytorium bez żadnego tagu `github-tag-action` v6 porównuje `HEAD...GITHUB_SHA` i najpewniej nie znajdzie commitów — pierwszy przebieg może skończyć się bez wydania. Wtedy właściciel wypycha ręcznie tag `0.1.0` (wydanie ręczne działa tak samo). Kolejne wydania liczą się już od tego tagu.

## 9. Renovate (`renovate.json`)

(decyzje architekta)

- Menedżery:
  - `helm-values` — obraz nginx w `values.yaml`, z przypinaniem skrótu (digest),
  - `github-actions`.
- Commity semantyczne:
  - aktualizacja obrazu nginx: typ `fix(deps)`. Typ `chore(deps)` nie wyzwoliłby wydania i poprawki bezpieczeństwa nigdy nie trafiłyby na stronę.
  - aktualizacja akcji GitHuba: `chore(deps)` lub `ci(deps)` (bez wydania).
- Bez automatycznego scalania. Każde scalenie do `main` to publiczne wdrożenie, więc właściciel scala ręcznie.

## 10. Wdrożenie we Flux

Zmiana w repozytorium `flux-homeapps`, osobnym commitem w tamtym repozytorium.

Katalog `applications/homepage/`:

- `namespace.yaml` — namespace `homepage` z etykietami Pod Security: `enforce: restricted` oraz `audit` i `warn`.
- `repository.yaml` — `HelmRepository` `jabbas-helm-charts`:
  - `url: https://jabbas.github.io/helm-charts`,
  - `interval: 10m`,
  - w namespace `homepage`.
- `release.yaml` — `HelmRelease` `homepage`:
  - chart `homepage`,
  - `version: ">=0.1.0 <1.0.0"` — od wydania 1.0.0 (2026-11-04, decyzja właściciela) `">=1.0.0 <2.0.0"`; każdy kolejny major wymaga świadomej zmiany zakresu,
  - `interval: 1m`,
  - `install.remediation.retries: 3` i `upgrade.remediation.retries: 3`. Domyślne odinstalowanie przy nieudanej instalacji jest tu nieszkodliwe, bo aplikacja jest bezstanowa.
  - bez `values`,
  - komentarz z instrukcją cofnięcia wersji.
- Trzy pliki dopisane do `applications/kustomization.yaml`.

Cofnięcie wersji — jeden z dwóch sposobów:

- tymczasowo `version: "0.x.y"` (poprzednia wersja) w HelmRelease,
- commit `fix` z poprawką, który daje nową wersję.

Aplikacja jest bezstanowa, więc cofnięcie jest zawsze bezpieczne.

## 11. Kroki ręczne właściciela (warunki wstępne)

1. Utworzyć publiczne repozytorium `jabbas/homepage-dziegielew.ski` i wypchnąć do niego lokalne repozytorium (obecnie nie ma zdalnego `origin`).
2. W ustawieniach repozytorium utworzyć środowisko `helm-charts` z sekretem `HELM_CHARTS_TOKEN`. Może to być ten sam fine-grained PAT co w secretspec-operator, jeśli jest ograniczony do `jabbas/helm-charts`, albo nowy o tym samym zakresie.
3. Cloudflare:
   - strefa `dziegielew.ski` aktywna (serwery nazw ustawione u rejestratora),
   - rekordy `dziegielew.ski` i `www` jako CNAME (proxied) na `<uuid>.cfargotunnel.com` tunelu,
   - włączone „Always Use HTTPS",
   - tryb SSL zgodny z resztą stref,
   - HSTS (HTTP Strict Transport Security) włączony w ustawieniach SSL/TLS strefy: `max-age` 6 miesięcy (15552000 s), BEZ `includeSubDomains`, BEZ `preload` (decyzja właściciela — bezpieczny start, łatwy do wycofania; rozszerzenie to osobna decyzja dla całej domeny).
   - Weryfikacja przed wdrożeniem: `curl -sI https://dziegielew.ski` zwraca 404 Traefika, a nie błąd 1033 Cloudflare.
4. Upewnić się, że aktualna konfiguracja `container-cloudflared` (z regułami `dziegielew.ski`) jest wdrożona.

### 11.1. Kto wypycha zmiany (decyzja właściciela)

- Wykonawca pracuje WYŁĄCZNIE lokalnie, na gałęziach roboczych — w tym repozytorium i w `~/Projects/flux-homeapps`. Nie wykonuje `git push`, nie tworzy tagów, nie scala do `main`.
- Właściciel przegląda, wypycha i scala. Punkty zatrzymania planu:
  1. przed pierwszym pushem tego repozytorium na GitHub (pierwszy push `feat` na `main` = wydanie 0.1.0, wpis we wspólnym `index.yaml` jest nieodwracalny),
  2. przed scaleniem zmian w `flux-homeapps` (scalenie = natychmiastowa zmiana w klastrze i publiczny Ingress).
- Kolejność: najpierw wydanie 0.1.0 widoczne w `https://jabbas.github.io/helm-charts/index.yaml`, dopiero potem scalenie w `flux-homeapps`.
- Kryteria akceptacji „na żywo" (sekcja 12) sprawdza się po obu scaleniach; plan wskazuje, kto i jakimi poleceniami.

## 12. Kryteria akceptacji

- Adresy:
  - `https://dziegielew.ski/` → 200, wizytówka,
  - `/cv` → 200,
  - `/cv/` → 301 na `/cv`,
  - `/nie-ma` → 404 z własną stroną,
  - `https://www.dziegielew.ski/cokolwiek` → 301 na `https://dziegielew.ski/cokolwiek`.
- Nagłówki bezpieczeństwa z sekcji 6.4 są obecne; dodatkowo `Strict-Transport-Security: max-age=15552000` (z Cloudflare, bez `includeSubDomains` i `preload`).
- W narzędziach deweloperskich przeglądarki: zero żądań do innych domen, zero naruszeń CSP.
- Podgląd wydruku `/cv` jest czytelny: format A4, jasne tło także przy ciemnym motywie systemu.
- Na stronie nie ma daty urodzenia, adresu, telefonu ani klauzuli RODO.
- `kubectl get pods --namespace homepage` pokazuje 2 pody Ready w namespace z Pod Security `restricted`.
- Commit `feat:` na `main` daje nowy tag minor → GitHub Release → wpis w `index.yaml` → Flux wdraża nową wersję w czasie nie dłuższym niż około 15 minut.
- Commit `docs:` nie daje tagu ani wydania.

## 13. Dług i świadome pominięcia

- **Brak weryfikacji podpisu chartu.** (decyzja właściciela: tylko GitHub Pages)
  - Flux i Helm nie sprawdzają podpisów dla repozytoriów HTTP.
  - Ryzyko: kto ma token z prawem zapisu do `jabbas/helm-charts` (albo do Release tego repozytorium), może podmienić chart wdrażany do klastra.
  - Złagodzenie: restrykcyjny namespace (Pod Security `restricted`), brak tokena konta serwisowego, kontrola SHA-256 w pipeline.
  - Spłata: kanał OCI z cosign i `OCIRepository.verify`.
- **Dwie kopie `helm-index.sh`** (secretspec-operator i to repozytorium).
  - Spłata przy trzecim charcie w `jabbas/helm-charts`: workflow wielokrotnego użytku w `jabbas/helm-charts`.
  - Zapisane w pamięci projektu.
- **Brak automatycznych testów wizualnych i dostępności.** Sprawdzenie ręczne przy akceptacji.
- **Brak ochrony tagów** (darmowy plan GitHuba, jeden właściciel). Każdy z prawem push może wyzwolić wydanie.

## 14. Pozostawione implementatorowi

- Dokładny układ i CSS w granicach sekcji 2 i 7, na podstawie makiet.
- Szczegóły szablonów Helm i nazwy pomocników w `_helpers.tpl`.
- Wybór wersji alpine obrazu `nginx-unprivileged`.
- Sposób uruchomienia `kubeconform` i `shellcheck` w CI.
- Instalacja narzędzi potrzebnych skryptom indeksu w CI (`helm`, `yq` w wersji mikefarah v4, `jq` dla testów). W secretspec-operator `yq` instaluje osobny skrypt `install-yq.sh` z weryfikacją sumy kontrolnej; ten skrypt nie jest na liście plików z sekcji 5.
- Warunki `if` jobów `release` i `helm-index`. Na ręcznym pushu tagu job `version` jest pominięty, a pominięty job w `needs` domyślnie pomija też zależne joby. Oryginał z secretspec-operator rozwiązuje to jawnym warunkiem `!cancelled()` z wynikami zależności.
- Obsługa skryptów `docker-entrypoint.d` obrazu przy systemie plików tylko do odczytu. Nie mogą zatrzymać startu. Zweryfikować lokalnie, np. `helm template` i uruchomienie kontenera z `--read-only`.
- Kolejność bloków `server` w nginx tak, by sondy kubeleta (nagłówek `Host` z adresem IP poda) trafiały w serwer z `location = /healthz`, a nie w przekierowanie `www`.
- Treść README.

## 15. Potwierdzone przez właściciela (2026-11-03)

- Tekst „o mnie" i lokalizacja „Kraków, Poland" (sekcja 7.3).
- Makiety w `docs/design/stitch/` (z zastrzeżeniami z sekcji 7.6).
