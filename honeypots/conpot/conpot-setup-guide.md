# Conpot Honeypot Setup Guide

This guide walks through deploying Conpot ICS/SCADA honeypot on Google Cloud Platform using Docker.

## Prerequisites

- Google Cloud Platform account (free tier available)
- Basic Docker knowledge
- SSH client

## Step 1: Create Google Cloud Instance

1. Log in to Google Cloud Console
2. Navigate to **Compute Engine** → **VM Instances** → **Create Instance**
3. Configure:
   - **Name:** `honeypot-conpot`
   - **Region:** us-central1 (or closest to your location)
   - **Machine type:** e2-micro (free tier eligible)
   - **Boot disk:** Ubuntu 22.04 LTS, 20GB
   - **Firewall:** Check both "Allow HTTP traffic" and "Allow HTTPS traffic"
4. Click **Create**
5. Note the external IP address

## Step 2: Reserve a Static IP (Recommended)

Google Cloud's ephemeral IPs change on reboot. Reserve a static IP:

1. Navigate to **VPC Network** → **IP Addresses**
2. Click **Reserve External Static Address**
3. Name: `conpot-static-ip`
4. Region: same as your instance
5. Attached to: `honeypot-conpot`

## Step 3: Configure Firewall Rules

Create a firewall rule allowing ICS protocol ports:

1. Navigate to **VPC Network** → **Firewall** → **Create Firewall Rule**
2. Configure:
   - **Name:** `allow-conpot-ports`
   - **Direction:** Ingress
   - **Targets:** All instances in the network
   - **Source IP ranges:** `0.0.0.0/0`
   - **Protocols and ports:**
     - TCP: `21, 80, 102, 502, 623, 2244, 44818`
     - UDP: `69, 161, 47808`

## Step 4: Connect to Instance

Use the SSH-in-browser option from Google Cloud Console, or set up SSH key authentication:

```bash
gcloud compute ssh honeypot-conpot
```

Or with SSH key:
```bash
ssh -i path/to/gcp-key shrushti@<YOUR_CONPOT_IP>
```

## Step 5: Move Real SSH to Port 2244

```bash
sudo nano /etc/ssh/sshd_config
```

Change `Port 22` to `Port 2244`, save, then:

```bash
sudo systemctl restart ssh
```

## Step 6: Install Docker

```bash
sudo apt update
sudo apt install -y docker.io
sudo systemctl enable docker
sudo systemctl start docker
sudo usermod -aG docker $USER
```

Log out and back in for group change.

## Step 7: Configure Docker Log Rotation

```bash
sudo nano /etc/docker/daemon.json
```

Add:
```json
{
  "log-driver": "json-file",
  "log-opts": {
    "max-size": "100m",
    "max-file": "3"
  }
}
```

Restart Docker:
```bash
sudo systemctl restart docker
```

## Step 8: Deploy Conpot Container

Conpot requires port remapping since the container runs services on non-standard internal ports:

```bash
sudo docker run -d \
  --name conpot \
  --restart always \
  -p 502:5020 \
  -p 102:10201 \
  -p 80:8800 \
  -p 161:16100/udp \
  -p 47808:47808/udp \
  -p 623:6230 \
  -p 44818:44818 \
  -p 21:2121 \
  -p 69:6969/udp \
  honeynet/conpot
```

Port mapping explanation:

| External Port | Internal Port | Service |
|--------------|---------------|---------|
| 502 | 5020 | Modbus |
| 102 | 10201 | S7comm |
| 80 | 8800 | HTTP |
| 161 | 16100 | SNMP |
| 47808 | 47808 | BACnet |
| 623 | 6230 | IPMI |
| 44818 | 44818 | EtherNet/IP |
| 21 | 2121 | FTP |
| 69 | 6969 | TFTP |

## Step 9: Verify Conpot is Running

```bash
sudo docker ps | grep conpot
sudo docker logs --tail 20 $(sudo docker ps -q --filter ancestor=honeynet/conpot)
```

You should see Conpot initializing each industrial protocol service.

