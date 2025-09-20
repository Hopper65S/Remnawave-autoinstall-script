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
    

    # Проверяем, существует ли переменная SSL_CERT_KEY в текущей сессии
    if [ -z "$SSL_CERT_KEY" ]; then
        # Если переменной нет, пытаемся прочитать ее напрямую из .env файла
        local config_file="/opt/Remnawave-autoinstall-script/.env"
        if [ -f "$config_file" ] && grep -q "SSL_CERT_KEY" "$config_file"; then
            SSL_CERT_KEY=$(grep "SSL_CERT_KEY" "$config_file" | cut -d'=' -f2 | tr -d '"')
        else
            SSL_CERT_KEY=""
        fi
    fi

    echo "$(get_text CREATE_ENV_FILE)"
    # Используем printf для надежной записи
    printf "APP_PORT=2222\nSSL_CERT=%s\n" "$SSL_CERT_KEY" | sudo tee .env > /dev/null
    echo "$(get_text SUCCESS_ENV_FILE)"
    
    echo "$(get_text CHECK_DOCKER_COMPOSE)"
    if [ ! -f docker-compose.yml ]; then
        # --- ИСПРАВЛЕННЫЙ СИНТАКСИС HERE-DOCUMENT ---
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
    
    if ! command -v docker &> /dev/null || ! command -v docker compose &> /dev/null; then
        echo "$(get_text DOCKER_COMPOSE_NOT_INSTALLED)"
        echo "$(get_text DOCKER_COMPOSE_NOT_INSTALLED_HINT)"
        return 1
    fi
    
    local CADDY_DIR="/opt/remnanode_caddy"
    
    # Шаг 1: Принудительно останавливаем и удаляем старый контейнер, если он существует.
    if sudo docker ps -a --format '{{.Names}}' | grep -q "^remnanode-caddy$"; then
        echo "$(get_text CADDY_CONTAINER_DELETING)"
        sudo docker rm -f remnanode-caddy &>/dev/null
        echo "$(get_text CADDY_CONTAINER_DELETED)"
    fi

    # Шаг 2: Создаем директории
    echo "$(get_text CREATE_CADDY_DIRS)"
    sudo mkdir -p "$CADDY_DIR/www"
    
    # Шаг 3: Создаем Caddyfile. УБРАНА вся логика с доменами и SSL.
    # Caddy будет просто слушать порт 8443 и отдавать статику.
    echo "$(get_text CREATE_CADDYFILE)"
    local CADDYFILE_CONTENT
    CADDYFILE_CONTENT=$(cat <<-CADDYFILE_EOF
		$CADDY_DOMAIN:8443 {
	    root * /var/www/html
	    file_server {
	        index index.html
	    }
	}
	CADDYFILE_EOF
    )
    echo "$CADDYFILE_CONTENT" | sudo tee "$CADDY_DIR/Caddyfile" > /dev/null
    echo "$(get_text SUCCESS_CADDYFILE)"

    # Шаг 4: Создаем docker-compose.yml. УБРАНЫ порты 80 и 443.
    local COMPOSE_CONTENT
    COMPOSE_CONTENT=$(cat <<COMPOSE_EOF
services:
    caddy:
        image: caddy:latest
        container_name: remnanode-caddy
        restart: always
        ports:
            - "80:80"
            - "8443:8443"
        volumes:
            - ./Caddyfile:/etc/caddy/Caddyfile
            - ./www:/var/www/html
            - caddy-ssl-data:/data
volumes:
    caddy-ssl-data:
        driver: local
        external: false
        name: caddy-ssl-data
COMPOSE_EOF
    )
    echo "$COMPOSE_CONTENT" | sudo tee "$CADDY_DIR/docker-compose.yml" > /dev/null
    
    # Шаг 5: Запускаем Caddy
    echo "$(get_text START_CADDY_CONTAINER)"
    cd "$CADDY_DIR"
    sudo docker compose up -d &>/dev/null
    
    # Шаг 6: Проверяем, что контейнер запустился
    echo "$(get_text WAITING_FOR_CONTAINER_START)"
    for i in {1..10}; do
        if sudo docker ps --filter "name=remnanode-caddy" --filter "status=running" | grep -q "remnanode-caddy"; then
            echo -e "${GREEN}$(get_text CONTAINER_START_SUCCESS)${NC}"
            break
        fi
        sleep 2
    done

    if ! sudo docker ps --filter "name=remnanode-caddy" --filter "status=running" | grep -q "remnanode-caddy"; then
        echo -e "${RED}$(get_text ERROR_START_CADDY)${NC}"
        sudo docker logs remnanode-caddy --tail 20
        return 1
    fi
    
    # Шаг 7: Конфигурация заглушки
    echo -e "\n--- $(get_text WEBPAGE_SETUP_HEADER) ---"
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
    
    sleep 1
    echo -e "\n${GREEN}$(get_text CADDY_INSTALL_COMPLETE)${NC}"
    sleep 2
}

    



