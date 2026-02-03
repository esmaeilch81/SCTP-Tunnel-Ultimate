#!/bin/bash
# =========================================================
# WIREGUARD + SCTP TUNNEL | ULTIMATE EDITION V2
# Author: Esmaeilch81
# Web Status Port: 5999 (Server Only)
# Speed Test: Integrated iperf3 logic
# =========================================================

# ================= Colors =================
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
PURPLE='\033[0;35m'
CYAN='\033[0;36m'
WHITE='\033[1;37m'
RAINBOW='\033[38;5;198m'
NC='\033[0m'

clear
echo -e "${RAINBOW}"
echo "╔══════════════════════════════════════════╗"
echo "║ 🚀 WireGuard + SCTP Tunnel ULTIMATE      ║"
echo "║ 👤 Author: Esmaeilch81                   ║"
echo "║ 🌐 Web Status: 5999 (Server Only)        ║"
echo "║ ⚡ Speed Test Module: Integrated         ║"
echo "╚══════════════════════════════════════════╝"
echo -e "${NC}"

# ================= Root =================
if [ "$EUID" -ne 0 ]; then
  echo -e "${RED}❌ Run as root${NC}"
  exit 1
fi

# ================= Packages =================
echo -e "${YELLOW}📦 Installing packages and dependencies...${NC}"
apt update -y
apt install -y wireguard wireguard-go socat curl openssl python3 ufw iperf3 qrencode psmisc

# ================= Sysctl =================
cat <<SYS > /etc/sysctl.d/99-tunnel.conf
net.core.default_qdisc=fq
net.ipv4.tcp_congestion_control=bbr
net.sctp.sctp_mem=100000 150000 200000
net.sctp.sctp_rmem=8388608
net.sctp.sctp_wmem=8388608
net.core.rmem_max=8388608
net.core.wmem_max=8388608
SYS
sysctl -p /etc/sysctl.d/99-tunnel.conf >/dev/null 2>&1
modprobe sctp

# ================= Keys =================
echo -e "${PURPLE}🔒 Security Layer: Generating Deterministic Keys${NC}"
read -s -p "🔐 Master Passphrase: " MASTER_SECRET
echo
SRV_PRIV=$(echo -n "${MASTER_SECRET}_server" | sha256sum | awk '{print $1}' | xxd -r -p | base64)
SRV_PUB=$(echo "$SRV_PRIV" | wg pubkey)
CLT_PRIV=$(echo -n "${MASTER_SECRET}_client" | sha256sum | awk '{print $1}' | xxd -r -p | base64)
CLT_PUB=$(echo "$CLT_PRIV" | wg pubkey)

# ================= Role =================
echo -e "${CYAN}Select Node Role:${NC}"
echo -e "1) Server (Foreign/Exit)"
echo -e "2) Client (Local/Iran)"
read -p "Selection: " ROLE

# ================= Config Logic =================
if [ "$ROLE" == "1" ]; then
  MY_PRIV=$SRV_PRIV
  PEER_PUB=$CLT_PUB
  LOCAL_IP="10.0.0.1"

cat <<WG > /etc/wireguard/wg0.conf
[Interface]
PrivateKey = $MY_PRIV
Address = $LOCAL_IP/24
ListenPort = 51820
MTU = 1200

[Peer]
PublicKey = $PEER_PUB
AllowedIPs = 10.0.0.2/32
WG

SOCAT_CMD="/usr/bin/socat -u SCTP-LISTEN:1234,fork,reuseaddr,sndbuf=8388608,rcvbuf=8388608 UDP4-SENDTO:127.0.0.1:51820"

# ---------- Web Status Service ----------
mkdir -p /opt/tunnel-web
cat <<'HTML' > /opt/tunnel-web/index.sh
#!/bin/bash
echo "Content-Type: text/html"
echo
echo "<html><body style='background:#1a1a1a;color:#00ff00;font-family:monospace;padding:20px;'>"
echo "<h1>🚀 SCTP Tunnel Status</h1><hr>"
echo "<h3>WireGuard Stats:</h3><pre style='color:#00ccff'>"
wg show
echo "</pre><h3>Service Status:</h3><pre>"
systemctl is-active sctp-tunnel
echo "</pre></body></html>"
HTML
chmod +x /opt/tunnel-web/index.sh

cat <<WEB > /etc/systemd/system/tunnel-web.service
[Unit]
After=network.target
[Service]
ExecStart=/usr/bin/python3 -m http.server 5999 --directory /opt/tunnel-web
Restart=always
[Install]
WantedBy=multi-user.target
WEB
systemctl enable tunnel-web --now >/dev/null 2>&1

