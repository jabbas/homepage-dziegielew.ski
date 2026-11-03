{{/*
Etykiety selektora — niezmienne, używane w selektorach Deploymentu, Service
i PodDisruptionBudget.
*/}}
{{- define "homepage.selectorLabels" -}}
app.kubernetes.io/name: homepage
app.kubernetes.io/instance: {{ .Release.Name }}
{{- end }}

{{/*
Etykiety wspólne wszystkich zasobów.
*/}}
{{- define "homepage.labels" -}}
{{ include "homepage.selectorLabels" . }}
app.kubernetes.io/managed-by: {{ .Release.Service }}
{{- end }}

{{/*
Obraz przypięty tagiem i skrótem: repozytorium:tag@sha256:...
*/}}
{{- define "homepage.image" -}}
{{ .Values.image.repository }}:{{ .Values.image.tag }}@{{ .Values.image.digest }}
{{- end }}
