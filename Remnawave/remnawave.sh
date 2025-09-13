#!/bin/bash

# === ФУНКЦИИ УСТАНОВКИ И НАСТРОЙКИ (REMNAWAVE) ===

change_panel_domain() {
    clear
    echo "$(get_text CHANGE_DOMAIN_HEADER)"
    echo "--------------------------------------------------"

    # Запрос подтверждения в начале
    read -p "$(get_text CONFIRM_CHANGE_DOMAIN)" -n 1 -r CONFIRMATION
    echo ""
    if [[ ! $CONFIRMATION =~ ^[Yy]$ ]]; then
        echo -e "\n${YELLOW}❌ $(get_text OPERATION_CANCELLED)${NC}"
        return 0
    fi
    
    # Теперь запрашиваем новый домен
    read -p "$(get_text ENTER_NEW_DOMAIN)" NEW_DOMAIN
    if [ -z "$NEW_DOMAIN" ]; then
        echo -e "\n${RED}❌ $(get_text INPUT_REQUIRED)${NC}"
        return 1
    fi
    
    # Пути к файлам
    local caddyfile_path="/opt/remnawave/caddy/Caddyfile"
    local env_path="/opt/remnawave/.env"

    # Проверка наличия Caddyfile и .env
    if [ ! -f "$caddyfile_path" ]; then
        echo -e "${RED}❌ $(get_text ERROR_CADDYFILE_NOT_FOUND)${NC}"
        return 1
    fi
    if [ ! -f "$env_path" ]; then
        echo -e "${RED}❌ $(get_text ERROR_ENV_NOT_FOUND)${NC}"
        return 1
    fi

    # Обновляем домен в Caddyfile
    echo -e "\n⚙️ $(get_text UPDATING_CADDYFILE)"
    sudo sed -i "1s/.*/$NEW_DOMAIN/" "$caddyfile_path"
    if [ $? -ne 0 ]; then
        echo -e "${RED}❌ $(get_text ERROR_UPDATE_CADDYFILE)${NC}"
        return 1
    fi
    echo -e "✅ $(get_text SUCCESS_UPDATE_CADDYFILE)"

    # Обновляем домен в .env
    echo -e "\n⚙️ $(get_text UPDATING_ENV)"
    sudo sed -i "s|^FRONT_END_DOMAIN=.*|FRONT_END_DOMAIN=$NEW_DOMAIN|" "$env_path"
    sudo sed -i "s|^SUB_PUBLIC_DOMAIN=.*|SUB_PUBLIC_DOMAIN=$NEW_DOMAIN/api/sub|" "$env_path"
    if [ $? -ne 0 ]; then
        echo -e "${RED}❌ $(get_text ERROR_UPDATE_ENV)${NC}"
        return 1
    fi
    echo -e "✅ $(get_text SUCCESS_UPDATE_ENV)"

    # Перезапускаем контейнер Caddy
    echo -e "\n🔄 $(get_text RESTARTING_CADDY)"
    sudo docker compose -f /opt/remnawave/docker-compose.yml restart caddy
    if [ $? -ne 0 ]; then
        echo -e "${RED}❌ $(get_text ERROR_RESTART_CADDY)${NC}"
        return 1
    fi
    echo -e "✅ $(get_text SUCCESS_RESTART_CADDY)"

    echo -e "\n🎉 $(get_text CHANGE_DOMAIN_COMPLETE)"
    sleep 3
}
check_logs_and_suggest_fix() {
    echo "$(get_text CHECK_PANEL_LOGS_START)"

    # Проверяем, существует ли контейнер remnawave, прежде чем читать логи
    if ! sudo docker ps -a --format '{{.Names}}' | grep -q 'remnawave'; then
        echo "$(get_text CONTAINER_NOT_FOUND_LOGS)"
        return 1
    fi

    # Ищем в логах сообщение об ошибке аутентификации.
    # Используем `grep` и флаг `-q` для тихой проверки наличия совпадений.
    if sudo docker logs remnawave 2>&1 | grep -q "Error: P1000"; then
        echo "--------------------------------------------------------------------------------"
        echo "$(get_text LOG_ERROR_FOUND)"
        echo "$(get_text LOG_ERROR_DB_CONNECT)"
        echo "$(get_text LOG_ERROR_REASON)"
        echo "$(get_text LOG_ERROR_RECOMMENDATION)"
        
        # Запрашиваем ввод от пользователя
        read -p "$(get_text LOG_ERROR_PROMPT)" choice
        if [[ "$choice" =~ ^[yY]$ ]]; then
            cd /opt/remnawave
            echo "$(get_text CLEANING_VOLUMES)"
            sudo docker compose down --volumes
            sudo docker compose up -d --force-recreate
            echo "$(get_text VOLUMES_CLEANED_RESTART)"
        else
            echo "$(get_text CLEANUP_CANCELED)"
        fi
        
        echo "--------------------------------------------------------------------------------"
        return 1
    else
        echo "$(get_text NO_DB_AUTH_ERROR)"
        return 0
    fi
}
setup_remnawave() {
    echo "$(get_text PANEL_INSTALL_START)"
    sleep 2
    echo -e "${WHITE}"

    # Проверяем и устанавливаем Docker, если нужно
    install_docker
    if [ $? -ne 0 ]; then
        echo "$(get_text DOCKER_INSTALL_ERROR)"
        return 1
    fi
    sleep 2

    # Перезапускаем Docker, чтобы восстановить цепочки iptables
    sudo systemctl restart docker
    if [ $? -ne 0 ]; then
        echo "$(get_text DOCKER_RESTART_ERROR)"
        return 1
    fi
    echo "$(get_text DOCKER_RESTART_SUCCESS)"
    sleep 2

    # Создаем директорию и переходим в неё
    echo "$(get_text CREATE_DIR_PANEL)"
    sudo mkdir -p /opt/remnawave
    if [ $? -ne 0 ]; then
        echo "$(get_text ERROR_CREATE_DIR_PANEL)"
        return 1
    fi
    cd /opt/remnawave
    echo "$(get_text SUCCESS_DIR_CREATED_PANEL)"
    sleep 0.5

    # Скачиваем файлы docker-compose.yml и .env
    echo "$(get_text DOWNLOAD_FILES_PANEL)"
    sudo curl -o docker-compose.yml https://raw.githubusercontent.com/remnawave/backend/main/docker-compose-prod.yml
    sudo curl -o .env https://raw.githubusercontent.com/remnawave/backend/main/.env.sample
    if [ $? -ne 0 ]; then
        echo "$(get_text ERROR_DOWNLOAD_FILES_PANEL)"
        return 1
    fi
    echo "$(get_text SUCCESS_DOWNLOAD_FILES_PANEL)"
    sleep 0.5

    # Проверяем и генерируем ключи, если .env файл существует или если содержит 'change_me'
    if [ -f .env ]; then
        echo "$(get_text ENV_EXISTS_PANEL)"
        sleep 1
        
        # Проверяем и обновляем JWT_AUTH_SECRET, если он содержит 'change_me'
        if grep -q "JWT_AUTH_SECRET=change_me" .env; then
            echo "$(get_text GENERATE_KEYS_PANEL)"
            sudo sed -i "s/^JWT_AUTH_SECRET=.*/JWT_AUTH_SECRET=$(openssl rand -hex 64)/" .env
            echo "$(get_text SUCCESS_KEYS_GENERATED_PANEL)"
        fi

        # Проверяем и обновляем JWT_API_TOKENS_SECRET, если он содержит 'change_me'
        if grep -q "JWT_API_TOKENS_SECRET=change_me" .env; then
            echo "$(get_text GENERATE_KEYS_PANEL)"
            sudo sed -i "s/^JWT_API_TOKENS_SECRET=.*/JWT_API_TOKENS_SECRET=$(openssl rand -hex 64)/" .env
            echo "$(get_text SUCCESS_KEYS_GENERATED_PANEL)"
        fi
        
        # Проверяем и обновляем METRICS_PASS, если он содержит 'change_me'
        if grep -q "METRICS_PASS=change_me" .env; then
            echo "$(get_text GENERATE_KEYS_PANEL)"
            sudo sed -i "s/^METRICS_PASS=.*/METRICS_PASS=$(openssl rand -hex 64)/" .env
            echo "$(get_text SUCCESS_KEYS_GENERATED_PANEL)"
        fi
        
        # Проверяем и обновляем WEBHOOK_SECRET_HEADER, если он содержит 'change_me'
        if grep -q "WEBHOOK_SECRET_HEADER=change_me" .env; then
            echo "$(get_text GENERATE_KEYS_PANEL)"
            sudo sed -i "s/^WEBHOOK_SECRET_HEADER=.*/WEBHOOK_SECRET_HEADER=$(openssl rand -hex 64)/" .env
            echo "$(get_text SUCCESS_KEYS_GENERATED_PANEL)"
        fi

        # Проверяем и обновляем POSTGRES_PASSWORD, если он содержит 'change_me'
        if grep -q "POSTGRES_PASSWORD=change_me" .env; then
            echo "$(get_text GENERATE_DB_PASSWORD_PANEL)"
            pw=$(openssl rand -hex 24)
            sudo sed -i "s/^POSTGRES_PASSWORD=.*/POSTGRES_PASSWORD=$pw/" .env
            sudo sed -i "s|^\(DATABASE_URL=\"postgresql://postgres:\)[^\@]*\(@.*\)|\1$pw\2|" .env
            echo "$(get_text SUCCESS_DB_PASSWORD_PANEL)"
        fi
    else
        # Если .env файла нет, генерируем все ключи и пароли
        echo "$(get_text GENERATE_KEYS_PANEL)"
        sudo sed -i "s/^JWT_AUTH_SECRET=.*/JWT_AUTH_SECRET=$(openssl rand -hex 64)/" .env
        sudo sed -i "s/^JWT_API_TOKENS_SECRET=.*/JWT_API_TOKENS_SECRET=$(openssl rand -hex 64)/" .env
        sudo sed -i "s/^METRICS_PASS=.*/METRICS_PASS=$(openssl rand -hex 64)/" .env
        sudo sed -i "s/^WEBHOOK_SECRET_HEADER=.*/WEBHOOK_SECRET_HEADER=$(openssl rand -hex 64)/" .env
        echo "$(get_text SUCCESS_KEYS_GENERATED_PANEL)"
        sleep 0.5
        
        echo "$(get_text GENERATE_DB_PASSWORD_PANEL)"
        pw=$(openssl rand -hex 24)
        sudo sed -i "s/^POSTGRES_PASSWORD=.*/POSTGRES_PASSWORD=$pw/" .env
        sudo sed -i "s|^\(DATABASE_URL=\"postgresql://postgres:\)[^\@]*\(@.*\)|\1$pw\2|" .env
        echo "$(get_text SUCCESS_DB_PASSWORD_PANEL)"
        sleep 0.5
    fi

    # Настройка конфига .env Remnawave
    echo "$(get_text SET_DOMAIN_PANEL)"
    sudo sed -i "s/^FRONT_END_DOMAIN=.*/FRONT_END_DOMAIN=$DOMAIN/" .env
    sudo sed -i "s|^SUB_PUBLIC_DOMAIN=.*|SUB_PUBLIC_DOMAIN=$DOMAIN/api/sub|" .env
    echo "$(get_text SUCCESS_DOMAIN_SET_PANEL)"

    # Запускаем контейнеры Remnawave
    echo "$(get_text RUN_CONTAINERS_PANEL)"
    sudo docker compose up -d
    if [ $? -ne 0 ]; then
        echo "$(get_text ERROR_RUN_CONTAINERS_PANEL)"
        check_logs_and_suggest_fix
        return 1
    fi
    echo "$(get_text SUCCESS_CONTAINERS_RUN_PANEL)"
    sleep 5

    # Установка и настройка Caddy
    install_caddy_docker
    if [ $? -ne 0 ]; then
        echo "$(get_text CADDY_INSTALL_ERROR_PANEL)"
        return 1
    fi
    sleep 1

    # Проверка доступности панели
    check_panel_status
    if [ $? -ne 0 ]; then
        echo "$(get_text PANEL_UNREACHABLE_DNS_FW)"
        return 1
    fi

    echo "$(get_text PANEL_INSTALL_COMPLETE)"
    sleep 7
}

