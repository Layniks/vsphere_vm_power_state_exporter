#!/bin/bash

function createKey {
    echo "Creating session key"
    key=$(curl -ksX POST -H "Authorization: Basic c3ZjLXZzcGhlcmUtc3RhdHNAY29yZXN2Yy50ZWNoOmR5alVZRjU1Y2FINnky" 'https://mskpvc01.coresvc.tech/api/session')

    if [[ $key == "" ]]; then
	echo "Error"
	exit 1
    fi
    echo "Key generated successfully"
}

function sessStatus {
    sessStatus=$(curl -ksX GET -H "vmware-api-session-id: ${key:1:-1}" 'https://mskpvc01.coresvc.tech/api/session' | grep -o "error")

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
    vms=$(curl -ksX GET -H "vmware-api-session-id: ${key:1:-1}" 'https://mskpvc01.coresvc.tech/api/vcenter/vm' | grep -Eo "\"name\":\"[a-zA-Z0-9]+\",\"power_state\":\"[a-zA-Z_-]+\"")
    esxis=$(curl -ksX GET -H "vmware-api-session-id: ${key:1:-1}" 'https://mskpvc01.coresvc.tech/api/vcenter/host' | grep -Eo "\"name\":\"[a-zA-Z0-9.]+\",\"connection_state\":\"[a-zA-Z_-]+\"(,\"power_state\":\"[a-zA-Z_-]+\")?")

    for i in $vms
    do
	vmname=`echo $i | awk -F '"' '{print $4}'`
	state=`echo $i | awk -F '"' '{print $8}'`

	if [[ $state == "POWERED_ON" ]]; then
	    stateNumeric=1
	else
	    stateNumeric=0
	fi
	echo "vsphere_vm_power_state $stateNumeric" | curl -sX PUT --data-binary @- "http://10.1.1.78:9091/metrics/job/telegraf_vcenter/instance/localhost:9273/vmname/$vmname"
    done

    for i in $esxis
    do
	esxname=`echo $i | awk -F '"' '{print $4}'`
	connstate=`echo $i | awk -F '"' '{print $8}'`
	if [[ $connstate == "CONNECTED" ]]; then
	    connStateNumeric=1
	elif [[ $connstate == "NOT_RESPONDING" ]]; then
	    connStateNumeric=2
	else
	    connStateNumeric=0
	fi

	pwstate=`echo $i | awk -F '"' '{print $12}'`
	if [[ $pwstate == "POWERED_ON" ]]; then
	    pwStateNumeric=1
	else
	    pwStateNumeric=0
	fi
	echo "vsphere_host_conn_state $connStateNumeric" | curl -sX PUT --data-binary @- "http://10.1.1.78:9091/metrics/job/telegraf_vcenter/instance/localhost:9273/esxhostname/$esxname/state/connection"
	echo "vsphere_host_power_state $pwStateNumeric" | curl -sX PUT --data-binary @- "http://10.1.1.78:9091/metrics/job/telegraf_vcenter/instance/localhost:9273/esxhostname/$esxname/state/power"
    done


### info about snapshots has been generating via azure pipeline "vms_snapshots"

    snaps_names_descrs_creTimes=$(grep -Po "\"vm_name\": \"[a-zA-Z0-9]+\", \"folder\": \".*?\", \"id\": [0-9]*, \"name\": \".*?\", \"description\": \".*?\", \"creation_time\": \".+?\"" /var/log/loki-promtail/vm_snapshots.json)
    if [[ "$snaps_names_descrs_creTimes" != "" ]]; then

	IFS=$'\n'

	/bin/bash /etc/telegraf/pushgateway_delete_metrics.sh
	rm /etc/telegraf/pushgateway_delete_metrics.sh

	for i in $snaps_names_descrs_creTimes
	do
	    vm_name=$(echo $i | awk -F '"' '{print $4}')
	    vm_folder=$(echo $i | awk -F '"' '{print $8}')
	    snap_id=$(echo $i | awk -F '"' '{print $11}')
	    snap_name=$(echo $i | awk -F '"' '{print $14}'| jq -sRr '@uri')
	    snap_descr=$(echo $i | awk -F '"' '{print $18}'| jq -sRr '@uri')
	    snap_creTime=$(echo $i | awk -F '"' '{print $22}')
	    snap_creTime_numeric=$(date -d "$snap_creTime" +"%s")
	    pushtime=$(date +%s)

	    echo "vsphere_vm_snapshot_creation_time $snap_creTime_numeric" | curl -sX PUT --data-binary @- "http://localhost:9091/metrics/job/telegraf_vcenter_vm_snapshots/instance/localhost:9273/vmname/$vm_name/folder/$vm_folder/snapName/$snap_name/snapDescr/$snap_descr/snapID/${snap_id:2:-2}"

	    echo "curl -X DELETE \"http://localhost:9091/metrics/job/telegraf_vcenter_vm_snapshots/instance/localhost:9273/vmname/$vm_name/folder/$vm_folder/snapName/$snap_name/snapDescr/$snap_descr/snapID/${snap_id:2:-2}\"" >> /etc/telegraf/pushgateway_delete_metrics.sh
	done

	echo "Cleaning log file /var/log/loki-promtail/vm_snapshots.json"
	> /var/log/loki-promtail/vm_snapshots.json

	unset $IFS
    fi

    sleep 120
done