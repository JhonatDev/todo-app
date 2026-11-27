# Terraform da entrega PM-04

O diretório provisiona uma VPC, EC2 da aplicação com Elastic IP, EC2 privada do banco, NAT zonal, acesso administrativo por SSM e EBS dedicado. Os outputs alimentam o inventário do Ansible.

O estado é remoto, criptografado e isolado por ambiente em um bucket S3 versionado. O Terraform 1.12.2 usa o arquivo de bloqueio S3. A preparação inicial da conta, a configuração dos ambientes GitHub e os comandos de operação estão no [manual](../docs/operacao-pm04.md).

Para validação estática local:

```bash
terraform -chdir=terraform fmt -check
terraform -chdir=terraform init -backend=false
terraform -chdir=terraform validate
```

Para consultar ou recuperar o estado, o operador AWS autorizado deve suspender as execuções do ambiente, localizar a chave 'pm04/<ambiente>/terraform.tfstate' e revisar o histórico de versões do bucket. Preserve a versão atual antes de promover uma versão anterior. Rode o workflow em modo 'plan' e confira o resultado antes de voltar a aplicar mudanças. Investigue o dono de qualquer bloqueio ativo antes de tentar liberá-lo.
