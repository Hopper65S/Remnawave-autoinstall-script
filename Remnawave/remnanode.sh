#!/bin/bash
# === ФУНКЦИИ УСТАНОВКИ И НАСТРОЙКИ (REMNANODE) ===
add_remnawave_node_auto() {
    clear
    echo "=================================================="
    echo -e "     ${CYAN}$(get_text ADD_NODE_AUTO_HEADER)${NC}"
    echo "=================================================="

    local api_domain_url="localhost:3000"

    # 1. Получение токена панели
    echo -e "\n⚙️ $(get_text GETTING_TOKEN)"
    local panel_token=$(get_panel_token)
    if [ -z "$panel_token" ]; then
        echo -e "${RED}❌ $(get_text ERROR_MISSING_TOKEN)${NC}"
        sleep 3
        return 1
    fi
    
    # 2. Получение UUID профиля конфигурации
    echo -e "\n⚙️ $(get_text GETTING_CONFIG_PROFILE_UUID)"
    local config_profile_uuid=$(get_config_profiles "$api_domain_url" "$panel_token")
    if [ -z "$config_profile_uuid" ]; then
        echo -e "${RED}❌ $(get_text ERROR_CONFIG_PROFILE_NOT_FOUND)${NC}"
        sleep 3
        return 1
    fi

    # 3. Получение UUID инбаунда с помощью API
    echo -e "\n⚙️ $(get_text SELECT_INBOUND)"
    local inbound_uuid=$(get_inbound_from_panel "$api_domain_url" "$panel_token")
    if [ -z "$inbound_uuid" ]; then
        echo -e "${RED}❌ $(get_text ERROR_NO_INBOUND_SELECTED)${NC}"
        sleep 3
        return 1
    fi

    # 4. Запрос данных у пользователя
    echo -e "\n${CYAN}$(get_text ENTER_NODE_DETAILS)${NC}"
    read -p "$(get_text ENTER_NODE_DOMAIN): " node_domain
    if [ -z "$node_domain" ]; then
        echo -e "${RED}❌ $(get_text INPUT_REQUIRED)${NC}"
        sleep 2
        return 1
    fi

    read -p "$(get_text ENTER_NODE_NAME) (Default: $node_domain): " node_name
    if [ -z "$node_name" ]; then
        node_name="$node_domain"
    fi
    
    # 5. Создание ноды
    echo ""
    echo -e "⚙️ $(get_text ADDING_NODE_TO_PANEL)"
    echo "--------------------------------------------------"
    create_node "$api_domain_url" "$panel_token" "$config_profile_uuid" "$inbound_uuid" "$node_domain" "$node_name"
    sleep 5
}

install_docker() {
    echo "$(get_text DOCKER_INSTALLING)"
    sleep 0.5
    echo "$(get_text CHECK_DOCKER)"
    sleep 0.5
    if ! check_docker_installed; then
        echo "$(get_text DOCKER_INSTALLING)"
        sleep 0.5
        curl -fsSL https://get.docker.com | sh
        sleep 4
    else
        echo "$(get_text DOCKER_ALREADY_INSTALLED)"
        sleep 0.5
    fi

    echo "$(get_text DOCKER_INSTALL_COMPLETE)"
    sleep 3
}

