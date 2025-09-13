#!/bin/bash
get_required_input() {
    local prompt_text="$1"
    local var_name="$2"
    
    while true; do
        read -p "$prompt_text" input_value
        if [[ -n "$input_value" ]]; then
            eval "$var_name=\"$input_value\""
            break
        else
            echo "$(get_text INPUT_REQUIRED)"
        fi
    done
}
get_password() {
    local prompt_text="$1"
    local var_name="$2"

    while true; do
        read -s -p "$prompt_text" input_value
        echo # Добавляем переход на новую строку для читаемости после скрытого ввода

        if [[ -n "$input_value" ]]; then
            eval "$var_name=\"$input_value\""
            break
        else
            echo "$(get_text PASSWORD_REQUIRED)"
        fi
    done
}
about_script() {
    clear
    echo -e "${ORANGE}ℹ️ $(get_text ABOUT_HEADER)${NC}"
    echo "-------------------------------------------------"
    
    echo -e "$(get_text ABOUT_INFO)"
    
    echo "-------------------------------------------------"
    echo -e "${GREEN}$(get_text PRESS_ENTER_TO_RETURN)${NC}"
    read -n 1
    start
}
resolve_domain_to_ip() {
    local domain=$1
    # Использование 'dig +short' для получения только IP-адреса
    local ip=$(dig +short "$domain" | grep -E '^[0-9]+\.[0-9]+\.[0-9]+\.[0-9]+$')
    
    if [[ -z "$ip" ]]; then
        echo "$(get_text ERROR_DOMAIN_RESOLVE_FAILED)" >&2
        return 1
    else
        echo "$ip"
        return 0
    fi
}
install_required_repos() {
    clear
    echo -e "${ORANGE}⚙️ Установка репозиториев${NC}"
    echo "---"
    echo -e "Этот шаг установит базовые пакеты и добавит официальные репозитории Docker, что необходимо для корректной работы всех компонентов.\n"

    if [ -f /etc/os-release ]; then
        . /etc/os-release
        case "$ID" in
            debian|ubuntu)
                echo -e "${GREEN}📦 Обнаружен Debian/Ubuntu. Установка необходимых репозиториев...${NC}"
                apt update -y
                apt install -y software-properties-common ca-certificates curl gnupg
                
                # Добавление репозитория Docker
                install -m 0755 -d /etc/apt/keyrings
                curl -fsSL https://download.docker.com/linux/debian/gpg | gpg --dearmor -o /etc/apt/keyrings/docker.gpg
                chmod a+r /etc/apt/keyrings/docker.gpg
                echo \
                  "deb [arch=$(dpkg --print-architecture) signed-by=/etc/apt/keyrings/docker.gpg] https://download.docker.com/linux/debian \
                  $(. /etc/os-release && echo "$VERSION_CODENAME") stable" | \
                  tee /etc/apt/sources.list.d/docker.list > /dev/null
                apt update -y
                ;;
            centos|fedora|rhel)
                echo -e "${GREEN}📦 Обнаружен CentOS/Fedora/RHEL. Установка необходимых репозиториев...${NC}"
                yum install -y yum-utils device-mapper-persistent-data lvm2
                yum-config-manager --add-repo https://download.docker.com/linux/centos/docker-ce.repo
                yum install -y docker-ce docker-ce-cli containerd.io
                ;;
            *)
                echo -e "${RED}❌ Неподдерживаемая операционная система: $ID${NC}"
                sleep 2
                return 1
                ;;
        esac
    else
        echo -e "${RED}❌ Не удалось определить операционную систему.${NC}"
        sleep 2
        return 1
    fi
    echo -e "\n${GREEN}✅ Установка необходимых репозиториев завершена!${NC}"
    sleep 2
}
toggle_ipv6() {
    clear
    echo -e "${ORANGE}$(get_text IPV6_TOGGLE_HEADER)${NC}"
    local ipv6_status=$(cat /proc/sys/net/ipv6/conf/all/disable_ipv6 2>/dev/null || echo "1")
    local status_text=""
    
    if [ "$ipv6_status" == "0" ]; then
        status_text="$(get_text IPV6_ENABLED)"
        echo -e "$(get_text IPV6_STATUS) ${GREEN}${status_text}${NC}"
        if yn_prompt "$(get_text PROMPT_DISABLE_IPV6)"; then
            sudo sysctl -w net.ipv6.conf.all.disable_ipv6=1 >/dev/null 2>&1
            sudo sysctl -w net.ipv6.conf.default.disable_ipv6=1 >/dev/null 2>&1
            echo -e "${GREEN}$(get_text IPV6_DISABLED_SUCCESS)${NC}"
        else
            echo "$(get_text OPERATION_CANCELLED)"
        fi
    else
        status_text="$(get_text IPV6_DISABLED)"
        echo -e "$(get_text IPV6_STATUS) ${RED}${status_text}${NC}"
        if yn_prompt "$(get_text PROMPT_ENABLE_IPV6)"; then
            sudo sysctl -w net.ipv6.conf.all.disable_ipv6=0 >/dev/null 2>&1
            sudo sysctl -w net.ipv6.conf.default.disable_ipv6=0 >/dev/null 2>&1
            echo -e "${GREEN}$(get_text IPV6_ENABLED_SUCCESS)${NC}"
        else
            echo "$(get_text OPERATION_CANCELLED)"
        fi
    fi
    echo ""
    read -p "Нажмите Enter для продолжения..."
}

