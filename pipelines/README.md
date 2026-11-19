# Pipelines

Esta carpeta reúne la documentación y los scripts de los tres pipelines.

## Dónde están las definiciones

GitHub Actions **solo ejecuta** workflows guardados en `.github/workflows/`, por eso las definiciones viven ahí y no en esta carpeta:

| Pipeline | Definición | Qué hace |
|---|---|---|
| 1 · Infraestructura | [`../.github/workflows/infra.yml`](../.github/workflows/infra.yml) | Terraform: `fmt` → `init` → `validate` → `plan` → `apply` (o `destroy`). |
| 2 · Construcción | [`../.github/workflows/build.yml`](../.github/workflows/build.yml) | Pruebas del backend, `docker build` y push a Amazon ECR con tag = SHA del commit. |
| 3 · Despliegue | [`../.github/workflows/deploy.yml`](../.github/workflows/deploy.yml) | Nueva task definition, actualización de Amazon ECS y smoke test. |

> La carpeta `.github` empieza con punto, así que algunos exploradores de archivos la ocultan. Si no la ves, activa "mostrar archivos ocultos".

## Scripts que ejecutan los pipelines

| Script | Lo usa | Qué hace |
|---|---|---|
| [`scripts/build-push.sh`](scripts/build-push.sh) | Pipeline 2 | Construye una imagen y la publica en ECR; si ese SHA ya existe, no la vuelve a subir. |
| [`scripts/deploy.sh`](scripts/deploy.sh) | Pipeline 3 | Registra una task definition con la imagen nueva, actualiza los servicios y espera a que se estabilicen. |
| [`scripts/smoke-test.sh`](scripts/smoke-test.sh) | Pipeline 3 | Comprueba a través del balanceador que `/` y `/api/health` respondan. |

## Cuándo se ejecutan

- **Pipeline 1:** al cambiar `terraform/**` en `main`, o a mano desde la pestaña Actions (`plan`, `apply` o `destroy`).
- **Pipeline 2:** al cambiar `aplicacion/**` en `main`, o a mano.
- **Pipeline 3:** solo, cuando el Pipeline 2 termina con éxito; o a mano con un SHA anterior para hacer rollback.

Las credenciales de AWS se obtienen por OIDC, sin claves guardadas. Explicación completa en la sección 4 del [README principal](../README.md).
