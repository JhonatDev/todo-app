# Imagem base com versão explícita e reproduzível
FROM node:18.20.8-alpine

# Definindo o diretório de trabalho dentro do container
WORKDIR /app

# Copiando o package.json e o package-lock.json para instalar as dependências
COPY package*.json ./

# Instalando apenas dependências de produção de forma determinística
RUN npm ci --omit=dev

# Copiando o restante do conteúdo do projeto para o container
COPY . .

# Expondo a porta padrão do backend
EXPOSE 5000

HEALTHCHECK --interval=30s --timeout=5s --start-period=15s --retries=3 \
  CMD node -e "const http=require('http');const port=process.env.PORT||5000;http.get('http://127.0.0.1:'+port+'/health',r=>process.exit(r.statusCode===200?0:1)).on('error',()=>process.exit(1))"

# Comando para rodar a aplicação
CMD ["node", "index.js"]