install_caddy_docker() {
    echo "$(get_text CADDY_INSTALL_START)"

    # Создаем директорию для Caddy
    echo "$(get_text CREATE_CADDY_DIRS)"
    sudo mkdir -p /opt/remnawave/caddy
    if [ $? -ne 0 ]; then
        echo "$(get_text ERROR_CREATE_CADDY_DIR)"
        return 1
    fi

    # Переходим в директорию Caddy
    cd /opt/remnawave/caddy
    if [ $? -ne 0 ]; then
        echo "$(get_text ERROR_CADDY_CD)"
        return 1
    fi

    # Проверяем и удаляем существующий Caddyfile, если это директория
    if [ -d Caddyfile ]; then
        echo "$(get_text CADDYFILE_IS_DIR)"
        sudo rm -rf Caddyfile
    fi

    # Создаем файл конфигурации Caddyfile
    echo "$(get_text CREATE_CADDYFILE)"
    sleep 1
    sudo cat > Caddyfile <<EOF
https://$DOMAIN {
    reverse_proxy * http://remnawave:3000
}
:443 {
    tls internal
    respond 204
}
EOF
    if [ $? -ne 0 ]; then
        echo "$(get_text ERROR_CREATE_CADDYFILE)"
        return 1
    fi

    # Создаем файл docker-compose.yml для Caddy
    echo "$(get_text CREATE_CADDY_COMPOSE)"
    sleep 1
    sudo cat > docker-compose.yml <<EOF
