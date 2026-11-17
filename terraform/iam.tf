# ----------------------------------------------------------------------------
# ROLES IAM DE ECS  (dos roles distintos, con propositos distintos)
#
#  - Execution role: lo usa ECS/Fargate (la "infraestructura") ANTES y
#    ALREDEDOR de tu contenedor: descargar la imagen de ECR y escribir logs.
#  - Task role:      lo usa TU CODIGO dentro del contenedor para llamar a AWS.
#                    Nuestra app no llama a AWS, asi que no tiene permisos.
# ----------------------------------------------------------------------------

data "aws_iam_policy_document" "ecs_tasks_assume" {
  statement {
    actions = ["sts:AssumeRole"]
    principals {
      type        = "Service"
      identifiers = ["ecs-tasks.amazonaws.com"]
    }
  }
}

resource "aws_iam_role" "ecs_exec" {
  name               = "${var.project_name}-ecs-exec"
  assume_role_policy = data.aws_iam_policy_document.ecs_tasks_assume.json
}

# Politica administrada por AWS: pull de ECR + CreateLogStream/PutLogEvents.
resource "aws_iam_role_policy_attachment" "ecs_exec" {
  role       = aws_iam_role.ecs_exec.name
  policy_arn = "arn:aws:iam::aws:policy/service-role/AmazonECSTaskExecutionRolePolicy"
}

resource "aws_iam_role" "ecs_task" {
  name               = "${var.project_name}-ecs-task"
  assume_role_policy = data.aws_iam_policy_document.ecs_tasks_assume.json
}
