#!/bin/bash
PROJECT_ID=125177
INPUT_FILE="src/code/utils/lang/en-US-master.json"

# argument processing from https://stackoverflow.com/a/14203146
while [[ $# -gt 1 ]]
do
key="$1"

case $key in
    -a|--api_token)
    API_TOKEN="$2"
    shift # past argument
    ;;
esac
shift # past argument or value
done

PUSHARGS="-p $PROJECT_ID -i $INPUT_FILE -a $API_TOKEN"
# echo "PUSHARGS=$PUSHARGS"
./bin/strings-push.sh $PUSHARGS
