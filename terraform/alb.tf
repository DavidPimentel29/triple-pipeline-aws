# ----------------------------------------------------------------------------
# APPLICATION LOAD BALANCER: unica puerta de entrada publica.
#
#   http://<alb-dns>/        --> target group "frontend" (nginx)
#   http://<alb-dns>/api/*   --> target group "backend"  (Node)
#
# Con ruteo por ruta, el navegador ve UN solo origen: el frontend llama a
# "/api/..." sin CORS ni URLs del backend escritas en el codigo.
# ----------------------------------------------------------------------------

resource "aws_lb" "main" {
  name               = "${var.project_name}-alb"
  load_balancer_type = "application"
  internal           = false
  security_groups    = [aws_security_group.alb.id]
  subnets            = aws_subnet.public[*].id # minimo 2 AZ distintas
}

# Target group = lista de destinos que reciben trafico + como comprobar su salud.
# target_type "ip" es obligatorio con Fargate (cada tarea tiene su propia IP).
resource "aws_lb_target_group" "app" {
  for_each = local.services

  name        = "${var.project_name}-${each.key}"
  port        = each.value.port
  protocol    = "HTTP"
  target_type = "ip"
  vpc_id      = aws_vpc.main.id

  deregistration_delay = 30 # despliegues mas rapidos (por defecto son 300 s)

  health_check {
    path                = each.value.health_path
    matcher             = "200"
    interval            = 15
    timeout             = 5
    healthy_threshold   = 2
    unhealthy_threshold = 3
  }
}

resource "aws_lb_listener" "http" {
  load_balancer_arn = aws_lb.main.arn
  port              = 80
  protocol          = "HTTP"

  # Por defecto, todo va al frontend.
  default_action {
    type             = "forward"
    target_group_arn = aws_lb_target_group.app["frontend"].arn
  }
}

# Excepcion: lo que empiece con /api/ va al backend.
resource "aws_lb_listener_rule" "api" {
  listener_arn = aws_lb_listener.http.arn
  priority     = 10

  action {
    type             = "forward"
    target_group_arn = aws_lb_target_group.app["backend"].arn
  }

  condition {
    path_pattern {
      values = ["/api/*"]
    }
  }
}
