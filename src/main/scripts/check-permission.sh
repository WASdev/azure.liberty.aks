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

# Get the type of managed identity
uamiType=$(az identity show --ids ${AZ_SCRIPTS_USER_ASSIGNED_IDENTITY} --query "type" -o tsv)
if [ $? == 1 ]; then
    echo "The user-assigned managed identity may not exist or has no access to the subscription, please check ${AZ_SCRIPTS_USER_ASSIGNED_IDENTITY}" >&2
    exit 1
fi

# Check if the managed identity is a user-assigned managed identity
if [[ "${uamiType}" != "Microsoft.ManagedIdentity/userAssignedIdentities" ]]; then
    echo "You must select a user-assigned managed identity instead of other types, please check ${AZ_SCRIPTS_USER_ASSIGNED_IDENTITY}" >&2
    exit 1
fi

# Query principal Id of the user-assigned managed identity
principalId=$(az identity show --ids ${AZ_SCRIPTS_USER_ASSIGNED_IDENTITY} --query "principalId" -o tsv)

# Check if the user assigned managed identity has Owner role or Contributor and User Access Administrator roles
roleAssignments=$(az role assignment list --assignee ${principalId})
roleLength=$(echo $roleAssignments | jq '[ .[] | select(.roleDefinitionName=="Owner") ] | length')
if [ ${roleLength} -ne 1 ]; then
    roleLength=$(echo $roleAssignments | jq '[ .[] | select(.roleDefinitionName=="Contributor" or .roleDefinitionName=="User Access Administrator") ] | length')
    if [ ${roleLength} -ne 2 ]; then
        echo "The user-assigned managed identity must have Contributor and User Access Administrator roles or Owner role in the subscription, please check ${AZ_SCRIPTS_USER_ASSIGNED_IDENTITY}" >&2
        exit 1
    fi
fi

# Check if the user assigned managed identity has Directory readers role in the Azure AD
az ad user list 1>/dev/null
if [ $? == 1 ]; then
    echo "The user-assigned managed identity must have Directory readers role in the Azure AD, please check ${AZ_SCRIPTS_USER_ASSIGNED_IDENTITY}" >&2
    exit 1
fi
