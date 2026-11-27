locals {
  name_prefix       = "${var.project_name}-${var.environment}"
  app_vm_final_name = var.app_vm_name != "" ? var.app_vm_name : "${local.name_prefix}-app"
  db_vm_final_name  = var.db_vm_name != "" ? var.db_vm_name : "${local.name_prefix}-db"
  app_instance_type = var.app_instance_type != "" ? var.app_instance_type : var.instance_type
  db_instance_type  = var.db_instance_type != "" ? var.db_instance_type : var.instance_type
  effective_key     = var.ssh_public_key != "" ? aws_key_pair.deployer[0].key_name : var.ssh_key_name
}

data "aws_availability_zones" "available" {
  state = "available"
}

# --- Chave SSH ---

resource "aws_key_pair" "deployer" {
  count      = var.ssh_public_key != "" ? 1 : 0
  key_name   = "${local.name_prefix}-${var.ssh_key_name}"
  public_key = var.ssh_public_key

  tags = {
    Name = "${local.name_prefix}-${var.ssh_key_name}"
  }
}

# --- Rede (VPC, Sub-redes, Internet Gateway e Rotas) ---

resource "aws_vpc" "main" {
  cidr_block           = var.vpc_cidr
  enable_dns_support   = true
  enable_dns_hostnames = true

  tags = {
    Name = "${local.name_prefix}-vpc"
  }
}

resource "aws_internet_gateway" "main" {
  vpc_id = aws_vpc.main.id

  tags = {
    Name = "${local.name_prefix}-igw"
  }
}

resource "aws_subnet" "app" {
  vpc_id                  = aws_vpc.main.id
  cidr_block              = var.public_subnet_cidr
  availability_zone       = data.aws_availability_zones.available.names[0]
  map_public_ip_on_launch = true

  tags = {
    Name = "${local.name_prefix}-subnet-app"
    Tier = "public"
  }
}

resource "aws_subnet" "db" {
  vpc_id                  = aws_vpc.main.id
  cidr_block              = var.db_subnet_cidr
  availability_zone       = data.aws_availability_zones.available.names[0]
  map_public_ip_on_launch = false

  tags = {
    Name = "${local.name_prefix}-subnet-db"
    Tier = "database"
  }
}

resource "aws_route_table" "public" {
  vpc_id = aws_vpc.main.id

  route {
    cidr_block = "0.0.0.0/0"
    gateway_id = aws_internet_gateway.main.id
  }

  tags = {
    Name = "${local.name_prefix}-rt-public"
  }
}

resource "aws_route_table_association" "app" {
  subnet_id      = aws_subnet.app.id
  route_table_id = aws_route_table.public.id
}

resource "aws_eip" "app" {
  domain = "vpc"

  tags = { Name = "${local.name_prefix}-app" }
}

resource "aws_eip_association" "app" {
  instance_id   = aws_instance.app.id
  allocation_id = aws_eip.app.id
}

resource "aws_eip" "nat" {
  domain = "vpc"

  tags = { Name = "${local.name_prefix}-nat" }
}

resource "aws_nat_gateway" "db" {
  allocation_id = aws_eip.nat.id
  subnet_id     = aws_subnet.app.id
  depends_on    = [aws_route_table_association.app]

  tags = { Name = "${local.name_prefix}-nat" }
}

resource "aws_route_table" "db" {
  vpc_id = aws_vpc.main.id

  route {
    cidr_block     = "0.0.0.0/0"
    nat_gateway_id = aws_nat_gateway.db.id
  }

  tags = { Name = "${local.name_prefix}-rt-db" }
}

resource "aws_route_table_association" "db" {
  subnet_id      = aws_subnet.db.id
  route_table_id = aws_route_table.db.id
}


# --- Regras de Acesso (Security Groups) ---

