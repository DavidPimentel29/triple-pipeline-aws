# ----------------------------------------------------------------------------
# ECR: registro privado de imagenes Docker (un repositorio por componente).
# ----------------------------------------------------------------------------

resource "aws_ecr_repository" "app" {
  for_each = local.services

  name = "${var.project_name}-${each.key}"

  # IMMUTABLE: un tag ya publicado no se puede sobrescribir. Usamos el SHA del
  # commit como tag, asi "imagen X" siempre significa "codigo del commit X".
  image_tag_mutability = "IMMUTABLE"

  # Permite borrar el repo con imagenes dentro al hacer terraform destroy.
  force_delete = true

  image_scanning_configuration {
    scan_on_push = true # escaneo basico de vulnerabilidades en cada push
  }

  encryption_configuration {
    encryption_type = "AES256"
  }
}

# Evita acumular imagenes (el almacenamiento se cobra por GB).
resource "aws_ecr_lifecycle_policy" "app" {
  for_each = aws_ecr_repository.app

  repository = each.value.name
  policy = jsonencode({
    rules = [{
      rulePriority = 1
      description  = "Conservar solo las ultimas 10 imagenes"
      selection = {
        tagStatus   = "any"
        countType   = "imageCountMoreThan"
        countNumber = 10
      }
      action = { type = "expire" }
    }]
  })
}
