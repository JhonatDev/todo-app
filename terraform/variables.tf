variable "project_name" {
  description = "Nome do projeto utilizado como prefixo e tag nos recursos"
  type        = string
  default     = "todo-app"
}

variable "environment" {
  description = "Ambiente de implantação (dev, homolog, prod)"
  type        = string
  default     = "dev"

  validation {
    condition     = contains(["dev", "homolog", "prod"], var.environment)
    error_message = "O valor de environment deve ser dev, homolog ou prod."
  }
}

variable "region" {
  description = "Região da AWS onde os recursos serão provisionados"
  type        = string
  default     = "sa-east-1"
}

variable "app_vm_name" {
  description = "Nome da VM da aplicação (Nginx + Frontend + API)"
  type        = string
  default     = ""
}

variable "db_vm_name" {
  description = "Nome da VM exclusiva do banco de dados MongoDB"
  type        = string
  default     = ""
}

variable "instance_type" {
  description = "Tipo padrão da instância EC2 para aplicação e banco (pode ser sobrescrito individualmente)"
  type        = string
  default     = "t3.micro"
}

variable "app_instance_type" {
  description = "Tipo da instância EC2 da VM da aplicação (usa instance_type se vazio)"
  type        = string
  default     = ""
}

variable "db_instance_type" {
  description = "Tipo da instância EC2 da VM do MongoDB (usa instance_type se vazio)"
  type        = string
  default     = ""
}

variable "os_image_ami" {
  description = "ID específico de AMI (opcional; se vazio, busca Ubuntu 24.04 LTS automaticamente)"
  type        = string
  default     = ""
}

variable "ssh_user" {
  description = "Usuário padrão de acesso SSH da imagem selecionada"
  type        = string
  default     = "ubuntu"
}

variable "root_volume_size" {
  description = "Tamanho em GB do disco raiz (sistema operacional) de cada VM"
  type        = number
  default     = 20
}

variable "db_volume_size" {
  description = "Tamanho em GB do volume EBS persistente dedicado aos dados do MongoDB"
  type        = number
  default     = 20

  validation {
    condition     = var.db_volume_size >= 10 && var.db_volume_size <= 500
    error_message = "db_volume_size deve estar entre 10 e 500 GB."
  }
}

variable "vpc_cidr" {
  description = "Bloco CIDR da VPC"
  type        = string
  default     = "10.0.0.0/16"
}

variable "public_subnet_cidr" {
  description = "Bloco CIDR da sub-rede da VM de aplicação"
  type        = string
  default     = "10.0.1.0/24"
}

variable "db_subnet_cidr" {
  description = "Bloco CIDR da sub-rede da VM do banco de dados"
  type        = string
  default     = "10.0.2.0/24"
}

variable "db_associate_public_ip" {
  description = "Atribui IP público administrativo à VM do banco para SSH/Ansible sem NAT Gateway (porta 27017 nunca é aberta na internet)"
  type        = bool
  default     = true
}

variable "admin_cidr" {
  description = "CIDR de origem permitido para acesso SSH administrativo (ex.: 203.0.113.10/32)"
  type        = string
}

variable "ssh_key_name" {
  description = "Nome do Key Pair na AWS"
  type        = string
  default     = "todo-app-key"
}

variable "ssh_public_key" {
  description = "Conteúdo da chave pública SSH para criação do Key Pair (se vazio, utiliza um Key Pair já existente com ssh_key_name)"
  type        = string
  default     = ""
}

