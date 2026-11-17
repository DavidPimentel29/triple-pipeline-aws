# Imagen base desde el espejo oficial en ECR Public (evita los limites de pull de Docker Hub).
FROM public.ecr.aws/docker/library/node:22-alpine

WORKDIR /app
ENV NODE_ENV=production PORT=3000

# Solo copiamos lo necesario (sin tests): imagen mas pequena y menos superficie.
COPY package.json server.js ./

# El pipeline pasa el SHA del commit; queda visible en /api/info (trazabilidad).
ARG GIT_SHA=dev
ENV APP_VERSION=$GIT_SHA

# No ejecutar como root dentro del contenedor.
USER node

EXPOSE 3000
CMD ["node", "server.js"]
