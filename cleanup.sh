#!/usr/bin/env bash

readonly function_name=$1

bounded_versions=$(aws lambda list-aliases --function-name ${function_name} | jq "[(.Aliases[] | .FunctionVersion)] + [\"\$LATEST\"]")

aws lambda list-versions-by-function --function-name ${function_name} | jq "[(.Versions[] | .Version)] - ${bounded_versions}" | jq '.[] | tonumber' | while read version; do
    aws lambda delete-function --function-name ${function_name} --qualifier ${version}
done