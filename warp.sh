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
    echo "          🚀 УСТАНОВКА WARP          "
    echo "================================================"
    sleep 2

    # Яркий и понятный запрос порта
    echo -e "\n${CYAN}🌐 ВЫБОР ПОРТА ДЛЯ WARP PROXY${NC}"
    echo -e "${YELLOW}↓ Введите порт для WARP прокси (по умолчанию: 40000)${NC}"
    echo -e "${GREEN}➤ Рекомендуется использовать порты от 10000 до 65535${NC}"
    
    local selected_port=$(get_valid_port "ENTER_WARP_PORT" "40000")
    echo -e "${GREEN}✅ Выбран порт: $selected_port${NC}"
    sleep 2

    # Проверка на права root
    if [[ $EUID -ne 0 ]]; then
        echo -e "${RED}❌ ОШИБКА: Требуются права root для установки WARP${NC}"
        sleep 2
        return 1
    fi

    echo -e "\n${CYAN}🔍 ПРОВЕРКА ОПЕРАЦИОННОЙ СИСТЕМЫ${NC}"
    sleep 2
    if [[ -f "/etc/os-release" ]]; then
        . /etc/os-release
        if [[ "$ID" != "ubuntu" && "$ID" != "debian" ]]; then
            echo -e "${RED}❌ ОШИБКА: Поддерживаются только Ubuntu и Debian${NC}"
            sleep 2
            return 1
        fi
        echo -e "${GREEN}✅ ОС: $PRETTY_NAME${NC}"
    else
        echo -e "${RED}❌ ОШИБКА: Не удалось определить ОС${NC}"
        sleep 2
        return 1
    fi
    sleep 2

    echo -e "\n${CYAN}📦 УСТАНОВКА ЗАВИСИМОСТЕЙ${NC}"
    sleep 2
    sudo apt-get update -y
    sudo apt-get install -y curl gnupg2 apt-transport-https lsb-release ca-certificates
    echo -e "${GREEN}✅ Зависимости установлены${NC}"
    sleep 2

    echo -e "\n${CYAN}➕ ДОБАВЛЕНИЕ РЕПОЗИТОРИЯ CLOUDFLARE${NC}"
    sleep 2
    if ! sudo curl -fsSL https://pkg.cloudflareclient.com/pubkey.gpg | sudo gpg --dearmor | sudo tee /usr/share/keyrings/cloudflare-warp-archive-keyring.gpg >/dev/null; then
        echo -e "${RED}❌ ОШИБКА: Не удалось добавить GPG ключ${NC}"
        sleep 2
        return 1
    fi
    
    if ! echo "deb [arch=amd64 signed-by=/usr/share/keyrings/cloudflare-warp-archive-keyring.gpg] https://pkg.cloudflareclient.com/ $(lsb_release -cs) main" | sudo tee /etc/apt/sources.list.d/cloudflare-client.list > /dev/null; then
        echo -e "${RED}❌ ОШИБКА: Не удалось добавить репозиторий${NC}"
        sleep 2
        return 1
    fi
    
    sudo apt-get update -y
    echo -e "${GREEN}✅ Репозиторий Cloudflare добавлен${NC}"
    sleep 2

    echo -e "\n${CYAN}📥 УСТАНОВКА CLOUDFLARE WARP${NC}"
    sleep 2
    if ! sudo apt-get install -y cloudflare-warp; then
        echo -e "${RED}❌ ОШИБКА: Не удалось установить WARP${NC}"
        sleep 2
        return 1
    fi
    echo -e "${GREEN}✅ WARP успешно установлен${NC}"
    sleep 2

    echo -e "\n${CYAN}⚙️  НАСТРОЙКА WARP${NC}"
    sleep 2
    
    echo -e "${YELLOW}📝 Регистрация в WARP...${NC}"
    if ! sudo warp-cli registration new; then
        echo -e "${RED}❌ ОШИБКА: Не удалось зарегистрироваться${NC}"
        sleep 2
        return 1
    fi
    echo -e "${GREEN}✅ Регистрация успешна${NC}"
    sleep 2
    
    echo -e "${YELLOW}🔧 Установка порта $selected_port...${NC}"
    if ! sudo warp-cli proxy port "$selected_port"; then
        echo -e "${RED}❌ ОШИБКА: Не удалось установить порт${NC}"
        sleep 2
        return 1
    fi
    echo -e "${GREEN}✅ Порт $selected_port установлен${NC}"
    sleep 2

    echo -e "${YELLOW}🔧 Установка режима прокси...${NC}"
    if ! sudo warp-cli mode proxy; then
        echo -e "${RED}❌ ОШИБКА: Не удалось установить режим прокси${NC}"
        sleep 2
        return 1
    fi
    echo -e "${GREEN}✅ Режим прокси активирован${NC}"
    sleep 2

    echo -e "\n${CYAN}🔗 ПОДКЛЮЧЕНИЕ К WARP${NC}"
    sleep 2
    if ! sudo timeout 15 warp-cli connect; then
        echo -e "${RED}❌ ОШИБКА: Не удалось подключиться${NC}"
        sleep 2
        return 1
    fi
    echo -e "${GREEN}✅ Подключение выполнено${NC}"
    sleep 3

    # Очистка экрана и вывод финального статуса
    clear
    echo "================================================"
    echo "           🎉 WARP УСТАНОВЛЕН И НАСТРОЕН 🎉"
    echo "================================================"
    
    # Получаем информацию о порте
    local actual_port=$(sudo warp-cli settings list 2>/dev/null | grep -i "proxy.port" | awk '{print $2}')
    actual_port=${actual_port:-$selected_port}
    
    # Проверяем работу прокси и получаем данные
    local warp_ip=$(curl --socks5 127.0.0.1:$actual_port -s -m 10 https://ifconfig.me)
    local country_info=$(curl --socks5 127.0.0.1:$actual_port -s -m 10 "https://ipapi.co/$warp_ip/country_name/")
    local city_info=$(curl --socks5 127.0.0.1:$actual_port -s -m 10 "https://ipapi.co/$warp_ip/city/")
    
    echo -e "\n${CYAN}📋 ИНФОРМАЦИЯ О СТАТУСЕ${NC}"
    echo "------------------------------------------------"
    echo -e "${GREEN}• Статус: ${WHITE}Подключено${NC}"
    echo -e "${GREEN}• Порт прокси: ${WHITE}$actual_port${NC}"
    [[ -n "$warp_ip" ]] && echo -e "${GREEN}• Внешний IP: ${WHITE}$warp_ip${NC}"
    if [[ -n "$country_info" && "$country_info" != "Undefined" ]]; then
        echo -e "${GREEN}• Страна: ${WHITE}$country_info${NC}"
        [[ -n "$city_info" ]] && echo -e "${GREEN}• Город: ${WHITE}$city_info${NC}"
    else
        echo -e "${YELLOW}• Локация: ${WHITE}Cloudflare Global Network${NC}"
    fi
    echo "------------------------------------------------"
    
    echo -e "\n${CYAN}📋 КОМАНДЫ ДЛЯ УПРАВЛЕНИЯ:${NC}"
    echo "------------------------------------------------"
    echo -e "${GREEN}• Проверить статус: ${WHITE}sudo warp-cli status${NC}"
    echo -e "${GREEN}• Отключить: ${WHITE}sudo warp-cli disconnect${NC}"
    echo -e "${GREEN}• Подключить: ${WHITE}sudo warp-cli connect${NC}"
    echo -e "${GREEN}• Настройки: ${WHITE}sudo warp-cli settings list${NC}"
    echo -e "${GREEN}• Использовать прокси: ${WHITE}export ALL_PROXY=socks5://127.0.0.1:$actual_port${NC}"
    echo "------------------------------------------------"
    sleep 2

    # Финальная пауза для чтения (30 секунд)
    echo -e "\n${YELLOW}⏳ Скрипт завершится через 30 секунд...${NC}"
    for i in {30..1}; do
        echo -ne "${YELLOW}⏰ Осталось: ${i} сек...\033[0K\r${NC}"
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
        echo -e "         ${CYAN}$(get_text WARP_STATUS_HEADER)${NC}"
        echo "================================================"

        local status_output=$(sudo warp-cli status 2>/dev/null)
        
        if echo "$status_output" | grep -qE "Connected|Подключено"; then
            echo -e "${GREEN}🎉 WARP УСПЕШНО ПОДКЛЮЧЕН!${NC}"
            sleep 2
            
            local actual_port=$(sudo warp-cli settings list 2>/dev/null | grep "WarpProxy on port" | awk '{print $NF}')
            
            if [[ -z "$actual_port" ]]; then
                echo -e "${RED}❌ Не удалось получить порт прокси. Проверьте настройки WARP.${NC}"
            else
                # Используем ifconfig.me для получения внешнего IP
                local warp_ip=$(curl --socks5 127.0.0.1:$actual_port -s -m 10 https://ifconfig.me)
                
                # Используем ip-api.com по HTTP, так как HTTPS требует платного тарифа
                local geo_info=$(curl --socks5 127.0.0.1:$actual_port -s -m 10 http://ip-api.com/json/$warp_ip)
                
                # Проверяем, что ответ не пуст
                if [[ -n "$geo_info" ]]; then
                    # Парсим JSON-ответ с помощью grep и awk
                    local country_info=$(echo "$geo_info" | grep -o '"country":"[^"]*"' | awk -F'"' '{print $4}')
                    local city_info=$(echo "$geo_info" | grep -o '"city":"[^"]*"' | awk -F'"' '{print $4}')
                fi

                echo -e "\n${CYAN}📋 ИНФОРМАЦИЯ О СТАТУСЕ${NC}"
                echo "------------------------------------------------"
                echo -e "${GREEN}• Статус: ${WHITE}Подключено${NC}"
                echo -e "${GREEN}• Порт прокси: ${WHITE}$actual_port${NC}"
                [[ -n "$warp_ip" ]] && echo -e "${GREEN}• Внешний IP: ${WHITE}$warp_ip${NC}"
                
                if [[ -n "$country_info" && "$country_info" != "Undefined" ]]; then
                    echo -e "${GREEN}• Страна: ${WHITE}$country_info${NC}"
                    [[ -n "$city_info" ]] && echo -e "${GREEN}• Город: ${WHITE}$city_info${NC}"
                else
                    echo -e "${YELLOW}• Локация: ${WHITE}Cloudflare Global Network${NC}"
                fi
                echo "------------------------------------------------"
            fi
        else
            echo -e "${RED}❌ WARP НЕ ПОДКЛЮЧЕН${NC}"
            echo -e "${YELLOW}Вывод статуса:${NC}"
            echo "$status_output"
        fi
        
        echo -e "${YELLOW}Чтобы выйти из этого раздела, введите 'exit'${NC}"
        echo -ne "${CYAN}➤ Введите 'exit' или нажмите Enter для обновления: ${NC}"
        read choice
        if [[ "$choice" == "exit" ]]; then
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