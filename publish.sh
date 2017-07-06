#!/usr/bin/env bash

function_name=$1
alias_name=$2

published_version=$(aws lambda publish-version --function-name ${function_name} | jq -r '.Version')
aws lambda update-alias --function-name ${function_name} --name ${alias_name} --function-version ${published_version}