resource "aws_security_group" "app" {
  name        = "${local.name_prefix}-sg-app"
  description = "Permite HTTP e HTTPS publicos para a VM da aplicacao"
  vpc_id      = aws_vpc.main.id

  ingress {
    description = "HTTP publico (redirecionamento e desafio ACME)"
    from_port   = 80
    to_port     = 80
    protocol    = "tcp"
    cidr_blocks = ["0.0.0.0/0"]
  }

  ingress {
    description = "HTTPS publico da aplicacao"
    from_port   = 443
    to_port     = 443
    protocol    = "tcp"
    cidr_blocks = ["0.0.0.0/0"]
  }

  egress {
    description = "Trafego de saida necessario para atualizacoes, Docker e conexao ao MongoDB"
    from_port   = 0
    to_port     = 0
    protocol    = "-1"
    cidr_blocks = ["0.0.0.0/0"]
  }

  tags = {
    Name = "${local.name_prefix}-sg-app"
  }
}

resource "aws_security_group" "db" {
  name        = "${local.name_prefix}-sg-db"
  description = "Permite MongoDB exclusivamente da VM da aplicacao pela rede privada"
  vpc_id      = aws_vpc.main.id

  ingress {
    description     = "MongoDB acessivel apenas pela VM da aplicacao"
    from_port       = 27017
    to_port         = 27017
    protocol        = "tcp"
    security_groups = [aws_security_group.app.id]
  }

  egress {
    description = "Trafego de saida necessario para atualizacoes de sistema e Docker"
    from_port   = 0
    to_port     = 0
    protocol    = "-1"
    cidr_blocks = ["0.0.0.0/0"]
  }

  tags = {
    Name = "${local.name_prefix}-sg-db"
  }
}

# --- VM 1: Aplicação (Nginx + Frontend React + API Express) ---

resource "aws_instance" "app" {
  ami                         = var.os_image_ami
  instance_type               = local.app_instance_type
  subnet_id                   = aws_subnet.app.id
  vpc_security_group_ids      = [aws_security_group.app.id]
  key_name                    = local.effective_key
  associate_public_ip_address = false
  iam_instance_profile        = aws_iam_instance_profile.ssm.name
  user_data                   = file("${path.module}/ssm-agent.sh")
  depends_on                  = [aws_iam_role_policy_attachment.ssm, aws_route_table_association.app]

  metadata_options {
    http_tokens = "required"
  }

  root_block_device {
    encrypted             = true
    volume_size           = var.root_volume_size
    volume_type           = "gp3"
    delete_on_termination = true
  }

  tags = {
    Name = local.app_vm_final_name
    Role = "app"
  }
}

# --- VM 2: Banco de Dados Exclusivo (MongoDB) ---

resource "aws_instance" "db" {
  ami                         = var.os_image_ami
  instance_type               = local.db_instance_type
  subnet_id                   = aws_subnet.db.id
  vpc_security_group_ids      = [aws_security_group.db.id]
  key_name                    = local.effective_key
  associate_public_ip_address = false
  iam_instance_profile        = aws_iam_instance_profile.ssm.name
  user_data                   = file("${path.module}/ssm-agent.sh")
  depends_on                  = [aws_iam_role_policy_attachment.ssm, aws_route_table_association.db]

  metadata_options {
    http_tokens = "required"
  }

  root_block_device {
    encrypted             = true
    volume_size           = var.root_volume_size
    volume_type           = "gp3"
    delete_on_termination = true
  }

  tags = {
    Name = local.db_vm_final_name
    Role = "db"
  }
}

# --- Volume Persistente Dedicado para o MongoDB ---

resource "aws_ebs_volume" "mongo_data" {
  availability_zone = aws_instance.db.availability_zone
  size              = var.db_volume_size
  type              = "gp3"
  encrypted         = true

  tags = {
    Name = "${local.name_prefix}-mongo-data"
    Role = "db-storage"
  }
}

resource "aws_volume_attachment" "mongo_data" {
  device_name = "/dev/sdf"
  volume_id   = aws_ebs_volume.mongo_data.id
  instance_id = aws_instance.db.id
}