## Step 10: Verify Ports are Listening

```bash
sudo ss -tlnp | grep docker
```

You should see Docker proxy listening on ports 21, 80, 102, 502, 623, 44818.

## Step 11: Test Conpot

From your Kali machine:

```bash
# Modbus discovery
nmap --script modbus-discover -p 502 <YOUR_CONPOT_IP>

# Siemens S7comm info
nmap --script s7-info -p 102 <YOUR_CONPOT_IP>

# HTTP test
curl http://<YOUR_CONPOT_IP>

# SNMP walk
snmpwalk -v2c -c public <YOUR_CONPOT_IP>

# EtherNet/IP enumeration
nmap -p 44818 <YOUR_CONPOT_IP>
```

Watch logs in real time during attacks:

```bash
sudo docker logs -f $(sudo docker ps -q --filter ancestor=honeynet/conpot)
```

## Step 12: Install Filebeat

```bash
wget -qO - https://artifacts.elastic.co/GPG-KEY-elasticsearch | sudo gpg --dearmor -o /usr/share/keyrings/elastic.gpg
echo "deb [signed-by=/usr/share/keyrings/elastic.gpg] https://artifacts.elastic.co/packages/8.x/apt stable main" | sudo tee /etc/apt/sources.list.d/elastic-8.x.list
sudo apt update
sudo apt install -y filebeat
```

## Step 13: Configure Filebeat

Get the exact Conpot log file path:

```bash
sudo docker inspect --format='{{.LogPath}}' $(sudo docker ps -q --filter ancestor=honeynet/conpot)
```

Copy this path and use it in the Filebeat config from `filebeat-configs/filebeat-conpot.yml`.

Critical settings to include:
- `type: log`
- `close_inactive: 24h`
- `scan_frequency: 5s`

These prevent Filebeat from closing the file after 5 minutes of inactivity, which is the default behavior that causes lost logs.

## Step 14: Fix Permissions and Start Filebeat

```bash
sudo chmod 644 $(sudo docker inspect --format='{{.LogPath}}' $(sudo docker ps -q --filter ancestor=honeynet/conpot))
sudo systemctl enable filebeat
sudo systemctl start filebeat
sudo filebeat test output
```

## Step 15: Verify End-to-End Pipeline

1. Attack Conpot from Kali (Modbus, S7, or HTTP)
2. Verify Conpot captured it: `sudo docker logs --tail 5 $(sudo docker ps -q --filter ancestor=honeynet/conpot)`
3. Verify Filebeat is forwarding: `sudo journalctl -u filebeat -n 20`
4. Open Kibana → **Discover** → filter `honeypot_type : "conpot"` → confirm logs appear

## Useful Conpot Commands

```bash
# Show only Modbus attacks
sudo docker logs $(sudo docker ps -q --filter ancestor=honeynet/conpot) 2>&1 | grep -i modbus | tail -10

# Show unique attacker IPs
sudo docker logs $(sudo docker ps -q --filter ancestor=honeynet/conpot) 2>&1 | grep -oE "[0-9]+\.[0-9]+\.[0-9]+\.[0-9]+" | sort | uniq -c | sort -rn | head -10

# Live attack monitoring
sudo docker logs -f $(sudo docker ps -q --filter ancestor=honeynet/conpot)
```

## Troubleshooting

**Container exits immediately:** Check logs: `sudo docker logs conpot`. Usually a port conflict — verify nothing else is listening on the same ports.

**No logs appearing in Kibana:** Common causes:
1. Wrong ELK IP in Filebeat config — verify with `grep hosts /etc/filebeat/filebeat.yml`
2. Filebeat registry stale — reset: `sudo rm -rf /var/lib/filebeat/registry && sudo systemctl restart filebeat`
3. `close_inactive` is too low — set to 24h
4. IP changed after reboot — reserve a static IP

**External IP changed:** This happens with ephemeral IPs. Always reserve a static IP for production honeypots.

**Conpot stops responding:** Restart the container: `sudo docker restart $(sudo docker ps -q --filter ancestor=honeynet/conpot)`
