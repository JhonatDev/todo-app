# Diagnóstico do Repositório — ToDo App

**Data da análise:** 25/11/2026  
**Repositório:** `todo-app` (`https://github.com/LaercioMLB/todo-app.git`)  
**Objetivo:** Mapear a estrutura atual da aplicação e identificar os ajustes necessários antes de iniciar testes locais e a automação de infraestrutura em nuvem (Terraform, Ansible e CI/CD).

---

## 1. Estrutura de Diretórios Identificada

```text
.
├── .gitattributes
├── .gitignore
├── LICENSE
├── README.md
├── docker-compose.yaml
├── escopo.pdf
├── backend/
│   ├── .dockerignore
│   ├── .gitignore
│   ├── Dockerfile
│   ├── index.js
│   ├── package-lock.json
│   └── package.json
├── banco-de-dados/
│   ├── .dockerignore
│   ├── .gitignore
│   ├── Dockerfile
│   └── init-mongo.js
├── docs/
│   ├── assets/fluxo-aplicacao.pdf
│   └── escopo.md
├── frontend/
│   ├── .dockerignore
│   ├── .gitignore
│   ├── Dockerfile
│   ├── package-lock.json
│   ├── package.json
│   ├── public/
│   └── src/
│       ├── App.css
│       ├── App.js
│       ├── App.test.js
│       ├── index.css
│       ├── index.js
│       ├── reportWebVitals.js
│       └── setupTests.js
└── scripts/
    └── render-escopo.py
```

Não existem, no momento, diretórios ou arquivos de `terraform/`, `ansible/`, `.github/workflows/` ou `.env.example`.

---

## 2. Serviços Identificados

Definidos em `docker-compose.yaml` na rede bridge `todo-net` (`todo-app_todo-net`):

1. **`frontend`**:
   - Aplicação React (`react` `^19.0.0`, `react-dom` `^19.0.0`, `react-scripts` `5.0.1`, `axios` `^1.8.3`).
   - Compilada para arquivos estáticos e servida pelo Nginx.
   - `depends_on`: `backend` (apenas ordem de inicialização, sem health check).

2. **`backend`**:
   - API Node.js/Express (`express` `^4.21.2`, `mongoose` `^8.12.1`, `cors` `^2.8.5`, `body-parser` `^1.20.3`).
   - Implementada em `backend/index.js` com rotas:
     - `GET /todos` — lista todas as tarefas;
     - `POST /todos` — cria tarefa (`{ text }`);
     - `PATCH /todos/:id` — alterna campo booleano `completed`;
     - `DELETE /todos/:id` — remove tarefa pelo ID.
   - `depends_on`: `mongo` (apenas ordem de inicialização, sem health check).

3. **`mongo`** (`container_name: mongo-todo`):
   - Banco de dados MongoDB inicializado pelo script `banco-de-dados/init-mongo.js`, que cria a coleção `todos` no banco `todo-app` e insere 3 registros iniciais de demonstração.

---

## 3. Portas

| Serviço | Porta Interna (Container) | Porta Publicada (Host) | Protocolo / Uso |
| :--- | :---: | :---: | :--- |
| `frontend` (Nginx) | `80` | `80` | HTTP — entrega arquivos estáticos do React |
| `backend` (Express) | `5000` | `5000` | HTTP — API REST consumida diretamente pelo navegador |
| `mongo` (MongoDB) | `27017` | `27017` | TCP — exposta no host e acessível internamente em `mongo-todo:27017` |

**Observação:** Não há configuração de HTTPS (porta `443`) no projeto atual.

---

## 4. Imagens Docker

| Serviço | Dockerfile | Imagem Base Atual | Observações |
| :--- | :--- | :--- | :--- |
| `frontend` | `frontend/Dockerfile` | Multi-stage: `node:18-alpine` (build) e `nginx:alpine` (runtime) | Usa `npm install` (não `npm ci`); não possui `nginx.conf` customizado; tags sem versão patch/minor fixa. |
| `backend` | `backend/Dockerfile` | `node:18-alpine` | Usa `npm install`; inicia com `CMD ["node", "index.js"]`; sem `HEALTHCHECK`. |
| `mongo` | `banco-de-dados/Dockerfile` | `mongo:latest` | **Usa tag `latest`**, o que compromete reprodutibilidade; copia `init-mongo.js` para `/docker-entrypoint-initdb.d/`. |

---

## 5. Volumes

- **Nenhum volume persistente** (nomeado ou bind mount) está configurado em `docker-compose.yaml`.
- Os dados do MongoDB residem exclusivamente na camada gravável efêmera do container `mongo-todo` (`/data/db`). Ao executar `docker compose down` seguido de remoção/recriação ou atualização do container, todas as tarefas cadastradas são perdidas.

