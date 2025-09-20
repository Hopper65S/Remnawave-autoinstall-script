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
        if [ $? -ne 0 ]; then
            echo -e "${RED}❌ $(get_text DOCKER_INSTALL_ERROR)${NC}"
            exit 1
        fi
        sleep 4
    else
        echo "$(get_text DOCKER_ALREADY_INSTALLED)"
        sleep 0.5
    fi

    echo "$(get_text DOCKER_INSTALL_COMPLETE)"
    sleep 3
}

# Новая функция для создания сети, чтобы избежать дублирования кода
create_remnanode_network() {
    echo "$(get_text "NETWORK_CREATION_START")"
    if ! sudo docker network inspect remnanode-network &>/dev/null; then
        sudo docker network create remnanode-network
        if [ $? -ne 0 ]; then
            echo -e "${RED}$(get_text "NETWORK_CREATE_FAILED")${NC}"
            return 1
        fi
        echo -e "${GREEN}$(get_text "NETWORK_CREATED_SUCCESS")${NC}"
    else
        echo -e "${YELLOW}$(get_text "NETWORK_ALREADY_EXISTS")${NC}"
    fi
    sleep 1
    return 0
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
    
    echo "$(get_text CREATE_ENV_FILE)"
    sudo tee .env > /dev/null <<EOF
APP_PORT=2222
SSL_CERT=$SSL_CERT_KEY
EOF
    echo "$(get_text SUCCESS_ENV_FILE)"
    
    echo "$(get_text CHECK_DOCKER_COMPOSE)"
    if [ ! -f docker-compose.yml ]; then
        sudo tee docker-compose.yml > /dev/null <<EOF
services:
  remnanode:
    container_name: remnanode
    hostname: remnanode
    image: remnawave/node:latest
    restart: always
    network_mode: "host"
    env_file:
      - .env
EOF
        echo "$(get_text CREATE_DOCKER_COMPOSE)"
    else
        echo "$(get_text DOCKER_COMPOSE_EXISTS)"
    fi
}

install_caddy_for_remnanode() {
    echo "$(get_text CADDY_INSTALL_START)"
    sleep 1
    
    if ! command -v docker &> /dev/null || ! command -v docker-compose &> /dev/null; then
        echo "$(get_text DOCKER_COMPOSE_NOT_INSTALLED)"
        echo "$(get_text DOCKER_COMPOSE_NOT_INSTALLED_HINT)"
        return 1
    fi
    
    # Создаем сеть, если она не существует
    create_remnanode_network
    if [ $? -ne 0 ]; then return 1; fi

    # Используем отдельную папку для Caddy, чтобы не было конфликтов
    local CADDY_DIR="/opt/remnanode_caddy"
    
    # Если контейнер Caddy существует, останавливаем и удаляем его
    if sudo docker ps -a --format '{{.Names}}' | grep -q "^remnanode-caddy$"; then
        echo "$(get_text CADDY_CONTAINER_EXISTS)"
        if yn_prompt "$(get_text CADDY_CONTAINER_DELETE_PROMPT)"; then
            echo "$(get_text CADDY_CONTAINER_DELETING)"
            sudo docker rm -f remnanode-caddy
            echo "$(get_text CADDY_CONTAINER_DELETED)"
        else
            echo "$(get_text CADDY_CONTAINER_KEEP)"
            return 1
        fi
    fi

    echo "$(get_text CREATE_CADDY_DIRS)"
    sudo mkdir -p "$CADDY_DIR/www"
    
    echo "$(get_text CREATE_CADDYFILE)"
    sudo tee "$CADDY_DIR/Caddyfile" > /dev/null <<EOF
$DOMAIN:8443 {
    reverse_proxy remnanode:2222
    root * /var/www/html
    file_server {
        index index.html
    }
}
EOF
    echo "$(get_text SUCCESS_CADDYFILE)"

    echo "$(get_text CREATE_CADDY_COMPOSE)"
    sudo tee "$CADDY_DIR/docker-compose.yml" > /dev/null <<EOF
services:
  caddy:
    image: caddy:latest
    container_name: remnanode-caddy
    restart: always
    ports:
      - "8443:8443"
    networks:
      - remnanode-network
    volumes:
      - ./Caddyfile:/etc/caddy/Caddyfile
      - ./www:/var/www/html
      - caddy_data:/data

networks:
  remnanode-network:
    external: true

volumes:
  caddy_data:
EOF
    echo "$(get_text SUCCESS_CADDY_COMPOSE)"

    # Настройка веб-страницы (заглушки)
    echo -e "\n--- $(get_text WEBPAGE_SETUP_HEADER) ---"
    echo "$(get_text WEBPAGE_SETUP_INFO1)"
    read -p "$(get_text ENTER_WEBPAGE_PATH)" WEB_FILE_PATH
    
    if [[ -n "$WEB_FILE_PATH" && "$WEB_FILE_PATH" != "0" ]]; then
        if [ -f "$WEB_FILE_PATH" ]; then
            sudo cp "$WEB_FILE_PATH" "$CADDY_DIR/www/index.html"
            echo "$(get_text SUCCESS_COPY_FILE)"
        else
            echo "$(get_text FILE_NOT_FOUND_SKIP)"
        fi
    else
        echo "$(get_text WEBPAGE_SKIP)"
    fi
    
    echo "$(get_text START_CADDY_CONTAINER)"
    cd "$CADDY_DIR"
    sudo docker-compose up -d
    if [ $? -ne 0 ]; then
        echo -e "${RED}$(get_text ERROR_START_CADDY)${NC}"
        echo "$(get_text CHECK_PORT_BUSY)"
        return 1
    fi
    echo "$(get_text CADDY_CONTAINER_STARTED)"
    sleep 3
    echo "$(get_text CADDY_INSTALL_COMPLETE)"
    sleep 2
}

