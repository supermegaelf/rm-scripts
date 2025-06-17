#!/bin/bash

# Цвета для вывода
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m' # No Color

echo -e "${BLUE}=== Настройка Remnawave ===${NC}"
echo -e "${YELLOW}Введите необходимые параметры:${NC}"
echo

# Функция для запроса ввода с валидацией
ask_input() {
    local prompt="$1"
    local var_name="$2"
    local value=""
    
    while [ -z "$value" ]; do
        echo -e -n "${GREEN}$prompt: ${NC}"
        read -r value
        if [ -z "$value" ]; then
            echo -e "${RED}Значение не может быть пустым!${NC}"
        fi
    done
    
    eval "$var_name='$value'"
}

# Запрос параметров
ask_input "PANEL_DOMAIN (например: example.com)" PANEL_DOMAIN
ask_input "SUB_DOMAIN (например: example.com)" SUB_DOMAIN  
ask_input "SELFSTEAL_DOMAIN (например: example.com)" SELFSTEAL_DOMAIN
ask_input "CLOUDFLARE_EMAIL" CLOUDFLARE_EMAIL
ask_input "CLOUDFLARE_API_KEY" CLOUDFLARE_API_KEY

echo
echo -e "${YELLOW}Генерирую файл с переменными окружения...${NC}"

# Создание файла с переменными
cat > remnawave-vars.sh << EOF
# remnawave-vars.sh
export PANEL_DOMAIN="$PANEL_DOMAIN"
export SUB_DOMAIN="$SUB_DOMAIN"
export SELFSTEAL_DOMAIN="$SELFSTEAL_DOMAIN"
export CLOUDFLARE_API_KEY="$CLOUDFLARE_API_KEY"
export CLOUDFLARE_EMAIL="$CLOUDFLARE_EMAIL"

# Генерируемые переменные
export SUPERADMIN_USERNAME=\$(tr -dc 'a-zA-Z' < /dev/urandom | fold -w 8 | head -n 1)

# Правильная генерация пароля
password=""
password+=\$(head /dev/urandom | tr -dc 'A-Z' | head -c 1)
password+=\$(head /dev/urandom | tr -dc 'a-z' | head -c 1)
password+=\$(head /dev/urandom | tr -dc '0-9' | head -c 1)
password+=\$(head /dev/urandom | tr -dc '!@#%^&*()_+' | head -c 3)
password+=\$(head /dev/urandom | tr -dc 'A-Za-z0-9!@#%^&*()_+' | head -c \$((24 - 6)))
export SUPERADMIN_PASSWORD=\$(echo "\$password" | fold -w1 | shuf | tr -d '\n')

export cookies_random1=\$(tr -dc 'a-zA-Z' < /dev/urandom | fold -w 8 | head -n 1)
export cookies_random2=\$(tr -dc 'a-zA-Z' < /dev/urandom | fold -w 8 | head -n 1)
export METRICS_USER=\$(tr -dc 'a-zA-Z' < /dev/urandom | fold -w 8 | head -n 1)
export METRICS_PASS=\$(tr -dc 'a-zA-Z' < /dev/urandom | fold -w 8 | head -n 1)
export JWT_AUTH_SECRET=\$(openssl rand -base64 48 | tr -dc 'a-zA-Z0-9' | head -c 64)
export JWT_API_TOKENS_SECRET=\$(openssl rand -base64 48 | tr -dc 'a-zA-Z0-9' | head -c 64)
EOF

# Делаем файл исполняемым
chmod +x remnawave-vars.sh

echo -e "${GREEN}✓ Файл remnawave-vars.sh создан успешно!${NC}"
echo
echo -e "${YELLOW}Загружаю переменные окружения...${NC}"

# Загружаем переменные окружения
source remnawave-vars.sh

echo -e "${GREEN}✓ Переменные окружения загружены!${NC}"
