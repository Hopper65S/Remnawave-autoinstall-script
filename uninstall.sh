#!/bin/bash
# Удаление скрипта
uninstall_script() {
    clear
    
    local SCRIPT_PATH="/opt/Remnawave-autoinstall-script"

    if [ ! -d "$SCRIPT_PATH" ]; then
        echo -e "\n${YELLOW}$(get_text SCRIPT_NOT_FOUND)${NC}"
        sleep 3
        return 1
    fi

    echo -e "\n${RED}$(get_text UNINSTALL_WARNING)${NC}"
    yn_prompt "$(get_text UNINSTALL_PROMPT)"
    if [ "$?" -ne 0 ]; then
        echo -e "${YELLOW}$(get_text UNINSTALL_CANCELLED)${NC}"
        sleep 2
        return 1
    fi

    echo -e "\n${CYAN}$(get_text UNINSTALLING_SCRIPT)${NC}"
    if sudo rm -rf "$SCRIPT_PATH"; then
        echo -e "${GREEN}$(get_text UNINSTALL_SUCCESS)${NC}"
    else
        echo -e "${RED}$(get_text UNINSTALL_FAILED)${NC}"
        sleep 3
        return 1
    fi
    
    echo -e "\n${YELLOW}$(get_text EXITING_SCRIPT)${NC}"
    sleep 2
    exit 0
}