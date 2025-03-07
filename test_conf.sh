#!/usr/bin/env bash

# -----------------------------
# Настройки, которые можно менять
# -----------------------------
# Предполагается, что у сервера IP = 192.168.3.36 (локальный адрес)
# Интерфейс с интернетом (или той сетью, куда будет NAT):
EXT_IF="eth0"

# VPN-пул адресов (виртуальная подсеть для клиентов)
# Клиенты будут получать адреса отсюда.
# Можете настроить любую незанятую внутреннюю подсеть,
# лишь бы не конфликтовала с существующими.
VPN_POOL="10.10.10.0/24"

# Ваш Pre-Shared Key:
PSK="MyStrongPSK"

# -----------------------------
# Установка пакетов StrongSwan
# -----------------------------
apt update -y
apt install -y strongswan libcharon-extra-plugins

# -----------------------------
# Конфигурация /etc/ipsec.conf
# -----------------------------
cat <<EOF > /etc/ipsec.conf
config setup
    # Для отладки можно убрать "charondebug=all" и поставить "ike=2, net=2" и т.п.
    charondebug="all"

conn ikev2-psk
    # IKEv2, аутентификация по PSK
    keyexchange=ikev2
    authby=secret

    ike=aes256-sha256-modp2048
    esp=aes256-sha256

    # Мы - "левая" сторона, сервер
    left=%any
    leftsubnet=0.0.0.0/0    # Раздаем default route для full-tunnel
    leftfirewall=yes        # Позволяет strongSwan самому поднять политики iptables

    # Клиенты (правая сторона) - любой IP
    right=%any
    rightsourceip=$VPN_POOL

    # Запускать соединение при наличии клиента
    auto=add
EOF

# -----------------------------
# Конфигурация /etc/ipsec.secrets
# -----------------------------
cat <<EOF > /etc/ipsec.secrets
: PSK "$PSK"
EOF

# -----------------------------
# Разрешаем форвардинг пакетов
# -----------------------------
echo "net.ipv4.ip_forward = 1" >> /etc/sysctl.conf
sysctl -p

# -----------------------------
# Настраиваем iptables:
# 1) Разрешаем IKE (UDP/500 и UDP/4500) с rate-limit (базовая защита от DDoS).
# 2) Включаем MASQUERADE для подсети VPN, чтобы клиенты могли ходить во внешнюю сеть.
# -----------------------------

# Сбросим цепочки и политику (будьте осторожны, если у вас уже есть правила!)
iptables -F
iptables -t nat -F
iptables -X
iptables -t nat -X

# Политика по умолчанию
iptables -P INPUT DROP
iptables -P FORWARD DROP
iptables -P OUTPUT ACCEPT

# Разрешаем lo-интерфейс
iptables -A INPUT -i lo -j ACCEPT

# Разрешаем уже установленные соединения
iptables -A INPUT -m state --state ESTABLISHED,RELATED -j ACCEPT

# 1) Разрешаем IKE (UDP 500 и 4500) с rate-limit
#    - burst ограничивает "залповую" атаку
#    - limit -- ограничение количества пакетов в секунду
iptables -A INPUT -p udp --dport 500  -m limit --limit 10/s --limit-burst 30 -j ACCEPT
iptables -A INPUT -p udp --dport 500  -j DROP
iptables -A INPUT -p udp --dport 4500 -m limit --limit 10/s --limit-burst 30 -j ACCEPT
iptables -A INPUT -p udp --dport 4500 -j DROP

# Разрешаем IPsec ESP (Protocol 50), если потребуется (хотя при NAT-T обычен трафик через 4500)
iptables -A INPUT -p esp -m limit --limit 10/s --limit-burst 30 -j ACCEPT
iptables -A INPUT -p esp -j DROP

# Разрешаем форвард для VPN-подсети
iptables -A FORWARD -s $VPN_POOL -j ACCEPT
iptables -A FORWARD -d $VPN_POOL -j ACCEPT

# NAT (MASQUERADE) для VPN-клиентов, которые будут ходить во вне
iptables -t nat -A POSTROUTING -s $VPN_POOL -o $EXT_IF -j MASQUERADE

# -----------------------------
# Перезапуск StrongSwan
# -----------------------------
systemctl enable strongswan
systemctl restart strongswan

echo "StrongSwan IKEv2 VPN-сервер настроен."
echo "PSK: $PSK"
echo "Подсеть VPN: $VPN_POOL"
echo "Не забудьте настроить клиент!"
