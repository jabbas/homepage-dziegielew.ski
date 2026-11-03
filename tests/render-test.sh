#!/usr/bin/env bash
# Test renderowania chartu homepage: helm lint, kubeconform, walidacja schematu
# wartości oraz asercje na wyrenderowanych manifestach (yq).
#
# Wymaga: helm, yq (mikefarah v4), kubeconform, base64, sha256sum.
# kubeconform pobiera schematy Kubernetes z sieci. Uruchamiany bez argumentów:
#
#   bash tests/render-test.sh
#   HELM=/ścieżka/do/helm bash tests/render-test.sh   # inna wersja helma
#
# Kod wyjścia 0 = wszystkie testy PASS.
set -euo pipefail

cd "$(dirname "${BASH_SOURCE[0]}")/.."

helm_binary="${HELM:-helm}"
chart=charts/homepage
release=homepage
namespace=homepage
# Limit ConfigMapy w etcd to 1 MiB; test wymaga zapasu: < 900 KiB.
configmap_size_limit=921600

work="$(mktemp -d)"
trap 'rm -rf "$work"' EXIT
rendered="$work/rendered.yaml"

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

# expect_success <nazwa> <polecenie...>: polecenie musi zakończyć się kodem 0.
expect_success() {
  local name="$1"
  shift
  local output
  if output="$("$@" 2>&1)"; then
    pass "$name"
    return
  fi
  fail "$name"
  echo "$output" >&2
}

# expect_schema_rejection <nazwa> <argumenty --set...>: render musi się
# nie powieść właśnie przez schemat wartości, a nie z innego powodu.
expect_schema_rejection() {
  local name="$1"
  shift
  local output
  if output="$("$helm_binary" template "$release" "$chart" --namespace "$namespace" "$@" 2>&1)"; then
    fail "$name (render się udał, a powinien zostać odrzucony)"
    return
  fi
  if grep -qi "schema" <<<"$output"; then
    pass "$name"
    return
  fi
  fail "$name (błąd, ale nie ze schematu)"
  echo "$output" >&2
}

# Zapytania do wyrenderowanego manifestu: <rodzaj zasobu> <wyrażenie yq>.
# Dwa kroki yq, bo wyrażenia budujące tablicę (`[ ... ]`) zwracają `[]` także
# dla dokumentów, które odfiltrował `select`.
query() { yq "select(.kind == \"$1\")" "$rendered" | yq -N "$2"; }
query_json() { yq "select(.kind == \"$1\")" "$rendered" | yq -N -o=json -I=0 "$2"; }

# render <katalog chartu>: wypisuje manifesty na standardowe wyjście.
render() { "$helm_binary" template "$release" "$1" --namespace "$namespace"; }

echo "helm: $("$helm_binary" version --short)"

expect_success "lint" "$helm_binary" lint --strict "$chart"

# Bez wyrenderowanego chartu pozostałe asercje nie mają sensu.
if ! render "$chart" > "$rendered"; then
  fail "render chartu"
  echo "$failures test(ów) nie przeszło" >&2
  exit 1
fi

expect_success "kubeconform" kubeconform -strict -summary "$rendered"

expect_schema_rejection "schema rejects unknown key" --set unknownKey=1
expect_schema_rejection "schema rejects bad digest" --set image.digest=latest

expect_equal "deployment replicas" "2" "$(query Deployment '.spec.replicas')"

expect_equal "pod security (pod)" '[true,101,101,"RuntimeDefault"]' \
  "$(query_json Deployment '.spec.template.spec.securityContext | [.runAsNonRoot, .runAsUser, .runAsGroup, .seccompProfile.type]')"
expect_equal "pod security (container)" '[true,false,["ALL"]]' \
  "$(query_json Deployment '.spec.template.spec.containers[0].securityContext | [.readOnlyRootFilesystem, .allowPrivilegeEscalation, .capabilities.drop]')"

expect_equal "no service account token" "false" \
  "$(query Deployment '.spec.template.spec.automountServiceAccountToken')"

image_expected="$(yq '.image.repository + ":" + .image.tag + "@" + .image.digest' "$chart/values.yaml")"
expect_equal "image pinned" "$image_expected" \
  "$(query Deployment '.spec.template.spec.containers[0].image')"

# volume_source <ścieżka montowania>: skąd pochodzi wolumen zamontowany w tej ścieżce.
volume_source() {
  query Deployment ".spec.template.spec as \$pod | \$pod.containers[0].volumeMounts[] | select(.mountPath == \"$1\") | .name as \$volume_name | \$pod.volumes[] | select(.name == \$volume_name) | (.configMap.name | select(. != null) | \"configMap:\" + .) // \"emptyDir\""
}
expect_equal "mount html" "configMap:homepage-site" "$(volume_source /usr/share/nginx/html)"
expect_equal "mount nginx conf" "configMap:homepage-nginx" "$(volume_source /etc/nginx/conf.d)"
expect_equal "mount tmp" "emptyDir" "$(volume_source /tmp)"
expect_equal "mounts without subPath" "0" \
  "$(query Deployment '[.spec.template.spec.containers[].volumeMounts[] | select(has("subPath"))] | length')"