services:
    caddy:
        image: caddy:2.9
        container_name: 'caddy'
        hostname: caddy
        restart: always
        ports:
            - '0.0.0.0:443:443'
            - '0.0.0.0:80:80'
        networks:
            - remnawave-network
        volumes:
            - ./Caddyfile:/etc/caddy/Caddyfile
            - caddy-ssl-data:/data

networks:
    remnawave-network:
        name: remnawave-network
        driver: bridge
        external: true

volumes:
    caddy-ssl-data:
        driver: local
        external: false
        name: caddy-ssl-data
EOF
    if [ $? -ne 0 ]; then
        echo "$(get_text ERROR_CREATE_CADDY_COMPOSE)"
        sleep 1
        return 1
    fi

    # Запускаем контейнер Caddy
    echo "$(get_text START_CADDY_CONTAINER)"
    sudo docker compose up -d

    # Проверяем код выхода и автоматически исправляем проблему
    if [ $? -ne 0 ]; then
        echo "$(get_text ERROR_START_CADDY)"
        echo "$(get_text CADDY_AUTOFIX_START)"
        
        # Удаление контейнера и томов
        sudo docker compose down --volumes
        sleep 2
        echo "$(get_text CADDY_AUTOFIX_SUCCESS)"
        
        # Повторный запуск Caddy после очистки
        sudo docker compose up -d
        if [ $? -eq 0 ]; then
            echo "$(get_text CADDY_ALREADY_RUNNING)"
        else
            echo "$(get_text CADDY_AUTOFIX_FAILED)"
            return 1
        fi
    fi

    echo "$(get_text CADDY_INSTALL_COMPLETE)"
    # === ОЖИДАНИЕ ЗАПУСКА КОНТЕЙНЕРА ===
    start_time=$(date +%s)
    found_log=false
    # Скрываем курсор
    echo -e "\033[?25l"
    # Анимация ожидания
    spinner_chars=("." ".." "..." "")
    spinner_index=0
    
    while [ $(( $(date +%s) - start_time )) -lt 30 ]; do
        if sudo docker logs remnawave 2>&1 | grep -q "Remnawave Backend"; then
            echo -e "\r${GREEN}$(get_text CONTAINER_START_SUCCESS)      "
            found_log=true
            break
        fi
        
        # Вывод анимации
        echo -ne "\r$(get_text WAITING_FOR_CONTAINER_START)${spinner_chars[spinner_index]}   "
        
        # Обновление индекса анимации
        spinner_index=$(( (spinner_index + 1) % 4 ))
        
        sleep 1
    done

    # Очистка строки после завершения цикла
    echo -ne "\r${NC}"

    # Возвращаем курсор
    echo -e "\033[?25h"

    if [ "$found_log" = false ]; then
        echo "$(get_text CONTAINER_START_TIMEOUT)"
    fi
    # === КОНЕЦ ОЖИДАНИЯ ===
    sleep 3
}

