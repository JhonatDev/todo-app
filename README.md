# ToDo App

Aplicação de lista de tarefas utilizada como base do projeto de infraestrutura em nuvem (Docker, Terraform, Ansible e CI/CD).

A aplicação permite cadastrar, listar, concluir, reabrir e excluir tarefas. Consulte também o [escopo em PDF](escopo.pdf) ou a [versão editável](docs/escopo.md) com os requisitos arquiteturais, operacionais e critérios de aceite.

---

## Executar localmente

Pré-requisitos: Git, Docker Engine e Docker Compose v2. No Windows, execute o Docker Desktop com containers Linux antes de iniciar.

1. Crie o arquivo `.env` a partir do modelo de exemplo (não versionado):

   ```bash
   cp .env.example .env
   ```

2. Edite o `.env` definindo senhas locais para `MONGO_INITDB_ROOT_PASSWORD` e `MONGO_APP_PASSWORD` (por padrão, o ambiente local usa `FRONTEND_PORT=8080` para evitar conflito caso a porta `80` do host já esteja em uso).

3. Construa as imagens e inicie os serviços:

   ```bash
   docker compose up --build -d
   ```

4. Confira o status (`healthy`) e acompanhe os logs:

   ```bash
   docker compose ps
   docker compose logs -f
   ```

5. Acesse a aplicação em **http://localhost:8080**:
   - **Interface React:** `http://localhost:8080/`
   - **API (via proxy reverso Nginx):** `http://localhost:8080/todos`
   - **Health check (API + MongoDB):** `http://localhost:8080/health`

6. Para parar os serviços preservando os dados no volume `mongo_data`:

   ```bash
   docker compose down
   ```

---

## Fluxo e Estrutura Atual

```text
Navegador ──► Nginx (:8080 -> :80)
                ├── /        ──► Frontend React (arquivos estáticos)
                ├── /todos*  ──► Proxy reverso -> Backend Express (:5000)
                └── /health  ──► Proxy reverso -> Backend Express (:5000/health)
                                                     │
                                      (rede interna todo-net :27017)
                                                     ▼
                                              MongoDB (volume mongo_data)
```

- `frontend/`: interface React compilada e servida pelo Nginx com template de proxy reverso (`frontend/nginx.conf.template`).
- `backend/`: API Node.js com Express e Mongoose, configurada por variáveis de ambiente e endpoint `/health`.
- `banco-de-dados/`: imagem MongoDB (`mongo:9.0.8`) e script `init-mongo.js` com criação de usuário dedicado e carga inicial.
- `docker-compose.yaml`: orquestração local com volume nomeado `mongo_data`, health checks e isolamento das portas `5000` e `27017`.
- `deploy/`: arquivos Compose separados para implantação em duas VMs na nuvem (`docker-compose.app.yml` e `docker-compose.db.yml`).
- `terraform/`: infraestrutura como código na AWS (VPC, sub-redes, Security Groups, 2 instâncias EC2, EBS persistente e outputs para o Ansible).
- `.env.example`: modelo de variáveis de ambiente sem credenciais reais.
- `DIAGNOSTICO.md`: levantamento inicial do repositório e lacunas para nuvem.
- `TESTE-LOCAL.md`: registro dos testes locais executados antes e depois da adaptação.
- `ARQUITETURA.md`: desenho da arquitetura na AWS (`sa-east-1`), firewall, HTTPS, backup/restauração e estimativa de custos.

---

## Alterações Realizadas até a Fase 5

### Fase 1 — Diagnóstico do Repositório
- Mapeamento completo dos serviços, portas, imagens Docker, volumes, variáveis de ambiente, fluxo de rede e pontos de acoplamento para implantação em nuvem registrado em [DIAGNOSTICO.md](DIAGNOSTICO.md).

### Fase 2 — Teste Local da Base Original
- Validação inicial com Docker Compose identificando conflito local na porta `80`, perda de dados após `docker compose down && docker compose up -d` (ausência de volume persistente) e avisos de opções depreciadas. Resultados documentados em [TESTE-LOCAL.md](TESTE-LOCAL.md).

