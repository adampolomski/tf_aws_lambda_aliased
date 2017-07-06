#!/usr/bin/env bash

function_name=$1

if aws lambda list-functions | grep --quiet ${function_name} ; then
  aws lambda list-aliases --function-name ${function_name} | jq "[ (.Aliases[] | {(.Name): .FunctionVersion})]" | jq add
else
    echo "{}"
fi