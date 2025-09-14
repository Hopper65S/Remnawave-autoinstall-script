#!/bin/bash
get_valid_port() {
    local prompt="$1"
    local default_value="$2"
    local port_var=""

    while true; do
        read -p "$(get_text "$prompt")$(get_text 'DEFAULT_PROMPT' | sed "s/XXX/$default_value/")" port_var
        port_var="${port_var:-$default_value}"

        if [[ "$port_var" =~ ^[0-9]+$ ]] && (( port_var >= 1 && port_var <= 65535 )); then
            echo "$port_var"
            break
        else
            echo "$(get_text INVALID_PORT)"
            sleep 2
        fi
    done
}
install_warp() {
    echo "================================================"
    echo -e "${CYAN} $(get_text WARP_INSTALL_HEADER) ${NC}"
    echo "================================================"
    sleep 2

    echo -e "\n${CYAN}$(get_text WARP_PORT_HEADER)${NC}"
    echo -e "${YELLOW}$(get_text ENTER_WARP_PORT)${NC}"
    echo -e "${GREEN}$(get_text WARP_PORT_RECOMMENDATION)${NC}"
    
    local selected_port=$(get_valid_port "ENTER_WARP_PORT" "40000")
    echo -e "${GREEN}$(get_text PORT_SELECTED)${NC}"
    sleep 2

    if [[ $EUID -ne 0 ]]; then
        echo -e "${RED}$(get_text ERROR_ROOT_REQUIRED)${NC}"
        sleep 2
        return 1
    fi

    echo -e "\n${CYAN}$(get_text CHECKING_OS_HEADER)${NC}"
    sleep 2
    if [[ -f "/etc/os-release" ]]; then
        . /etc/os-release
        if [[ "$ID" != "ubuntu" && "$ID" != "debian" ]]; then
            echo -e "${RED}$(get_text ERROR_UNSUPPORTED_OS)${NC}"
            sleep 2
            return 1
        fi
        echo -e "${GREEN}$(get_text OS_DETECTED)${NC}"
    else
        echo -e "${RED}$(get_text ERROR_OS_DETECT_FAIL)${NC}"
        sleep 2
        return 1
    fi
    sleep 2

    echo -e "\n${CYAN}$(get_text INSTALLING_DEPENDENCIES_HEADER)${NC}"
    sleep 2
    sudo apt-get update -y
    sudo apt-get install -y curl gnupg2 apt-transport-https lsb-release ca-certificates
    echo -e "${GREEN}$(get_text DEPENDENCIES_SUCCESS)${NC}"
    sleep 2

    echo -e "\n${CYAN}$(get_text ADDING_REPO_HEADER)${NC}"
    sleep 2
    if ! sudo curl -fsSL https://pkg.cloudflareclient.com/pubkey.gpg | sudo gpg --dearmor | sudo tee /usr/share/keyrings/cloudflare-warp-archive-keyring.gpg >/dev/null; then
        echo -e "${RED}$(get_text ERROR_GPG_KEY)${NC}"
        sleep 2
        return 1
    fi
    
    if ! echo "deb [arch=amd64 signed-by=/usr/share/keyrings/cloudflare-warp-archive-keyring.gpg] https://pkg.cloudflareclient.com/ $(lsb_release -cs) main" | sudo tee /etc/apt/sources.list.d/cloudflare-client.list > /dev/null; then
        echo -e "${RED}$(get_text ERROR_REPO_ADD)${NC}"
        sleep 2
        return 1
    fi
    
    sudo apt-get update -y
    echo -e "${GREEN}$(get_text REPO_ADDED_SUCCESS)${NC}"
    sleep 2

    echo -e "\n${CYAN}$(get_text INSTALLING_WARP_HEADER)${NC}"
    sleep 2
    if ! sudo apt-get install -y cloudflare-warp; then
        echo -e "${RED}$(get_text ERROR_WARP_INSTALL)${NC}"
        sleep 2
        return 1
    fi
    echo -e "${GREEN}$(get_text WARP_INSTALL_SUCCESS)${NC}"
    sleep 2

    echo -e "\n${CYAN}$(get_text CONFIGURING_WARP_HEADER)${NC}"
    sleep 2
    
    echo -e "${YELLOW}$(get_text REGISTERING_WARP)${NC}"
    if ! sudo warp-cli registration new; then
        echo -e "${RED}$(get_text ERROR_WARP_REGISTRATION)${NC}"
        sleep 2
        return 1
    fi
    echo -e "${GREEN}$(get_text REGISTRATION_SUCCESS)${NC}"
    sleep 2
    
    echo -e "${YELLOW}$(get_text SETTING_PORT)${NC}"
    if ! sudo warp-cli proxy port "$selected_port"; then
        echo -e "${RED}$(get_text ERROR_PORT_SET)${NC}"
        sleep 2
        return 1
    fi
    echo -e "${GREEN}$(get_text PORT_SET_SUCCESS)${NC}"
    sleep 2

    echo -e "${YELLOW}$(get_text SETTING_PROXY_MODE)${NC}"
    if ! sudo warp-cli mode proxy; then
        echo -e "${RED}$(get_text ERROR_PROXY_MODE)${NC}"
        sleep 2
        return 1
    fi
    echo -e "${GREEN}$(get_text PROXY_MODE_SUCCESS)${NC}"
    sleep 2

    echo -e "\n${CYAN}$(get_text CONNECTING_WARP_HEADER)${NC}"
    sleep 2
    if ! sudo timeout 15 warp-cli connect; then
        echo -e "${RED}$(get_text ERROR_CONNECT)${NC}"
        sleep 2
        return 1
    fi
    echo -e "${GREEN}$(get_text CONNECTION_SUCCESS)${NC}"
    sleep 3

    clear
    echo "================================================"
    echo -e "${CYAN} $(get_text WARP_INSTALL_FINAL_SUCCESS) ${NC}"
    echo "================================================"
    
    local actual_port=$(sudo warp-cli settings list 2>/dev/null | grep -i "proxy.port" | awk '{print $2}')
    actual_port=${actual_port:-$selected_port}
    
    local warp_ip=$(curl --socks5 127.0.0.1:$actual_port -s -m 10 https://ifconfig.me)
    local country_info=$(curl --socks5 127.0.0.1:$actual_port -s -m 10 "https://ipapi.co/$warp_ip/country_name/")
    local city_info=$(curl --socks5 127.0.0.1:$actual_port -s -m 10 "https://ipapi.co/$warp_ip/city/")
    
    echo -e "\n${CYAN}$(get_text STATUS_INFO_HEADER)${NC}"
    echo "------------------------------------------------"
    echo -e "${GREEN}$(get_text STATUS): ${WHITE}$(get_text STATUS_CONNECTED)${NC}"
    echo -e "${GREEN}$(get_text PROXY_PORT): ${WHITE}$actual_port${NC}"
    [[ -n "$warp_ip" ]] && echo -e "${GREEN}$(get_text EXTERNAL_IP): ${WHITE}$warp_ip${NC}"
    if [[ -n "$country_info" && "$country_info" != "Undefined" ]]; then
        echo -e "${GREEN}$(get_text COUNTRY): ${WHITE}$country_info${NC}"
        [[ -n "$city_info" ]] && echo -e "${GREEN}$(get_text CITY): ${WHITE}$city_info${NC}"
    else
        echo -e "${YELLOW}$(get_text LOCATION): ${WHITE}$(get_text CLOUDFLARE_NETWORK)${NC}"
    fi
    echo "------------------------------------------------"
    
    echo -e "\n${CYAN}$(get_text MANAGEMENT_COMMANDS_HEADER):${NC}"
    echo "------------------------------------------------"
    echo -e "${GREEN}$(get_text CHECK_STATUS): ${WHITE}sudo warp-cli status${NC}"
    echo -e "${GREEN}$(get_text DISCONNECT): ${WHITE}sudo warp-cli disconnect${NC}"
    echo -e "${GREEN}$(get_text CONNECT): ${WHITE}sudo warp-cli connect${NC}"
    echo -e "${GREEN}$(get_text SETTINGS): ${WHITE}sudo warp-cli settings list${NC}"
    echo -e "${GREEN}$(get_text USE_PROXY): ${WHITE}export ALL_PROXY=socks5://127.0.0.1:$actual_port${NC}"
    echo "------------------------------------------------"
    sleep 2

    echo -e "\n${YELLOW}$(get_text SCRIPT_EXIT_TIMER)${NC}"
    for i in {30..1}; do
        echo -ne "${YELLOW}$(get_text TIMER_REMAINING) ${i} $(get_text SECONDS)...\033[0K\r${NC}"
        sleep 1
    done
    echo -e "\n"

    return 0
}

# Вспомогательная функция для проверки порта
check_warp_status() {
    while true; do
        clear
        echo "================================================"
        echo -e "      ${CYAN}$(get_text WARP_STATUS_HEADER)${NC}"
        echo "================================================"

        local status_output=$(sudo warp-cli status 2>/dev/null)
        
        if echo "$status_output" | grep -qE "Connected|Подключено"; then
            echo -e "${GREEN}$(get_text WARP_CONNECTED_SUCCESS)${NC}"
            sleep 2
            
            local actual_port=$(sudo warp-cli settings list 2>/dev/null | grep "WarpProxy on port" | awk '{print $NF}')
            
            if [[ -z "$actual_port" ]]; then
                echo -e "${RED}$(get_text ERROR_PORT_FAIL)${NC}"
            else
                local warp_ip=$(curl --socks5 127.0.0.1:$actual_port -s -m 10 https://ifconfig.me)
                local geo_info=$(curl --socks5 127.0.0.1:$actual_port -s -m 10 http://ip-api.com/json/$warp_ip)
                
                if [[ -n "$geo_info" ]]; then
                    local country_info=$(echo "$geo_info" | grep -o '"country":"[^"]*"' | awk -F'"' '{print $4}')
                    local city_info=$(echo "$geo_info" | grep -o '"city":"[^"]*"' | awk -F'"' '{print $4}')
                fi

                echo -e "\n${CYAN}$(get_text STATUS_INFO_HEADER)${NC}"
                echo "------------------------------------------------"
                echo -e "${GREEN}$(get_text STATUS): ${WHITE}$(get_text STATUS_CONNECTED)${NC}"
                echo -e "${GREEN}$(get_text PROXY_PORT): ${WHITE}$actual_port${NC}"
                [[ -n "$warp_ip" ]] && echo -e "${GREEN}$(get_text EXTERNAL_IP): ${WHITE}$warp_ip${NC}"
                
                if [[ -n "$country_info" && "$country_info" != "Undefined" ]]; then
                    echo -e "${GREEN}$(get_text COUNTRY): ${WHITE}$country_info${NC}"
                    [[ -n "$city_info" ]] && echo -e "${GREEN}  • Город: ${WHITE}$city_info${NC}"
                else
                    echo -e "${YELLOW}$(get_text LOCATION): ${WHITE}$(get_text CLOUDFLARE_NETWORK)${NC}"
                fi
                echo "------------------------------------------------"
            fi
        else
            echo -e "${RED}$(get_text WARP_NOT_CONNECTED)${NC}"
            echo -e "${YELLOW}$(get_text STATUS_OUTPUT_INFO)${NC}"
            echo "$status_output"
        fi
        
        echo -e "${CYAN}---$(get_text WARP_REFRESH_PROMPT_EXIT_ENTER)---${NC}"
        read -s -r -t 10 choice
        if [[ $? -eq 0 ]]; then
            break
        fi
    done
}
uninstall_warp() {
    echo "$(get_text WARP_PROXY_UNINSTALL_START)"
    sleep 2
    
    # Отключение интерфейса WARP
    if sudo warp-cli status | grep -q "Connected"; then
        echo -e "${ORANGE}$(get_text WARP_PROXY_STOPPING)${NC}"
        sleep 2
        sudo warp-cli disconnect &>/dev/null || true
    fi

    # Удаление пакетов Cloudflare WARP и WireGuard
    echo -e "${ORANGE}$(get_text WARP_PROXY_REMOVING_PACKAGES)${NC}"
    sleep 2
    sudo apt-get purge -y cloudflare-warp &>/dev/null || true
    sudo apt-get purge -y wireguard &>/dev/null || true
    sudo apt-get autoremove -y &>/dev/null || true
    
    # Удаление репозитория и ключа
    sudo rm -rf /etc/apt/sources.list.d/cloudflare-client.list &>/dev/null || true
    sudo rm -f /usr/share/keyrings/cloudflare-warp-archive-keyring.gpg &>/dev/null || true

    echo -e "${GREEN}$(get_text WARP_PROXY_UNINSTALL_COMPLETE)${NC}"
    sleep 3
}
disconnect_warp() {
    echo "================================================"
    echo -e "${CYAN} $(get_text WARP_DISCONNECT_HEADER) ${NC}"
    echo "================================================"
    sleep 1

    if sudo warp-cli status 2>/dev/null | grep -q "Connected"; then
        echo -e "${YELLOW}$(get_text WARP_DISCONNECTING_MSG)${NC}"
        if sudo warp-cli disconnect &>/dev/null; then
            echo -e "${GREEN}$(get_text WARP_DISCONNECT_SUCCESS)${NC}"
        else
            echo -e "${RED}$(get_text WARP_DISCONNECT_ERROR)${NC}"
            return 1
        fi
    else
        echo -e "${YELLOW}$(get_text WARP_ALREADY_DISCONNECTED)${NC}"
    fi

    echo -e "${GREEN}$(get_text OPERATION_COMPLETE)${NC}"
    sleep 2
    return 0
}
connect_warp() {
    echo "================================================"
    echo -e "${CYAN} $(get_text WARP_CONNECT_HEADER) ${NC}"
    echo "================================================"
    sleep 1

    # Проверка, установлен ли пакет `cloudflare-warp`
    if ! command -v warp-cli &> /dev/null; then
        echo -e "${RED}❌ $(get_text ERROR_WARP_NOT_INSTALLED)${NC}"
        echo -e "${YELLOW}ℹ️ $(get_text WARP_INSTALL_PROMPT)${NC}"
        sleep 3
        return 1
    fi
    
    # Проверка текущего статуса WARP
    if sudo warp-cli status 2>/dev/null | grep -q "Connected"; then
        echo -e "${YELLOW}$(get_text WARP_ALREADY_CONNECTED)${NC}"
    else
        echo -e "${YELLOW}$(get_text WARP_CONNECTING_MSG)${NC}"
        if sudo warp-cli connect &>/dev/null; then
            echo -e "${GREEN}$(get_text WARP_CONNECT_SUCCESS)${NC}"
        else
            echo -e "${RED}$(get_text WARP_CONNECT_ERROR)${NC}"
            return 1
        fi
    fi

    echo -e "${GREEN}$(get_text OPERATION_COMPLETE)${NC}"
    sleep 2
    return 0
}