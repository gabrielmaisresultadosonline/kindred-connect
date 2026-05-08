#!/bin/bash
# SCRIPT DE SINCRONIZAÇÃO DE CÓDIGO - ZAPMRO CLOUD

echo "🔄 Sincronizando código do Lovable para a pasta do projeto..."

# 1. Definir pastas
PROJECT_DIR=~/kindred-connect
SERVER_FILE=$PROJECT_DIR/Server/index.js
PUBLIC_DIR=$PROJECT_DIR/Public

# 2. Criar pastas se não existirem
mkdir -p $PROJECT_DIR/Server
mkdir -p $PROJECT_DIR/Public

# 3. Criar o arquivo do servidor (Server/index.js) com o código mais recente
cat << 'SERVER_EOF' > $SERVER_FILE
$(cat Server/index.js)
SERVER_EOF

# 4. Criar o arquivo de Proxy
cat << 'PROXY_EOF' > $PROJECT_DIR/Server/proxyManager.js
$(cat Server/proxyManager.js)
PROXY_EOF

# 5. Sincronizar pasta Public (HTML/JS)
# Nota: Como o cat não funciona bem com múltiplos arquivos, sugerimos o upload manual ou git push
# Mas para o Server/index.js que é o coração, vamos garantir que ele esteja lá.

echo "✅ Código sincronizado em $PROJECT_DIR"
echo "🚀 Iniciando com PM2..."
cd $PROJECT_DIR
pm2 delete zapmro 2>/dev/null
pm2 start Server/index.js --name "zapmro"
pm2 save
pm2 logs zapmro
