# Teste Local — ToDo App (Fases 2 e 3)

**Última atualização:** 25/11/2026  
**Ambiente:** Linux local (`Docker 29.1.3`, `Docker Compose v2.40.3`)

---

## Parte 1 — Teste Local Original (Fase 2)

### Endereços Locais Utilizados (Antes da Adaptação)
- **Frontend (Nginx + React):** `http://localhost:8080` *(ajustado de `80` para `8080` devido ao Apache ativo na porta `80` do host)*
- **API Backend (Node.js/Express):** `http://localhost:5000/todos`
- **Banco de Dados (MongoDB):** `localhost:27017`

### Resultados e Achados da Fase 2
- O `frontend` falhou inicialmente por conflito na porta `80` (`apache2` ativo no host), sendo ajustado para `8080:80`.
- Todas as operações CRUD (`GET`, `POST`, `PATCH`, `DELETE`) responderam corretamente (`200`/`201`).
- **Falha identificada:** após `docker compose down && docker compose up -d`, os dados criados foram **perdidos**, pois não havia volume persistente configurado no `mongo-todo`.
- Foram observados avisos de atributo `version: '3.8'` obsoleto no Compose e opções depreciadas (`useNewUrlParser`, `useUnifiedTopology`) no Mongoose 8.

---

## Parte 2 — Validação Após Adaptação da Aplicação (Fase 3)

### Endereço Local Único (Proxy Reverso Nginx)
- **Aplicação e API (mesma origem):** `http://localhost:8080`
  - Interface React: `http://localhost:8080/`
  - API ToDo (via proxy Nginx): `http://localhost:8080/todos`
  - Saúde da API e banco (via proxy Nginx): `http://localhost:8080/health`
- **Portas `5000` (backend) e `27017` (MongoDB):** **não publicadas no host** (acessíveis apenas na rede interna Docker `todo-net`).

### Comandos Utilizados

```bash
docker compose config -q
docker compose down
docker compose up --build -d
docker compose ps
docker compose logs --tail=50
curl -sS http://localhost:8080/health
curl -sS http://localhost:8080/todos
docker compose down && docker compose up -d
docker compose ps
curl -sS http://localhost:8080/todos
```

### Resultado de Cada Teste (Fase 3)

| Item Validado | Método / Ação | Resultado Observado | Status |
| :--- | :--- | :--- | :---: |
| **1. Página inicial (`http://localhost:8080`)** | `GET http://localhost:8080/` + inspeção do bundle | HTTP `200`, `nginx/1.31.10`, HTML com `id="root"`; zero ocorrências de `localhost:5000` no build servido. | Aprovado |
| **2. Listagem de tarefas** | `GET http://localhost:8080/todos` | HTTP `200`, retornou as 3 tarefas iniciais de `init-mongo.js` gravadas no volume novo `todo-app_mongo_data`. | Aprovado |
| **3. Criação de tarefa** | `POST http://localhost:8080/todos` (`{"text": "Teste Fase 3 Persistente"}`) | HTTP `201`, tarefa criada com `completed: false` e `_id: 6b078063f3b564c9bb717290`. | Aprovado |
| **4. Concluir e reabrir** | `PATCH http://localhost:8080/todos/:id` (3x) | HTTP `200`, alternou `completed: true` -> `false` -> `true`. | Aprovado |
| **5. Exclusão** | Criação de `"Tarefa Temporaria Excluir"` + `DELETE /todos/:id` | HTTP `200`, resposta `{"message":"Tarefa excluída com sucesso"}`. | Aprovado |
| **6. API pelo caminho relativo `/todos`** | Chamadas via `http://localhost:8080/todos` + tentativa de acesso direto em `localhost:5000` | Todas as operações funcionaram via Nginx em `:8080/todos`; conexão direta na porta `5000` recusada (porta não exposta no host). | Aprovado |
| **7. Endpoint `/health`** | `GET http://localhost:8080/health` | HTTP `200`, retorno `{"status":"ok","database":"connected"}`. | Aprovado |
| **8. Containers saudáveis** | `docker compose ps` | `mongo-todo`, `todo-app-backend-1` e `todo-app-frontend-1` todos em estado `Up ... (healthy)`. | Aprovado |
| **9. Persistência após `down` e `up`** | `docker compose down && docker compose up -d` + `GET /todos` | Tarefa `"Teste Fase 3 Persistente"` (`_id: 6b078063f3b564c9bb717290`, `completed: true`) permaneceu preservada no volume `todo-app_mongo_data`. | Aprovado |
| **Logs e autenticação dedicada** | `docker compose logs` | Backend sem avisos de depreciação (`Servidor rodando na porta 5000`, `Conectado ao MongoDB`); MongoDB autenticou usuário dedicado `todo_app_local` no banco `todo-app`. | Aprovado |

### Problemas Encontrados e Correções Realizadas na Fase 3

| Arquivo Alterado / Criado | Problema Encontrado | Correção Realizada |
| :--- | :--- | :--- |
| `frontend/src/App.js` | Chamadas fixas para `http://localhost:5000/todos`. | Parametrizado com `REACT_APP_API_URL` (padrão vazio, usando `/todos`). |
| `frontend/nginx.conf.template` e `frontend/Dockerfile` | Ausência de proxy reverso Nginx, `npm install` e tag `nginx:alpine`. | Proxy reverso para `/todos` e `/health`, `npm ci`, imagens fixas (`node:18.20.8-alpine`, `nginx:1.31.10-alpine`) e `HEALTHCHECK`. |
| `backend/index.js` e `backend/Dockerfile` | Senha/URI hardcoded, `cors()` aberto, opções depreciadas do Mongoose, sem `/health`. | Leitura via env (`PORT`, `MONGODB_URI`/`MONGO_*`, `CORS_ORIGIN`), `GET /health`, retry de conexão, remoção das opções depreciadas, `npm ci --omit=dev` e `HEALTHCHECK`. |
| `banco-de-dados/Dockerfile` e `init-mongo.js` | Tag `mongo:latest` e ausência de usuário próprio da aplicação. | Versão fixa `mongo:9.0.8`, `HEALTHCHECK` e criação idempotente do usuário `readWrite` da aplicação via env. |
| `docker-compose.yaml` e `deploy/docker-compose.{app,db}.yml` | Atributo `version` obsoleto, porta `27017` pública, sem volume, sem `restart` e sem `healthcheck`. | Volume `mongo_data`, `restart: unless-stopped`, `healthcheck`, separação local vs. AWS (2 VMs sem expor `27017`). |
| `.env.example` e `.gitignore` | Ausência de `.env.example` e proteção incompleta de arquivos de infraestrutura/segredos. | Criado `.env.example` sem segredos reais; `.gitignore` ampliado para `.env*`, Terraform, chaves SSH e inventário Ansible. |
