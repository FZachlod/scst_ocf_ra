#!/bin/bash
targetports=""
if [[ -d /sys/class/fc_host ]]
then
  for port in $(ls /sys/class/fc_host | egrep "host[0-9]+" | sort -V)
  do
    if [[ -f /sys/class/fc_host/${port}/max_npiv_vports ]]
    then
      fcaddress=$(cat /sys/class/fc_host/${port}/port_name | egrep -o "[0-9A-Za-f]+$" | tr '[:upper:]' '[:lower:]' | sed -e 's/[0-9a-f]\{2\}/&:/g' -e 's/:$//')
      targetports=${targetports}${fcaddress}","
    fi
  done
  targetports=$(echo $targetports | sed "s/,$//g")
fi
local_node=$(crm_node -n)
if [[ ! -z $local_node ]]
then
  crm_attribute --node $local_node --name targetports --update=$targetports
fi