# Функция-обертка для запуска ноды, которая проверяет логи
run_remnanode_and_check_logs() {
    cd /opt/remnanode
    echo "$(get_text START_REMNANODE_CONTAINER)"
    sudo docker-compose up -d
    if [ $? -ne 0 ]; then
        echo -e "${RED}$(get_text ERROR_START_REMNANODE)${NC}"
        return 1
    fi

    echo "$(get_text REMNANODE_SETUP_COMPLETE)"
    sleep 4

    echo -e "\n--- $(get_text CHECK_REMNANODE_LOGS_HEADER) ---"
    if sudo docker logs remnanode 2>&1 | grep -q "spawn xray error"; then
        echo -e "${RED}$(get_text ERROR_LOGS_FOUND)${NC}"
        echo "$(get_text ERROR_LOGS_REASONS)"
        echo "$(get_text ERROR_LOGS_HINT)"
    else
        echo -e "${GREEN}$(get_text LOGS_CLEAN)${NC}"
    fi
    sleep 2
}

select_vpn_method() {
    local choice_index
    declare -a vpn_options=(
        "$(get_text "VPN_METHOD_REALITY")"
        "$(get_text "VPN_METHOD_SELFSTEAL")"
    )

    select_menu \
        vpn_options \
        "" \
        choice_index \
        "$(get_text "VPN_METHOD_SELECT_HEADER")" \
        "$(get_text "VPN_METHOD_PROMPT")"

    if [ "$choice_index" -eq 1 ]; then
        # --- Режим Self-steal ---
        echo -e "\n${CYAN}$(get_text "SELFSTEAL_MODE_SELECTED")${NC}"
        sleep 2
        install_caddy_for_remnanode
    else
        # --- Режим Reality ---
        echo -e "\n${CYAN}$(get_text "REALITY_MODE_SELECTED")${NC}"
        sleep 2
        # Если Caddy запущен, останавливаем его, чтобы освободить порты 80/443
        if sudo docker ps --format '{{.Names}}' | grep -q "caddy"; then
            echo "$(get_text "CADDY_STOPPING_FOR_REALITY")"
            if sudo docker stop caddy; then
                echo "$(get_text "CADDY_STOPPED_SUCCESS")"
            else
                echo -e "${RED}$(get_text "CADDY_STOP_FAILED")${NC}"
            fi
            sleep 2
        fi
    fi
}

run_full_install() {
    install_docker
    setup_remnanode
    select_vpn_method # Эта функция теперь устанавливает Caddy при необходимости
    setup_firewall
    run_remnanode_and_check_logs # Запускаем ноду и проверяем логи в конце
    echo -e "\n${GREEN}🎉 $(get_text FULL_INSTALL_COMPLETE)${NC}"
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