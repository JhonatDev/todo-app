# Manual de operação · PM-04

## Preparação única

1. Use a conta AWS autorizada para a atividade. O bootstrap cria dois buckets privados S3 e uma role OIDC. A role assume identidades dos ambientes dev, homolog e prod do repositório informado. O bootstrap usa permissões EC2 na região do projeto, portanto deve ser aplicado na conta de laboratório dedicada. Use a função de administrador da conta apenas nessa preparação. Os workflows usam a role criada pelo bootstrap.
2. No shell autenticado da AWS, confira a conta e rode na raiz do repositório:

```bash
aws sts get-caller-identity
aws cloudformation deploy --region sa-east-1 --stack-name pm04-bootstrap \
  --template-file terraform/bootstrap.yml --capabilities CAPABILITY_IAM \
  --parameter-overrides GitHubRepository=JhonatDev/todo-app
aws cloudformation describe-stacks --region sa-east-1 --stack-name pm04-bootstrap \
  --query 'Stacks[0].Outputs' --output table
```

Se a conta já usa o provedor OIDC token.actions.githubusercontent.com, acrescente 'CreateOIDCProvider=false' aos parâmetros. Antes do primeiro deploy, aguarde a propagação do versionamento S3. Consulte a [arquitetura e o custo estimado](../ARQUITETURA.md) antes de provisionar.

3. No GitHub, mantenha os workflows na branch padrão. Em 'Settings → Environments', crie 'dev' para o ensaio e qualquer outro ambiente que realmente será usado. Restrinja o ambiente às branches aprovadas. Cadastre as variáveis e os segredos no ambiente correspondente.

| Tipo | Nome | Valor |
| --- | --- | --- |
| Variável | AWS_ROLE_ARN | Saída RoleArn do bootstrap |
| Variável | STATE_BUCKET | Saída StateBucketName |
| Variável | BACKUP_BUCKET | Saída BackupBucketName |
| Variável | AWS_REGION | sa-east-1 |
| Variável | UBUNTU_AMI_ID | ID fixo da AMI Ubuntu 24.04 amd64 na região |
| Variável opcional | INSTANCE_TYPE | Tipo padrão das duas VMs, começa em t3.micro |
| Variável opcional | INSTANCE_NAME | Nome base fixo das duas VMs |
| Variável opcional | EXTRA_PACKAGES | Lista, por exemplo 'git,unzip' |
| Variável opcional | APP_DOMAIN | Domínio com registro A apontando para o IP obtido no Terraform |
| Segredo | SSH_PRIVATE_KEY | Chave SSH dedicada ao ambiente, sem passphrase para uso pelo runner |
| Segredo | MONGO_ROOT_PASSWORD | Senha exclusiva, pelo menos 20 caracteres usando letras, números, '_' ou '-' |
| Segredo | MONGO_APP_PASSWORD | Segunda senha exclusiva com o mesmo formato |

Gere as senhas com 'openssl rand -hex 24'. Gere a chave com 'ssh-keygen -t ed25519 -f pm04-dev -N ""'. Guarde localmente em local protegido e cadastre apenas a chave privada como segredo. O workflow deriva a chave pública. Preserve as senhas enquanto houver dados existentes. Para rotacioná-las, atualize os usuários no MongoDB junto com os segredos, porque a imagem só cria as credenciais de inicialização em um volume vazio.

Resolva a AMI uma vez na região e guarde o ID retornado:

```bash
aws ec2 describe-images --region sa-east-1 --owners 099720109477 \
  --filters 'Name=name,Values=ubuntu/images/hvm-ssd-gp3/ubuntu-noble-24.04-amd64-server-*' \
  --query 'sort_by(Images,&CreationDate)[-1].ImageId' --output text
```

## Publicação e atualização

