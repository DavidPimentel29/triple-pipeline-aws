# ----------------------------------------------------------------------------
# SECURITY GROUPS: firewall "con estado" a nivel de interfaz de red.
#
# Cadena de confianza:   Internet --80--> ALB --puerto de la app--> Tareas ECS
# Las tareas NO aceptan trafico de Internet; solo del Security Group del ALB.
# ----------------------------------------------------------------------------

resource "aws_security_group" "alb" {
  name        = "${var.project_name}-alb-sg"
  description = "Trafico HTTP desde Internet hacia el ALB"
  vpc_id      = aws_vpc.main.id

  tags = { Name = "${var.project_name}-alb-sg" }
}

resource "aws_vpc_security_group_ingress_rule" "alb_http" {
  security_group_id = aws_security_group.alb.id
  description       = "HTTP desde cualquier lugar"
  cidr_ipv4         = "0.0.0.0/0"
  from_port         = 80
  to_port           = 80
  ip_protocol       = "tcp"
}

resource "aws_vpc_security_group_egress_rule" "alb_all" {
  security_group_id = aws_security_group.alb.id
  description       = "El ALB puede hablar con las tareas"
  cidr_ipv4         = "0.0.0.0/0"
  ip_protocol       = "-1"
}

resource "aws_security_group" "ecs" {
  name        = "${var.project_name}-ecs-sg"
  description = "Tareas ECS: solo aceptan trafico del ALB"
  vpc_id      = aws_vpc.main.id

  tags = { Name = "${var.project_name}-ecs-sg" }
}

# Una regla de entrada por servicio, y el ORIGEN es otro Security Group
# (el del ALB), no un rango de IPs. Asi sigue funcionando aunque cambien las IPs.
resource "aws_vpc_security_group_ingress_rule" "ecs_from_alb" {
  for_each = local.services

  security_group_id            = aws_security_group.ecs.id
  description                  = "${each.key} desde el ALB"
  referenced_security_group_id = aws_security_group.alb.id
  from_port                    = each.value.port
  to_port                      = each.value.port
  ip_protocol                  = "tcp"
}

# Salida libre: las tareas necesitan llegar a ECR y CloudWatch (endpoints publicos).
resource "aws_vpc_security_group_egress_rule" "ecs_all" {
  security_group_id = aws_security_group.ecs.id
  description       = "Salida a Internet (ECR, CloudWatch Logs)"
  cidr_ipv4         = "0.0.0.0/0"
  ip_protocol       = "-1"
}
