output "app_url" {
  description = "URL publica de la aplicacion (a traves del ALB)."
  value       = "http://${aws_lb.main.dns_name}"
}

output "alb_dns_name" {
  value = aws_lb.main.dns_name
}

output "cluster_name" {
  value = aws_ecs_cluster.main.name
}

output "service_names" {
  value = { for k, s in aws_ecs_service.app : k => s.name }
}

output "ecr_repository_urls" {
  value = { for k, r in aws_ecr_repository.app : k => r.repository_url }
}
