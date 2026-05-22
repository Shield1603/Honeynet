# Honeynet-
Distributed multi-cloud honeynet using Cowrie, Dionaea, and Conpot with centralized ELK stack for real-time cyber threat intelligence

# DeceptiCloud: Distributed Multi-Cloud Honeynet

A production-grade distributed honeynet spanning Oracle Cloud and Google 
Cloud, designed to capture and analyze real-world cyber attacks in real time.

## Architecture

![Architecture](architecture/architecture-diagram.png)

## Honeypots Deployed

| Honeypot | Type | Cloud | Protocols |
|----------|------|-------|-----------|
| Cowrie | SSH/Telnet | Oracle Cloud | SSH (22), Telnet (23) |
| Dionaea | Malware Capture | Oracle Cloud | FTP, SMB, HTTP, MySQL, MSSQL |
| Conpot | ICS/SCADA | Google Cloud | Modbus, S7comm, SNMP, EtherNet/IP |

## Tech Stack

- **Honeypots:** Cowrie, Dionaea, Conpot
- **Log Pipeline:** Filebeat to Logstash to Elasticsearch to Kibana
- **Cloud:** Oracle Cloud Infrastructure and Google Cloud Platform
- **Containerization:** Docker
- **Attack Testing:** Kali Linux with Hydra, Nmap, Metasploit, Nikto

## Key Features

- Multi-cloud distributed architecture across two providers
- Real-time centralized log aggregation via ELK stack
- GeoIP enrichment for geographic attack analysis
- Custom Logstash pipeline with structured parsing
- Interactive Kibana dashboard with attack timelines and maps
- Docker-based honeypot isolation with automatic restart
- Automated attack simulation script covering all three honeypots

## Results

- SSH brute force bots discovered Cowrie within minutes of deployment
- Real-world ICS reconnaissance captured on Conpot from multiple countries
- SMB and FTP exploit attempts captured by Dionaea
- Sub-30-second pipeline latency from attack to dashboard
- Over 1700 attack events captured in a single one-hour observation window

## Setup Guides

- [Cowrie Setup](honeypots/cowrie/setup-guide.md)
- [Dionaea Setup](honeypots/dionaea/setup-guide.md)
- [Conpot Setup](honeypots/conpot/setup-guide.md)
- [ELK Stack Setup](elk-stack/setup-guide.md)

## Project Report

The full project report is available [here](report/final-report.pdf).

## Author

**Shrushti Samant**  
MSc Cybersecurity  
[LinkedIn](https://linkedin.com/in/YOUR-PROFILE) | [Email](mailto:your-email@gmail.com)
