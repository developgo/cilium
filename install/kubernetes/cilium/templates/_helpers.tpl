{{/*
Create chart name and version as used by the chart label.
*/}}
{{- define "cilium.chart" -}}
{{- printf "%s-%s" .Chart.Name .Chart.Version | replace "+" "_" | trunc 63 | trimSuffix "-" }}
{{- end }}

{{/*
Render full image name from given values, e.g:
```
image:
  repository: quay.io/cilium/cilium
  tag: v1.10.1
  useDigest: true
  digest: abcdefgh
```
then `include "cilium.image" .Values.image`
will return `quay.io/cilium/cilium:v1.10.1@abcdefgh`
*/}}
{{- define "cilium.image" -}}
{{- $digest := (.useDigest | default false) | ternary (printf "@%s" .digest) "" -}}
{{- printf "%s:%s%s" .repository .tag $digest -}}
{{- end -}}

{{/*
Return user specify priorityClass or default criticalPriorityClass
Usage:
  include "cilium.priorityClass" (list $ <priorityClass> <criticalPriorityClass>)
where:
* `priorityClass`: is user specify priorityClass e.g `.Values.operator.priorityClassName`
* `criticalPriorityClass`: default criticalPriorityClass, e.g `"system-cluster-critical"`
  This value is used when `priorityClass` is `nil` and 
  `.Values.enableCriticalPriorityClass=true` and kubernetes supported it.
*/}}
{{- define "cilium.priorityClass" -}}
{{- $root := index . 0 -}}
{{- $priorityClass := index . 1 -}}
{{- $criticalPriorityClass := index . 2 -}}
{{- if $priorityClass }}
  {{- $priorityClass }}
{{- else if and $root.Values.enableCriticalPriorityClass $criticalPriorityClass -}}
  {{- if and (eq $root.Release.Namespace "kube-system") (semverCompare ">=1.10-0" $root.Capabilities.KubeVersion.Version) -}}
    {{- $criticalPriorityClass }}
  {{- else if semverCompare ">=1.17-0" $root.Capabilities.KubeVersion.Version -}}
    {{- $criticalPriorityClass }}
  {{- end -}}
{{- end -}}
{{- end -}}

{{/*
Return the appropriate apiVersion for ingress.
*/}}
{{- define "ingress.apiVersion" -}}
{{- if semverCompare ">=1.16-0, <1.19-0" .Capabilities.KubeVersion.Version -}}
{{- print "networking.k8s.io/v1beta1" -}}
{{- else if semverCompare "^1.19-0" .Capabilities.KubeVersion.Version -}}
{{- print "networking.k8s.io/v1" -}}
{{- end -}}
{{- end -}}

{{/*
Return the appropriate backend for Hubble UI ingress.
*/}}
{{- define "ingress.paths" -}}
{{ if semverCompare ">=1.4-0, <1.19-0" .Capabilities.KubeVersion.Version -}}
backend:
  serviceName: hubble-ui
  servicePort: http
{{- else if semverCompare "^1.19-0" .Capabilities.KubeVersion.Version -}}
pathType: Prefix
backend:
  service:
    name: hubble-ui
    port:
      name: http
{{- end -}}
{{- end -}}


{{/*
Generate TLS certificates for Hubble Server and Hubble Relay.

Note: these 2 lines, that are repeated several times below, are a trick to
ensure the CA certs are generated only once:

    $ca := .ca | default (genCA "hubble-ca.cilium.io" (.Values.hubble.tls.auto.certValidityDuration | int))
    $_ := set . "ca" $ca

Please, don't try to "simplify" them as without this trick, every generated
certificate would be signed by a different CA.
*/}}
{{- define "hubble.ca.gen-cert-only" }}
{{- $ca := .ca | default (genCA "hubble-ca.cilium.io" (.Values.hubble.tls.auto.certValidityDuration | int)) -}}
{{- $_ := set . "ca" $ca -}}
ca.crt: |-
{{ $ca.Cert | indent 2 -}}
{{- end }}
{{- define "hubble.server.gen-certs" }}
{{- $ca := .ca | default (genCA "hubble-ca.cilium.io" (.Values.hubble.tls.auto.certValidityDuration | int)) -}}
{{- $_ := set . "ca" $ca -}}
{{- $cn := list "*" (.Values.cluster.name | replace "." "-") "hubble-grpc.cilium.io" | join "." }}
{{- $cert := genSignedCert $cn nil (list $cn) (.Values.hubble.tls.auto.certValidityDuration | int) $ca -}}
ca.crt: {{ $ca.Cert | b64enc }}
tls.crt: {{ $cert.Cert | b64enc }}
tls.key: {{ $cert.Key | b64enc }}
{{- end }}
{{- define "hubble.relay.gen-certs" }}
{{- $ca := .ca | default (genCA "hubble-ca.cilium.io" (.Values.hubble.tls.auto.certValidityDuration | int)) -}}
{{- $_ := set . "ca" $ca -}}
{{- $cert := genSignedCert "*.hubble-relay.cilium.io" nil (list "*.hubble-relay.cilium.io") (.Values.hubble.tls.auto.certValidityDuration | int) $ca -}}
ca.crt: {{ $ca.Cert | b64enc }}
tls.crt: {{ $cert.Cert | b64enc }}
tls.key: {{ $cert.Key | b64enc }}
{{- end }}

