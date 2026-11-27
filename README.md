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

## Entrega PM-04 na AWS

- [Arquitetura, decisões e estimativa](ARQUITETURA.md)
- [Manual de preparação, pipeline, operação e evidências](docs/operacao-pm04.md)
- [Terraform e estado da infraestrutura](terraform/README.md)
- [Ansible para configuração e manutenção](ansible/deploy.yml)
- [Workflow de infraestrutura](.github/workflows/infra.yml) e [workflow de aplicação](.github/workflows/app.yml)