# ---------- Speed Test Server ----------
systemctl stop iperf3 >/dev/null 2>&1
cat <<IPRF > /etc/systemd/system/iperf-server.service
[Unit]
After=network.target
[Service]
ExecStart=/usr/bin/iperf3 -s -p 5201
Restart=always
[Install]
WantedBy=multi-user.target
IPRF
systemctl enable iperf-server --now >/dev/null 2>&1

else
  MY_PRIV=$CLT_PRIV
  PEER_PUB=$SRV_PUB
  LOCAL_IP="10.0.0.2"
  
  read -p "🌐 Enter Server IP: " REMOTE_SRV_IP

cat <<WG > /etc/wireguard/wg0.conf
[Interface]
PrivateKey = $MY_PRIV
Address = $LOCAL_IP/24
MTU = 1200

[Peer]
PublicKey = $PEER_PUB
Endpoint = 127.0.0.1:51820
AllowedIPs = 10.0.0.1/32
PersistentKeepalive = 20
WG

SOCAT_CMD="/usr/bin/socat -u UDP4-LISTEN:51820,fork,reuseaddr,sndbuf=8388608,rcvbuf=8388608 SCTP:$REMOTE_SRV_IP:1234"
fi

# ================= Services Generation =================
cat <<SVC > /etc/systemd/system/sctp-tunnel.service
[Unit]
Description=SCTP Tunnel Service
After=network.target
[Service]
ExecStart=/bin/bash -c "$SOCAT_CMD"
Restart=always
RestartSec=3
[Install]
WantedBy=multi-user.target
SVC

systemctl daemon-reload
systemctl enable sctp-tunnel --now >/dev/null 2>&1
export WG_QUICK_USERSPACE_IMPLEMENTATION=wireguard-go
echo "export WG_QUICK_USERSPACE_IMPLEMENTATION=wireguard-go" >> /etc/environment
systemctl enable wg-quick@wg0 --now >/dev/null 2>&1

# ================= Firewall =================
echo -e "${YELLOW}🛡️  Configuring Firewall...${NC}"
ufw allow 51820/udp >/dev/null 2>&1
ufw allow 1234/sctp >/dev/null 2>&1
ufw allow 5201/tcp >/dev/null 2>&1 # iperf3
[ "$ROLE" == "1" ] && ufw allow 5999/tcp >/dev/null 2>&1
ufw --force enable >/dev/null 2>&1

# ================= Monitor Script =================
cat <<'MON' > /usr/local/bin/tunnel-monitor.sh
#!/bin/bash
while true; do
  ping -c2 10.0.0.1 &>/dev/null || ping -c2 10.0.0.2 &>/dev/null || {
    systemctl restart sctp-tunnel
    systemctl restart wg-quick@wg0
  }
  sleep 30
done
MON
chmod +x /usr/local/bin/tunnel-monitor.sh
nohup /usr/local/bin/tunnel-monitor.sh >/dev/null 2>&1 &

# ================= Backup =================
mkdir -p /backup/wireguard
cp /etc/wireguard/wg0.conf /backup/wireguard/wg0_$(date +%F).conf

# ================= Speed Test Logic =================
run_speedtest() {
    echo -e "${CYAN}⚡ Starting 10-second Speed Test over SCTP Tunnel...${NC}"
    if [ "$ROLE" == "2" ]; then
        iperf3 -c 10.0.0.1 -t 10
    else
        echo -e "${YELLOW}Server is in Listen mode. Run test from Client side.${NC}"
    fi
}

# ================= Final Dashboard =================
echo -e "${GREEN}✅ Tunnel ACTIVE & SECURED${NC}"
echo "------------------------------------------"
if [ "$ROLE" == "1" ]; then
    echo -e "${CYAN}🌐 Web Status: http://$(curl -s ifconfig.me):5999${NC}"
else
    echo -e "${WHITE}Internal IP: 10.0.0.2${NC}"
fi
echo "------------------------------------------"

# ================= Interactive Menu =================
while true; do
    echo -e "${BLUE}--- Tunnel Manager ---${NC}"
    echo "1) Check Status (wg show)"
    echo "2) Run Speed Test"
    echo "3) View Tunnel Logs"
    echo "4) Exit"
    read -p "Choose an option: " OPT
    case $OPT in
        1) wg show ;;
        2) run_speedtest ;;
        3) journalctl -u sctp-tunnel -n 20 ;;
        4) break ;;
        *) echo "Invalid option" ;;
    esac
done

echo -e "${RAINBOW}Happy Tunneling Esmaeilch81 🚀${NC}"
