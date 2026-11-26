# Infraestrutura Terraform — ToDo App (AWS)

Este diretório contém a definição da infraestrutura em nuvem na **AWS** (região padrão `sa-east-1`) para hospedar o ToDo App em **duas máquinas virtuais**:

- **VM 1 (`app`):** Nginx (proxy HTTPS + frontend React) e API Node.js/Express.
- **VM 2 (`db`):** MongoDB exclusivo com volume EBS dedicado (`gp3` criptografado) e porta `27017` acessível apenas pela VM 1 na rede privada da VPC.

## Arquivos

- `versions.tf`: versões mínimas do Terraform (`>= 1.6.0`) e provider `hashicorp/aws` (`~> 5.0`).
- `providers.tf`: configuração do provider AWS e tags padrão (`Project`, `Environment`, `ManagedBy`).
- `variables.tf`: variáveis parametrizáveis (ambiente, região, nomes e tipos das VMs, imagem, volume, CIDRs, IP administrativo e chave SSH).
- `main.tf`: VPC, Internet Gateway, sub-redes, tabelas de rota, Security Groups, Key Pair, 2 instâncias EC2 e volume EBS dedicado para o MongoDB.
- `outputs.tf`: IPs públicos/privados, domínio sugerido (`sslip.io`), nomes/IDs dos recursos e bloco `ansible_inventory_data`.
- `terraform.tfvars.example`: modelo de variáveis sem credenciais.

## Pré-requisitos

- Terraform `>= 1.6.0` instalado.
- Credenciais AWS configuradas via variáveis de ambiente (`AWS_ACCESS_KEY_ID`, `AWS_SECRET_ACCESS_KEY`, e `AWS_SESSION_TOKEN` caso utilize sessão temporária), nunca no código.
- Par de chaves SSH local (`~/.ssh/id_ed25519` e `.pub`) ou Key Pair existente na conta AWS.

## Fluxo de Execução

1. Crie o arquivo de variáveis local (ignorado pelo Git):

   ```bash
   cd terraform
   cp terraform.tfvars.example terraform.tfvars
   ```

2. Preencha `admin_cidr` com seu IP público (`/32`) e informe `ssh_public_key` (ou nome de Key Pair existente).

3. Verifique formatação, inicialize e valide antes de planejar:

   ```bash
   terraform fmt -check
   terraform init
   terraform validate
   terraform plan
   ```

4. Aplique somente após revisar o plano:

   ```bash
   terraform apply
   ```

5. Para encerrar todos os recursos provisionados e evitar cobranças:

   ```bash
   terraform destroy
   ```

## Observação sobre State Remoto

Para execução em equipe e pipelines no GitHub Actions, recomenda-se configurar um backend remoto (ex.: bucket S3 + bloqueio de estado) em `backend.tf` antes de compartilhar execuções entre máquinas diferentes. O arquivo local `terraform.tfstate` é protegido pelo `.gitignore` e não deve ser versionado.