expect_equal "probes" '["/healthz",8080,"/healthz",8080]' \
  "$(query_json Deployment '.spec.template.spec.containers[0] | [.readinessProbe.httpGet.path, .readinessProbe.httpGet.port, .livenessProbe.httpGet.path, .livenessProbe.httpGet.port]')"

expect_equal "resources" '["10m","16Mi","100m","64Mi"]' \
  "$(query_json Deployment '.spec.template.spec.containers[0].resources | [.requests.cpu, .requests.memory, .limits.cpu, .limits.memory]')"

expect_equal "topology spread" '["kubernetes.io/hostname","ScheduleAnyway"]' \
  "$(query_json Deployment '.spec.template.spec.topologySpreadConstraints[0] | [.topologyKey, .whenUnsatisfiable]')"

checksum_site="$(query Deployment '.spec.template.metadata.annotations["checksum/site"]')"
checksum_nginx="$(query Deployment '.spec.template.metadata.annotations["checksum/nginx"]')"
if [[ "$checksum_site" =~ ^[0-9a-f]{64}$ && "$checksum_nginx" =~ ^[0-9a-f]{64}$ ]]; then
  pass "checksums present"
else
  fail "checksums present (site: '$checksum_site', nginx: '$checksum_nginx')"
fi

# Kopia chartu z dopisanym bajtem w index.html: zmienia się tylko checksum/site.
modified_chart="$work/chart-copy"
mkdir "$modified_chart"
cp -R "$chart/." "$modified_chart"
printf ' ' >> "$modified_chart/files/site/index.html"
modified_rendered="$work/rendered-modified.yaml"
if render "$modified_chart" > "$modified_rendered"; then
  modified_site="$(yq 'select(.kind == "Deployment") | .spec.template.metadata.annotations["checksum/site"]' "$modified_rendered")"
  modified_nginx="$(yq 'select(.kind == "Deployment") | .spec.template.metadata.annotations["checksum/nginx"]' "$modified_rendered")"
  if [[ "$modified_site" != "$checksum_site" && "$modified_nginx" == "$checksum_nginx" ]]; then
    pass "checksum follows content"
  else
    fail "checksum follows content (site: $checksum_site -> $modified_site, nginx: $checksum_nginx -> $modified_nginx)"
  fi
else
  fail "checksum follows content (render kopii chartu się nie powiódł)"
fi

expect_equal "service" '[80,8080,"ClusterIP"]' \
  "$(query_json Service '.spec | [.ports[0].port, .ports[0].targetPort, .type]')"

expect_equal "pdb" "1" "$(query PodDisruptionBudget '.spec.minAvailable')"

expect_equal "ingress class" "traefik-external" "$(query Ingress '.spec.ingressClassName')"
expect_equal "ingress hosts" '["dziegielew.ski","www.dziegielew.ski"]' \
  "$(query_json Ingress '[.spec.rules[].host]')"
expect_equal "ingress paths" '["/:Prefix","/:Prefix"]' \
  "$(query_json Ingress '[.spec.rules[].http.paths[] | .path + ":" + .pathType]')"
expect_equal "ingress backend" '["homepage:80","homepage:80"]' \
  "$(query_json Ingress '[.spec.rules[].http.paths[] | .backend.service.name + ":" + (.backend.service.port.number | tostring)]')"
expect_equal "ingress without tls" "false" "$(query Ingress '.spec | has("tls")')"

photo_expected="$(sha256sum "$chart/files/site/photo.jpg" | cut -d' ' -f1)"
photo_rendered="$(yq 'select(.kind == "ConfigMap" and .metadata.name == "homepage-site") | .binaryData["photo.jpg"]' "$rendered" | base64 -d | sha256sum | cut -d' ' -f1)"
expect_equal "photo binary" "$photo_expected" "$photo_rendered"

configmap_names="$(query ConfigMap '.metadata.name')"
expect_equal "configmap names" $'homepage-nginx\nhomepage-site' "$(sort <<<"$configmap_names")"
while IFS= read -r configmap_name; do
  size="$(yq "select(.kind == \"ConfigMap\" and .metadata.name == \"$configmap_name\")" "$rendered" | wc -c | tr -d ' ')"
  if [[ "$size" -lt "$configmap_size_limit" ]]; then
    pass "configmap size $configmap_name ($size B)"
  else
    fail "configmap size $configmap_name ($size B >= $configmap_size_limit B)"
  fi
done <<<"$configmap_names"

if [[ "$failures" -gt 0 ]]; then
  echo "$failures test(ów) nie przeszło" >&2
  exit 1
fi
echo "Wszystkie testy przeszły"
