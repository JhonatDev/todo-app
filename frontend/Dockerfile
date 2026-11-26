# Etapa 1: Construção da aplicação
FROM node:18.20.8-alpine AS build

# URL base opcional da API em tempo de build (vazio usa caminho relativo via Nginx)
ARG REACT_APP_API_URL=""
ENV REACT_APP_API_URL=${REACT_APP_API_URL}

# Definindo o diretório de trabalho dentro do container
WORKDIR /app

# Copiando o package.json e o package-lock.json para instalar as dependências
COPY package*.json ./

# Instalando as dependências de forma determinística
RUN npm ci

# Copiando todo o conteúdo da pasta do projeto para o container
COPY . .

# Construindo a aplicação para produção
RUN npm run build

# Etapa 2: Servindo a aplicação e proxy reverso para a API
FROM nginx:1.31.10-alpine

ENV BACKEND_HOST=backend
ENV BACKEND_PORT=5000

# Copiando o build da etapa anterior para o diretório padrão do Nginx
COPY --from=build /app/build /usr/share/nginx/html

# Copiando o template de proxy reverso do Nginx
COPY nginx.conf.template /etc/nginx/templates/default.conf.template

# Expondo a porta 80 para acesso à aplicação
EXPOSE 80

HEALTHCHECK --interval=30s --timeout=5s --start-period=10s --retries=3 \
  CMD wget -qO- http://127.0.0.1/ > /dev/null || exit 1

# Comando para iniciar o Nginx e servir a aplicação
CMD ["nginx", "-g", "daemon off;"]
