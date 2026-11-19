# Terraform

Infraestructura del proyecto como código. Hay dos configuraciones independientes:

| Carpeta | Qué crea | Cómo se ejecuta |
|---|---|---|
| [`bootstrap/`](bootstrap/main.tf) | Bucket S3 del state, proveedor OIDC de GitHub y los dos roles IAM de los pipelines | **Una sola vez, a mano** |
| `terraform/` (esta carpeta) | VPC, Security Groups, ECR, ALB, ECS Fargate, roles de ECS y logs | Con el **Pipeline 1** (GitHub Actions) |

## Archivos

| Archivo | Contenido |
|---|---|
| `versions.tf` | Versión de Terraform, provider de AWS y backend S3 del state |
| `variables.tf` | Variables y valores por defecto |
| `terraform.tfvars.example` | **Variables de ejemplo** (cópialo a `terraform.tfvars` para ejecutar a mano) |
| `network.tf` | VPC, 2 subredes públicas, Internet Gateway y rutas |
| `security.tf` | Security Groups del balanceador y de las tareas |
| `ecr.tf` | Repositorios de imágenes (tags inmutables) |
| `iam.tf` | Roles de ECS (execution role y task role) |
| `alb.tf` | Balanceador, target groups y regla `/api/*` |
| `ecs.tf` | Clúster, task definitions, servicios y log groups |
| `outputs.tf` | URL de la app y nombres de los recursos |

## Instrucciones de ejecución

Requisitos: Terraform ≥ 1.10, AWS CLI v2 con sesión de un usuario IAM (no root) en `us-east-1`.

**1. Bootstrap (una sola vez):**

```bash
cd terraform/bootstrap
terraform init
terraform apply -var="github_repo=<usuario>/<repo>"
terraform output -raw gh_variable_commands | bash   # registra las variables en GitHub
```

Si el repo de GitHub es nuevo, añade también `-var="github_oidc_subject_prefix=..."` (ver el Paso 2 del README principal).

**2. Infraestructura (lo normal):** GitHub → Actions → *1 - Infraestructura (Terraform)* → Run workflow → `plan`, `apply` o `destroy`.

**2b. Infraestructura a mano (opcional, mismo resultado):**

```bash
cd terraform
cp terraform.tfvars.example terraform.tfvars
terraform init -backend-config="bucket=<bucket del state>" -backend-config="region=us-east-1"
terraform plan
terraform apply
```

**Apagar todo:** `terraform destroy`, o el pipeline con la acción `destroy`.

Nunca subas a Git `terraform.tfstate`, `.terraform/` ni `terraform.tfvars` (ya están en `.gitignore`).