# Функция-обертка для запуска ноды, которая проверяет логи
run_remnanode_and_check_logs() {
    cd /opt/remnanode
    echo "$(get_text START_REMNANODE_CONTAINER)"
    sudo docker compose up -d
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
add_iptables_rule_if_not_exists() {
    # Проверяем наличие правила с помощью флага -C
    if ! sudo iptables -C "$@" &>/dev/null; then
        # Если правила нет (команда завершилась с ошибкой), добавляем его
        echo -n "-> $(get_text "FIREWALL_ADDING_RULE") "
        sudo iptables -I "$@"
        # Выводим само правило для наглядности
        echo "iptables -I $@"
    else
        # Если правило уже есть, сообщаем об этом
        echo "-> $(get_text "FIREWALL_RULE_EXISTS") iptables -I $@"
    fi
}

setup_firewall() {
    echo "$(get_text FIREWALL_SETUP_START)"
    sleep 1

    # Проверка, установлен ли iptables
    if ! command -v iptables &> /dev/null; then
        echo "$(get_text IPTABLES_NOT_FOUND)"
        sleep 2
        sudo apt-get update && sudo apt-get install -y iptables
        echo "$(get_text IPTABLES_INSTALL_SUCCESS)"
    else
        echo "$(get_text IPTABLES_ALREADY_INSTALLED)"
    fi
    sleep 1

    echo "$(get_text APPLYING_IPTABLES)"
    sleep 2


    # Проверяем, существует ли переменная IP_PANEL в текущей сессии
    if [ -z "$IP_PANEL" ]; then
        echo -e "${YELLOW}$(get_text "FIREWALL_IP_PANEL_NOT_FOUND")${NC}"
        echo "$(get_text "FIREWALL_READING_ENV")"
        
        # Если переменной нет, пытаемся прочитать ее напрямую из .env файла
        local config_file="/opt/Remnawave-autoinstall-script/.env"
        if [ -f "$config_file" ] && grep -q "IP_PANEL" "$config_file"; then
            # Извлекаем значение, убирая кавычки
            IP_PANEL=$(grep "IP_PANEL" "$config_file" | cut -d'=' -f2 | tr -d '"')
            echo -e "${GREEN}$(get_text "FIREWALL_IP_PANEL_READ_SUCCESS") $IP_PANEL${NC}"
        else
            echo -e "${RED}$(get_text "FIREWALL_IP_PANEL_READ_FAIL")${NC}"
            # Убедимся, что переменная точно пустая, если чтение не удалось
            IP_PANEL=""
        fi
        sleep 1
    fi

    # --- БЕЗОПАСНОЕ ДОБАВЛЕНИЕ ПРАВИЛ В INPUT ---

    echo "$(get_text "FIREWALL_ALLOW_ESTABLISHED")"
    add_iptables_rule_if_not_exists INPUT -m conntrack --ctstate ESTABLISHED,RELATED -j ACCEPT

    echo "$(get_text "FIREWALL_ALLOWING_SSH") $SSH_PORT"
    add_iptables_rule_if_not_exists INPUT -p tcp --dport "$SSH_PORT" -j ACCEPT

    echo "$(get_text "FIREWALL_ALLOWING_WEB")"
    add_iptables_rule_if_not_exists INPUT -p tcp --dport 80 -j ACCEPT
    add_iptables_rule_if_not_exists INPUT -p tcp --dport 443 -j ACCEPT

    # Теперь добавляем правило для ноды, ТОЛЬКО если IP_PANEL не пустая
    if [ -n "$IP_PANEL" ]; then
        echo "$(get_text "FIREWALL_ALLOWING_NODE") $IP_PANEL"
        add_iptables_rule_if_not_exists INPUT -p tcp -s "$IP_PANEL" --dport 2222 -j ACCEPT
    fi

    echo ""
    echo -e "${GREEN}$(get_text IPTABLES_SUCCESS)${NC}"
    sleep 1
    echo -e "${GREEN}$(get_text FIREWALL_SETUP_COMPLETE)${NC}"
    sleep 1
}

run_full_install() {
    install_docker
    setup_remnanode
    select_vpn_method # Эта функция теперь устанавливает Caddy при необходимости
    install_caddy_for_remnanode
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
    sudo docker stop remnanode-caddy &>/dev/null
    sudo docker rm remnanode-caddy &>/dev/null
    echo "$(get_text CLEANUP_CONTAINERS_SUCCESS)"
    sleep 1

    # Удаление директорий
    echo "$(get_text CLEANUP_DIRS)"
    sudo rm -rf /opt/remnanode /opt/remnanode_caddy
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