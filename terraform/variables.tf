variable "region" {
  description = "Region de AWS."
  type        = string
  default     = "us-east-1"
}

variable "project_name" {
  description = "Prefijo de nombres. Debe coincidir con PROJECT_NAME en los workflows y con terraform/bootstrap."
  type        = string
  default     = "triple-pipeline"
}

variable "vpc_cidr" {
  description = "Rango de IPs privadas de la VPC."
  type        = string
  default     = "10.0.0.0/16"
}

variable "az_count" {
  description = "Cantidad de zonas de disponibilidad. El ALB exige minimo 2."
  type        = number
  default     = 2
}

variable "frontend_port" {
  description = "Puerto del contenedor frontend (nginx)."
  type        = number
  default     = 80
}

variable "backend_port" {
  description = "Puerto del contenedor backend (Node)."
  type        = number
  default     = 3000
}

variable "task_cpu" {
  description = "CPU por tarea Fargate (256 = 0.25 vCPU, el minimo)."
  type        = number
  default     = 256
}

variable "task_memory" {
  description = "Memoria por tarea Fargate en MiB (512 es el minimo para 256 de CPU)."
  type        = number
  default     = 512
}

variable "initial_desired_count" {
  description = "Tareas al crear el servicio. 0 porque aun no existe ninguna imagen en ECR; el Pipeline 3 lo sube a 1."
  type        = number
  default     = 0
}

variable "log_retention_days" {
  description = "Dias que CloudWatch conserva los logs (menos dias = menos costo)."
  type        = number
  default     = 7
}

# Definicion central de los dos componentes. Todo lo demas (repos ECR, target
# groups, servicios, logs) se genera con for_each sobre este mapa, asi
# frontend y backend se tratan igual y no se duplica codigo.
locals {
  services = {
    frontend = {
      port        = var.frontend_port
      health_path = "/"
    }
    backend = {
      port        = var.backend_port
      health_path = "/api/health"
    }
  }

  # Variables de entorno de cada contenedor.
  service_env = {
    frontend = {
      APP_ENV = "aws"
    }
    backend = {
      APP_ENV = "aws"
      PORT    = tostring(var.backend_port)
    }
  }
}
