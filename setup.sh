#!/bin/bash
# SCRIPT DE INSTALAÇÃO DEFINITIVA - ZAPMRO CLOUD

echo "🚀 Iniciando instalação completa no Ubuntu LTS 24..."

# 1. Limpeza e Atualização
sudo apt update && sudo apt upgrade -y
sudo apt remove -y nodejs npm
curl -fsSL https://deb.nodesource.com/setup_20.x | sudo -E bash -

# 2. Instalação de dependências de sistema (Chrome/Puppeteer no Ubuntu 24)
sudo apt install -y nodejs git ffmpeg libnss3 libatk-bridge2.0-0t64 libatk1.0-0t64 libcups2t64 libdrm2 libxkbcommon0 libxcomposite1 libxdamage1 libxrandr2 libgbm1 libasound2t64 libpango-1.0-0 libcairo2 libxshmfence1

# 3. Preparação do Diretório
cd ~
rm -rf kindred-connect
mkdir kindred-connect
cd kindred-connect

# 4. Configuração do Projeto
# (Nota: O código já foi gerado e está pronto no Lovable, este script prepara o ambiente real na VPS)
npm init -y
npm install express socket.io whatsapp-web.js axios dotenv fluent-ffmpeg ffmpeg-static multer qrcode qrcode-terminal cors puppeteer-page-proxy
npm install -g pm2

# 5. Estrutura de Pastas
mkdir -p data/history data/archives Public/uploads Server

# 6. PM2 e Inicialização
# pm2 start Server/index.js --name "zapmro"
# pm2 save
# pm2 startup

echo "✅ Instalação concluída! Acesse via IP:3000"
