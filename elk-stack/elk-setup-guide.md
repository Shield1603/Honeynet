# ELK Stack Setup Guide

This guide walks through deploying the ELK stack (Elasticsearch, Logstash, Kibana) on a dedicated Google Cloud instance for centralized honeypot log aggregation.

## Prerequisites

- Google Cloud Platform account
- Basic Linux administration knowledge
- 4GB+ RAM recommended for the ELK server

## Step 1: Create the ELK Server Instance

1. Log in to Google Cloud Console
2. Navigate to **Compute Engine** → **VM Instances** → **Create Instance**
3. Configure:
   - **Name:** `elk-server`
   - **Region:** Same as Conpot for low latency
   - **Machine type:** e2-medium (2 vCPU, 4 GB memory)
   - **Boot disk:** Ubuntu 22.04 LTS, 200GB
4. Click **Create**
5. Reserve a static external IP (critical — Filebeat agents need a stable target)

## Step 2: Configure Firewall Rules

Create a firewall rule allowing ELK ports from your honeypots only (or 0.0.0.0/0 for testing):

| Port | Service | Source |
|------|---------|--------|
| 5044 | Logstash (Beats input) | Honeypot IPs |
| 5601 | Kibana web UI | Your IP only |
| 9200 | Elasticsearch API | localhost only |
| 2244 | SSH management | Your IP only |

## Step 3: Connect to the Instance

```bash
gcloud compute ssh elk-server
```

## Step 4: Install Java

Elasticsearch requires Java:

```bash
sudo apt update
sudo apt install -y openjdk-17-jdk
java -version
```

## Step 5: Add Elastic Repository

```bash
wget -qO - https://artifacts.elastic.co/GPG-KEY-elasticsearch | sudo gpg --dearmor -o /usr/share/keyrings/elastic.gpg
echo "deb [signed-by=/usr/share/keyrings/elastic.gpg] https://artifacts.elastic.co/packages/8.x/apt stable main" | sudo tee /etc/apt/sources.list.d/elastic-8.x.list
sudo apt update
```

## Step 6: Install Elasticsearch

```bash
sudo apt install -y elasticsearch
```

Configure Elasticsearch:

```bash
sudo nano /etc/elasticsearch/elasticsearch.yml
```

Add or modify:
```yaml
network.host: 0.0.0.0
discovery.type: single-node
xpack.security.enabled: false
xpack.security.enrollment.enabled: false
xpack.security.http.ssl.enabled: false
xpack.security.transport.ssl.enabled: false
```

Configure JVM heap (use half your RAM, max 32GB):

```bash
sudo nano /etc/elasticsearch/jvm.options.d/heap.options
```

Add:
```
-Xms2g
-Xmx2g
```

Start Elasticsearch:

```bash
sudo systemctl daemon-reload
sudo systemctl enable elasticsearch
sudo systemctl start elasticsearch
```

Verify:
```bash
curl http://localhost:9200
```

## Step 7: Install Logstash

```bash
sudo apt install -y logstash
```

Create the honeypot pipeline configuration:

```bash
sudo nano /etc/logstash/conf.d/honeypot.conf
```

Add:
```
input {
  beats {
    port => 5044
  }
}

filter {
  # Parse Cowrie JSON logs
  if [fields][honeypot] == "cowrie" {
    json {
      source => "message"
    }
    mutate {
      add_field => { "honeypot_type" => "cowrie" }
      add_field => { "attack_category" => "ssh_telnet" }
    }
    if [src_ip] {
      mutate { add_field => { "source_ip" => "%{src_ip}" } }
    }
    if [username] {
      mutate { add_field => { "attempted_username" => "%{username}" } }
    }
    if [password] {
      mutate { add_field => { "attempted_password" => "%{password}" } }
    }
  }

  # Parse Dionaea Docker logs
  if [fields][honeypot] == "dionaea" {
    json {
      source => "message"
      target => "docker"
    }
    mutate {
      add_field => { "honeypot_type" => "dionaea" }
      add_field => { "attack_category" => "malware_capture" }
    }
    grok {
      match => { "[docker][log]" => "%{IP:source_ip}" }
      tag_on_failure => []
    }
  }

  # Parse Conpot Docker logs
  if [fields][honeypot] == "conpot" {
    json {
      source => "message"
      target => "docker"
    }
    mutate {
      add_field => { "honeypot_type" => "conpot" }
      add_field => { "attack_category" => "ics_scada" }
    }
    grok {
      match => { "[docker][log]" => "%{IP:source_ip}" }
      tag_on_failure => []
    }
    # Identify ICS protocol
    if [docker][log] =~ "modbus" {
      mutate { add_field => { "ics_protocol" => "modbus" } }
    }
    if [docker][log] =~ "s7comm|S7Comm" {
      mutate { add_field => { "ics_protocol" => "s7comm" } }
    }
    if [docker][log] =~ "bacnet|Bacnet" {
      mutate { add_field => { "ics_protocol" => "bacnet" } }
    }
    if [docker][log] =~ "enip|EtherNet" {
      mutate { add_field => { "ics_protocol" => "enip" } }
    }
  }

  # GeoIP enrichment for all source IPs
  if [source_ip] {
    geoip {
      source => "source_ip"
      target => "geoip"
    }
  }
}

output {
  # Unified index for all honeypots
  elasticsearch {
    hosts => ["localhost:9200"]
    index => "honeypot-unified-%{+YYYY.MM.dd}"
  }

  # Per-honeypot indices
  elasticsearch {
    hosts => ["localhost:9200"]
    index => "honeypot-%{[fields][honeypot]}-%{+YYYY.MM.dd}"
  }
}
```