check_panel_status() {
    clear
    local url="https://$DOMAIN"
    
    # Проверка и установка jq, если его нет
    if ! command -v jq &> /dev/null; then
        echo "jq не найден. Установка..."
        sudo apt-get update && sudo apt-get install jq -y
    fi

    clear
    echo "=================================================="
    echo -e "         ${CYAN}$(get_text PANEL_STATUS_HEADER)${NC}"
    echo "=================================================="
    sleep 1

    # Получение IP-адреса
    local ip_address=$(dig +short "$DOMAIN" | head -n 1)
    if [ -z "$ip_address" ]; then
        echo -e "${RED}❌ $(get_text ERROR_DOMAIN_RESOLVE_FAILED)${NC}"
        return 1
    fi

    # Определение страны по IP
    local geo_info=$(curl -s "https://ipinfo.io/$ip_address/json" 2>/dev/null)
    local country_name=$(echo "$geo_info" | jq -r '.country' 2>/dev/null)
    local city_name=$(echo "$geo_info" | jq -r '.city' 2>/dev/null)
    
    # Проверка HTTP-статуса
    local http_code=$(curl -sS -o /dev/null -w "%{http_code}" --connect-timeout 5 --max-time 15 --retry 3 --retry-delay 5 "$url")

    echo -e "\n${CYAN}📋 ИНФОРМАЦИЯ О СТАТУСЕ ПАНЕЛИ:${NC}"
    echo "--------------------------------------------------"
    echo -e "${GREEN}• Домен: ${WHITE}$DOMAIN${NC}"
    echo -e "${GREEN}• IP-адрес: ${WHITE}$ip_address${NC}"
    [[ "$country_name" != "null" ]] && echo -e "${GREEN}• Страна: ${WHITE}$country_name${NC}"
    [[ "$city_name" != "null" ]] && echo -e "${GREEN}• Город: ${WHITE}$city_name${NC}"
    echo -e "${GREEN}• HTTP-код: ${WHITE}$http_code${NC}"

    echo -e "${GREEN}• URL: ${CYAN}\e]8;;${url}\a${url}\e]8;;\a${NC}"

    if [[ "$http_code" == "200" || "$http_code" == "301" || "$http_code" == "302" ]]; then
        echo -e "\n${GREEN}$(get_text PANEL_SUCCESS_STATUS)${NC}"
    elif [[ "$http_code" == "000" ]]; then
        echo -e "\n${RED}$(get_text PANEL_UNREACHABLE_DNS_FW)${NC}"
    else
        echo -e "\n${RED}$(get_text PANEL_UNREACHABLE_CADDY)${NC}"
    fi

    echo "--------------------------------------------------"
    echo -e "${YELLOW}Нажмите Enter, чтобы продолжить...${NC}"
    read -r
}