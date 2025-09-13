#!/bin/bash
select_menu() {
    local -n menu_options=$1
    local prompt="$2"
    local -n result_var=$3
    local header="$4"
    local prompt_text="$5" # <-- Новый параметр для текста "Пожалуйста выберете действие"
    
    local selected_index=0
    
    while true; do
        clear
        echo -e "${ORANGE}$header${NC}"
        echo ""
        
        for i in "${!menu_options[@]}"; do
            if [[ $i -eq $selected_index ]]; then
                echo -e "${GREEN}● ${menu_options[$i]}${NC}"
            else
                echo -e "${ORANGE}○ ${menu_options[$i]}${NC}"
            fi
        done
        
        echo ""
        echo -e "${ORANGE}$prompt_text${NC}" # <-- Выводим новый текст
        echo -e "${ORANGE}$(get_text MENU_PROMPT_SELECT)${NC}"
        
        read -sn1 -r key
        
        case "$key" in
            $'\x1b')
                read -sn1 -r -t 0.001 key
                read -sn1 -r -t 0.001 key
                case "$key" in
                    A)
                        ((selected_index = (selected_index - 1 + ${#menu_options[@]}) % ${#menu_options[@]}))
                        ;;
                    B)
                        ((selected_index = (selected_index + 1) % ${#menu_options[@]}))
                        ;;
                esac
                ;;
            "")
                result_var=$selected_index
                break
                ;;
        esac
    done
}
start() {
    declare -a main_menu_options
    main_menu_options=(
        "$(get_text MENU_NODE)"
        "$(get_text MENU_PANEL)"
        "$(get_text MENU_BACKUP)"
        "$(get_text MENU_OTHER)"
        "$(get_text MENU_WARP)"
        "$(get_text MENU_VIEW_CONFIG)"
        "$(get_text MENU_EDIT_CONFIG)"
        "$(get_text MENU_DELETE)"
        "$(get_text START_MENU_ABOUT)"
        "$(get_text MENU_EXIT)"
    )
    
    local choice_index
    select_menu \
        main_menu_options \
        "$(get_text MENU_PROMPT)" \
        choice_index \
        "$(get_text WELCOME_HEADER) ${VERSION}\n${GREEN}By Hopper${NC}"\
        "$(get_text MAIN_MENU_PROMPT)"
    
    case "$choice_index" in
        0) node_menu; sleep 1 ;;
        1) remnawave_menu; sleep 1 ;;
        2) backup_menu; sleep 1 ;;
        3) other_menu; sleep 1 ;;
        4) warp_menu; sleep 1 ;;
        5) view_config; sleep 1 ;;
        6) edit_config_menu; sleep 1 ;;
        7) delete_menu; sleep 1 ;;
        8) about_script; sleep 1 ;;
        9) echo "$(get_text EXITING_SCRIPT)"; exit 0 ;;
    esac
}
setup_config() {
    local choice_index
    local -a config_menu_options=(
        "$(get_text CONFIG_MENU_SSH)"
        "$(get_text CONFIG_MENU_NODE)"
        "$(get_text CONFIG_MENU_BACK)"
    )

    while true; do
        select_menu \
            config_menu_options \
            "" \
            choice_index \
            "$(get_text CONFIG_SETUP_HEADER)" \
            "$(get_text CONFIG_SUBMENU_PROMPT)"

        case "$choice_index" in
            0) configure_ssh; sleep 1 ;;
            1) configure_node; sleep 1 ;;
            2) return ;;
        esac
    done
}
edit_config_menu() {
    local choice_index
    local -a config_menu_options=(
        "$(get_text CONFIG_MENU_SSH)"
        "$(get_text CONFIG_MENU_NODE)"
        "$(get_text CONFIG_MENU_BACK)"
    )

    while true; do
        select_menu \
            config_menu_options \
            "" \
            choice_index \
            "$(get_text CONFIG_SETUP_HEADER)" \
            "$(get_text CONFIG_SUBMENU_PROMPT)"

        case "$choice_index" in
            0) configure_ssh; sleep 1 ;;
            1) configure_node; sleep 1 ;;
            2) start; sleep 1 ;; # Go back to main menu
        esac
    done
}
configure_ssh() {
    local SSH_PORT NEW_USER USER_PASS AUTHORIZED_KEY

    clear
    echo -e "${ORANGE}$(get_text SSH_CONFIG_HEADER)${NC}"
    echo "---"
    echo -e "$(get_text SSH_CONFIG_INFO)"
    echo -e "\n---"

    echo -e "🔑 ${GREEN}$(get_text SSH_PORT_HEADER)${NC}"
    echo -e "$(get_text SSH_PORT_INFO)"
    get_required_input "$(get_text SSH_PORT_PROMPT)" SSH_PORT

    echo -e "\n👤 ${GREEN}$(get_text SSH_USER_HEADER)${NC}"
    echo -e "$(get_text SSH_USER_INFO)"
    get_required_input "$(get_text SSH_USER_PROMPT)" NEW_USER

    echo -e "\n🔑 ${GREEN}$(get_text SSH_PASSWORD_HEADER)${NC}"
    echo -e "$(get_text SSH_PASSWORD_INFO)"
    get_password "$(get_text SSH_PASSWORD_PROMPT)" USER_PASS
    echo ""

    echo -e "\nℹ️ ${GREEN}$(get_text SSH_KEY_HEADER)${NC}"
    echo -e "$(get_text SSH_KEY_INFO)"
    get_required_input "$(get_text SSH_KEY_PROMPT)" AUTHORIZED_KEY
    echo "---"

    echo "$(get_text SAVE_SETTINGS_START)"
    if [ ! -f "$CONFIG_FILE" ]; then touch "$CONFIG_FILE"; fi
    sed -i '/^SSH_PORT=/d' "$CONFIG_FILE"
    sed -i '/^NEW_USER=/d' "$CONFIG_FILE"
    sed -i '/^USER_PASS=/d' "$CONFIG_FILE"
    sed -i '/^AUTHORIZED_KEY=/d' "$CONFIG_FILE"

    echo "SSH_PORT=\"$SSH_PORT\"" >> "$CONFIG_FILE"
    echo "NEW_USER=\"$NEW_USER\"" >> "$CONFIG_FILE"
    echo "USER_PASS=\"$USER_PASS\"" >> "$CONFIG_FILE"
    echo "AUTHORIZED_KEY=\"$AUTHORIZED_KEY\"" >> "$CONFIG_FILE"
    echo "$(get_text SAVE_SETTINGS_SUCCESS)"
    sleep 2
}

