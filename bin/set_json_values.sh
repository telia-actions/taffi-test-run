#!/usr/bin/env bash

usage () {
  cat <<HELP_USAGE

  Sets values for given JSON path 
  usage: $(basename $0) [-h] <JSONFILE> <JSONPATH:value>...
    -h, --help        Show this help
    JSONFILE          File path to the JSON file to be edited
    JSONPATH:value    JSON path is the path where the value should be set in the JSON file.
                      Path and value are separated by a colon (:). Multiple path-value pairs can be given.
HELP_USAGE
  exit 1
}

function removeQuotes() {
  local arg="${1%\"}"
  local arg="${arg#\"}"
  echo "$arg"
}

function addQuotes() {
  local -n items=$1
  for i in "${!items[@]}"; do
    if [[ "${items[$i]:0:1}" != "\"" ]] && [[ "${items[$i]:0-1}" != "\"" ]]; then
      items[$i]="\"${items[$i]}\""
    fi
  done
}

function trim() {
    local var="$*"
    # remove leading whitespace characters
    var="${var#"${var%%[![:space:]]*}"}"
    # remove trailing whitespace characters
    var="${var%"${var##*[![:space:]]}"}"
    printf '%s' "$var"
}

function join_by {
  local d=$1
  shift
  local remove_quotes=$1
  shift
  local -n items=$1
  text=""
  for i in "${!items[@]}"; do
    if (( $remove_quotes )); then
      text+=${items[$i]//\"/""}
    else
      text+="${items[$i]}"
    fi
    if (( i < ${#items[@]}-1 )); then
      text+=$d
    fi
  done
  echo "$text"
}

function append_to_JSON_array() {
  local FILE_PATH=$1
  shift
  local JSON_PATH=$1
  shift
  local NEW_VALUES=$@

  current_values=$(jq -r 'getpath($path|split(".")|map(tonumber? // .)) | @sh' --arg path $JSON_PATH $FILE_PATH | tr "'" "\"")
  if [[ "$current_values" == "null" ]]; then
    current_values=""
  fi
  echo "    JSON array current values: $current_values"
  items="$current_values $NEW_VALUES"

  # Bash array to finally contain all items to be put into JSON array
  arr=()

  # Regex to match quoted OR non-space string
  re='"[^"]*"|[^[:space:]]+'

  # Start a loop to match our regex until string is non-empty
  n=0
  items=$(trim $items)
  while [[ -n $items && $items =~ $re ]]; do
    m="${BASH_REMATCH[0]}"
    arr+=("$m")
    ((n=${#m}))
    items=$(trim ${items:$n})
  done

  quote_arr=("${arr[@]}")
  addQuotes quote_arr
  echo "    Final JSON array values: [$(join_by ", " 0 quote_arr)]"

  split_sep="#,#"
  json_arr=$(join_by "$split_sep" 1 arr)
  # echo "json_arr=$json_arr"
  jq 'setpath( $path|split(".")|map(tonumber? // .); ($value|split($sep)))' --arg path $JSON_PATH --arg value "$json_arr" --arg sep "$split_sep" $FILE_PATH > tmp.$$.json && mv tmp.$$.json $FILE_PATH
}

function set_value() {
  local FILEPATH=$1
  shift
  local JSONPATH=$1
  shift
  local VALUE=$@
  arrayPrefix="__array__"
  numberPrefix="__number__"
  if [[ "$VALUE" == $arrayPrefix* ]]; then
    VALUES=${VALUE#"$arrayPrefix"}
    echo "    Appending values ($VALUES) to JSON array"
    append_to_JSON_array $FILEPATH $JSONPATH $VALUES
    # jq 'setpath( $path|split(".")|map(tonumber? // .); getpath($path|split(".")|map(tonumber? // .)) + ($value|split(",")))' --arg path $JSONPATH --arg value "$VALUE" $FILEPATH > tmp.$$.json && mv tmp.$$.json $FILEPATH
  elif [[ "$VALUE" == $numberPrefix* ]]; then
    VALUE=${VALUE#"$numberPrefix"}
    jq 'setpath( $path|split(".")|map(tonumber? // .); $value|tonumber)' --arg path $JSONPATH --arg value "$VALUE" $FILEPATH > tmp.$$.json && mv tmp.$$.json $FILEPATH
  else
    jq 'setpath( $path|split(".")|map(tonumber? // .); $value)' --arg path $JSONPATH --arg value "$VALUE" $FILEPATH > tmp.$$.json && mv tmp.$$.json $FILEPATH
  fi
}

JSONVALUES=()

while [[ $# -gt 0 ]]; do
  key="$1"

  case $key in
    -h|--help)
      usage
      shift
      ;;
    *)    # unknown option
      if [ "$JSONFILE" = "" ]; then
        JSONFILE="$1" # treat it as the json file
      else
        JSONVALUES+=("$1")
      fi
      shift
      ;;
  esac
done

# arg1=$1; shift
# array=( "$@" )

# printf "  %s\n" "${JSONVALUES[@]/:/ => }"

if [[ ! -f $JSONFILE ]]; then
  echo "File $JSONFILE does not exist!"
  usage
else
  echo "Updating JSON values to file $JSONFILE"
  for path_value in "${JSONVALUES[@]}"; do
    path=${path_value%%:*} 
    value=${path_value#*:}
    echo "  $path => $value"
    set_value $JSONFILE $path $value
  done
fi