### Fase 3 — Adaptação da Aplicação para Nuvem
1. **Remoção de `localhost:5000` no Frontend ([frontend/src/App.js](frontend/src/App.js)):**
   - Chamadas Axios passaram a usar `REACT_APP_API_URL` com fallback para caminho relativo `/todos`.
2. **Proxy reverso no Nginx ([frontend/nginx.conf.template](frontend/nginx.conf.template) e [frontend/Dockerfile](frontend/Dockerfile)):**
   - Encaminhamento de `/todos` e `/health` para o serviço `backend`, permitindo expor interface e API no mesmo endereço público.
   - Imagens fixadas em `node:18.20.8-alpine` e `nginx:1.31.10-alpine`, build com `npm ci` e adição de `HEALTHCHECK`.
3. **Parametrização e saúde do Backend ([backend/index.js](backend/index.js) e [backend/Dockerfile](backend/Dockerfile)):**
   - Configuração de `PORT`, `MONGODB_URI` (ou `MONGO_HOST`, `MONGO_PORT`, `MONGO_DB`, `MONGO_USER`, `MONGO_PASSWORD`, `MONGO_AUTH_SOURCE`) e `CORS_ORIGIN` via variáveis de ambiente.
   - Adição do endpoint `GET /health` verificando conexão e ping no MongoDB, além de reconexão automática (`connectWithRetry`).
   - Remoção das opções depreciadas do Mongoose 8 (`useNewUrlParser`, `useUnifiedTopology`).
   - Imagem fixada em `node:18.20.8-alpine`, `npm ci --omit=dev` e `HEALTHCHECK`.
4. **Banco de Dados e Menor Privilégio ([banco-de-dados/Dockerfile](banco-de-dados/Dockerfile) e [banco-de-dados/init-mongo.js](banco-de-dados/init-mongo.js)):**
   - Substituição de `mongo:latest` pela versão fixa `mongo:9.0.8` e adição de `HEALTHCHECK`.
   - Criação idempotente do usuário dedicado da aplicação (`MONGO_APP_USER` / `MONGO_APP_PASSWORD`) com permissão `readWrite` apenas no banco `todo-app`.
5. **Persistência, Isolamento e Preparação para 2 VMs ([docker-compose.yaml](docker-compose.yaml), [deploy/](deploy/)):**
   - Inclusão do volume nomeado `mongo_data`, `restart: unless-stopped`, `depends_on` com `condition: service_healthy` e remoção da publicação pública das portas `5000` e `27017` no ambiente local.
   - Separação da topologia de nuvem em `deploy/docker-compose.app.yml` (VM 1: frontend + backend) e `deploy/docker-compose.db.yml` (VM 2: MongoDB exclusivo vinculado ao IP privado).
6. **Proteção de Segredos ([.env.example](.env.example) e [.gitignore](.gitignore)):**
   - Criação do `.env.example` sem credenciais reais e ampliação do `.gitignore` para proteger `.env`, arquivos de estado/variáveis do Terraform, chaves SSH, segredos e inventário dinâmico do Ansible.

### Fase 4 — Desenho da Infraestrutura na AWS
- Definição da topologia de duas VMs na região `sa-east-1` (`ARQUITETURA.md`), regras de Security Groups isolando o MongoDB na rede privada, estratégia de persistência (EBS `gp3`), backup/restauração, HTTPS com `sslip.io`/DuckDNS + Let's Encrypt e estimativa de custos em [ARQUITETURA.md](ARQUITETURA.md).

### Fase 5 — Provisionamento com Terraform
- Criação dos arquivos em [terraform/](terraform/) (`versions.tf`, `providers.tf`, `variables.tf`, `main.tf`, `outputs.tf`, `terraform.tfvars.example` e `README.md`) para provisionar VPC, sub-redes, Internet Gateway, Security Groups, duas EC2, volume EBS dedicado e outputs estruturados para o Ansible, validado localmente com `terraform fmt -check`, `terraform init` e `terraform validate`.
