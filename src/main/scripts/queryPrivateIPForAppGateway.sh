#!/bin/bash

#      Copyright (c) Microsoft Corporation.
# 
#  Licensed under the Apache License, Version 2.0 (the "License");
#  you may not use this file except in compliance with the License.
#  You may obtain a copy of the License at
# 
#           http://www.apache.org/licenses/LICENSE-2.0
# 
#  Unless required by applicable law or agreed to in writing, software
#  distributed under the License is distributed on an "AS IS" BASIS,
#  WITHOUT WARRANTIES OR CONDITIONS OF ANY KIND, either express or implied.
#  See the License for the specific language governing permissions and
#  limitations under the License.

function echo_stderr() {
    echo >&2 "$@"
    # The function is used for scripts running within Azure Deployment Script
    # The value of AZ_SCRIPTS_OUTPUT_PATH is /mnt/azscripts/azscriptoutput
    echo -e "$@" >>${AZ_SCRIPTS_PATH_OUTPUT_DIRECTORY}/errors.log
}

function echo_stdout() {
    echo "$@"
    # The function is used for scripts running within Azure Deployment Script
    # The value of AZ_SCRIPTS_OUTPUT_PATH is /mnt/azscripts/azscriptoutput
    echo -e "$@" >>${AZ_SCRIPTS_PATH_OUTPUT_DIRECTORY}/debug.log
}

function query_ip() {
    echo_stdout "Subnet Id: ${SUBNET_ID}"

    # select a available private IP
    # azure reserves the first 3 private IPs.
    local ret=$(az network vnet check-ip-address \
        --ids ${SUBNET_ID} \
        --ip-address ${KNOWN_IP})
    local available=$(echo ${ret} | jq -r .available)
    if [[ "${available,,}" == "true" ]]; then
      outputPrivateIP=${KNOWN_IP}
    else
      local privateIPAddress=$(echo ${ret} | jq -r .availableIpAddresses[0])
      if [[ -z "${privateIPAddress}" ]] || [[ "${privateIPAddress}"=="null" ]]; then
        echo_stderr "ERROR: make sure there is available IP for application gateway in your subnet."
      fi

      outputPrivateIP=${privateIPAddress}
    fi
}

function output_result() {
  echo "Available Private IP: ${outputPrivateIP}"
  result=$(jq -n -c \
    --arg privateIP "$outputPrivateIP" \
    '{privateIP: $privateIP}')
  echo "result is: $result"
  echo $result >$AZ_SCRIPTS_OUTPUT_PATH
}

# main script
outputPrivateIP="10.0.0.1"

query_ip

output_result