1. Rode 'Actions → Aplicação → Run workflow' com 'deploy_environment=none'. Confira a validação do ambiente e anote a tag 'sha-...' do resumo. O GitHub Container Registry tem três imagens para a mesma tag. Para publicar e implantar de uma vez, informe o ambiente ao rodar 'Aplicação'.
2. Rode 'Infraestrutura e operação' com 'operation=plan'. Revise o plano e confirme o ambiente. Para aplicar, rode 'deploy' com a tag. O fluxo roda Terraform, configura as VMs via Ansible e testa a URL HTTPS, a API e o isolamento da entrada pública.
3. Para atualizar infraestrutura e operação, reutilize o ambiente e passe os parâmetros desejados, como 'instance_name=todo-feira-v2' e 'extra_packages=unzip'. Para atualizar as imagens, use outra tag publicada. Use 'update_os=true' somente na janela de manutenção para aplicar atualizações do Ubuntu e eventuais reinícios.
4. Para voltar à versão anterior, rode 'deploy' com a tag anterior, preservando parâmetros de infraestrutura e o disco. Se a versão anterior do MongoDB for incompatível com o formato dos dados, mantenha a versão compatível do banco e use o backup verificado conforme o plano de recuperação. Registre a versão antes de intervir.

## Rotinas da feira

| Operação | Como usar e o que verificar |
| --- | --- |
| Saúde e logs | Rode 'diagnose' para ver contêineres, versões e logs recentes. Confira '/health' na URL HTTPS e espere 'database=connected'. Em falha de HTTPS, confira o DNS, as portas 80/443 e o estado do Caddy via SSM. |
| Reinício | Rode 'restart'. Selecione 'application' ou 'database'. Confira o healthcheck e a tarefa de demonstração que existia antes da execução. |
| Backup | Rode 'backup'; o resumo da etapa mostra a chave do arquivo no S3. Para backup diário às 03h35 de Brasília, defina a variável de repositório 'TODO_BACKUP_ENVIRONMENT' para o ambiente em uso. O agendamento funciona na branch padrão. |
| Restauração | Rode 'restore-test' com 'backup_name' ou deixe em branco para usar o mais recente. O comando restaura em um MongoDB temporário, valida a coleção e exibe a contagem. A VM principal continua servindo sua lista. |
| Preparar a lista | Rode 'reset-list' e informe 'reset-list' em 'confirm'. O workflow faz backup antes de limpar a lista compartilhada. Cadastre somente exemplos para a apresentação. |
| Desativar | Remova a variável de backup agendado, guarde as evidências e rode 'destroy' com 'confirm=destroy'. O workflow faz backup antes de remover as VMs, o NAT, os IPs e o EBS. 'destroy-sem-backup' é reservado a ambiente vazio/quebrado ou dados já salvos. Revise no console os recursos remanescentes. Buckets privados retidos continuam sujeitos à cobrança de armazenamento. |

Em caso de autorização negada, revise as variáveis do ambiente e a confiança OIDC da role. Se o Ansible não conseguir abrir o túnel, confira se as instâncias estão registradas no Session Manager e se a chave do ambiente corresponde à usada na criação. Se os contêineres não ficarem saudáveis, use 'diagnose', confira a tag no GHCR e a conexão do backend ao IP privado do banco.

## Evidências exigidas

| Teste | Parâmetros, ação e comprovação |
| --- | --- |
| Criação do zero | Em ambiente novo, execute 'deploy' com uma tag publicada. Guarde o link da execução, o inventário das duas EC2, o recap do Ansible e a URL HTTPS. |
| Atualização | Rode 'deploy' com o mesmo ambiente e tag, altere 'instance_name' e acrescente um pacote ausente em 'extra_packages'. Confirme no plano a alteração de tags e no Ansible a instalação. Registre versão e saúde da aplicação. |
| Reexecução idempotente | Repita exatamente os parâmetros anteriores. Guarde o 'No changes' do Terraform e o recap do Ansible sem alterações desnecessárias. |
| URL e persistência | Em outro dispositivo, abra a URL HTTPS, cadastre, liste, conclua, reabra e exclua uma tarefa. Deixe uma tarefa marcada, faça reinício ou atualização e recarregue para verificar dados e estado. Registre também a recriação do contêiner MongoDB com o EBS montado e verifique a mesma tarefa. |
| Isolamento e recuperação | Guarde o inventário com a VM do MongoDB sem endereço público, a verificação da porta 27017 no runner, a chave S3 do backup e o log de restauração isolada. |
| Transferência | Na apresentação, os integrantes demonstram a aplicação, consultam saúde/logs e preparam a lista usando este manual. |

Use links de execução ou trechos de logs sem segredos, URL e versões. O PDF da Blackboard reúne integrantes, análise da demanda, decisões, link do repositório e evidências. Use somente dados de demonstração.
