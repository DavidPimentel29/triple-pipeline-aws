# ============================================================================
# BOOTSTRAP  (se ejecuta UNA sola vez, a mano, desde tu computador)
#
# Por que existe: el Pipeline 1 (Terraform en GitHub Actions) necesita dos
# cosas que no pueden crearse a si mismas:
#   1) un lugar donde guardar el "state" de Terraform (bucket S3), y
#   2) permiso para entrar a AWS SIN claves guardadas (OIDC + roles IAM).
# Es el clasico problema del huevo y la gallina; por eso se resuelve aqui,
# con una configuracion aparte y pequena.
# ============================================================================

terraform {
  required_version = ">= 1.10"
  required_providers {
    aws = {
      source  = "hashicorp/aws"
      version = "~> 6.0"
    }
  }
}

provider "aws" {
  region = var.region
  default_tags {
    tags = {
      Project   = var.project_name
      ManagedBy = "terraform-bootstrap"
    }
  }
}

variable "region" {
  description = "Region de AWS donde vive todo el proyecto."
  type        = string
  default     = "us-east-1"
}

variable "project_name" {
  description = "Prefijo para nombrar recursos. Debe coincidir con el de terraform/ y los workflows."
  type        = string
  default     = "triple-pipeline"
}

variable "github_repo" {
  description = "Repositorio de GitHub con formato owner/repo. Solo ESTE repo podra asumir los roles."
  type        = string
}

variable "github_oidc_subject_prefix" {
  description = "Opcional. Prefijo del 'subject' inmutable de GitHub (repos nuevos): repo:OWNER@ID/REPO@ID. Ver: gh api repos/OWNER/REPO/actions/oidc/customization/sub"
  type        = string
  default     = ""
}

variable "create_oidc_provider" {
  description = "false si tu cuenta ya tiene un proveedor OIDC de GitHub (solo puede existir uno por cuenta)."
  type        = bool
  default     = true
}

data "aws_caller_identity" "current" {}

locals {
  account_id   = data.aws_caller_identity.current.account_id
  state_bucket = "${var.project_name}-tfstate-${local.account_id}"
}

# ---------------------------------------------------------------------------
# 1) Bucket S3 para el state remoto
# ---------------------------------------------------------------------------
resource "aws_s3_bucket" "tfstate" {
  bucket = local.state_bucket
}

resource "aws_s3_bucket_versioning" "tfstate" {
  bucket = aws_s3_bucket.tfstate.id
  versioning_configuration {
    status = "Enabled" # permite recuperar versiones anteriores del state
  }
}

resource "aws_s3_bucket_server_side_encryption_configuration" "tfstate" {
  bucket = aws_s3_bucket.tfstate.id
  rule {
    apply_server_side_encryption_by_default {
      sse_algorithm = "AES256"
    }
  }
}

resource "aws_s3_bucket_public_access_block" "tfstate" {
  bucket                  = aws_s3_bucket.tfstate.id
  block_public_acls       = true
  block_public_policy     = true
  ignore_public_acls      = true
  restrict_public_buckets = true
}

# ---------------------------------------------------------------------------
# 2) Proveedor OIDC de GitHub: AWS confia en los tokens que firma GitHub
# ---------------------------------------------------------------------------
resource "aws_iam_openid_connect_provider" "github" {
  count          = var.create_oidc_provider ? 1 : 0
  url            = "https://token.actions.githubusercontent.com"
  client_id_list = ["sts.amazonaws.com"]
}

data "aws_iam_openid_connect_provider" "github" {
  count = var.create_oidc_provider ? 0 : 1
  url   = "https://token.actions.githubusercontent.com"
}

locals {
  oidc_arn = var.create_oidc_provider ? aws_iam_openid_connect_provider.github[0].arn : data.aws_iam_openid_connect_provider.github[0].arn
}

# Politica de confianza: QUIEN puede asumir el rol.
# Solo workflows de TU repo, ejecutandose en la rama main.
data "aws_iam_policy_document" "github_trust" {
  statement {
    actions = ["sts:AssumeRoleWithWebIdentity"]
    principals {
      type        = "Federated"
      identifiers = [local.oidc_arn]
    }
    condition {
      test     = "StringEquals"
      variable = "token.actions.githubusercontent.com:aud"
      values   = ["sts.amazonaws.com"]
    }
    condition {
      test     = "StringEquals"
      variable = "token.actions.githubusercontent.com:sub"
      values = compact([
        "repo:${var.github_repo}:ref:refs/heads/main",
        var.github_oidc_subject_prefix == "" ? "" : "${var.github_oidc_subject_prefix}:ref:refs/heads/main",
      ])
    }
  }
}

