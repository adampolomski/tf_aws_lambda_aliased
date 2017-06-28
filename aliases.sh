#!/usr/bin/env bash

aws lambda list-aliases --function-name $1 | jq "[ {$2: \"\$LATEST\"}, (.Aliases[] | {(.Name): .FunctionVersion})]" | jq add | jq "{$2}"