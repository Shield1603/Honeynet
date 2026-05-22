# Dionaea Honeypot Setup Guide

This guide walks through deploying Dionaea malware capture honeypot on an Oracle Cloud instance using Docker.

## Prerequisites

- Oracle Cloud account
- Basic Docker knowledge
- SSH access to your instance

## Step 1: Create Oracle Cloud Instance

1. Log in to Oracle Cloud Console
2. Navigate to **Compute** → **Instances** → **Create Instance**
3. Configure:
   - **Name:** `honeypot-dionaea`
   - **Image:** Ubuntu 22.04
   - **Shape:** VM.Standard.E2.1.Micro (free tier)
   - **Boot volume:** At least 50GB recommended (Dionaea collects malware binaries)
4. Use the same SSH key as your Cowrie instance for convenience
5. Note the public IP address

## Step 2: Configure Firewall Rules

Allow these ports in your VCN security list:

| Protocol | Port | Source | Service |
|----------|------|--------|---------|
| TCP | 21 | 0.0.0.0/0 | FTP |
| TCP | 23 | 0.0.0.0/0 | Telnet |
| TCP | 25 | 0.0.0.0/0 | SMTP |
| TCP | 80 | 0.0.0.0/0 | HTTP |
| TCP | 443 | 0.0.0.0/0 | HTTPS |
| TCP | 445 | 0.0.0.0/0 | SMB |
| TCP | 1433 | 0.0.0.0/0 | MSSQL |
| TCP | 3306 | 0.0.0.0/0 | MySQL |
| TCP | 5060 | 0.0.0.0/0 | SIP |
| UDP | 69 | 0.0.0.0/0 | TFTP |
| TCP | 2244 | 0.0.0.0/0 | SSH management |

## Step 3: Connect and Move SSH to Port 2244

```bash
ssh -i path/to/pv_1_hp1.key ubuntu@<YOUR_DIONAEA_IP>
sudo nano /etc/ssh/sshd_config
```

Change `Port 22` to `Port 2244`, save, then:

```bash
sudo systemctl restart ssh
```

Reconnect using the new port:
```bash
ssh -i path/to/pv_1_hp1.key -p 2244 ubuntu@<YOUR_DIONAEA_IP>
```

## Step 4: Install Docker

```bash
sudo apt update
sudo apt install -y docker.io
sudo systemctl enable docker
sudo systemctl start docker
sudo usermod -aG docker ubuntu
```

Log out and back in for the group change to take effect.

## Step 5: Configure Docker Log Rotation

This prevents disk from filling up over time:

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

## Step 6: Deploy Dionaea Container

```bash
sudo docker run -d \
  --name dionaea \
  --restart always \
  -p 21:21 \
  -p 23:23 \
  -p 25:25 \
  -p 80:80 \
  -p 443:443 \
  -p 445:445 \
  -p 1433:1433 \
  -p 3306:3306 \
  -p 5060:5060 \
  -p 5060:5060/udp \
  -p 69:69/udp \
  dinotools/dionaea
```

## Step 7: Verify Dionaea is Running

```bash
sudo docker ps | grep dionaea
sudo docker logs --tail 20 dionaea
```

You should see Dionaea starting up its services on each port.

## Step 8: Test Dionaea

From your Kali machine:

```bash
# FTP test
ftp <YOUR_DIONAEA_IP>
# Username: admin
# Password: any

# SMB scan
nmap -p 445 --script smb-os-discovery <YOUR_DIONAEA_IP>

# MySQL test
mysql -h <YOUR_DIONAEA_IP> -u root -p
```

Check the logs to verify capture:
```bash
sudo docker logs --tail 20 dionaea
```

## Step 9: View Captured Malware

Dionaea stores captured binaries inside the container:

```bash
sudo docker exec dionaea ls -lh /var/lib/dionaea/binaries/
```

To copy a captured binary to the host for analysis:
```bash
sudo docker cp dionaea:/var/lib/dionaea/binaries/ ./captured-malware/
```

## Step 10: Query the SQLite Database

Dionaea logs connections to an SQLite database:

```bash
sudo docker exec -it dionaea sqlite3 /var/lib/dionaea/dionaea.sqlite \
  "SELECT connection_timestamp, remote_host, remote_port, connection_protocol \
   FROM connections ORDER BY connection_timestamp DESC LIMIT 10;"
```

## Step 11: Install Filebeat

```bash
wget -qO - https://artifacts.elastic.co/GPG-KEY-elasticsearch | sudo gpg --dearmor -o /usr/share/keyrings/elastic.gpg
echo "deb [signed-by=/usr/share/keyrings/elastic.gpg] https://artifacts.elastic.co/packages/8.x/apt stable main" | sudo tee /etc/apt/sources.list.d/elastic-8.x.list
sudo apt update
sudo apt install -y filebeat
```

## Step 12: Configure Filebeat for Docker Logs

Get the exact log file path:

```bash
sudo docker inspect --format='{{.LogPath}}' dionaea
```

Edit Filebeat config with this exact path. Use the template from `filebeat-configs/filebeat-dionaea.yml`.

Critical settings:
- `type: log` (not `container` if wildcards fail)
- `close_inactive: 24h` (prevents Filebeat from closing the file)
- `scan_frequency: 5s` (checks for new entries every 5 seconds)

## Step 13: Start Filebeat

```bash
sudo chmod 644 $(sudo docker inspect --format='{{.LogPath}}' dionaea)
sudo systemctl enable filebeat
sudo systemctl start filebeat
sudo filebeat test output
```

## Step 14: Verify End-to-End Pipeline

1. Attack Dionaea from Kali
2. Watch live logs: `sudo docker logs -f dionaea`
3. Check Filebeat journal: `sudo journalctl -u filebeat -n 20`
4. Open Kibana → **Discover** → filter `honeypot_type : "dionaea"` → confirm logs appear

## Troubleshooting

**Container won't start:** Check port conflicts: `sudo ss -tlnp | grep <port>`

**Disk filling up:** Check Docker logs size: `sudo du -sh /var/lib/docker/containers/`. If full, restart container: `sudo docker restart dionaea`

**Logs not forwarding:** Check Filebeat is reading the file: `sudo journalctl -u filebeat | grep harvester`. Reset registry if needed: `sudo rm -rf /var/lib/filebeat/registry && sudo systemctl restart filebeat`

**Permission denied on Docker logs:** `sudo chmod -R 755 /var/lib/docker/containers/`
