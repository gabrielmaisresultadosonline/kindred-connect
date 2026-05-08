#!/bin/bash
# SCRIPT DE INSTALAÇÃO DEFINITIVA - ZAPMRO CLOUD (UBUNTU 24.04 LTS)

echo "🚀 Iniciando instalação completa e limpeza..."

# 1. Limpeza total de Node/NPM antigos para evitar conflitos
sudo apt remove -y nodejs npm
sudo apt autoremove -y

# 2. Instalação do Node.js 20 (LTS)
curl -fsSL https://deb.nodesource.com/setup_20.x | sudo -E bash -
sudo apt install -y nodejs

# 3. Instalação de dependências de sistema para Chrome/Puppeteer (Específico Ubuntu 24)
# Substituindo libasound2 por libasound2t64 conforme erro reportado
sudo apt update
sudo apt install -y git ffmpeg libnss3 libatk-bridge2.0-0t64 libatk1.0-0t64 libcups2t64 libdrm2 libxkbcommon0 libxcomposite1 libxdamage1 libxrandr2 libgbm1 libasound2t64 libpango-1.0-0 libcairo2 libxshmfence1

# 4. Preparação do Diretório do Projeto
cd ~
rm -rf kindred-connect
mkdir -p kindred-connect/Server kindred-connect/Public kindred-connect/data
cd kindred-connect

# 5. Instalação do PM2 Global
sudo npm install -g pm2

# 6. Inicialização do Projeto e Dependências
npm init -y
npm install express socket.io whatsapp-web.js axios dotenv fluent-ffmpeg ffmpeg-static multer qrcode qrcode-terminal cors puppeteer-page-proxy

# 7. Criar estrutura de dados
mkdir -p data/history data/archives Public/uploads

# 8. Copiar arquivos do projeto (Simulado aqui, na VPS você faria o git clone ou upload)
# O código já está no servidor via Lovable.

echo "✅ Ambiente preparado com sucesso!"
echo "👉 Agora execute: pm2 start Server/index.js --name 'zapmro' && pm2 logs zapmro"