{{- define "hubble.ui.gen-certs" }}
{{- $ca := .ca | default (genCA "hubble-ca.cilium.io" (.Values.hubble.tls.auto.certValidityDuration | int)) -}}
{{- $_ := set . "ca" $ca -}}
{{- $cert := genSignedCert "*.hubble-ui.cilium.io" nil (list "*.hubble-ui.cilium.io") (.Values.hubble.tls.auto.certValidityDuration | int) $ca -}}
ca.crt: {{ $ca.Cert | b64enc }}
tls.crt: {{ $cert.Cert | b64enc }}
tls.key: {{ $cert.Key | b64enc }}
{{- end }}

{{/* Generate CA "vmca" for clustermesh-apiserver in the global dict. */}}
{{- define "clustermesh.apiserver.generate.ca" }}
{{- $ca := .cmca | default (genCA "clustermesh-apiserver-ca.cilium.io" (.Values.clustermesh.apiserver.tls.auto.certValidityDuration | int)) -}}
{{- $_ := set . "cmca" $ca -}}
{{- end }}

{{/* Generate CA certificate clustermesh-apiserver. */}}
{{- define "clustermesh.apiserver.ca.gen-cert" }}
{{- template "clustermesh.apiserver.generate.ca" . -}}
ca.crt: {{ .cmca.Cert | b64enc }}
ca.key: {{ .cmca.Key | b64enc }}
{{- end }}

{{/* Generate server certificate clustermesh-apiserver. */}}
{{- define "clustermesh.apiserver.server.gen-cert" }}
{{- template "clustermesh.apiserver.generate.ca" . }}
{{- $CN := "clustermesh-apiserver.cilium.io" }}
{{- $IPs := (list "127.0.0.1") }}
{{- $SANs := (list $CN) }}
{{- $cert := genSignedCert $CN $IPs $SANs (.Values.clustermesh.apiserver.tls.auto.certValidityDuration | int) .cmca -}}
ca.crt: {{ .cmca.Cert | b64enc }}
tls.crt: {{ $cert.Cert | b64enc }}
tls.key: {{ $cert.Key | b64enc }}
{{- end }}

{{/* Generate admin certificate clustermesh-apiserver. */}}
{{- define "clustermesh.apiserver.admin.gen-cert" }}
{{- template "clustermesh.apiserver.generate.ca" . }}
{{- $CN := "root" }}
{{- $SANs := (list "localhost") }}
{{- $cert := genSignedCert $CN nil $SANs (.Values.clustermesh.apiserver.tls.auto.certValidityDuration | int) .cmca -}}
ca.crt: {{ .cmca.Cert | b64enc }}
tls.crt: {{ $cert.Cert | b64enc }}
tls.key: {{ $cert.Key | b64enc }}
{{- end }}

{{/* Generate client certificate clustermesh-apiserver. */}}
{{- define "clustermesh.apiserver.client.gen-cert" }}
{{- template "clustermesh.apiserver.generate.ca" . }}
{{- $CN := "externalworkload" }}
{{- $cert := genSignedCert $CN nil nil (.Values.clustermesh.apiserver.tls.auto.certValidityDuration | int) .cmca -}}
ca.crt: {{ .cmca.Cert | b64enc }}
tls.crt: {{ $cert.Cert | b64enc }}
tls.key: {{ $cert.Key | b64enc }}
{{- end }}

{{/* Generate remote certificate clustermesh-apiserver. */}}
{{- define "clustermesh.apiserver.remote.gen-cert" }}
{{- template "clustermesh.apiserver.generate.ca" . }}
{{- $CN := "remote" }}
{{- $cert := genSignedCert $CN nil nil (.Values.clustermesh.apiserver.tls.auto.certValidityDuration | int) .cmca -}}
ca.crt: {{ .cmca.Cert | b64enc }}
tls.crt: {{ $cert.Cert | b64enc }}
tls.key: {{ $cert.Key | b64enc }}
{{- end }}
