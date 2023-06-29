#!/bin/bash

#      Copyright (c) IBM Corporation.
#      Copyright (c) Microsoft Corporation.

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

# Validate teminal status with $?, exit with exception if errors happen.
function validate_status() {
    if [ $? != 0 ]; then
        echo_stderr "$@"
        echo_stderr "Errors happen, exit 1."
        exit 1
    else
        echo_stdout "$@"
    fi
}

# Validate teminal status with $?, exit with exception if errors happen.
# $1 - operation executed
# $2 - root cause message
function validate_status_with_hint() {
    if [ $? != 0 ]; then
        echo_stderr "Errors happen during: $1." $2
        exit 1
    else
        echo_stdout "$1"
    fi
}

# Install kubectl
function install_kubectl() {
    az aks install-cli 2>/dev/null
    kubectl --help
    validate_status "Install kubectl."
}
