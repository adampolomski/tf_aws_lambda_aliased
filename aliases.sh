#!/usr/bin/env bash

if aws lambda list-functions | grep --quiet $1 ; then
  aws lambda list-aliases --function-name $1 | jq "[ {$2: \"\$LATEST\"}, (.Aliases[] | {(.Name): .FunctionVersion})]" | jq add | jq "{$2}"
else
    echo "{$2: \"\$LATEST\"}"
fi