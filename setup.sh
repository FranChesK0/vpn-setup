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

read -rp "Введите часовой пояс в формате Обалсть/Регион (По умолчанию: 'Europe/Moscow'): " timezone
if [ -z $timezone ]; then timezone="Europe/Moscow"; fi
# Update timezone
timedatectl set-timezone $timezone
msg_info "Часовой пояс обновлен: "
timedatectl

read -rp "Введите имя пользователя: (По умолчанию: 'vpnuser'): " username
if [ -z $username ]; then username="vpnuser"; fi
# Check if user does not exist
[[ -n $(egrep -i "^$username:" /etc/passwd) ]] && msg_error "Пользовтель $username уже существует" && exit 1

# Add user and grant privileges
useradd --create-home --shell "/bin/bash" --groups sudo -p "$(echo changeme | openssl passwd -1 -stdin)" $username
# Force password change
chage --lastday 0 $username
msg_warn "Пользователь с имененм '$username' и временным паролем 'changeme' создан"

msg_info "Создание SSH файлов..."
home_dir=/home/$username
# Create SSH directory
mkdir -p $home_dir/.ssh
# Create 'authorized_keys' file
touch $home_dir/.ssh/authorized_keys
# Adjust ownership and permissions
chmod 0700 $home_dir/.ssh
chmod 0600 $home_dir/.ssh/authorized_keys
chown -R $username:$username $home_dir/.ssh

read -rp "Вставьте ваш публичный SSH ключ: " pubkey
[[ -z $pubkey ]] && msg_error "Публичный ключ не был передан" && exit 1
# Add user SSH public key
echo $pubkey > $home_dir/.ssh/authorized_keys

# Create copy of SSH config file
cp /etc/ssh/sshd_config /etc/ssh/sshd_config.bak
msg_info "Копия настроек SSH сохранена в файле '/etc/ssh/sshd_config.bak'"

msg_info "Обновление конфигурации SSH..."
# Disable root login
sed -i -Ee 's/^#?(PermitRootLogin)[[:space:]]+.*/\1 no/g' /etc/ssh/sshd_config
# Enable public key authentication
sed -i -Ee 's/^#?(PubkeyAuthentication)[[:space:]]+.*/\1 yes/g' /etc/ssh/sshd_config
# Disable password authentication
sed -i -Ee 's/^#?(PasswordAuthentication)[[:space:]]+.*/\1 no/g' /etc/ssh/sshd_config

msg_info "Перезапуск службы SSH..."
# Restart SSH service
systemctl restart sshd

# Enable and start fail2ban
systemctl enable --now fail2ban &> /dev/null
systemctl start fail2ban &> /dev/null

msg_info "Установка Docker..."
# Add Docker's GPG key
install -m 0755 -d /etc/apt/keyrings
curl -fsSL https://download.docker.com/linux/debian/gpg -o /etc/apt/keyrings/docker.asc
chmod a+r /etc/apt/keyrings/docker.asc

# Add Docker reporsitory to apt sources
echo \
    "deb [arch=$(dpkg --print-architecture) signed-by=/etc/apt/keyrings/docker.asc] https://download.docker.com/linux/debian \
    $(. /etc/os-release && echo "$VERSION_CODENAME") stable" | \
    tee /etc/apt/sources.list.d/docker.list > /dev/null
apt update &> /dev/null

# Install Docker packages
apt install -y docker-ce docker-ce-cli containerd.io docker-buildx-plugin docker-compose-plugin &> /dev/null

# Add user to 'docker' group
usermod -aG docker $username

read -rp "Установить 3x-ui? [Y/n]: " install_xui
if [ -z $install_xui ]; then install_xui="y"; fi
if [[ $install_xui == [yY] ]]; then
    # Update hostname
    sed -i -Ee "s/(.*)SERVER-HOSTNAME(.*)/\1$(cat /etc/hostname)\2/g" $PWD/3x-ui/compose.yaml
    msg_info "Установка 3x-ui..."
    # Run 3x-ui Docker container
    docker compose -f $PWD/3x-ui/compose.yaml up -d &> /dev/null
fi

msg_info "Обновление правил UFW..."
# Setup default firewall rules
ufw default deny incoming
ufw default allow outgoing

# Allow SSH port and Web ports
ufw allow 22/tcp
ufw allow 80/tcp
ufw allow 443

# Enable firewall
ufw enable

# Change user
su $username