setup_remnanode() {
    echo "$(get_text SETUP_REMNANODE)"
    echo "$(get_text CREATE_REMNANODE_DIR)"
    sudo mkdir -p /opt/remnanode
    cd /opt/remnanode
    if [ $? -ne 0 ]; then
        echo "$(get_text ERROR_CREATE_DIR_REMNANODE)"
        return 1
    fi
    
    # Всегда обновляем файл .env с актуальным ключом
    echo "$(get_text CREATE_ENV_FILE)"
    sudo cat > .env <<EOF
APP_PORT=2222
SSL_CERT=$SSL_CERT_KEY
EOF
    echo "$(get_text SUCCESS_ENV_FILE)"
    
    # Создаем docker-compose.yml только если файла нет
    echo "$(get_text CHECK_DOCKER_COMPOSE)"
    if [ ! -f docker-compose.yml ]; then
        sudo cat > docker-compose.yml <<EOF
services:
    remnanode:
        container_name: remnanode
        hostname: remnanode
        image: remnawave/node:latest
        restart: always
        network_mode: host
        env_file:
            - .env
networks:
  remnanode-network:
    name: remnanode-network
    driver: bridge
    external: true
EOF
        echo "$(get_text CREATE_DOCKER_COMPOSE)"
    else
        echo "$(get_text DOCKER_COMPOSE_EXISTS)"
    fi
    
    # Запускаем контейнер
    echo "$(get_text START_REMNANODE_CONTAINER)"
    sudo docker compose up -d
    if [ $? -ne 0 ]; then
        echo "$(get_text ERROR_START_REMNANODE)"
        return 1
    fi

    echo "$(get_text REMNANODE_SETUP_COMPLETE)"
}

install_caddy_docker_remnanode() {
    # Функция для проверки существования Docker-контейнера
    container_exists() {
        sudo docker ps -a --format '{{.Names}}' | grep -q "^caddy$"
    }

    echo "$(get_text CADDY_INSTALL_START)"
    sleep 1
    
    # Проверка наличия Docker и Docker Compose
    if ! command -v docker &> /dev/null || ! command -v docker compose &> /dev/null; then
        echo "$(get_text DOCKER_COMPOSE_NOT_INSTALLED)"
        sleep 1
        echo "$(get_text DOCKER_COMPOSE_NOT_INSTALLED_HINT)"
        sleep 1
        return 1
    fi

    # === Шаг 1: Проверка и удаление существующего контейнера Caddy ===
    if container_exists; then
        echo "$(get_text CADDY_CONTAINER_EXISTS)"
        read -p "$(get_text CADDY_CONTAINER_DELETE_PROMPT)" REPLY
        if [[ $REPLY =~ ^[Yy]$ ]]; then
            echo ""
            echo "$(get_text CADDY_CONTAINER_DELETING)"
            sleep 1
            sudo docker rm -f caddy
            echo "$(get_text CADDY_CONTAINER_DELETED)"
            sleep 1
        else
            echo ""
            echo "$(get_text CADDY_CONTAINER_KEEP)"
            sleep 1
            return 1 # Прерываем выполнение функции, если пользователь отказался
        fi
    fi

    # === Шаг 2: Создание директорий для Caddy ===
    CADDY_DIR="/opt/remnanode/caddy"
    echo "$(get_text CREATE_CADDY_DIRS)"
    sleep 1
    sudo mkdir -p "$CADDY_DIR"
    sudo mkdir -p "$CADDY_DIR/www"
    # Устанавливаем права на директорию, чтобы избежать ошибок
    sudo chown -R $USER:$USER "$CADDY_DIR"
    echo "$(get_text SUCCESS_CREATE_DIRS)"
    sleep 1

    # === Шаг 3: Создание файла конфигурации Caddyfile ===
    echo "$(get_text CREATE_CADDYFILE)"
    sleep 1
    cat <<EOF | sudo tee "$CADDY_DIR/Caddyfile" > /dev/null
$DOMAIN:8443 {
    reverse_proxy remnanode:2222
    root * /var/www/html
    file_server {
        index index.html
    }
}
EOF
    if [ $? -ne 0 ]; then
        echo "$(get_text ERROR_CREATE_CADDYFILE)"
        sleep 1
        return 1
    fi
    echo "$(get_text SUCCESS_CADDYFILE)"
    sleep 1

    # === Шаг 4: Создание файла docker-compose.yml ===
    echo "$(get_text CREATE_CADDY_COMPOSE)"
    sleep 1
    cat <<EOF | sudo tee "$CADDY_DIR/docker-compose.yml" > /dev/null
services:
  caddy:
    image: caddy:2.9
    container_name: caddy
    hostname: caddy
    restart: always
    ports:
      - '0.0.0.0:8443:8443'
    networks:
      - remnanode-network
    volumes:
      - ./Caddyfile:/etc/caddy/Caddyfile
      - caddy-ssl-data:/data
      - ./www:/var/www/html

networks:
  remnanode-network:
    name: remnanode-network
    driver: bridge
volumes:
  caddy-ssl-data:
    name: caddy-ssl-data
    driver: local
EOF
    if [ $? -ne 0 ]; then
        echo "$(get_text ERROR_CREATE_CADDY_COMPOSE)"
        sleep 1
        return 1
    fi
    echo "$(get_text SUCCESS_CADDY_COMPOSE)"
    sleep 1

    # === Шаг 5: Настройка веб-страницы ===
    echo ""
    echo "=============================================="
    echo "$(get_text WEBPAGE_SETUP_HEADER)"
    echo "$(get_text WEBPAGE_SETUP_INFO1)"
    echo "$(get_text WEBPAGE_SETUP_INFO2)"
    echo "$(get_text WEBPAGE_SETUP_INFO3)"
    read -p "$(get_text ENTER_WEBPAGE_PATH)" WEB_FILE_PATH
    
    if [ "$WEB_FILE_PATH" != "0" ]; then
        if [ -f "$WEB_FILE_PATH" ]; then
            echo "$(get_text COPYING_FILE)"
            sleep 1
            sudo cp "$WEB_FILE_PATH" "$CADDY_DIR/www/index.html"
            if [ $? -ne 0 ]; then
                echo "$(get_text ERROR_COPY_FILE)"
                sleep 1
                return 1
            fi
            echo "$(get_text SUCCESS_COPY_FILE)"
            sleep 1
        else
            echo "$(get_text FILE_NOT_FOUND_SKIP)"
            sleep 1
        fi
    else
        echo "$(get_text WEBPAGE_SKIP)"
        sleep 1
    fi

    # === Шаг 6: Запуск контейнера Caddy ===
    echo "$(get_text START_CADDY_CONTAINER)"
    sleep 1
    cd "$CADDY_DIR" || { echo "Ошибка: Не удалось перейти в директорию $CADDY_DIR"; return 1; }
    sudo docker compose up -d
    if [ $? -ne 0 ]; then
        echo "$(get_text ERROR_START_CADDY)"
        sleep 1
        echo "$(get_text CHECK_PORT_BUSY)"
        sleep 1
        return 1
    fi
    echo "$(get_text CADDY_CONTAINER_STARTED)"
    sleep 3
    clear
    
    echo "$(get_text CADDY_INSTALL_COMPLETE)"
    sleep 4
    # === Шаг 7: Проверка логов Remnanode на наличие ошибок ===
    echo ""
    echo "=============================================="
    echo "$(get_text CHECK_REMNANODE_LOGS_HEADER)"
    sleep 1
    if sudo docker logs remnanode 2>&1 | grep -q "spawn xray error"; then
        echo "$(get_text ERROR_LOGS_FOUND)"
        sleep 1
        echo "$(get_text ERROR_LOGS_REASONS)"
        sleep 1
        echo "$(get_text ERROR_LOGS_HINT)"
        sleep 1
    else
        echo "$(get_text LOGS_CLEAN)"
        sleep 2
    fi
}


