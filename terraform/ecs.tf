# ----------------------------------------------------------------------------
# ECS + FARGATE
#
#   Cluster         = agrupacion logica de servicios
#   Task definition = "receta" inmutable: imagen, CPU, memoria, puertos, logs, roles
#   Service         = mantiene N tareas corriendo, las registra en el ALB y
#                     reemplaza las que fallan
#   Fargate         = AWS pone los servidores; tu solo defines CPU y memoria
# ----------------------------------------------------------------------------

resource "aws_ecs_cluster" "main" {
  name = "${var.project_name}-cluster"
}

resource "aws_cloudwatch_log_group" "app" {
  for_each = local.services

  name              = "/ecs/${var.project_name}/${each.key}"
  retention_in_days = var.log_retention_days
}

resource "aws_ecs_task_definition" "app" {
  for_each = local.services

  family                   = "${var.project_name}-${each.key}"
  requires_compatibilities = ["FARGATE"]
  network_mode             = "awsvpc" # cada tarea recibe su propia interfaz de red e IP
  cpu                      = var.task_cpu
  memory                   = var.task_memory
  execution_role_arn       = aws_iam_role.ecs_exec.arn
  task_role_arn            = aws_iam_role.ecs_task.arn

  runtime_platform {
    operating_system_family = "LINUX"
    cpu_architecture        = "X86_64" # debe coincidir con la arquitectura con la que se construye la imagen
  }

  container_definitions = jsonencode([{
    name      = each.key
    essential = true

    # ":bootstrap" es un marcador: esa imagen aun no existe. Esta revision
    # inicial nunca se ejecuta (desired_count = 0). El Pipeline 3 registra
    # nuevas revisiones con el tag real (el SHA del commit).
    image = "${aws_ecr_repository.app[each.key].repository_url}:bootstrap"

    portMappings = [{
      containerPort = each.value.port
      protocol      = "tcp"
    }]

    environment = [for k, v in local.service_env[each.key] : { name = k, value = v }]

    logConfiguration = {
      logDriver = "awslogs"
      options = {
        "awslogs-group"         = aws_cloudwatch_log_group.app[each.key].name
        "awslogs-region"        = var.region
        "awslogs-stream-prefix" = "ecs"
      }
    }
  }])
}

resource "aws_ecs_service" "app" {
  for_each = local.services

  name            = "${var.project_name}-${each.key}"
  cluster         = aws_ecs_cluster.main.id
  task_definition = aws_ecs_task_definition.app[each.key].arn
  desired_count   = var.initial_desired_count
  launch_type     = "FARGATE"

  health_check_grace_period_seconds = 30 # tiempo de gracia antes de juzgar la salud al arrancar

  # Si un despliegue nuevo no logra estabilizarse, ECS lo detiene y vuelve
  # solo a la version anterior (rollback automatico).
  deployment_circuit_breaker {
    enable   = true
    rollback = true
  }

  network_configuration {
    subnets          = aws_subnet.public[*].id
    security_groups  = [aws_security_group.ecs.id]
    assign_public_ip = true # necesario sin NAT para llegar a ECR
  }

  load_balancer {
    target_group_arn = aws_lb_target_group.app[each.key].arn
    container_name   = each.key
    container_port   = each.value.port
  }

  # El listener debe existir antes de que el servicio se registre en el ALB.
  depends_on = [aws_lb_listener.http, aws_lb_listener_rule.api]

  # Terraform es dueno de la INFRAESTRUCTURA; el Pipeline 3 es dueno de la
  # VERSION desplegada. Sin esto, cada "terraform apply" revertiria el
  # despliegue a la imagen marcador.
  lifecycle {
    ignore_changes = [task_definition, desired_count]
  }
}