---

## 6. Variáveis de Ambiente

### Definidas atualmente em `docker-compose.yaml` (serviço `mongo`):
- `MONGO_INITDB_ROOT_USERNAME=root`
- `MONGO_INITDB_ROOT_PASSWORD=rootpassword`
- `MONGO_INITDB_DATABASE=todo-app`

### Ausência de configuração dinâmica na aplicação:
- **`backend/index.js`**:
  - Porta fixa: `const port = 5000;` (linha 8).
  - URI de conexão hardcoded com credenciais de demonstração e nome de container local (linha 11):
    `mongodb://root:rootpassword@mongo-todo:27017/todo-app?authSource=admin`
- **`frontend/src/App.js`**:
  - URL da API hardcoded para `http://localhost:5000` nas quatro chamadas Axios (linhas 11, 18, 26 e 35).
- **Arquivos de ambiente**:
  - `.gitignore` já protege `.env` e `.env.*` (com exceção `!.env.example`), mas não há `.env.example` no repositório.

---

## 7. Fluxo Entre Frontend, API e Banco

### Fluxo Atual (Local)
```text
Navegador ──(HTTP :80)──────► Nginx (frontend) ──► HTML/JS/CSS do React
Navegador ──(HTTP :5000)────► Express API (backend) ──(TCP :27017, rede todo-net)──► MongoDB (mongo-todo)
```

1. O usuário acessa `http://localhost` (porta 80) e baixa o bundle React estático servido pelo Nginx padrão.
2. O JavaScript no navegador executa chamadas HTTP diretas para `http://localhost:5000/todos` e `http://localhost:5000/todos/:id`.
3. A API Express aceita requisições de qualquer origem (`app.use(cors())`), lê/grava na coleção `todos` do banco `todo-app` via Mongoose e retorna JSON ao navegador.

### Fluxo Exigido para a Nuvem (conforme demanda e `docs/escopo.md`)
```text
Navegador ──(HTTPS :443)──► Nginx (VM 1 - Aplicação)
                              ├── /         ──► Frontend React (estático)
                              └── /todos*   ──► Proxy reverso -> API Express (:5000, VM 1)
                                                                  │
                                                  (Rede privada, TCP :27017)
                                                                  ▼
                                                          MongoDB (VM 2 - Banco + volume persistente)
```

---

## 8. Como Executar Localmente (Estado Atual)

Pré-requisitos verificados no ambiente local:
- Docker Engine `29.1.3`
- Docker Compose `v2.40.3`
- Portas locais `80`, `5000` e `27017` livres.

Comandos documentados no `README.md`:
```bash
docker compose up --build -d
docker compose ps
docker compose logs -f
```
- Frontend: `http://localhost`
- API: `http://localhost:5000/todos`
- Encerrar: `docker compose down`

*(Nota: `docker compose config` validou o arquivo com sucesso, emitindo apenas o aviso de que o atributo `version: '3.8'` é obsoleto.)*

---

## 9. Problemas Identificados para Levar a Aplicação à Nuvem

1. **URL `localhost:5000` fixa no Frontend (`frontend/src/App.js`)**:
   - Em qualquer dispositivo externo na nuvem, `localhost` aponta para a própria máquina do visitante, quebrando todas as operações da lista de tarefas.
2. **Ausência de proxy reverso no Nginx**:
   - Sem um `nginx.conf` customizado encaminhando `/todos` e `/todos/:id` para o backend, o frontend e a API não ficam acessíveis pelo mesmo endereço público, exigindo expor a porta `5000` e causando problemas de conteúdo misto (HTTPS -> HTTP).
3. **Ausência de HTTPS**:
   - O projeto só escuta na porta `80` (HTTP). A demanda exige acesso público via HTTPS.
4. **Credenciais e host do MongoDB hardcoded (`backend/index.js` e `docker-compose.yaml`)**:
   - Senha `rootpassword` fixa no código e no Compose; host `mongo-todo` fixo para rede Docker local, impedindo apontar para o IP privado da VM 2 (banco dedicado).
5. **Exposição pública da porta `27017` do MongoDB**:
   - `docker-compose.yaml` publica `"27017:27017"` em todas as interfaces (`0.0.0.0`). Em produção/nuvem, o banco deve ficar em VM exclusiva e aceitar conexões apenas da VM da aplicação pela rede privada.
6. **Falta de persistência de dados**:
   - Não há volume nomeado/persistente para `/data/db` do MongoDB.
7. **CORS totalmente aberto**:
   - `app.use(cors())` permite qualquer origem sem restrição configurável por variável de ambiente.
