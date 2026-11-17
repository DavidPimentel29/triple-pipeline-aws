#!/usr/bin/env bash
# Pipeline 2: construye UNA imagen y la publica en ECR con el SHA del commit como tag.
# Uso:  AWS_REGION=us-east-1 IMAGE_TAG=<sha> ./build-push.sh frontend|backend
set -euo pipefail

SERVICE="${1:?Uso: build-push.sh frontend|backend}"
: "${AWS_REGION:?Falta AWS_REGION}"
: "${IMAGE_TAG:?Falta IMAGE_TAG}"
PROJECT="${PROJECT_NAME:-triple-pipeline}"

ACCOUNT_ID="$(aws sts get-caller-identity --query Account --output text)"
REGISTRY="${ACCOUNT_ID}.dkr.ecr.${AWS_REGION}.amazonaws.com"
REPO="${PROJECT}-${SERVICE}"
IMAGE="${REGISTRY}/${REPO}:${IMAGE_TAG}"

# Los repos son IMMUTABLE: si este tag ya existe (re-ejecucion del mismo commit),
# no hay nada que publicar y el pipeline sigue en verde.
if aws ecr describe-images --region "$AWS_REGION" --repository-name "$REPO" \
     --image-ids imageTag="$IMAGE_TAG" >/dev/null 2>&1; then
  echo "La imagen ${REPO}:${IMAGE_TAG} ya existe en ECR. Se omite la publicacion."
  exit 0
fi

echo "Autenticando Docker contra ${REGISTRY}"
aws ecr get-login-password --region "$AWS_REGION" \
  | docker login --username AWS --password-stdin "$REGISTRY"

echo "Construyendo ${IMAGE}"
docker build --platform linux/amd64 --build-arg GIT_SHA="$IMAGE_TAG" -t "$IMAGE" "aplicacion/${SERVICE}"

echo "Publicando ${IMAGE}"
docker push "$IMAGE"
echo "Listo: ${IMAGE}"