configure_node() {
    local IP_PANEL DOMAIN SSL_CERT_KEY CADDY_DOMAIN
    
    clear
    echo -e "${ORANGE}$(get_text NODE_CONFIG_HEADER)${NC}"
    echo "---"
    echo -e "$(get_text NODE_CONFIG_INFO)"
    echo "---"

    local ip_or_domain_choice
    declare -a ip_domain_options=(
        "1) По домену"
        "2) По IP-адресу"
    )
    
    select_menu \
        ip_domain_options \
        "" \
        ip_or_domain_choice \
        "🌐 ${GREEN}$(get_text NODE_CONNECT_HEADER)${NC}" \
        "$(get_text MENU_PROMPT_SELECT)"

    if [ "$ip_or_domain_choice" -eq 0 ]; then # Domain
        echo -e "\n🌐 ${GREEN}$(get_text NODE_DOMAIN_HEADER)${NC}"
        get_required_input "$(get_text NODE_DOMAIN_PROMPT)" PANEL_INPUT
        IP_PANEL=$(dig +short "$PANEL_INPUT")
        if [ -z "$IP_PANEL" ]; then
            echo "$(get_text NODE_DOMAIN_ERROR)"
            sleep 2
            return
        fi
        DOMAIN="$PANEL_INPUT"
    else # IP Address
        echo -e "\n⌨️ ${GREEN}$(get_text NODE_IP_HEADER)${NC}"
        get_required_input "$(get_text NODE_IP_PROMPT)" IP_PANEL
        DOMAIN="0"
    fi

    echo "---"
    echo -e "$(get_text CADDY_INFO)"
    get_required_input "$(get_text CADDY_PROMPT)" CADDY_DOMAIN
    echo "---"

    echo -e "🔑 ${GREEN}$(get_text SSL_KEY_HEADER)${NC}"
    echo -e "$(get_text SSL_KEY_INFO)"
    get_required_input "$(get_text SSL_KEY_PROMPT)" SSL_CERT_KEY
    
    SSL_CERT_KEY=$(echo "$SSL_CERT_KEY" | sed 's/SSL_CERT=\|SSL_CERT="//; s/"$//')
    echo "---"

    echo "$(get_text SAVE_SETTINGS_START)"
    if [ ! -f "$CONFIG_FILE" ]; then touch "$CONFIG_FILE"; fi
    sed -i '/^IP_PANEL=/d' "$CONFIG_FILE"
    sed -i '/^DOMAIN=/d' "$CONFIG_FILE"
    sed -i '/^CADDY_DOMAIN=/d' "$CONFIG_FILE"
    sed -i '/^SSL_CERT_KEY=/d' "$CONFIG_FILE"

    echo "IP_PANEL=\"$IP_PANEL\"" >> "$CONFIG_FILE"
    echo "DOMAIN=\"$DOMAIN\"" >> "$CONFIG_FILE"
    echo "CADDY_DOMAIN=\"$CADDY_DOMAIN\"" >> "$CONFIG_FILE"
    echo "SSL_CERT_KEY=\"$SSL_CERT_KEY\"" >> "$CONFIG_FILE"
    echo "$(get_text SAVE_SETTINGS_SUCCESS)"
    sleep 2
}
remnawave_menu() {
    while true; do
        declare -a panel_menu_options
        panel_menu_options=(
            "$(get_text PANEL_MENU_FULL_INSTALL)"
            "$(get_text PANEL_MENU_UPLOAD_DB)"
            "$(get_text PANEL_MENU_CHANGE_DOMAIN)"
            "$(get_text PANEL_MENU_CHECK_ERRORS)"
            "$(get_text PANEL_MENU_CADDY_ONLY)"
            "$(get_text PANEL_MENU_STATUS)"
            "$(get_text GO_BACK)"
        )
        local choice_index
        select_menu \
            panel_menu_options \
            "$(get_text MENU_PROMPT)" \
            choice_index \
            "$(get_text PANEL_MENU_HEADER) ${VERSION}" \
            "$(get_text PANEL_MENU_PROMPT)"
        
        case "$choice_index" in
            0) setup_remnawave; break ;;
            1) upload_db; break ;;
            2) change_panel_domain; break ;;
            3) check_logs_and_suggest_fix; break ;;
            4) install_caddy_docker; break ;;
            5) check_panel_status; break ;;
            6) echo "$(get_text RETURNING)"; sleep 1; start; ;; # <-- Изменено
        esac
    done
}