8. **Ausência de Health Checks, políticas de reinício e resiliência na inicialização**:
   - Não há endpoint `/health` na API, nem `HEALTHCHECK` nos Dockerfiles/Compose, nem política `restart: unless-stopped`.
   - Se o MongoDB demorar a subir na VM 2, o `backend` pode falhar na conexão inicial sem retentativa ou verificação de saúde clara.
9. **Uso de tag `mongo:latest` e ausência de tags explícitas**:
   - `banco-de-dados/Dockerfile` usa `mongo:latest`, violando reprodutibilidade exigida pelo projeto.
10. **Opções depreciadas no Mongoose 8 e atributo obsoleto no Compose**:
    - `useNewUrlParser` e `useUnifiedTopology` não têm efeito/são depreciadas no `mongoose` `^8.12.1`.
    - `version: '3.8'` gera warning no Docker Compose v2.
11. **Testes automatizados ausentes ou quebrados**:
    - `backend` não possui testes (`exit 1`).
    - `frontend/src/App.test.js` ainda contém o teste padrão do CRA (`learn react`), incompatível com o `App.js` atual.

---

## 10. Arquivos que Precisarão ser Alterados ou Criados nas Próximas Fases

### Adaptação da aplicação (Fase 3):
- `frontend/src/App.js` — usar caminho relativo ou variável de ambiente (`REACT_APP_API_URL` com fallback seguro para `/todos` via Nginx).
- `frontend/Dockerfile` e novo `frontend/nginx.conf` (ou template Nginx) — configurar proxy reverso `/todos` -> backend, suporte a health check e preparação para HTTPS/reverse proxy.
- `backend/index.js` — ler `PORT`, `MONGODB_URI` (ou variáveis equivalentes), `CORS_ORIGIN` via `process.env`, adicionar rota `/health` (verificando conexão com o MongoDB) e remover opções depreciadas do Mongoose.
- `backend/Dockerfile` — usar `npm ci --omit=dev` (ou `npm ci`), fixar tag de imagem e adicionar `HEALTHCHECK` (ou no Compose).
- `banco-de-dados/Dockerfile` — substituir `mongo:latest` por versão fixa explícita (ex.: `mongo:7.0` ou `mongo:8.0`).
- `docker-compose.yaml` (e/ou arquivos separados para aplicação e banco nas duas VMs) — remover `version` obsoleto, usar variáveis de ambiente, remover publicação externa da porta `27017`, configurar volume persistente, health checks e `restart: unless-stopped`.
- `.env.example` e atualização de `.gitignore` — documentar variáveis de ambiente sem segredos reais.

### Próximas entregas planejadas (Infraestrutura, Automação e Documentação)
- `ARQUITETURA.md`, `SECRETS.md`, `BACKUP-RESTAURACAO.md`, `EVIDENCIAS.md`, `OPERACAO.md`, `CUSTOS.md`, `TESTE-LOCAL.md`, `README.md`.
- `terraform/` (VPC, sub-redes, security groups, VM da aplicação, VM do banco, volume persistente e chave SSH).
- `ansible/` (inventário, `group_vars`, roles de sistema, Docker, MongoDB, aplicação e rotinas de backup/restauração).
- `.github/workflows/` (pipeline manual via `workflow_dispatch`).

---

## 11. Riscos e Pontos de Decisão

### Riscos identificados
1. **Conflito de portas no ambiente local**: o serviço `frontend` mapeia a porta `80` do host por padrão; caso exista outro servidor web ativo (como Apache/Nginx local), o container falhará ao iniciar sem ajuste de porta.
2. **Inicialização do banco (`init-mongo.js`) com usuário da aplicação vs. usuário root**:
   - Atualmente, `backend/index.js` conecta usando `root` (`authSource=admin`). O documento `docs/escopo.md` (`REQ-03`) recomenda usar uma credencial própria da aplicação no banco em vez de `root`, exigindo ajuste em `init-mongo.js` para criar usuário dedicado no banco `todo-app`.
3. **Estratégia de HTTPS**:
   - Para acesso público em HTTPS, um certificado válido (Let's Encrypt) requer um domínio ou DNS dinâmico apontando para a VM (ex.: domínio próprio, DuckDNS ou `sslip.io`), ou o uso de proxy/load balancer gerenciado no provedor de nuvem.
4. **Build vs. imagem pronta em registry**:
   - Para automação via pipeline, é necessário definir se as imagens Docker serão publicadas em um registry (GHCR ou Docker Hub) com tags versionadas ou construídas durante o fluxo de entrega.

### Pontos a definir para a arquitetura em nuvem
1. Seleção do provedor de nuvem (AWS, GCP, Azure ou equivalente) e região de implantação.
2. Estratégia de publicação HTTPS e nome DNS utilizado para a apresentação.

