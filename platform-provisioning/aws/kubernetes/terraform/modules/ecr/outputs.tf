output "repository_urls" {
  description = "Map of repository names to their URLs"
  value = {
    for k, v in aws_ecr_repository.repositories :
    k => v.repository_url
  }
}

output "repository_arns" {
  description = "Map of repository names to their ARNs"
  value = {
    for k, v in aws_ecr_repository.repositories :
    k => v.arn
  }
}

output "registry_id" {
  description = "Registry ID where repositories are created"
  value       = try(values(aws_ecr_repository.repositories)[0].registry_id, null)
}
