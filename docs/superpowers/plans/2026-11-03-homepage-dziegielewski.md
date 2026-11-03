# Strona-wizytówka dziegielew.ski — plan implementacji

> **Dla wykonawców (agentów):** WYMAGANA UMIEJĘTNOŚĆ: superpowers:subagent-driven-development (zalecana) albo superpowers:executing-plans — zadanie po zadaniu. Kroki mają składnię pól wyboru (`- [ ]`) do śledzenia postępu.

**Cel:** statyczna wizytówka `dziegielew.ski` (`/` + `/cv`) jako chart Helma `homepage`, wydawany automatycznie z `main` do `https://jabbas.github.io/helm-charts` i wdrażany przez Flux z `flux-homeapps`.

**Architektura:** pliki strony leżą w charcie (`files/site/`), chart pakuje je do ConfigMapy montowanej w oficjalnym `nginxinc/nginx-unprivileged` (system plików tylko do odczytu). Jeden workflow GitHub Actions: testy → wersja z Conventional Commits → GitHub Release z paczką → wpis we wspólnym `index.yaml`. Flux (`HelmRepository` + `HelmRelease` z zakresem semver) sam podnosi wersję.

**Technologie:** Helm 3 (v3.22.1 w CI), nginx-unprivileged (alpine), HTML5 + jeden plik CSS, Bash, `yq` (mikefarah v4), `kubeconform`, `shellcheck`, `actionlint`, podman lokalnie / docker w CI, GitHub Actions, Renovate, Flux v2.

