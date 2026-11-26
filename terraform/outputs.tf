output "app_public_ip" {
  description = "IP público da VM da aplicação"
  value       = aws_instance.app.public_ip
}

output "app_private_ip" {
  description = "IP privado da VM da aplicação na VPC"
  value       = aws_instance.app.private_ip
}

output "db_private_ip" {
  description = "IP privado da VM do MongoDB na VPC"
  value       = aws_instance.db.private_ip
}

output "db_public_ip" {
  description = "IP público administrativo da VM do banco (se habilitado; porta 27017 bloqueada)"
  value       = aws_instance.db.public_ip
}

output "suggested_https_domain" {
  description = "Subdomínio dinâmico gratuito (sslip.io) apontando para o IP público da aplicação"
  value       = "${replace(aws_instance.app.public_ip, ".", "-")}.sslip.io"
}

output "app_url_https" {
  description = "URL HTTPS sugerida após configuração do certificado Let's Encrypt"
  value       = "https://${replace(aws_instance.app.public_ip, ".", "-")}.sslip.io"
}

output "resource_names" {
  description = "Nomes e identificadores dos recursos provisionados"
  value = {
    vpc_id                = aws_vpc.main.id
    app_subnet_id         = aws_subnet.app.id
    db_subnet_id          = aws_subnet.db.id
    app_security_group_id = aws_security_group.app.id
    db_security_group_id  = aws_security_group.db.id
    app_instance_id       = aws_instance.app.id
    app_instance_name     = aws_instance.app.tags["Name"]
    db_instance_id        = aws_instance.db.id
    db_instance_name      = aws_instance.db.tags["Name"]
    db_volume_id          = aws_ebs_volume.mongo_data.id
    ami_id                = local.selected_ami
  }
}

output "ansible_inventory_data" {
  description = "Dados estruturados para geração automática do inventário do Ansible"
  value = {
    ssh_user       = var.ssh_user
    app_host       = aws_instance.app.public_ip
    app_private_ip = aws_instance.app.private_ip
    db_host        = var.db_associate_public_ip ? aws_instance.db.public_ip : aws_instance.db.private_ip
    db_private_ip  = aws_instance.db.private_ip
    db_device      = "/dev/sdf"
  }
}

