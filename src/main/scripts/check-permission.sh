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

# Check if the user assigned managed identity has Contributor or Owner role
roleLength=$(az role assignment list --assignee ${principalId} | jq '.[] | [select(.roleDefinitionName=="Contributor" or .roleDefinitionName=="Owner")] | length')
if [ ${roleLength} -lt 1 ]; then
    echo "The user-assigned managed identity must have Contributor or Owner role in the subscription, please check ${AZ_SCRIPTS_USER_ASSIGNED_IDENTITY}" >&2
    exit 1
fi