delete_menu() {
    while true; do
        clear
        echo ""
        declare -a delete_menu_options
        delete_menu_options=(
            "$(get_text MENU_CLEANUP_NODE)"
            "$(get_text MENU_BACK)"
        )
        local choice_index
        select_menu \
            delete_menu_options \
            "$(get_text MENU_PROMPT)" \
            choice_index \
            "$(get_text MENU_HEADER_DELETE)" \
            "$(get_text MENU_PROMPT)"
        
        case "$choice_index" in
            0) cleanup_remnanode; sleep 1 ;;
            1) echo "$(get_text RETURNING)"; sleep 1; start; ;; 
        esac
    done
}

other_menu() {
    while true; do
        declare -a other_menu_options
        other_menu_options=(
            "$(get_text OTHER_MENU_REPOSITORIES)" # Новый пункт
            "$(get_text OTHER_MENU_SSH_USER)"
            "$(get_text OTHER_MENU_IPV6_TOGGLE)"
            "$(get_text OTHER_MENU_IPTABLES_SAVE)"
            "$(get_text GO_BACK)"
        )
        local choice_index
        select_menu \
            other_menu_options \
            "$(get_text MENU_PROMPT)" \
            choice_index \
            "$(get_text OTHER_SETTINGS_HEADER)" \
            "$(get_text OTHER_MENU_PROMPT)"

        case "$choice_index" in
            0) install_required_repos; sleep 1; other_menu ;;
            1) setup_ssh_and_user; break ;;
            2) toggle_ipv6; sleep 1 ;;
            3) save_iptables_rules; sleep 1 ;;
            4) echo "$(get_text RETURNING)"; sleep 1; start ;;
        esac
    done
}
backup_menu() {
    while true; do
        declare -a backup_menu_options
        backup_menu_options=(
            "$(get_text BACKUP_DB_ONLY)"
            "$(get_text BACKUP_DB_AND_REMNASOFT)"
            "$(get_text BACKUP_OPT_DIR)"
            "$(get_text DISABLE_TELEGRAM_SENDING)"
            "$(get_text GO_BACK)"
        )
        local choice_index
        select_menu \
            backup_menu_options \
            "$(get_text MENU_PROMPT)" \
            choice_index \
            "$(get_text BACKUP_MENU_HEADER)" \
            "$(get_text BACKUP_MENU_PROMPT)"

        case "$choice_index" in
            0) run_backup_logic "db"; sleep 2; break ;;
            1) run_backup_logic "db_and_remnawave"; sleep 2; break ;;
            2) run_backup_logic "all_opt"; sleep 2; break ;;
            3) disable_telegram_backup; sleep 2; break ;;
            4) echo "$(get_text RETURNING)"; sleep 1; start ;;
        esac
    done
}
warp_menu() {
    while true; do
        declare -a warp_menu_options
        warp_menu_options=(
            "$(get_text WARP_PROXY_MENU_INSTALL)"
            "$(get_text WARP_PROXY_MENU_UNINSTALL)"
            "$(get_text WARP_PROXY_MENU_STATUS)"
            "$(get_text GO_BACK)"
        )
        local choice_index
        select_menu \
            warp_menu_options \
            "$(get_text MENU_PROMPT)" \
            choice_index \
            "$(get_text WARP_PROXY_MENU_HEADER) ${VERSION}" \
            "$(get_text WARP_PROXY_PROMPT)"
        
        case "$choice_index" in
            0) install_warp; break ;;
            1) uninstall_warp; break ;;
            2) check_warp_status; break ;;
            3) echo "$(get_text RETURNING)"; sleep 1; start; ;; 
        esac
    done
}

node_menu() {
    while true; do
        declare -a node_menu_options
        node_menu_options=(
            "$(get_text NODE_MENU_FULL_INSTALL)"
            "$(get_text NODE_MENU_DOCKER_ONLY)"
            "$(get_text NODE_MENU_NODE_ONLY)"
            "$(get_text NODE_MENU_CADDY_ONLY)"
            "$(get_text NODE_MENU_FIREWALL_ONLY)"
            "$(get_text NODE_MENU_ADD_NODE_AUTO)"
            "$(get_text GO_BACK)"
        )
        local choice_index
        select_menu \
            node_menu_options \
            "$(get_text MENU_PROMPT)" \
            choice_index \
            "$(get_text NODE_MENU_HEADER) ${VERSION}" \
            "$(get_text NODE_MENU_PROMPT)"

        case "$choice_index" in
            0) run_full_install; break ;;
            1) install_docker; break ;;
            2) setup_remnanode; break ;;
            3) install_caddy_docker_remnanode; break ;;
            4) setup_firewall; break ;;
            5) add_remnawave_node_auto; break ;;
            6) echo "$(get_text RETURNING)"; sleep 1; start; ;; # <-- ИЗМЕНЕНО: вызов `start`
        esac
    done
}