setup_firewall() {
    echo "$(get_text FIREWALL_SETUP_START)"
    sleep 1

    # Проверка, установлен ли iptables
    if ! command -v iptables &> /dev/null; then
        echo "$(get_text IPTABLES_NOT_FOUND)"
        sleep 2
        sudo apt-get update
        sudo apt-get install -y iptables
        echo "$(get_text IPTABLES_INSTALL_SUCCESS)"
        sleep 1
    else
        echo "$(get_text IPTABLES_ALREADY_INSTALLED)"
        sleep 1
    fi

    echo "$(get_text APPLYING_IPTABLES)"
    sleep 2

    sudo iptables -F INPUT


    sudo iptables -P INPUT DROP
    

    # Разрешаем весь трафик на loopback-интерфейсе
    sudo iptables -A INPUT -i lo -j ACCEPT

    # Разрешаем уже установленные и связанные с ними соединения.
    sudo iptables -A INPUT -m conntrack --ctstate ESTABLISHED,RELATED -j ACCEPT

    echo "-> $(get_text "FIREWALL_ALLOWING_SSH") $SSH_PORT"
    sudo iptables -A INPUT -p tcp --dport "$SSH_PORT" -j ACCEPT

    echo "-> $(get_text "FIREWALL_ALLOWING_WEB")"
    sudo iptables -A INPUT -p tcp --dport 443 -j ACCEPT
    sudo iptables -A INPUT -p tcp --dport 80 -j ACCEPT

    echo "-> $(get_text "FIREWALL_ALLOWING_NODE") $IP_PANEL"
    sudo iptables -A INPUT -p tcp -s "$IP_PANEL" --dport 2222 -j ACCEPT

    echo ""
    echo "$(get_text IPTABLES_SUCCESS)"
    sleep 1
    echo "$(get_text FIREWALL_SETUP_COMPLETE)"
    sleep 1
}
select_vpn_method() {
    clear
    echo -e "1) 👻 Reality: ${WHITE}маскировка под чужие сайты (по умолчанию)${NC}"
    echo -e "2) 🕵️ Reality+ Selfsteal: ${WHITE}кража отпечатка с собственного сайта${NC}"
    echo "================================================="
    read -p "Выберите опцию (1 или 2): " VPN_CHOICE

    if [[ "$VPN_CHOICE" == "2" ]]; then
        install_caddy_docker_remnanode
    else
        echo -e "Вы выбрали ${ORANGE}Reality${NC} (маскировка под чужие сайты). Установка Caddy будет пропущена."
        sleep 2
    fi
}

