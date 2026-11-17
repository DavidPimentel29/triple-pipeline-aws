#!/usr/bin/env bash
# Pipeline 3: despliega en ECS la imagen publicada en ECR con el tag IMAGE_TAG.
#
# Para cada servicio (frontend y backend):
#   1) lee la task definition vigente,
#   2) la copia cambiando SOLO la imagen,
#   3) registra la nueva revision,
#   4) actualiza el servicio para usarla.
# Despues espera a que ECS declare los servicios estables.
#
# Rollback: volver a ejecutar con el IMAGE_TAG (SHA) de una version anterior.
set -euo pipefail

: "${AWS_REGION:?Falta AWS_REGION}"
: "${IMAGE_TAG:?Falta IMAGE_TAG}"
PROJECT="${PROJECT_NAME:-triple-pipeline}"
DESIRED_COUNT="${DESIRED_COUNT:-1}"
CLUSTER="${PROJECT}-cluster"
SERVICES=(frontend backend)

ACCOUNT_ID="$(aws sts get-caller-identity --query Account --output text)"
REGISTRY="${ACCOUNT_ID}.dkr.ecr.${AWS_REGION}.amazonaws.com"

deploy_service() {
  local svc="$1"
  local name="${PROJECT}-${svc}"          # familia de task definition = nombre del servicio
  local image="${REGISTRY}/${name}:${IMAGE_TAG}"

  # Falla pronto y con un mensaje claro si la imagen no existe.
  aws ecr describe-images --region "$AWS_REGION" --repository-name "$name" \
    --image-ids imageTag="$IMAGE_TAG" >/dev/null

  echo "[$svc] imagen: $image"

  local new_def
  new_def="$(aws ecs describe-task-definition --region "$AWS_REGION" --task-definition "$name" \
    --query taskDefinition --output json \
    | jq --arg img "$image" '
        .containerDefinitions[0].image = $img
        | del(.taskDefinitionArn, .revision, .status, .requiresAttributes,
              .compatibilities, .registeredAt, .registeredBy)')"

  local arn
  arn="$(aws ecs register-task-definition --region "$AWS_REGION" --cli-input-json "$new_def" \
    --query taskDefinition.taskDefinitionArn --output text)"
  echo "[$svc] nueva task definition: $arn"

  aws ecs update-service --region "$AWS_REGION" --cluster "$CLUSTER" --service "$name" \
    --task-definition "$arn" --desired-count "$DESIRED_COUNT" >/dev/null
  echo "[$svc] servicio actualizado"
}

for svc in "${SERVICES[@]}"; do
  deploy_service "$svc"
done

echo "Esperando a que los servicios queden estables (puede tardar unos minutos)..."
if ! aws ecs wait services-stable --region "$AWS_REGION" --cluster "$CLUSTER" \
     --services "${SERVICES[@]/#/${PROJECT}-}"; then
  echo "ERROR: los servicios no se estabilizaron. Ultimos eventos de ECS:" >&2
  aws ecs describe-services --region "$AWS_REGION" --cluster "$CLUSTER" \
    --services "${SERVICES[@]/#/${PROJECT}-}" \
    --query 'services[].{servicio:serviceName,eventos:events[:5].message}' --output json >&2
  exit 1
fi
echo "Despliegue completado."