# ---------------------------------------------------------------------------
# 3) Rol para el Pipeline 1 (Terraform): crea VPC, ALB, ECS, IAM...
#    Necesita mucho poder; por eso solo lo asume la rama main.
# ---------------------------------------------------------------------------
resource "aws_iam_role" "terraform" {
  name               = "${var.project_name}-github-terraform"
  assume_role_policy = data.aws_iam_policy_document.github_trust.json
}

resource "aws_iam_role_policy_attachment" "terraform_admin" {
  role       = aws_iam_role.terraform.name
  policy_arn = "arn:aws:iam::aws:policy/AdministratorAccess"
}

# ---------------------------------------------------------------------------
# 4) Rol para los Pipelines 2 y 3 (build y deploy): minimo privilegio.
#    Solo puede subir imagenes a SUS repos ECR y actualizar SUS servicios ECS.
# ---------------------------------------------------------------------------
resource "aws_iam_role" "app" {
  name               = "${var.project_name}-github-app"
  assume_role_policy = data.aws_iam_policy_document.github_trust.json
}

data "aws_iam_policy_document" "app" {
  statement {
    sid       = "EcrLogin"
    actions   = ["ecr:GetAuthorizationToken"]
    resources = ["*"] # esta accion no admite restringir por recurso
  }

  statement {
    sid = "EcrPushToProjectRepos"
    actions = [
      "ecr:BatchCheckLayerAvailability",
      "ecr:InitiateLayerUpload",
      "ecr:UploadLayerPart",
      "ecr:CompleteLayerUpload",
      "ecr:PutImage",
      "ecr:BatchGetImage",
      "ecr:GetDownloadUrlForLayer",
      "ecr:DescribeImages",
    ]
    resources = ["arn:aws:ecr:${var.region}:${local.account_id}:repository/${var.project_name}-*"]
  }

  statement {
    sid = "EcsTaskDefinitions"
    actions = [
      "ecs:RegisterTaskDefinition",
      "ecs:DescribeTaskDefinition",
    ]
    resources = ["*"] # estas acciones no admiten restringir por recurso
  }

  statement {
    sid = "EcsUpdateProjectServices"
    actions = [
      "ecs:UpdateService",
      "ecs:DescribeServices",
    ]
    resources = ["arn:aws:ecs:${var.region}:${local.account_id}:service/${var.project_name}-cluster/*"]
  }

  statement {
    sid       = "PassOnlyProjectEcsRoles"
    actions   = ["iam:PassRole"]
    resources = ["arn:aws:iam::${local.account_id}:role/${var.project_name}-ecs-*"]
    condition {
      test     = "StringEquals"
      variable = "iam:PassedToService"
      values   = ["ecs-tasks.amazonaws.com"]
    }
  }

  statement {
    sid       = "ReadAlbForSmokeTest"
    actions   = ["elasticloadbalancing:DescribeLoadBalancers"]
    resources = ["*"]
  }
}

resource "aws_iam_role_policy" "app" {
  name   = "build-and-deploy"
  role   = aws_iam_role.app.id
  policy = data.aws_iam_policy_document.app.json
}

# ---------------------------------------------------------------------------
# Salidas: valores que debes copiar a GitHub como "Variables" (no son secretos)
# ---------------------------------------------------------------------------
output "state_bucket" {
  value = aws_s3_bucket.tfstate.bucket
}

output "terraform_role_arn" {
  value = aws_iam_role.terraform.arn
}

output "app_role_arn" {
  value = aws_iam_role.app.arn
}

output "gh_variable_commands" {
  description = "Comandos listos para registrar las variables en el repo de GitHub."
  value       = <<-EOT
    gh variable set AWS_REGION       --repo ${var.github_repo} --body "${var.region}"
    gh variable set TF_STATE_BUCKET  --repo ${var.github_repo} --body "${aws_s3_bucket.tfstate.bucket}"
    gh variable set TF_ROLE_ARN      --repo ${var.github_repo} --body "${aws_iam_role.terraform.arn}"
    gh variable set APP_ROLE_ARN     --repo ${var.github_repo} --body "${aws_iam_role.app.arn}"
  EOT
}