**Specyfikacja:** `docs/superpowers/specs/2026-11-03-homepage-dziegielewski-design.md` — wykonawca czyta ją razem z planem; numery sekcji poniżej („spec 6.4") odnoszą się do niej.

## Ograniczenia globalne

Każde zadanie domyślnie zawiera wszystkie poniższe wymagania.

- **Bez `git push`, bez tagów, bez scalania do `main`** — ani w tym repozytorium, ani w `~/Projects/flux-homeapps`. Wyłącznie lokalne commity na gałęzi `feat/homepage` (spec 11.1). Jedyny wyjątek: pierwszy commit dokumentów na `main` w Zadaniu 0 (repozytorium nie ma jeszcze żadnego commita; `docs:` nie wydaje wersji).
- **Odstępstwa od układu ze spec 5 (uzasadnione):** katalog `tests/` (trzy skrypty testowe chartu, nginx i treści — spec wymaga sprawdzeń, nie mówi gdzie); `install-tools.sh` zamiast `install-yq.sh` (jeden przypięty instalator dla `yq`, `kubeconform`, `actionlint` zamiast trzech kopii); `next-version.sh` z testem (logika „major → minor tylko przed 1.0" jest nowa względem homebudget, więc dostaje własny test); w CI dodatkowo `nginx-smoke-test.sh` i `actionlint` (konfiguracja nginx i workflow to najbardziej ryzykowny kod, a każdy push na `main` to publiczne wydanie).
- Commity w Conventional Commits. Zmiany treści, chartu i konfiguracji strony: `feat`/`fix`. Testy: `test`. Workflow: `ci`. Dokumentacja repozytorium: `docs` (spec 8.7).
- Język: treść strony po angielsku; README, komentarze w skryptach, workflow i manifestach — po polsku; identyfikatory po angielsku. Bez skrótowców w identyfikatorach (spec „No abbreviations" z zasad projektu).
- Zero zasobów zewnętrznych na stronie, zero JavaScriptu, zero `style=`/`<style>`/`<script>` w HTML (spec 2, 7.1).
- Nigdzie w repozytorium (także w testach) nie wpisujemy adresu domowego, daty urodzenia ani numeru telefonu właściciela — repozytorium będzie publiczne (spec 8.2).
- Wartości pinowane w spec: `canonicalHost: dziegielew.ski`, `redirectHosts: [www.dziegielew.ski]`, `ingress.className: traefik-external`, `replicaCount: 2`, requests `10m`/`16Mi`, limits `100m`/`64Mi`, nasłuch `8080`, Service `80`, UID/GID `101`, `Cache-Control` 1 godzina (`max-age=3600`), limit ConfigMapy w testach `< 900 KiB`.
- `Chart.yaml`: `version: 0.0.0`, `appVersion: "0.0.0"` — zaślepki, nigdy nie podbijane ręcznie (spec 5).
- Akcje GitHuba przypięte pełnym SHA z komentarzem wersji. Znane przypięcia (z `~/Projects/secretspec-operator/.github/workflows/release.yml` i `~/Projects/homebudget/.github/workflows/ci.yml`): `actions/checkout@3d3c42e5aac5ba805825da76410c181273ba90b1 # v7.0.1`, `azure/setup-helm@9bc31f4ebc9c6b171d7bfbaa5d006ae7abdb4310 # v5.0.1` (helm `v3.22.1`), `mathieudutour/github-tag-action@a22cf08638b34d5badda920f9daf6e72c477b07b # v6.2`.
- Brak obrazów i chartów Bitnami.

## Na co patrzeć przy przeglądzie

Pięć sytuacji, których spec wprost nie testuje, a które najłatwiej przeoczyć. Każda ma test w zadaniu, które jest jej właścicielem.

1. **Dziedziczenie `add_header` w nginx** — `add_header` w bloku `location` kasuje nagłówki z poziomu `server`. Oczekiwanie: nagłówki bezpieczeństwa na KAŻDEJ odpowiedzi (200, 301, 404). Test: Zadanie 2, `nginx-smoke-test.sh` sprawdza je na 200, 301 i 404.
2. **Absolutne przekierowania z `http://` i portem 8080** — domyślnie nginx buduje `Location: http://dziegielew.ski:8080/cv`. Oczekiwanie: `/cv/` → `Location: /cv` (względne). Test: Zadanie 2, dokładna wartość nagłówka `Location`.
3. **Sondy kubeleta z `Host: <IP poda>`** — trafiają w blok domyślny. Oczekiwanie: `/healthz` → 200 dla dowolnego hosta, także `10.0.0.1`. Test: Zadanie 2.
4. **Ciemny motyw systemu + wydruk CV** — oczekiwanie: wydruk zawsze jasny, czarny tekst na białym. Test: Zadanie 3, `content-test.sh` sprawdza, że reguły `@media print` ustawiają jasne tło i ciemny tekst; ręczna kontrola w przeglądarce (krok 3.7).
5. **Pakowanie bez `--version`** — paczka `homepage-0.0.0.tgz` trafiłaby do Release i indeksu. Oczekiwanie: job `release` odrzuca wszystko poza `homepage-<tag>.tgz`. Test: Zadanie 5, krok sprawdzający nazwę paczki + `actionlint`.

---

## Zadanie 0: Przygotowanie repozytorium i narzędzi

**Pliki:** brak nowych (commit istniejących dokumentów).

- [ ] **Krok 1: Sprawdź narzędzia**

Uruchom: `helm version --short`, `yq --version`, `jq --version`, `kubeconform -v`, `shellcheck --version`, `actionlint -version`, `podman --version`, `git --version`, `python3 --version` (lokalny serwer HTTP w `helm-index-test.sh`), `kubectl version --client`.
Oczekiwane: wszystkie odpowiadają; `yq` to mikefarah v4 (`yq (https://github.com/mikefarah/yq/) version v4.…`). Brakujące narzędzie → zatrzymaj się i zgłoś koordynatorowi (instalacja przez Homebrew wymaga zgody właściciela).

- [ ] **Krok 2: Pierwszy commit dokumentów na `main`**

Repozytorium nie ma jeszcze żadnego commita. Zacommituj `docs/` (spec, plan, makiety) na `main`:

```bash
git add docs
git commit -m "docs: specyfikacja, plan i makiety strony dziegielew.ski"
```

`docs:` nie wyzwala wydania — to celowe.

- [ ] **Krok 3: Gałąź robocza**

Run: `git switch -c feat/homepage`
Oczekiwane: `Switched to a new branch 'feat/homepage'`. Cała dalsza praca w tej gałęzi.

---

## Zadanie 1: Szkielet chartu i test renderowania

**Pliki:**
- Utwórz: `charts/homepage/Chart.yaml`, `values.yaml`, `values.schema.json`, `templates/_helpers.tpl`, `templates/configmap-site.yaml`, `templates/configmap-nginx.yaml`, `templates/deployment.yaml`, `templates/service.yaml`, `templates/ingress.yaml`, `templates/poddisruptionbudget.yaml`, `templates/NOTES.txt`
- Utwórz: `charts/homepage/files/site/photo.jpg` (kopia bajt w bajt `/Users/jabbas/Projects/cv/photo.jpg`), `charts/homepage/files/site/index.html` (tymczasowy: `<!DOCTYPE html><html lang="en"><head><meta charset="utf-8"><title>dziegielew.ski</title></head><body><h1>Grzegorz Dzięgielewski</h1></body></html>` — zastąpi go Zadanie 3)
- Utwórz: `charts/homepage/files/nginx/default.conf` (tymczasowy: jeden blok `server { listen 8080 default_server; root /usr/share/nginx/html; }` — zastąpi go Zadanie 2)
- Test: `tests/render-test.sh`

**Interfejsy:**
- Produkuje — klucze `values.yaml` (dokładnie te, `additionalProperties: false` na każdym poziomie):
  ```yaml
  image: {repository: nginxinc/nginx-unprivileged, tag: "<aktualna stabilna>-alpine", digest: "sha256:<64 hex>"}
  replicaCount: 2
  resources: {requests: {cpu: 10m, memory: 16Mi}, limits: {cpu: 100m, memory: 64Mi}}
  ingress: {className: traefik-external}
  canonicalHost: dziegielew.ski
  redirectHosts: [www.dziegielew.ski]
  ```
  Schemat: `digest` pasuje do `^sha256:[0-9a-f]{64}$`; `canonicalHost` i elementy `redirectHosts` to nazwy hostów (`format: hostname` lub wzorzec); `replicaCount` integer ≥ 1.
- Produkuje — nazwy zasobów: ConfigMapy `{{ .Release.Name }}-site` i `{{ .Release.Name }}-nginx`; Deployment, Service, Ingress, PodDisruptionBudget: `{{ .Release.Name }}`; etykiety selektora `app.kubernetes.io/name: homepage`, `app.kubernetes.io/instance: {{ .Release.Name }}`.
- Produkuje — `configmap-nginx.yaml` renderuje `files/nginx/default.conf` przez `tpl` (plik może używać `.Values.canonicalHost` i `.Values.redirectHosts`); klucz w ConfigMapie: `default.conf`.
- Produkuje — `configmap-site.yaml`: każdy plik `files/site/*` jako klucz = nazwa pliku; rozszerzenia `jpg`, `jpeg`, `png`, `webp`, `ico` → `binaryData` (`b64enc`), reszta → `data`.
- Produkuje — `tests/render-test.sh`: bez argumentów, z katalogu głównego repozytorium; kod wyjścia 0 = wszystko PASS; wypisuje `PASS: …`/`FAIL: …` jak `helm-index-test.sh` z secretspec-operator.

- [ ] **Krok 1: Napisz `tests/render-test.sh` (najpierw pada)**

Renderuje `helm template homepage charts/homepage --namespace homepage` i sprawdza `yq`-iem:

| Test | Asercja |
|---|---|
| `lint` | `helm lint --strict charts/homepage` kończy się kodem 0 |
| `kubeconform` | wynik `helm template` przechodzi `kubeconform -strict -summary` |
| `schema rejects unknown key` | `helm template … --set unknownKey=1` kończy się kodem ≠ 0 |
| `schema rejects bad digest` | `helm template … --set image.digest=latest` kończy się kodem ≠ 0 |
| `deployment replicas` | `.spec.replicas == 2` |
| `pod security` | pod: `runAsNonRoot: true`, `runAsUser: 101`, `runAsGroup: 101`, `seccompProfile.type: RuntimeDefault`; kontener: `readOnlyRootFilesystem: true`, `allowPrivilegeEscalation: false`, `capabilities.drop == ["ALL"]` |
| `no service account token` | `automountServiceAccountToken: false` |
| `image pinned` | `image == "nginxinc/nginx-unprivileged:<tag>@sha256:<digest>"` (wartości z `values.yaml`) |
| `mounts` | `/usr/share/nginx/html` ← ConfigMapa `homepage-site`, `/etc/nginx/conf.d` ← `homepage-nginx`, `/tmp` ← `emptyDir`; żaden `volumeMount` nie ma `subPath` |
| `probes` | readiness i liveness: `httpGet.path == "/healthz"`, `port == 8080` |
| `resources` | requests `10m`/`16Mi`, limits `100m`/`64Mi` |
| `topology spread` | `topologyKey: kubernetes.io/hostname`, `whenUnsatisfiable: ScheduleAnyway` |
| `checksums present` | adnotacje szablonu poda `checksum/site` i `checksum/nginx` to 64 znaki hex |
| `checksum follows content` | kopia chartu w `mktemp -d` z dopisanym bajtem do `files/site/index.html` → inna `checksum/site`, ta sama `checksum/nginx` |
| `service` | `port: 80`, `targetPort: 8080`, `type: ClusterIP` |
| `pdb` | `minAvailable: 1` |
| `ingress` | `ingressClassName == "traefik-external"`; hosty reguł == `["dziegielew.ski", "www.dziegielew.ski"]`; ścieżka `/`, `Prefix`; brak `.spec.tls` |
| `photo binary` | `binaryData["photo.jpg"]` po `base64 -d` ma ten sam SHA-256 co `charts/homepage/files/site/photo.jpg` |
| `configmap size` | każdy wyrenderowany dokument `kind: ConfigMap` ma < 921600 bajtów |

- [ ] **Krok 2: Uruchom — ma paść**

Run: `bash tests/render-test.sh`
Oczekiwane: FAIL (brak chartu).

- [ ] **Krok 3: Zaimplementuj chart**

`image.tag` i `image.digest`: aktualny stabilny `nginxinc/nginx-unprivileged:<wersja>-alpine`; skrót odczytaj np. `podman manifest inspect` / `skopeo inspect` (skrót listy manifestów, wieloarchitekturowy). Checksumy: `sha256sum` z `include` wyrenderowanych szablonów ConfigMap. `topologySpreadConstraints` z `maxSkew: 1`. Komentarz w `values.yaml` dla Renovate nie jest potrzebny — menedżer `helm-values` rozpoznaje układ `repository`/`tag`/`digest` (Zadanie 5).

- [ ] **Krok 4: Uruchom — ma przejść**

Run: `bash tests/render-test.sh`
Oczekiwane: same `PASS`, kod 0. Dodatkowo `shellcheck tests/render-test.sh` bez uwag.

- [ ] **Krok 5: Commit**

```bash
git add charts tests/render-test.sh
git commit -m "feat(chart): szkielet chartu homepage z testem renderowania"
```

---

## Zadanie 2: Konfiguracja nginx i test zachowania w kontenerze

**Pliki:**
- Zmień: `charts/homepage/files/nginx/default.conf`
- Dodaj: `charts/homepage/files/site/404.html` (tymczasowy, zawiera tekst `Page not found` — Zadanie 3 nada mu wygląd), `charts/homepage/files/site/cv.html` (tymczasowy, zawiera `Professional experience`)
- Test: `tests/nginx-smoke-test.sh`

**Interfejsy:**
- Konsumuje: chart z Zadania 1 (nazwy ConfigMap, klucz `default.conf`, `values.yaml`).
- Produkuje — `tests/nginx-smoke-test.sh`:
  - bez argumentów: renderuje chart, wypakowuje obie ConfigMapy (`data` jako tekst, `binaryData` przez `base64 -d`) do katalogów w `mktemp -d`, uruchamia obraz z `values.yaml` (`repository:tag@digest`) i sprawdza zachowanie; na końcu zatrzymuje kontener; kod 0 = wszystko PASS;
  - `--serve`: to samo przygotowanie, ale kontener zostaje na `127.0.0.1:8080` na pierwszym planie (do ręcznego oglądania w Zadaniu 3);
  - silnik kontenerów: `podman`, jeśli jest w `PATH`, w przeciwnym razie `docker` (CI).
- Kontener uruchamiany tak jak w klastrze: `--read-only --tmpfs /tmp --user 101:101 --cap-drop ALL --security-opt no-new-privileges`, oba katalogi montowane tylko do odczytu w `/usr/share/nginx/html` i `/etc/nginx/conf.d`.

- [ ] **Krok 1: Napisz `tests/nginx-smoke-test.sh` (najpierw pada)**

Asercje (curl na `127.0.0.1:<port>`, nagłówek `Host` ustawiany jawnie):

| Test | Żądanie | Oczekiwane |
|---|---|---|
| `starts read-only` | — | kontener odpowiada na `/healthz` w ≤ 10 s; w logach brak `emerg` |
| `home` | `Host: dziegielew.ski` `/` | 200, `Content-Type: text/html` |
| `cv` | `/cv` | 200, treść zawiera `Professional experience` |
| `cv trailing slash` | `/cv/` | 301, `Location: /cv` (dokładnie) |
| `cv html` | `/cv.html` | 301, `Location: /cv` (dokładnie) |
| `not found` | `/nie-ma` | 404, treść zawiera `Page not found` |
| `404 page not directly` | `/404.html` | 404 |
| `www redirect` | `Host: www.dziegielew.ski` `/x?y=1` | 301, `Location: https://dziegielew.ski/x?y=1` |
| `probe by IP` | `Host: 10.0.0.1` `/healthz` | 200 |
| `probe on canonical` | `Host: dziegielew.ski` `/healthz` | 200 |
| `photo` | `/photo.jpg` | 200, `Content-Type: image/jpeg`, SHA-256 ciała == SHA-256 `files/site/photo.jpg` |
| `security headers` | po kolei na `/` (200), `/cv/` (301), `/nie-ma` (404), www `/` (301) | każda odpowiedź ma dokładnie: `Content-Security-Policy: default-src 'none'; style-src 'self'; img-src 'self'; base-uri 'none'; form-action 'none'; frame-ancestors 'none'`, `X-Content-Type-Options: nosniff`, `Referrer-Policy: strict-origin-when-cross-origin`, `Permissions-Policy: camera=(), microphone=(), geolocation=(), payment=(), usb=()` |
| `cache` | `/` i `/photo.jpg` | `Cache-Control: max-age=3600` |
| `no version leak` | `/` | nagłówek `Server` to dokładnie `nginx` |
| `no hsts` | `/` | brak `Strict-Transport-Security` (HSTS daje Cloudflare) |

- [ ] **Krok 2: Uruchom — ma paść**

Run: `bash tests/nginx-smoke-test.sh`
Oczekiwane: FAIL na przekierowaniach i nagłówkach (tymczasowy `default.conf`).

- [ ] **Krok 3: Napisz `default.conf`**

Wymagane decyzje (reszta dowolna):
- blok domyślny: `listen 8080 default_server; server_name {{ .Values.canonicalHost }};` — łapie też sondy z adresem IP;
- osobny blok `server_name` z `.Values.redirectHosts` → `return 301 https://{{ .Values.canonicalHost }}$request_uri;`;
- `absolute_redirect off;` i `server_tokens off;` na poziomie bloków `server`;
- nagłówki bezpieczeństwa przez `add_header … always` w KAŻDYM bloku `server`; w blokach `location` nie używaj `add_header` (kasuje dziedziczenie) — `Cache-Control` przez `expires 1h;`;
- `location = /cv { try_files /cv.html =404; }`, `location = /cv/` i `location = /cv.html` → `return 301 /cv;`;
- `error_page 404 /404.html;` + `location = /404.html { internal; }`;
- `location = /healthz { access_log off; return 200; }` — w obu blokach albo tylko w domyślnym (test `probe by IP` i `probe on canonical`).

- [ ] **Krok 4: Uruchom — ma przejść**

Run: `bash tests/nginx-smoke-test.sh` oraz `bash tests/render-test.sh`
Oczekiwane: same `PASS` w obu. `shellcheck tests/nginx-smoke-test.sh` bez uwag.

- [ ] **Krok 5: Commit**

```bash
git add charts tests/nginx-smoke-test.sh
git commit -m "feat(nginx): adresy, przekierowanie www i nagłówki bezpieczeństwa"
```

---

## Zadanie 3: Treść strony (HTML, CSS) i test treści

**Pliki:**
- Zastąp: `charts/homepage/files/site/index.html`, `cv.html`, `404.html`
- Utwórz: `charts/homepage/files/site/style.css`, `charts/homepage/files/site/favicon.svg` (monogram „GD" w kolorze akcentu)
- Test: `tests/content-test.sh`

**Interfejsy:**
- Konsumuje: `tests/nginx-smoke-test.sh --serve` (Zadanie 2) do ręcznego oglądania.
- Źródła: `/Users/jabbas/Projects/cv/index.html` (treść CV), `docs/design/stitch/home-desktop.png`, `cv-desktop.png`, `README.md` (paleta, odstępy, stosy fontów), spec 7.

- [ ] **Krok 1: Napisz `tests/content-test.sh` (najpierw pada)**

Bez argumentów, grep/`yq`-owy, na plikach w `charts/homepage/files/site/`:

| Test | Asercja |
|---|---|
| `no external resources` | w `*.html` i `style.css` brak `src=`, `<link … href=`, `url(`, `@import` wskazujących na `http:`, `https:` lub `//` (`<a href>` dozwolone) |
| `no inline code or style` | w `*.html` brak `<script`, `<style`, ` style=` |
| `no phone link` | brak `tel:` we wszystkich plikach |
| `no private sections` | `cv.html` nie zawiera: `Date of birth`, `Wyrażam zgodę`, `Online version` |
| `typos fixed` | `cv.html` nie zawiera: `technican`, `Labolatory`, `Spectometry` |
| `lang` | każdy `*.html` ma `<html lang="en">` |
| `head` | `index.html` i `cv.html` mają: `<title>`, `meta name="description"`, `meta name="viewport"`, `link rel="icon" … href="/favicon.svg"`, `og:title`, `og:description`, `og:image` z `content="https://dziegielew.ski/photo.jpg"`, `og:url` |
| `stylesheet` | każdy `*.html` linkuje `/style.css` |
| `home content` | `index.html` zawiera: `Grzegorz Dzięgielewski`, `Tech Lead DevOps/Kubernetes Engineer`, `Kraków, Poland`, `mailto:jabbas@jabbas.eu`, `https://github.com/jabbas`, `https://linkedin.com/in/jabbas`, `href="/cv"` oraz dokładny tekst „o mnie" ze spec 7.3 |
| `cv sections` | `cv.html` zawiera nagłówki: `Professional experience`, `Education`, `Additional experience`, `Knowledge`, `Language skills`, `Hobbies and interests` |
| `dark mode` | `style.css` zawiera `prefers-color-scheme: dark` |
| `print light` | `style.css` ma blok `@media print`, który ustawia jasne tło i ciemny tekst (np. przez nadpisanie zmiennych kolorów) |

- [ ] **Krok 2: Uruchom — ma paść**

Run: `bash tests/content-test.sh`
Oczekiwane: FAIL (strony tymczasowe).

- [ ] **Krok 3: Napisz HTML i CSS**

Według spec 7 i makiet. Treść CV: przepisana ze starego CV z usunięciami i poprawkami ze spec 7.4 (merytorycznie bez zmian; makieta CV skróciła teksty — nie jest źródłem treści). Każdy link `http://` do firmy sprawdź `curl -sIL https://…`; działa → `https://`, nie działa → zostaw `http://`. Kolor nagłówków sekcji CV: kontrast ≥ 4.5:1 do tła w obu motywach. Stopka: `$ whoami → jabbas · © 2026 Grzegorz Dzięgielewski` czcionką `ui-monospace`. `404.html` w tym samym stylu, z linkiem do `/`.

- [ ] **Krok 4: Uruchom testy — mają przejść**

Run: `bash tests/content-test.sh`, `bash tests/render-test.sh`, `bash tests/nginx-smoke-test.sh`
Oczekiwane: same `PASS` we wszystkich trzech.

- [ ] **Krok 5: Commit**

```bash
git add charts tests/content-test.sh
git commit -m "feat(site): wizytówka, CV i strona 404"
```

- [ ] **Krok 6: Przegląd wizualny (koordynator)**

Wykonawca uruchamia `bash tests/nginx-smoke-test.sh --serve` w tle i zgłasza gotowość. Koordynator zleca `@webdebugger` zrzuty `http://127.0.0.1:8080/` i `/cv` w czterech wariantach: jasny i ciemny motyw × szerokość 1280 px i 390 px, plus podgląd wydruku `/cv` przy ciemnym motywie. Porównanie z `home-desktop.png` / `cv-desktop.png`; sprawdzenie: zero żądań do innych domen i zero naruszeń CSP w konsoli.

- [ ] **Krok 7: Poprawki po przeglądzie (jeśli są)**

Poprawki → ponownie krok 4 → commit `fix(site): …`.

---

## Zadanie 4: Skrypty wydania (indeks Helma, wersja, narzędzia)

**Pliki:**
- Utwórz (kopia z `~/Projects/secretspec-operator/.github/scripts/`): `.github/scripts/helm-index.sh`, `.github/scripts/helm-index-test.sh`
- Utwórz: `.github/scripts/install-tools.sh` (na wzór `install-yq.sh` z secretspec-operator)
- Utwórz: `.github/scripts/next-version.sh`, test `.github/scripts/next-version-test.sh`

**Interfejsy:**
- Produkuje — `helm-index.sh`: te same funkcje co oryginał (`update_index`, `publish_index`, `wait_for_pages`, …); jedyna zmiana logiki: `CHART_NAME` czytany ze zmiennej środowiskowej, wymagany (`: "${CHART_NAME:?…}"`), zamiast stałej. Nagłówek SPDX zachowany + komentarz pochodzenia: `Kopia z jabbas/secretspec-operator (<skrót commita>), CHART_NAME jako parametr. Dług: dwie kopie — spłata przy trzecim charcie (reusable workflow w jabbas/helm-charts).`
- Produkuje — `helm-index-test.sh`: ustawia `CHART_NAME=homepage` i `chart_dir="$root/charts/$CHART_NAME"`; scenariusze bez zmian.
- Produkuje — `install-tools.sh <tool>`: `<tool>` ∈ {`yq`, `kubeconform`, `actionlint`}; pobiera przypiętą wersję linux/amd64, weryfikuje SHA-256 z pliku sum upstreamu, dodaje do `$GITHUB_PATH`; nieznane narzędzie → kod 1. Każda wersja ma komentarz `# renovate: datasource=github-releases depName=<owner>/<repo>`.
- Produkuje — `next-version.sh`: wejście wyłącznie przez env `RELEASE_TYPE`, `PREVIOUS`, `NEW` (wyjścia `github-tag-action` w trybie `dry_run`); wypisuje na stdout jedną linię `version=<X.Y.Z>` albo `version=` (brak wydania); kod 1 przy niepoprawnym `PREVIOUS`, gdy jest potrzebny.

- [ ] **Krok 1: Napisz `next-version-test.sh` (najpierw pada)**

| Test | Wejście | Oczekiwane |
|---|---|---|
| `no release` | `NEW=""` | `version=` , kod 0 |
| `minor passes through` | `RELEASE_TYPE=minor PREVIOUS=0.1.0 NEW=0.2.0` | `version=0.2.0` |
| `patch passes through` | `RELEASE_TYPE=patch PREVIOUS=0.2.0 NEW=0.2.1` | `version=0.2.1` |
| `breaking before 1.0 is minor` | `RELEASE_TYPE=major PREVIOUS=0.3.2 NEW=1.0.0` | `version=0.4.0` |
| `breaking from nothing` | `RELEASE_TYPE=major PREVIOUS=0.0.0 NEW=1.0.0` | `version=0.1.0` |
| `breaking after 1.0 is major` | `RELEASE_TYPE=major PREVIOUS=1.2.3 NEW=2.0.0` | `version=2.0.0` |
| `malformed previous` | `RELEASE_TYPE=major PREVIOUS=abc NEW=1.0.0` | kod 1 |

- [ ] **Krok 2: Uruchom — ma paść**

Run: `bash .github/scripts/next-version-test.sh`
Oczekiwane: FAIL (brak skryptu).

- [ ] **Krok 3: Napisz `next-version.sh`**

Logika jak krok „Ustal wersję" w `~/Projects/homebudget/.github/workflows/ci.yml` (linie 85–113), z jedną różnicą (spec 8.3): zamiana `major` → następny minor tylko, gdy major `PREVIOUS` to `0`.

- [ ] **Krok 4: Skopiuj i sparametryzuj skrypty indeksu**

Kopiuj `helm-index.sh` i `helm-index-test.sh`, wprowadź zmiany z „Interfejsy".

- [ ] **Krok 5: Napisz `install-tools.sh`**

- [ ] **Krok 6: Uruchom wszystko**

Run: `bash .github/scripts/next-version-test.sh`, `bash .github/scripts/helm-index-test.sh`, `shellcheck .github/scripts/*.sh tests/*.sh`
Oczekiwane: same `PASS`; `shellcheck` bez uwag; `grep -n secretspec .github/scripts/*.sh` zwraca wyłącznie komentarz pochodzenia. (`install-tools.sh` działa tylko na runnerze — lokalnie wystarczy `shellcheck`.)

- [ ] **Krok 7: Commit**

```bash
git add .github/scripts
git commit -m "ci: skrypty wydania — indeks Helma, wersja, narzędzia"
```

---

## Zadanie 5: Workflow, Renovate i README

**Pliki:**
- Utwórz: `.github/workflows/ci.yml`, `renovate.json`, `README.md`

**Interfejsy:**
- Konsumuje: `tests/render-test.sh`, `tests/nginx-smoke-test.sh`, `tests/content-test.sh` (Zadania 1–3), `.github/scripts/*` (Zadanie 4).
- `ci.yml` — zmienne na poziomie workflow: `CHART_NAME: homepage`, `HELM_REPO_URL: https://jabbas.github.io/helm-charts`; `permissions: contents: read` na górze.

- [ ] **Krok 1: Napisz `ci.yml`**

Wyzwalacze (spec 8.1): `pull_request` (`branches: [main]`), `push` (`branches: [main]`, `tags: ['[0-9]+.[0-9]+.[0-9]+']`).

Joby:

| Job | `needs` / `if` | Kroki |
|---|---|---|
| `test` | zawsze | checkout → setup-helm (v3.22.1) → `install-tools.sh yq`, `kubeconform`, `actionlint` → `bash tests/render-test.sh` → `bash tests/content-test.sh` → `bash tests/nginx-smoke-test.sh` (docker na runnerze) → `shellcheck .github/scripts/*.sh tests/*.sh` → `actionlint` → `bash .github/scripts/next-version-test.sh` → `bash .github/scripts/helm-index-test.sh` |
| `version` | `needs: test`; `if: github.event_name == 'push' && github.ref == 'refs/heads/main'`; `permissions: contents: write`; `concurrency: {group: release, cancel-in-progress: false}`; wyjście `version` | `github-tag-action` z `dry_run: "true"`, `fetch_all_tags: "true"`, `tag_prefix: ""`, `default_bump: "false"`, `release_branches: main`, `custom_release_rules: refactor:patch` → checkout → `next-version.sh` (env z wyjść akcji, wynik do `$GITHUB_OUTPUT`) → jeśli `version` niepusta: `github-tag-action` z `custom_tag` (tag lekki na `GITHUB_SHA`) |
| `release` | `needs: [test, version]`; `if: ${{ !cancelled() && needs.test.result == 'success' && ((github.ref_type == 'tag') \|\| (needs.version.result == 'success' && needs.version.outputs.version != '')) }}`; `permissions: contents: write`; wyjście `version` | wersja = `needs.version.outputs.version` albo `github.ref_name`; sprawdź `^[0-9]+\.[0-9]+\.[0-9]+$` → checkout z `ref: refs/tags/<wersja>` → setup-helm → `helm package charts/homepage --version <w> --app-version <w> --destination dist` → **asercja: w `dist/` jest dokładnie jeden plik i nazywa się `homepage-<w>.tgz`** → `SHA256SUMS` w `dist/` → `gh release create <w> dist/* --verify-tag --generate-notes --title <w>` (`GH_TOKEN: ${{ github.token }}`) |
| `helm-index` | `needs: release`; `if: ${{ !cancelled() && needs.release.result == 'success' }}`; `environment: helm-charts`; `permissions: contents: read`; wersja z `needs.release.outputs.version` | jak job `helm-index` w secretspec-operator `release.yml` (linie ~1093–1226) BEZ kroków OCI/crane/cosign: sprawdzenie `HELM_CHARTS_TOKEN` → checkout → setup-helm → `install-tools.sh yq` → pobranie `homepage-<w>.tgz` i `SHA256SUMS` z Release, porównanie SHA-256 → checkout `jabbas/helm-charts` do `helm-charts/` (`persist-credentials: false`) → `publish_index` → `wait_for_pages` (te same kody wyjścia i komunikaty) |

Komentarze w workflow po polsku, w tym: dlaczego wszystko w jednym przebiegu (tag z `GITHUB_TOKEN` nie uruchamia workflow), dlaczego `!cancelled()` (ręczny tag pomija `version`), że preset angular nie rozpoznaje `feat!:` (zmiana łamiąca tylko stopką `BREAKING CHANGE:`).

- [ ] **Krok 2: Sprawdź workflow**

Run: `actionlint .github/workflows/ci.yml`
Oczekiwane: brak błędów.

- [ ] **Krok 3: Napisz `renovate.json`**

Wymagane (spec 9): `extends: ["config:recommended"]`, `semanticCommits: "enabled"`, `automerge: false`; menedżery `helm-values` (z `pinDigests: true` dla obrazu w `charts/homepage/values.yaml`), `github-actions`, `regex`/`custom.regex` dla komentarzy `# renovate:` w `.github/scripts/install-tools.sh`; `packageRules`: obraz `nginxinc/nginx-unprivileged` → `semanticCommitType: "fix"`, `semanticCommitScope: "deps"`; akcje GitHuba i narzędzia z `install-tools.sh` → `semanticCommitType: "ci"`. Uwaga: Renovate podbije wersję narzędzia, ale nie sumę SHA-256 — taki PR padnie w CI i wymaga ręcznej poprawki sumy (tak samo jak w secretspec-operator); zapisz to w README.

Run: `npx --yes --package renovate -- renovate-config-validator renovate.json` (jeśli `npx` niedostępny — zgłoś, nie pomijaj po cichu)
Oczekiwane: `Config validated successfully`.

- [ ] **Krok 4: Napisz `README.md` (po polsku)**

Sekcje: czym jest repozytorium; układ katalogów; uruchomienie lokalne (`bash tests/nginx-smoke-test.sh --serve`); testy (trzy skrypty w `tests/` + skrypty w `.github/scripts/`); **konwencja commitów** (tabela ze spec 8.3, zmiany treści = `feat`/`fix`, nigdy `docs`; `feat!:` nie działa, zmiana łamiąca = stopka `BREAKING CHANGE:`); wydanie ręczne i 1.0.0 (spec 8.8); sekret `HELM_CHARTS_TOKEN` w środowisku `helm-charts`; aktualizacja narzędzi z sumami; długi ze spec 13.

- [ ] **Krok 5: Pełny przebieg testów lokalnie**

Run: `bash tests/render-test.sh && bash tests/content-test.sh && bash tests/nginx-smoke-test.sh && bash .github/scripts/next-version-test.sh && bash .github/scripts/helm-index-test.sh && actionlint`
Oczekiwane: wszystko PASS, kod 0.

- [ ] **Krok 6: Commit**

```bash
git add .github/workflows/ci.yml renovate.json README.md
git commit -m "ci: workflow testów i automatycznego wydania, Renovate, README"
```

---

## Zadanie 6: Wdrożenie we `flux-homeapps` (inne repozytorium)

**Katalog roboczy:** `~/Projects/flux-homeapps`.

**Pliki:**
- Utwórz: `applications/homepage/namespace.yaml`, `applications/homepage/repository.yaml`, `applications/homepage/release.yaml`
- Zmień: `applications/kustomization.yaml` (trzy wpisy, po `homebudget`)

**Interfejsy:**
- Konsumuje: chart `homepage` z `https://jabbas.github.io/helm-charts` (opublikowany dopiero po pushu właściciela — tu tylko pliki).
- Wzorce: `applications/ibakery/repository.yaml` (HelmRepository), `applications/homebudget/release.yaml` (komentarze, remediation).

- [ ] **Krok 1: Gałąź**

Run: `git switch -c feat/homepage` (w `~/Projects/flux-homeapps`; najpierw `git status` — brudne drzewo → zatrzymaj się i zgłoś).

- [ ] **Krok 2: Napisz manifesty**

- `namespace.yaml`: `Namespace` `homepage`, etykiety `pod-security.kubernetes.io/enforce: restricted`, `…/audit: restricted`, `…/warn: restricted`.
- `repository.yaml`: `HelmRepository` `jabbas-helm-charts`, namespace `homepage`, `url: https://jabbas.github.io/helm-charts`, `interval: 10m`.
- `release.yaml`: `HelmRelease` `homepage`, namespace `homepage`, `chart.spec.chart: homepage`, `chart.spec.version: ">=0.1.0 <1.0.0"`, `sourceRef` → `HelmRepository/jabbas-helm-charts` w `homepage`, `interval: 1m0s`, `install.remediation.retries: 3`, `upgrade.remediation.retries: 3`, bez `values`. Komentarz po polsku: skąd chart, że nowe wersje wchodzą same, cofnięcie (spec 10), 1.0.0 wymaga zmiany zakresu (Renovate z menedżerem `flux` zaproponuje wtedy PR poszerzający zakres).

- [ ] **Krok 3: Sprawdź**

Run: `kubectl kustomize applications`
Oczekiwane: kod 0, w wyniku `Namespace/homepage`, `HelmRepository/jabbas-helm-charts`, `HelmRelease/homepage`.

Run: `kubectl kustomize applications | kubeconform -strict -summary -schema-location default -schema-location 'https://raw.githubusercontent.com/datreeio/CRDs-catalog/main/{{.Group}}/{{.ResourceKind}}_{{.ResourceAPIVersion}}.json'`
Oczekiwane: `Invalid: 0, Errors: 0`.

- [ ] **Krok 4: Commit (bez push)**

```bash
git add applications/homepage applications/kustomization.yaml
git commit -m "feat(homepage): wdrożenie strony dziegielew.ski"
```

---

## Po implementacji: kroki właściciela (punkty zatrzymania ze spec 11.1)

Wykonawca kończy na Zadaniu 6. Dalej działa właściciel; koordynator podaje mu tę listę.

1. **Cloudflare** (spec 11.3): strefa aktywna, `dziegielew.ski` i `www` jako CNAME (proxied) na tunel, „Always Use HTTPS", HSTS `max-age=15552000` bez `includeSubDomains` i `preload`. Sprawdzenie: `curl -sI https://dziegielew.ski` → 404 Traefika (nie 1033).
2. **GitHub:** publiczne repozytorium `jabbas/homepage-dziegielew.ski`; środowisko `helm-charts` z sekretem `HELM_CHARTS_TOKEN` — **przed** pierwszym pushem, inaczej job `helm-index` padnie (można go ponowić).
3. **STOP 1 — wydanie 0.1.0:** przegląd gałęzi `feat/homepage`, scalenie do `main` (fast-forward), `git remote add origin git@github.com:jabbas/homepage-dziegielew.ski.git`, `git push -u origin main`. Jeśli job `version` w pierwszym przebiegu nie utworzył tagu (repozytorium bez tagów — patrz spec 8.8), wypchnij ręcznie: `git tag 0.1.0 && git push origin 0.1.0`. Sprawdzenie: Actions zielone; Release `0.1.0` z `homepage-0.1.0.tgz` i `SHA256SUMS`; `curl -s https://jabbas.github.io/helm-charts/index.yaml | yq '.entries.homepage[].version'` zawiera `0.1.0`.
4. **STOP 2 — klaster:** przegląd i scalenie `feat/homepage` w `flux-homeapps`, push. Sprawdzenie (w kontekście klastra domowego): `flux get helmreleases --namespace homepage` → `Ready True`, wersja `0.1.0`; `kubectl get pods --namespace homepage` → 2 pody `Running`/Ready.
5. **Kryteria akceptacji na żywo** (spec 12): `curl -sI` dla `https://dziegielew.ski/`, `/cv`, `/cv/`, `/nie-ma`, `https://www.dziegielew.ski/cokolwiek` — kody i `Location` jak w spec 12; nagłówki z spec 6.4 + `Strict-Transport-Security: max-age=15552000`. Przegląd w przeglądarce (lub `@webdebugger`): zero żądań do innych domen, zero naruszeń CSP, wydruk `/cv` jasny.
6. **Test automatyki:** commit `docs: …` na `main` → brak tagu; commit `feat: …` (dowolna drobna zmiana treści) → tag `0.2.0` → Flux wdraża w ≤ ~15 min.
