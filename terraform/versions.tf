terraform {
  required_version = ">= 1.10"

  required_providers {
    aws = {
      source  = "hashicorp/aws"
      version = "~> 6.0"
    }
  }

  # State remoto en S3 (creado por terraform/bootstrap).
  # "bucket" y "region" NO van aqui: un bloque backend no admite variables, asi
  # que se pasan al inicializar con  -backend-config  (lo hace el pipeline).
  backend "s3" {
    key          = "triple-pipeline/terraform.tfstate"
    encrypt      = true
    use_lockfile = true # bloqueo nativo en S3: evita dos "apply" simultaneos
  }
}

provider "aws" {
  region = var.region

  # Etiquetas automaticas en TODO recurso: sirven para rastrear costos y duenos.
  default_tags {
    tags = {
      Project   = var.project_name
      ManagedBy = "terraform"
    }
  }
}
