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

data "aws_ami" "ubuntu" {
  count       = var.os_image_ami == "" ? 1 : 0
  most_recent = true
  owners      = ["099720109477"] # Canonical

  filter {
    name   = "name"
    values = ["ubuntu/images/hvm-ssd-gp3/ubuntu-noble-24.04-amd64-server-*"]
  }

  filter {
    name   = "virtualization-type"
    values = ["hvm"]
  }
}

locals {
  selected_ami = var.os_image_ami != "" ? var.os_image_ami : data.aws_ami.ubuntu[0].id
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
  map_public_ip_on_launch = var.db_associate_public_ip

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

resource "aws_route_table_association" "db" {
  count          = var.db_associate_public_ip ? 1 : 0
  subnet_id      = aws_subnet.db.id
  route_table_id = aws_route_table.public.id
}

# --- Regras de Acesso (Security Groups) ---

resource "aws_security_group" "app" {
  name        = "${local.name_prefix}-sg-app"
  description = "Permite HTTP/HTTPS publicos e SSH administrativo para a VM da aplicacao"
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

  ingress {
    description = "SSH administrativo restrito"
    from_port   = 22
    to_port     = 22
    protocol    = "tcp"
    cidr_blocks = [var.admin_cidr]
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
  description = "Permite MongoDB (27017) exclusivamente da VM da aplicacao pela rede privada e SSH restrito"
  vpc_id      = aws_vpc.main.id

  ingress {
    description     = "MongoDB acessivel apenas pela VM da aplicacao"
    from_port       = 27017
    to_port         = 27017
    protocol        = "tcp"
    security_groups = [aws_security_group.app.id]
  }

  ingress {
    description = "SSH administrativo restrito"
    from_port   = 22
    to_port     = 22
    protocol    = "tcp"
    cidr_blocks = [var.admin_cidr]
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
  ami                         = local.selected_ami
  instance_type               = local.app_instance_type
  subnet_id                   = aws_subnet.app.id
  vpc_security_group_ids      = [aws_security_group.app.id]
  key_name                    = local.effective_key
  associate_public_ip_address = true

  root_block_device {
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
  ami                         = local.selected_ami
  instance_type               = local.db_instance_type
  subnet_id                   = aws_subnet.db.id
  vpc_security_group_ids      = [aws_security_group.db.id]
  key_name                    = local.effective_key
  associate_public_ip_address = var.db_associate_public_ip

  root_block_device {
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

