#!/bin/bash
PROJECT_DIR=~/kindred-connect
cd $PROJECT_DIR
pm2 delete zapmro 2>/dev/null
pm2 start Server/index.js --name "zapmro"
pm2 save
echo "🚀 Servidor reiniciado!"
echo "🔗 Acesse agora: http://167.88.42.133:3000"
pm2 logs zapmro
