# vsphere_host_vm_power_state_exporter
A VM power state (vSphere) exporter for Prometheus Pushgateway. It is using vSphere vCenter official API 

## Logic
1. Get token (key) from vSphere API using userpass
2. API requests to vSphere vCenter to get data about host connection and power state, vm power state
3. Parse gathered data
4. Push to Prometheus Pushgateway

## Installation
Download file: **vc_host_vm_pw_state_exporter.sh**, or just copy its content to the same files

## Configuration
You need to setup vars in the main file:
```bash
#!/bin/bash

userpass=""
vc_host=""
prom_pg_host="ip:port"
instance="localhost"
sleep_time=120

... (rest of a code)
```
- **userpass** - username and password with Basic Authentication
- **vc_host** - vSphere host
- **prom_pg_host** - DNS name or ip + port of Prometheus Pushgateway
- **instance** - who sending metrics, default localhost
- **sleep_time** - how long (in seconds) to wait before next run, set 0 if you want to run script once, default 120

## Run the script
- Do `chmod +x ./vc_host_vm_pw_state_exporter.sh`
- Do `./vc_host_vm_pw_state_exporter.sh` or `/bin/bash vc_host_vm_pw_state_exporter.sh`

## systemd
Create systemd service to autorun exporter:
```bash
[Unit]
Description=host/vm power state exporter
After=network.target

[Service]
Type=simple
ExecStart=/bin/bash /path/to/file/vc_host_vm_pw_state_exporter.sh
Restart=on-failure

[Install]
WantedBy=multi-user.target
```
