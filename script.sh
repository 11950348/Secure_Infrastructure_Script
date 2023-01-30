#!/bin/bash
#Author: Nathan
#About: This is a Bash script to install and configure WireGuard, PiHole, Unbound.
#Target OS: Digital Ocean Debian Droplet

CYAN='\033[0;36m'
NC='\033[0m'

clear
echo -e "${CYAN}Starting Script!${NC}"

#Update
echo -e "\n${CYAN}Updating...${NC}"
sudo apt update -y
#sudo apt upgrade -y

#Install Firewall
echo -e "\n${CYAN}Installing Firewall...${NC}"
sudo apt install firewalld -y
sudo systemctl enable firewalld --now

# Enabling IP Forwarding
echo -e "\n${CYAN}Enabling IP Forwarding...${NC}"
sysctl -w net.ipv4.ip_forward=1
sed -i "29i net.ipv4.ip_forward=1" /etc/sysctl.conf
#sudo sysctl -p

#Installing and configuring WireGuard
echo -e "\n${CYAN}Installing WireGuard...${NC}"

#Get Host Public Key.
echo -e "\n${CYAN}Please add your Public WireGuard key from WireGuard Client!${NC}" 
read -p 'Host Public Key: ' HOSTPUBLICKEY
sudo apt install wireguard -y
cd /etc/wireguard

#Generate Private and Public Keys.
umask 077; wg genkey | tee privatekey | wg pubkey > publickey
SERVERPRIVATEKEY=$(cat privatekey)

#Create Server Config File.
touch /etc/wireguard/wg0.conf
cat >> /etc/wireguard/wg0.conf << $CONFIG
[Interface]
Address = 192.168.2.1/24
ListenPort = 48965
PrivateKey = $SERVERPRIVATEKEY
[Peer]
#Client One
PublicKey = $HOSTPUBLICKEY
AllowedIPs = 192.168.2.2/32
$CONFIG

#Bring up Interface
echo -e "\n${CYAN}Bringing up interface.${NC}"
systemctl enable wg-quick@wg0 --now
wg

#WireGuard Firewall Rules
echo -e "\n${CYAN}Adding Firewall Rules.${NC}"
firewall-cmd --permanent --add-port=48965/udp
firewall-cmd --permanent --add-masquerade
firewall-cmd --reload
firewall-cmd --list-all
firewall-cmd --zone=internal --add-interface=wg0
firewall-cmd --permanent --zone=internal --add-masquerade
firewall-cmd --zone=internal --list-all

#Generate config for the WireGuard Client on the Host machine
sudo apt install dnsutils -y
SERVERIP=$(dig +short myip.opendns.com @resolver1.opendns.com)
cd /etc/wireguard
SERVERPUBLICKEY=$(cat publickey)
echo -e "\n${CYAN}---------------Generated Host Config---------------\n"
echo [Interface]
echo PrivateKey =
echo Address = 192.168.2.2/24
echo DNS = 192.168.2.1
echo
echo [Peer]
echo PublicKey = $SERVERPUBLICKEY
echo AllowedIPs = 0.0.0.0/0, ::/0
echo Endpoint = $SERVERIP:48965 
echo -e "\n---------------Generated Host Config---------------${NC}\n"
echo -e "${CYAN}Setup Complete. Please paste into WireGuard - do NOT connect yet!${NC}"
read -p "Press any [key] to continue script..."

#Install Docker if not installed already
if [ -x "$(command -v docker)" ]; then
    echo -e "\n${CYAN}Docker Installed - Skipping!${NC}"
else
    echo -e "\n${CYAN}Installing Docker!${NC}"
    sudo apt-get remove docker docker-engine docker.io containerd runc
    sudo apt-get update -y
    curl -fsSL https://get.docker.com -o get-docker.sh
    sudo sh get-docker.sh
    sudo systemctl restart docker
fi

#Install Unbound
echo -e "${CYAN}Installing Unbound!${NC}"
docker run -d \
--name=unbound \
-v unbound:/opt/unbound/etc/unbound/ \
-p 192.168.2.1:5353:53/tcp \
-p 192.168.2.1:5353:53/udp \
--restart=unless-stopped \
mvance/unbound:latest
#Should see: SERVFAIL + NO IP
dig fail01.dnssec.works @192.168.2.1 -p 5353
#Should see: NOERROR + an IP
dig dnssec.works @192.168.2.1 -p 5353

#Install PiHole
echo -e "\n${CYAN}Installing PiHole!${NC}"
read -p 'Set PiHole Password: ' PiHolePass
docker run -d \
--name pihole \
-p 192.168.2.1:53:53/tcp -p 192.168.2.1:53:53/udp \
-p 192.168.2.1:8888:80 \
-e TZ="America/Chicago" \
-e WEBPASSWORD=$PiHolePass \
--dns=127.0.0.1 --dns=1.1.1.1 \
--restart=unless-stopped \
pihole/pihole:latest


#Manual Config Information
sudo docker ps
echo -e "\n${CYAN}---------------Manual Config Required---------------\n"
echo -e "1. Write down URLs and open Example URL in browser for PiHole!"
echo -e "   Note: You will not have internet until PiHole is configured!\n"
echo -e "2. Connect to WireGuard!"
echo -e "   Note: You will be disconnected from SSH!\n"
echo -e "3. Reconnect to SSH and configure PiHole!\n"
echo -e "Manual configuration for PiHole using Unbound for DNS:"
echo -e "PiHole Login: http://192.168.2.1:8888/admin/login.php"
echo -e "Unbound DNS IP: 192.168.2.1#5353"
echo -e "See Example: https://imgbox.com/dGtF5jOk\n"
echo -e "\n---------------Manual Config Required---------------${NC}\n"