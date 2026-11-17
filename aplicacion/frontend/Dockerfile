FROM public.ecr.aws/docker/library/nginx:1.27-alpine

COPY nginx.conf /etc/nginx/conf.d/default.conf
COPY index.html /usr/share/nginx/html/index.html

# Sustituye el marcador por el SHA del commit para mostrar la version desplegada.
ARG GIT_SHA=dev
RUN sed -i "s/__GIT_SHA__/${GIT_SHA}/" /usr/share/nginx/html/index.html

EXPOSE 80
