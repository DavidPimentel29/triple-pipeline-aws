#!/usr/bin/env bash
# Verifica que la aplicacion responde a traves del ALB (prueba de humo).
# Reintenta hasta 3 minutos: el ALB tarda un poco en marcar las tareas como sanas.
set -euo pipefail

: "${AWS_REGION:?Falta AWS_REGION}"
PROJECT="${PROJECT_NAME:-triple-pipeline}"

DNS="$(aws elbv2 describe-load-balancers --region "$AWS_REGION" --names "${PROJECT}-alb" \
  --query 'LoadBalancers[0].DNSName' --output text)"
URL="http://${DNS}"
echo "Probando ${URL}"

for attempt in $(seq 1 36); do
  if curl -fsS --max-time 5 "${URL}/api/health" | grep -q '"ok"' \
     && curl -fsS --max-time 5 "${URL}/" | grep -qi "Triple Pipeline"; then
    echo "OK: backend (/api/health) y frontend (/) responden."
    echo "Info del backend:"
    curl -fsS "${URL}/api/info"
    echo
    echo "URL de la aplicacion: ${URL}"
    exit 0
  fi
  echo "Intento ${attempt}/36: aun no responde, reintentando en 5 s..."
  sleep 5
done

echo "ERROR: la aplicacion no respondio a tiempo en ${URL}" >&2
exit 1
