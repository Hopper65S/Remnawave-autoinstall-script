#!/bin/bash
# REMNAWAVE MANAGER SCRIPT by Hopper
# Colors
ORANGE='\033[93m'
GREEN='\033[32m'
RED='\033[0;31m'
NC='\033[0m' # No Color
WHITE='\033[1;37m'
CYAN='\033[0;36m'
# Initial system update and setup
clear
# apt install sudo &>/dev/null
if ! command -v sudo &>/dev/null; then
  echo "Installing sudo..."
  apt-get update &>/dev/null
  apt-get install sudo -y &>/dev/null
  echo "Sudo installed."
else
  echo "Sudo is already installed. Skipping."
fi

# sudo apt-get update &>/dev/null
echo "Updating package list..."
sudo apt-get update &>/dev/null
echo "Update complete."

# sudo apt-get install fonts-noto-color-emoji &>/dev/null
if dpkg-query -W -f='${Status}' fonts-noto-color-emoji 2>/dev/null | grep -q "install ok installed"; then
  echo "The fonts-noto-color-emoji package is already installed. Skipping."
else
  echo "Installing fonts-noto-color-emoji..."
  sudo apt-get install fonts-noto-color-emoji -y &>/dev/null
  echo "Fonts-noto-color-emoji installed."
fi

# sudo fc-cache -f -v &>/dev/null
echo "Updating font cache..."
sudo fc-cache -f -v &>/dev/null
echo "Font cache updated.
# Global variables
VERSION="v 0.6.1"
CONFIG_FILE=".env"
export DUMMY_IP="1.1.1.1"
 #Libraries and Functions
source "translations.sh"
source "menu.sh"
source "other_func.sh"
source "lib.sh"
source "Remnawave/remnanode.sh"
source "Remnawave/remnwave.sh"
source "api.sh"
source "warp.sh"
source "check.sh"
source "backup.sh"



function cleanup {
    echo -e "\033[?25h"  # Show cursor
    exit 1
}
trap cleanup SIGINT

main() {
    local choice_lang

    while true; do
        clear
        echo -e "${GREEN}Choose a language / Выберите язык: ${NC}"
        echo -e "${ORANGE}1) (EN) English${NC}"
        echo -e "${ORANGE}2) (RU) Русский${NC}"
        echo -e "${ORANGE}0) 🚪 Exit / Выход${NC}"
        echo ""
        read -p "Enter your choice / Введите ваш выбор: " choice_lang
        case "$choice_lang" in
            1) LANG_CHOICE="en"; break ;;
            2) LANG_CHOICE="ru"; break ;;
            0) echo "$(get_text EXITING_SCRIPT)"; exit 0 ;;
            *) echo "$(get_text INVALID_INPUT)"; sleep 2 ;;
        esac
    done

    # Check for .env file and load it
    if [ -f "$CONFIG_FILE" ]; then
        source "$CONFIG_FILE"
    else
        echo -e "${ORANGE}$(get_text CONFIG_REQUIRED_INFO)${NC}"
        
        # Новый вызов функции
        yn_prompt "$(get_text CONFIG_SETUP_PROMPT)"

        if [ "$?" -eq 0 ]; then
            edit_config_menu
        fi
    fi

    start
}

# Запуск основной функции
main