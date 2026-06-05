#!/usr/bin/env bash
set -euo pipefail

log() {
  echo "[$(date +'%F %T')] $*"
}

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
OUTPUT_DIR="${SCRIPT_DIR}"

log "Iniciando generacion de informe CVEs."

cd "${OUTPUT_DIR}"
log "Directorio de trabajo: $(pwd)"

# No borrar históricos
rm -f cves.zip
log "ZIP anterior eliminado si existia."

# -------- CONFIG --------
KV_HOST="kv-ca-admcloud-eastus2.vault.azure.net"
SEC_APP_ID="checkappid"
SEC_APP_SECRET="checkapp"
SEC_TENANT_ID="tenantid"
FIRST=1000
TS="$(date +%F_%H%M%S)"
ALL_CSV="./CVEs_ACR_AKS_${TS}.csv"
SUMMARY_FILE="./CVEs_ACR_AKS_${TS}.summary.txt"
META_FILE="./CVEs_ACR_AKS_${TS}.meta.json"

# -------- PRE-REQS --------
log "Validando prerequisitos: jq, Azure CLI y extension resource-graph."
command -v jq >/dev/null 2>&1 || { sudo apt-get update -y && sudo apt-get install -y jq; }
command -v az >/dev/null 2>&1 || { curl -sL https://aka.ms/InstallAzureCLIDeb | sudo bash; }
az extension show --name resource-graph >/dev/null 2>&1 || az extension add --name resource-graph
log "Prerequisitos OK."

# -------- TOKEN MI -> KV --------
log "Obteniendo token de Managed Identity para Key Vault."
IMDS_TOKEN="$(curl -sS -H "Metadata:true" \
  "http://169.254.169.254/metadata/identity/oauth2/token?resource=https://vault.azure.net&api-version=2019-08-01" \
  | jq -r .access_token)"
log "Token obtenido."

# -------- LEER SECRETOS --------
log "Leyendo secretos desde Key Vault."
APP_ID="$(curl -sS -H "Authorization: Bearer ${IMDS_TOKEN}" \
  "https://${KV_HOST}/secrets/${SEC_APP_ID}?api-version=7.2" | jq -r .value)"

SP_SECRET="$(curl -sS -H "Authorization: Bearer ${IMDS_TOKEN}" \
  "https://${KV_HOST}/secrets/${SEC_APP_SECRET}?api-version=7.2" | jq -r .value)"

TENANT_ID="$(curl -sS -H "Authorization: Bearer ${IMDS_TOKEN}" \
  "https://${KV_HOST}/secrets/${SEC_TENANT_ID}?api-version=7.2" | jq -r .value)"

test -n "$APP_ID"
test -n "$SP_SECRET"
test -n "$TENANT_ID"
log "Secretos cargados."

# -------- LOGIN SP --------
log "Autenticando Azure CLI con service principal."
az login --service-principal -u "$APP_ID" -p "$SP_SECRET" --tenant "$TENANT_ID" >/dev/null
log "Login Azure CLI OK."

# -------- QUERY --------
ACR_QUERY=$'securityresources
| where type =~ "microsoft.security/assessments/subassessments"
| where properties.additionalData.assessedResourceType == "AzureContainerRegistryVulnerability"
| extend p = todynamic(properties)
| project subscriptionId,resourceGroup,
          registryHost=tostring(p.additionalData.artifactDetails.registryHost),
          repository=tostring(p.additionalData.artifactDetails.repositoryName),
          digest=tostring(p.additionalData.artifactDetails.digest),
          tags=strcat_array(todynamic(p.additionalData.artifactDetails.tags), ","),
          cve=tostring(p.additionalData.vulnerabilityDetails.cveId),
          severity=tostring(p.additionalData.vulnerabilityDetails.severity),
          cvss_base=toreal(p.additionalData.vulnerabilityDetails.cvss["3.0"].base),
          package=tostring(p.additionalData.softwareDetails.packageName),
          version=tostring(p.additionalData.softwareDetails.version),
          fix_status=tostring(p.additionalData.softwareDetails.fixStatus),
          fixed_ver=tostring(p.additionalData.softwareDetails.fixedVersion),
          published=tostring(p.additionalData.vulnerabilityDetails.publishedDate),
          lastSeen=tostring(p.timeGenerated),
          subAssessmentId=name'

ACR_HEADERS='["subscriptionId","resourceGroup","registryHost","repository","digest","tags","cve","severity","cvss_base","package","version","fix_status","fixed_ver","published","lastSeen","subAssessmentId"]'

