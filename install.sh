#!/bin/bash
# SCRIPT DE INSTALAÇÃO DEFINITIVA - ZAPMRO CLOUD (UBUNTU 24.04 LTS)

echo "🚀 Iniciando instalação completa..."

# 1. Limpeza e Instalação do Node.js 20
sudo apt update
sudo apt remove -y nodejs npm
curl -fsSL https://deb.nodesource.com/setup_20.x | sudo -E bash -
sudo apt install -y nodejs git ffmpeg

# 2. Instalação de dependências de sistema para Chrome/Puppeteer (Específico Ubuntu 24)
sudo apt install -y libnss3 libatk-bridge2.0-0t64 libatk1.0-0t64 libcups2t64 libdrm2 libxkbcommon0 libxcomposite1 libxdamage1 libxrandr2 libgbm1 libasound2t64 libpango-1.0-0 libcairo2 libxshmfence1

# 3. Preparação do Diretório
cd ~
rm -rf kindred-connect
mkdir -p kindred-connect
cd kindred-connect

# 4. Instalação do PM2 Global
sudo npm install -g pm2

# 5. Inicialização e Dependências
npm init -y
npm install express socket.io whatsapp-web.js axios dotenv fluent-ffmpeg ffmpeg-static multer qrcode qrcode-terminal cors puppeteer-page-proxy

# 6. Criar estrutura
mkdir -p data/history data/archives Public/uploads Server

# 7. Finalização
echo "✅ Ambiente preparado!"
echo "👉 Agora, suba os arquivos para ~/kindred-connect e execute:"
echo "pm2 start Server/index.js --name 'zapmro' && pm2 logs zapmro"
