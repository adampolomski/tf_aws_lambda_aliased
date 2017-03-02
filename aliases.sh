#!/usr/bin/env bash

aws lambda list-aliases --function-name $1 | jq "[ {PRODUCTION: \"\$LATEST\", TEST: \"\$LATEST\"}, (.Aliases[] | {(.Name): .FunctionVersion})]" | jq add | jq "{PRODUCTION, TEST}"