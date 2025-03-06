#!/bin/bash
IP=$(ip route get 1.1.1.1 | awk '{print $7}')

sudo apt update
sudo apt install strongswan strongswan-pki libcharon-extra-plugins

clear

echo "PSK:"
read PSK
echo "server IP:"
read sIP

sudo bash -c "cat > /etc/ipsec.conf" <<EOF
config setup
    charondebug="all"
conn test
    keyexchange=ikev2
    authby=secret
    ike=aes256-sha256-modp2048
    esp=aes256-sha256
    left=$IP
    right=$sIP
    auto=add
EOF

sudo bash -c "cat > /etc/ipsec.secrets" <<EOF
: PSK "$PSK"
EOF

sudo systemctl restart strongswan-starter
sudo ipsec up test
