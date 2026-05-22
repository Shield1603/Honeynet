# Cowrie Honeypot Setup Guide

This guide walks through deploying Cowrie SSH and Telnet honeypot on an Oracle Cloud instance.

## Prerequisites

- Oracle Cloud account (free tier available)
- Basic Linux command-line knowledge
- SSH client on your local machine

## Step 1: Create Oracle Cloud Instance

1. Log in to Oracle Cloud Console
2. Navigate to **Compute** → **Instances** → **Create Instance**
3. Configure:
   - **Name:** `honeypot-cowrie`
   - **Image:** Ubuntu 22.04
   - **Shape:** VM.Standard.E2.1.Micro (free tier)
   - **Networking:** Create new VCN with public subnet
4. Download the SSH key file (e.g., `pv_1_hp1.key`) and save it securely
5. Click **Create** and wait for the instance to provision
6. Note the public IP address assigned

## Step 2: Configure Firewall Rules

In Oracle Cloud Console, edit the VCN security list to allow:

| Protocol | Port | Source | Purpose |
|----------|------|--------|---------|
| TCP | 22 | 0.0.0.0/0 | SSH honeypot |
| TCP | 23 | 0.0.0.0/0 | Telnet honeypot |
| TCP | 2244 | 0.0.0.0/0 | Real SSH management |

## Step 3: Connect to the Instance

```bash
ssh -i path/to/pv_1_hp1.key ubuntu@<YOUR_INSTANCE_IP>
```

## Step 4: Move Real SSH to Port 2244

This separates your management access from the honeypot.

```bash
sudo nano /etc/ssh/sshd_config
```

Find and change:
```
Port 22
```
to:
```
Port 2244
```

Save and restart SSH:
```bash
sudo systemctl restart ssh
```

**Important:** Open a new terminal and verify you can connect on port 2244 before closing the current session:
```bash
ssh -i path/to/pv_1_hp1.key -p 2244 ubuntu@<YOUR_INSTANCE_IP>
```

## Step 5: Install Cowrie Dependencies

```bash
sudo apt update
sudo apt install -y git python3-virtualenv libssl-dev libffi-dev build-essential libpython3-dev python3-minimal authbind virtualenv
```

## Step 6: Create Cowrie User

```bash
sudo adduser --disabled-password cowrie
sudo su - cowrie
```

## Step 7: Clone and Install Cowrie

```bash
git clone http://github.com/cowrie/cowrie
cd cowrie
python3 -m venv cowrie-env
source cowrie-env/bin/activate
pip install --upgrade pip
pip install --upgrade -r requirements.txt
```

## Step 8: Configure Cowrie

```bash
cp etc/cowrie.cfg.dist etc/cowrie.cfg
nano etc/cowrie.cfg
```

Key settings to verify:
```
[honeypot]
hostname = svr04

[ssh]
enabled = true
listen_endpoints = tcp:2222:interface=0.0.0.0

[telnet]
enabled = true
listen_endpoints = tcp:2223:interface=0.0.0.0
```

## Step 9: Set Up Port Redirection

Cowrie runs on port 2222 (unprivileged). Use iptables to redirect port 22 traffic to Cowrie:

```bash
exit  # Back to ubuntu user
sudo iptables -t nat -A PREROUTING -p tcp --dport 22 -j REDIRECT --to-port 2222
sudo iptables -t nat -A PREROUTING -p tcp --dport 23 -j REDIRECT --to-port 2223
sudo apt install -y iptables-persistent
sudo netfilter-persistent save
```

## Step 10: Start Cowrie

```bash
sudo su - cowrie
cd cowrie
source cowrie-env/bin/activate
bin/cowrie start
```

Verify it's running:
```bash
bin/cowrie status
```

## Step 11: Test the Honeypot

From your local machine:
```bash
ssh root@<YOUR_INSTANCE_IP>
```

Enter any password — you should be logged in to a fake shell. Type commands like `ls`, `whoami`, `cat /etc/passwd` to see Cowrie's responses.

## Step 12: View Logs

```bash
tail -f /home/cowrie/cowrie/var/log/cowrie/cowrie.json
tail -f /home/cowrie/cowrie/var/log/cowrie/cowrie.log
```

## Step 13: Install Filebeat for Log Forwarding

```bash
exit  # Back to ubuntu user
wget -qO - https://artifacts.elastic.co/GPG-KEY-elasticsearch | sudo gpg --dearmor -o /usr/share/keyrings/elastic.gpg
echo "deb [signed-by=/usr/share/keyrings/elastic.gpg] https://artifacts.elastic.co/packages/8.x/apt stable main" | sudo tee /etc/apt/sources.list.d/elastic-8.x.list
sudo apt update
sudo apt install -y filebeat
```

Configure Filebeat with the config from `filebeat-configs/filebeat-cowrie.yml`, then:

```bash
sudo systemctl enable filebeat
sudo systemctl start filebeat
```

## Troubleshooting

**Cowrie won't start:** Check Python virtual environment is activated and all dependencies installed.

**Can't connect on port 22:** Verify iptables rules: `sudo iptables -t nat -L -n -v`

**Logs not forwarding:** Check Filebeat status: `sudo systemctl status filebeat` and test output: `sudo filebeat test output`