run_full_install() {
    install_docker
    setup_remnanode
    select_vpn_method
    setup_firewall
    echo "$(get_text FULL_INSTALL_COMPLETE)"
}
cleanup_remnanode() {
    echo -e "${ORANGE}$(get_text CLEANUP_START)${NC}"
    sleep 2

    # Остановка и удаление контейнеров remnanode и caddy
    echo "$(get_text CLEANUP_CONTAINERS)"
    sudo docker stop remnanode &>/dev/null
    sudo docker rm remnanode &>/dev/null
    sudo docker stop caddy &>/dev/null
    sudo docker rm caddy &>/dev/null
    echo "$(get_text CLEANUP_CONTAINERS_SUCCESS)"
    sleep 1

    # Удаление директорий
    echo "$(get_text CLEANUP_DIRS)"
    sudo rm -rf /opt/remnanode /opt/caddy
    sudo rm -rf /opt/remnawave
    echo "$(get_text CLEANUP_DIRS_SUCCESS)"
    sleep 1

    # Проверка и удаление Docker volumes и сетей
    read -p "$(get_text CLEANUP_VOLUMES_PROMPT)" choice
    if [[ "$choice" =~ ^[Yy]$ ]]; then
        sudo docker volume prune -f &>/dev/null
        echo "$(get_text CLEANUP_VOLUMES_SUCCESS)"
        sudo docker network prune -f &>/dev/null
        echo "$(get_text CLEANUP_NETWORKS_SUCCESS)"
    fi

    # Очистка правил iptables
    echo "$(get_text CLEANUP_IPTABLES)"
    iptables -F
    iptables -X
    iptables -t nat -F
    iptables -t nat -X
    echo "$(get_text CLEANUP_IPTABLES_SUCCESS)"

    # Перезапуск Docker-сервиса после очистки iptables
    echo "$(get_text CLEANUP_RESTART_DOCKER)"
    sudo systemctl restart docker
    echo "$(get_text CLEANUP_RESTART_SUCCESS)"
    sleep 1

    sudo iptables -A INPUT -m conntrack --ctstate ESTABLISHED,RELATED -j ACCEPT
    sudo iptables -A OUTPUT -j ACCEPT

    # Добавление правила для SSH обратно
    sudo iptables -A INPUT -p tcp --dport "$SSH_PORT" -j ACCEPT

    echo -e "${ORANGE}$(get_text CLEANUP_COMPLETE)${NC}"
    sleep 3
}