#!/bin/bash

set -e

red='\033[0;31m'
green='\033[0;32m'
yellow='\033[0;33m'
plain='\033[0m'

function msg_info() {
    echo -e "${green}[INFO] $* ${plain}"
}

function msg_warn() {
    echo -e "${yellow}[WARN] $* ${plain}"
}

function msg_error() {
    echo -e "${red}[ERROR] $* ${plain}"
}

# Check root
[[ $EUID -ne 0 ]] && msg_error "Вы должны быть суперпользователем для запуска скрипта" && exit 1

msg_info "Обновление системы..."
# Update apt cache
apt update &> /dev/null
# Upgrade packages
apt upgrade -y &> /dev/null

msg_info "Установка зависимостей..."
# Install necessary packages
apt install -y sudo curl git ca-certificates iptables fail2ban ufw &> /dev/null
