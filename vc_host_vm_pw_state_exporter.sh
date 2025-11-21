#!/bin/bash

userpass="" #username and password with Basic Authentication 
vc_host="" # vSphere host
prom_pg_host="ip:port" #DNS name or ip + port
instance="localhost" #who sending metrics
sleep_time=120 #scrape interval

function createKey {
    echo "Creating session key"
    key=$(curl -ksX POST -H "Authorization: Basic $userpass" 'https://$vc_host/api/session')

    if [[ $key == "" ]]; then
		echo "Error"
		exit 1
    fi
    echo "Key generated successfully"
}

function sessStatus {
    sessStatus=$(curl -ksX GET -H "vmware-api-session-id: ${key:1:-1}" 'https://$vc_host/api/session' | grep -o "error")

    if [[ $sessStatus != "" ]]; then
		echo "Recreating session key..."
		createKey
    fi
}

echo "Starting..."
createKey

echo "Gathering VMs info..."
while true
do
    sessStatus
    vms=$(curl -ksX GET -H "vmware-api-session-id: ${key:1:-1}" 'https://$vc_host/api/vcenter/vm' | grep -Eo "\"name\":\"[a-zA-Z0-9]+\",\"power_state\":\"[a-zA-Z_-]+\"")
    esxis=$(curl -ksX GET -H "vmware-api-session-id: ${key:1:-1}" 'https://$vc_host/api/vcenter/host' | grep -Eo "\"name\":\"[a-zA-Z0-9.]+\",\"connection_state\":\"[a-zA-Z_-]+\"(,\"power_state\":\"[a-zA-Z_-]+\")?")

    for i in $vms
    do
		vmname=`echo $i | awk -F '"' '{print $4}'`
		state=`echo $i | awk -F '"' '{print $8}'`
	
		if [[ $state == "POWERED_ON" ]]; then
		    stateNumeric=1
		else
		    stateNumeric=0
		fi
		echo "vsphere_vm_power_state $stateNumeric" | curl -sX PUT --data-binary @- "http://$prom_pg_host/metrics/job/telegraf_vcenter/instance/$instance/vmname/$vmname"
    done

    for i in $esxis
    do
		esxname=`echo $i | awk -F '"' '{print $4}'`
		connstate=`echo $i | awk -F '"' '{print $8}'`
		pwstate=`echo $i | awk -F '"' '{print $12}'`
		
		if [[ $connstate == "CONNECTED" ]]; then
		    connStateNumeric=1
		elif [[ $connstate == "NOT_RESPONDING" ]]; then
		    connStateNumeric=2
		else
		    connStateNumeric=0
		fi
		
		if [[ $pwstate == "POWERED_ON" ]]; then
		    pwStateNumeric=1
		else
		    pwStateNumeric=0
		fi
		echo "vsphere_host_conn_state $connStateNumeric" | curl -sX PUT --data-binary @- "http://$prom_pg_host/metrics/job/telegraf_vcenter/instance/$instance/esxhostname/$esxname/state/connection"
		echo "vsphere_host_power_state $pwStateNumeric" | curl -sX PUT --data-binary @- "http://$prom_pg_host/metrics/job/telegraf_vcenter/instance/$instance/esxhostname/$esxname/state/power"
    done

    sleep $sleep_time
done