run_arg_to_csv() {
  local query="$1"
  local outfile="$2"
  local headers_json="$3"
  local skip=0
  local first_page=1

  : > "$outfile"

  while true; do
    TMP_JSON="$(mktemp)"
    log "Consultando Azure Resource Graph: pagina skip=${skip}, first=${FIRST}."

    az graph query \
      -q "$query" \
      --first "$FIRST" \
      --skip "$skip" \
      -o json > "$TMP_JSON"

    ROWS="$(jq '.data | length' "$TMP_JSON")"
    log "Filas recibidas en pagina actual: ${ROWS}."

    if [[ "$ROWS" -eq 0 ]]; then
      rm -f "$TMP_JSON"
      break
    fi

    if [[ "$first_page" -eq 1 ]]; then
      jq -r --argjson H "$headers_json" '
        .data as $rows |
        ($H | @csv),
        ($rows[] | [ .[$H[]] ] | @csv)
      ' "$TMP_JSON" >> "$outfile"
      first_page=0
    else
      jq -r --argjson H "$headers_json" '
        .data[] | [ .[$H[]] ] | @csv
      ' "$TMP_JSON" >> "$outfile"
    fi

    rm -f "$TMP_JSON"

    (( ROWS < FIRST )) && break
    skip=$(( skip + FIRST ))
  done
}

# -------- EJECUCIÓN --------
log "Generando CSV temporal desde Azure Resource Graph."
TMP_ACR_CSV="$(mktemp)"
run_arg_to_csv "$ACR_QUERY" "$TMP_ACR_CSV" "$ACR_HEADERS"
log "CSV temporal generado."

# Mantiene exactamente la misma estructura histórica
log "Construyendo CSV final con estructura historica."
{
  echo '"source","subscriptionId","resourceGroup","registryHost","repository","digest","tags","cve","severity","cvss_base","package","version","fix_status","fixed_ver","published","lastSeen","subAssessmentId"'
  tail -n +2 "$TMP_ACR_CSV" | sed 's/^/"ACR",/'
} > "$ALL_CSV"

rm -f "$TMP_ACR_CSV"

# -------- RESUMEN CONTROL --------
# El CSV historico no cambia; el resumen se calcula con parser CSV real
# para soportar campos entrecomillados que contienen comas, como tags.
log "Calculando resumen y metadata del reporte."
python3 - "$ALL_CSV" "$SUMMARY_FILE" "$META_FILE" "$TS" <<'PY'
import csv
import json
import os
import sys

csv_path, summary_path, meta_path, generated_at = sys.argv[1:5]

total_rows = 0
severity_counts = {
    "Critical": 0,
    "High": 0,
    "Medium": 0,
    "Low": 0,
}
unique_cves = set()
unique_repositories = set()
unique_registries = set()

with open(csv_path, newline="", encoding="utf-8-sig") as csv_file:
    reader = csv.DictReader(csv_file)
    for row in reader:
        total_rows += 1

        severity = row.get("severity", "")
        if severity in severity_counts:
            severity_counts[severity] += 1

        cve = row.get("cve", "")
        if cve:
            unique_cves.add(cve)

        repository = row.get("repository", "")
        if repository:
            unique_repositories.add(repository)

        registry = row.get("registryHost", "")
        if registry:
            unique_registries.add(registry)

summary = {
    "file": os.path.basename(csv_path),
    "generated_at": generated_at,
    "total_rows": total_rows,
    "critical": severity_counts["Critical"],
    "high": severity_counts["High"],
    "medium": severity_counts["Medium"],
    "low": severity_counts["Low"],
    "unique_cves": len(unique_cves),
    "unique_repositories": len(unique_repositories),
    "unique_registries": len(unique_registries),
}

with open(summary_path, "w", encoding="utf-8", newline="\n") as summary_file:
    for key, value in summary.items():
        summary_file.write(f"{key}={value}\n")

meta = {
    "file": summary["file"],
    "generated_at": generated_at,
    "total_rows": total_rows,
    "severity": severity_counts,
    "unique_cves": len(unique_cves),
    "unique_repositories": len(unique_repositories),
    "unique_registries": len(unique_registries),
}

with open(meta_path, "w", encoding="utf-8", newline="\n") as meta_file:
    json.dump(meta, meta_file, indent=2)
    meta_file.write("\n")
PY
log "Resumen y metadata generados."

echo "Listo:"
echo " - $(realpath "$ALL_CSV")"
echo " - $(realpath "$SUMMARY_FILE")"
echo " - $(realpath "$META_FILE")"

# ZIP solo del reporte generado actual + resumen/meta
log "Comprimiendo reporte actual en ${OUTPUT_DIR}/cves.zip."
zip -j "${OUTPUT_DIR}/cves.zip" "$ALL_CSV" "$SUMMARY_FILE" "$META_FILE"
log "ZIP generado."

log "Enviando correo."
python3 "${SCRIPT_DIR}/envio.py" "$@"