save_iptables_rules() {
    clear
    echo -e "${ORANGE}$(get_text IPTABLES_SAVE_HEADER)${NC}"
    echo ""
    local save_path
    read -p "$(get_text IPTABLES_SAVE_PROMPT)" save_path
    
    if [[ -z "$save_path" ]]; then
        echo -e "${RED}$(get_text INPUT_REQUIRED)${NC}"
        sleep 1
        return
    fi
    
    sudo iptables-save > "$save_path"
    
    if [ $? -eq 0 ]; then
        echo -e "${GREEN}$(get_text IPTABLES_SAVE_SUCCESS)${NC}"
        echo -e "${WHITE}${save_path}${NC}"
    else
        echo -e "${RED}$(get_text ERROR_IPTABLES_SAVE)${NC}"
    fi
    echo ""
    read -p "Нажмите Enter для продолжения..."
}
setup_ssh_and_user() {
    echo "$(get_text SSH_SETUP_START)"
    sleep 0.5
    echo "$(get_text CHECK_SSH_PORT)"
    sleep 0.5
    if ! check_ssh_port; then
        echo "$(get_text SSH_PORT_CONFIGURING)"
        sleep 0.5
        sed -i "s/^#Port.*/Port $SSH_PORT/" /etc/ssh/sshd_config
        sed -i "s/^Port .*/Port $SSH_PORT/" /etc/ssh/sshd_config
    else
        echo "$(get_text SSH_PORT_ALREADY_SET)"
        sleep 0.5
    fi

    echo "$(get_text CHECK_SSH_SECURITY)"
    sleep 0.5
    if ! check_ssh_security; then
        echo "$(get_text SSH_SECURITY_CONFIGURING)"
        sed -i "s/^#PermitRootLogin.*/PermitRootLogin no/" /etc/ssh/sshd_config
        sed -i "s/^PermitRootLogin.*/PermitRootLogin no/" /etc/ssh/sshd_config
        sed -i "s/^#PasswordAuthentication.*/PasswordAuthentication no/" /etc/ssh/sshd_config
        sed -i "s/^PasswordAuthentication.*/PasswordAuthentication no/" /etc/ssh/sshd_config
        sed -i "s/^#ChallengeResponseAuthentication.*/ChallengeResponseAuthentication no/" /etc/ssh/sshd_config
        sed -i "s/^ChallengeResponseAuthentication.*/ChallengeResponseAuthentication no/" /etc/ssh/sshd_config
        sed -i "s/^#UsePAM.*/UsePAM no/" /etc/ssh/sshd_config
        sed -i "s/^UsePAM.*/UsePAM no/" /etc/ssh/sshd_config
    else
        echo "$(get_text SSH_SECURITY_ALREADY_SET)"
        sleep 0.5
    fi

    echo "$(get_text CHECK_USER)"
    sleep 0.5
    if ! check_user_exists; then
        echo "$(get_text USER_CREATING)"
        adduser --disabled-password --gecos "" "$NEW_USER"
        echo "$NEW_USER:$USER_PASS" | chpasswd
        usermod -aG sudo "$NEW_USER"
    else
        echo "$(get_text USER_ALREADY_EXISTS)"
        sleep 0.5
    fi

    echo "$(get_text CHECK_SSH_KEY)"
    sleep 0.5
    if ! check_ssh_key; then
        echo "$(get_text SSH_KEY_CONFIGURING)"
        sleep 0.5
        USER_HOME="/home/$NEW_USER"
        mkdir -p "$USER_HOME/.ssh"
        echo "$AUTHORIZED_KEY" > "$USER_HOME/.ssh/authorized_keys"
        chown -R "$NEW_USER:$NEW_USER" "$USER_HOME/.ssh"
        chmod 700 "$USER_HOME/.ssh"
        chmod 600 "$USER_HOME/.ssh/authorized_keys"
    else
        echo "$(get_text SSH_KEY_ALREADY_SET)"
        sleep 0.5
    fi

    echo "$(get_text SYSTEM_UPDATE)"
    sleep 0.5
    apt update && apt -y upgrade

    echo "$(get_text SSH_RESTART)"
    sleep 1
    systemctl restart sshd

    echo "$(get_text SSH_SETUP_COMPLETE)"
    sleep 0.5
}
view_config() {
    local CONFIG_FILE=".env"
    
    clear
    echo -e "${ORANGE}$(get_text VIEW_CONFIG_HEADER)${NC}"
    echo "-------------------------------------------------"
    
    if [ ! -f "$CONFIG_FILE" ]; then
        echo -e "${RED}$(get_text CONFIG_FILE_NOT_FOUND_VIEW)${NC}"
    else
        while IFS= read -r line; do
            if [ ${#line} -gt 50 ]; then
                echo "${line:0:50}..."
            else
                echo "$line"
            fi
        done < "$CONFIG_FILE"
    fi
    
    echo "-------------------------------------------------"
    echo -e "${GREEN}$(get_text PRESS_ENTER_TO_RETURN)${NC}"
    read -n 1
    start
}
edit_config() {
    local CONFIG_FILE=".env"
    
    clear
    echo -e "${ORANGE}$(get_text EDIT_CONFIG_HEADER)${NC}"
    echo ""
    
    # Проверка существования файла .env
    if [ ! -f "$CONFIG_FILE" ]; then
        echo -e "${RED}$(get_text CONF_FILE_NOT_FOUND_PROMPT_EDIT)${NC}"
        sleep 2
        start
        return
    fi
    
    if yn_prompt "$(get_text CONF_FILE_PROMPT_EDIT)"; then
        # === Повторный ввод и сохранение конфига ===
        get_required_input "$(get_text ENTER_SSH_PORT)" SSH_PORT
        get_required_input "$(get_text ENTER_NEW_USER)" NEW_USER
        get_password "$(get_text ENTER_PASSWORD)" USER_PASS
        get_required_input "$(get_text ENTER_DOMAIN_CADDY)" DOMAIN
        echo "-------------------------------------------------"
        echo "$(get_text SSH_KEY_INFO)"
        get_required_input "$(get_text ENTER_SSH_KEY)" AUTHORIZED_KEY
        echo "-------------------------------------------------"
        get_required_input "$(get_text ENTER_SSL_KEY)" SSL_CERT_KEY
        SSL_CERT_KEY="${SSL_CERT_KEY#*SSL_CERT=}"
        echo "-------------------------------------------------"
        echo "$(get_text ENTER_PANEL_DOMAIN)"
        sleep 2
        get_required_input "$(get_text ENTER_DOMAIN_FOR_NODE_IP)" REMNAWAVE_DOMAIN
    
        IPTABLES_CONF=$(resolve_domain_to_ip "$REMNAWAVE_DOMAIN")
        
        if [[ -z "$IPTABLES_CONF" ]]; then
            echo "[!] $(get_text MANUAL_IP_PROMPT)"
            get_required_input "$(get_text MANUAL_IP_INPUT)" IPTABLES_CONF
        fi
    
        echo "$(get_text SAVE_SETTINGS_START)"
        sleep 2
        cat > "$CONFIG_FILE" <<EOF
SSH_PORT="$SSH_PORT"
NEW_USER="$NEW_USER"
USER_PASS="$USER_PASS"
DOMAIN="$DOMAIN"
AUTHORIZED_KEY="$AUTHORIZED_KEY"
SSL_CERT_KEY="$SSL_CERT_KEY"
IP_PANEL="$IPTABLES_CONF"
EOF
        echo -e "${GREEN}$(get_text SAVE_SETTINGS_SUCCESS)${NC}"
        sleep 2
    else
        echo -e "${RED}$(get_text OPERATION_CANCELLED)${NC}"
        sleep 1
    fi
    
    echo "$(get_text RETURNING)";
    sleep 1;
    start;
}