Configure JVM heap:

```bash
sudo nano /etc/logstash/jvm.options
```

Set:
```
-Xms1g
-Xmx1g
```

Start Logstash:

```bash
sudo systemctl enable logstash
sudo systemctl start logstash
```

## Step 8: Install Kibana

```bash
sudo apt install -y kibana
```

Configure Kibana:

```bash
sudo nano /etc/kibana/kibana.yml
```

Add:
```yaml
server.host: "0.0.0.0"
server.port: 5601
elasticsearch.hosts: ["http://localhost:9200"]
```

Start Kibana:

```bash
sudo systemctl enable kibana
sudo systemctl start kibana
```

Wait 1-2 minutes for Kibana to initialize.

## Step 9: Access Kibana

Open in your browser:

```
http://<YOUR_ELK_SERVER_IP>:5601
```

## Step 10: Add Swap Space (Recommended)

ELK can be memory-intensive. Add 4GB swap:

```bash
sudo fallocate -l 4G /swapfile
sudo chmod 600 /swapfile
sudo mkswap /swapfile
sudo swapon /swapfile
echo '/swapfile none swap sw 0 0' | sudo tee -a /etc/fstab
```

## Step 11: Create Data View in Kibana

1. Open Kibana → **Stack Management** → **Data Views**
2. Click **Create data view**
3. Configure:
   - **Name:** `Honeypot Unified`
   - **Index pattern:** `honeypot-unified-*`
   - **Timestamp field:** `@timestamp`
4. Click **Save data view**

## Step 12: Verify Logs Are Arriving

Once Filebeat is configured on your honeypot instances, verify in Kibana:

1. Go to **Discover**
2. Select `honeypot-unified-*` data view
3. Set time range to **Last 15 minutes**
4. You should see logs from all three honeypots

If empty, check:

```bash
# On ELK server
curl "http://localhost:9200/_cat/indices?v" | grep honeypot
sudo tail -50 /var/log/logstash/logstash-plain.log
```

## Step 13: Build the Dashboard

Create visualizations:

1. **World Map** — Maps → Add Documents layer → use `geoip.location` field
2. **Attack Timeline** — Lens → Area stacked → X: @timestamp, Y: Count, Break down by: honeypot_type
3. **Top Usernames** — Lens → Bar vertical → X: attempted_username.keyword, Y: Count
4. **Attack Categories** — Lens → Pie → Slice by: attack_category.keyword
5. **Top Attacker IPs** — Lens → Bar horizontal → Y: source_ip.keyword, X: Count
6. **Top Countries** — Lens → Bar horizontal → Y: geoip.country_name.keyword
7. **Live Feed** — Lens → Table → columns: @timestamp, source_ip, honeypot_type

Combine all into a single dashboard:

1. **Dashboard** → **Create dashboard**
2. **Add from library** → select all visualizations
3. Arrange in a grid layout
4. **Save** as `Honeynet Threat Intelligence Dashboard`

## Step 14: Set Auto-Refresh

In the dashboard, top right → **Refresh every 30 seconds**.

## Troubleshooting

**Elasticsearch won't start:** Check logs `sudo tail -50 /var/log/elasticsearch/elasticsearch.log`. Common causes are insufficient memory (reduce heap) or disk full.

**Kibana shows "Kibana server is not ready":** Wait 2-3 minutes. If persists, check `sudo systemctl status kibana` and the Kibana logs at `/var/log/kibana/kibana.log`.

**Logstash not receiving data:** Check it's listening: `sudo ss -tlnp | grep 5044`. Verify pipeline config: `sudo /usr/share/logstash/bin/logstash --config.test_and_exit -f /etc/logstash/conf.d/honeypot.conf`

**Memory issues:** Reduce JVM heaps. Add more swap. Consider upgrading instance.

**No data in Kibana:** Verify chain: Filebeat → Logstash → Elasticsearch → Kibana. Check each link individually.

## Performance Tuning

For higher attack volumes:

1. Increase Logstash workers in `/etc/logstash/logstash.yml`:
   ```yaml
   pipeline.workers: 4
   pipeline.batch.size: 250
   ```

2. Increase Elasticsearch heap (up to half of RAM).

3. Use cron to delete old indices:
   ```bash
   # Delete indices older than 30 days
   0 2 * * * curl -X DELETE "http://localhost:9200/honeypot-*-$(date -d '30 days ago' +\%Y.\%m.\%d)"
   ```
