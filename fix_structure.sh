#!/bin/bash
PROJECT_DIR=~/kindred-connect
echo "🛠 Fixando estrutura em $PROJECT_DIR..."

# 1. Garantir que as pastas existem
mkdir -p $PROJECT_DIR/Server
mkdir -p $PROJECT_DIR/Public
mkdir -p $PROJECT_DIR/data/history

# 2. Criar os arquivos do backend (Server)
cat << 'SERVER_JS' > $PROJECT_DIR/Server/index.js
$(cat Server/index.js)
SERVER_JS

cat << 'PROXY_JS' > $PROJECT_DIR/Server/proxyManager.js
$(cat Server/proxyManager.js)
PROXY_JS

# 3. Criar o package.json correto
cat << 'PKG_JSON' > $PROJECT_DIR/package.json
$(cat package.json)
PKG_JSON

# 4. Criar os arquivos do frontend (Public)
cat << 'INDEX_HTML' > $PROJECT_DIR/Public/index.html
$(cat Public/index.html)
INDEX_HTML

cat << 'APP_JS' > $PROJECT_DIR/Public/app.js
$(cat Public/app.js)
APP_JS

cat << 'CRM_HTML' > $PROJECT_DIR/Public/crm.html
$(cat Public/crm.html)
CRM_HTML

cat << 'CRM_JS' > $PROJECT_DIR/Public/crm.js
$(cat Public/crm.js)
CRM_JS

echo "🚀 Reiniciando PM2..."
cd $PROJECT_DIR
pm2 delete zapmro 2>/dev/null
pm2 start Server/index.js --name "zapmro"
pm2 save
pm2 logs zapmro
