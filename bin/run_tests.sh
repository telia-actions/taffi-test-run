#!/usr/bin/env bash

# Requires jq installation

usage () {
  cat <<HELP_USAGE

  usage: $(basename $0) [-h] [-o] [-r] [-s] [-d] [-v] [-x] [-l] <configFile>
    -h, --help    Show this help
    -o, --output  Show output from test runs after the run (and reporting)
    -r, --report  Show jUnit report of test runs after the run (and reporting)
    -s, --status  Show status of test runs after the run (and reporting)
    -d, --dry-run Dry run to show the commands that would be executed in shell. No test execution is done.
    -v, --verbose Be verbose on script flow.
    -x, --show-executions
                  Be verbose on all command executions.
    -l, --log     Docker logs from the execution are stored to 'docker' directory underneath
                  the serverConfig.resultsDir setting defined in <configFile>
    configFile    Path to a file containing configuration for running
                  TAFFi server and tests using the server
HELP_USAGE
  exit 1
}

removeQuotes() {
  local arg="${1%\"}"
  local arg="${arg#\"}"
  echo "$arg"
}

createNetwork() {
  local netname=$(removeQuotes "$1")
  if [[ $dryRun ]]; then
    echo "docker network inspect $netname > $(removeQuotes "$dockerLogdir")/${netname}_inspect.log 2>&1"
    echo "docker network create -d bridge $netname > $(removeQuotes "$dockerLogdir")/${netname}_create.log 2>&1"
  else
    docker network inspect $netname > "$(removeQuotes "$dockerLogdir")/${netname}_inspect.log" 2>&1
    if [[ "$?" != "0" ]]; then
      docker network create -d bridge $netname > "$(removeQuotes "$dockerLogdir")/${netname}_create.log" 2>&1
    fi
  fi
}

startServer() {
  local tests=$(removeQuotes "$1")
  shift
  local config=$(removeQuotes "$1")
  shift
  local results=$(removeQuotes "$1")
  shift
  local rest=("$@")
  if [[ "$dockerLog" != 1 ]]; then
    local rmOpt="--rm"
  fi
  if [[ $dryRun ]]; then
    echo "docker run $rmOpt -d --net=$taffiNetworkName --name taffiserver -e TAFFI_SERVER_CONFIG=$taffiServerConfigDocker -v '$tests:/taffi/tests' -v '$config:$taffiServerConfigDocker' -v '$results:/taffi/results' -p 4000:4000/tcp -e LOCAL_GID=$(id -g) -e CI="$CI" $(removeQuotes $taffiServerImage) ${rest[@]} | tee $(removeQuotes "$dockerLogdir")/taffiserver_start.log"
  else
    docker run $rmOpt -d --net=$taffiNetworkName --name taffiserver -e TAFFI_SERVER_CONFIG="$taffiServerConfigDocker" -v "$tests":/taffi/tests -v "$config":"$taffiServerConfigDocker" -v "$results":/taffi/results -p 4000:4000/tcp -e LOCAL_GID=$(id -g) -e CI="$CI" $(removeQuotes $taffiServerImage) "${rest[@]}" | tee "$(removeQuotes "$dockerLogdir")/taffiserver_start.log"
    if [[ "$?" != "0" ]]; then
      echo "Error: Could not launch TAFFi server"
    fi
  fi
}

poll_server() {
  local uri=$(removeQuotes "$1")
  local waitTime=$2
  # Polling TAFFi server to become available. This works only if the host name and port used in client configuration is available also on this host.
  if [[ $dryRun ]]; then
    :
  else
    timeout $waitTime sh -c 'until curl $0/api/test/run/all > /dev/null 2>&1; do sleep 1; done' $uri
  fi
  echo "$?"
}

runCli() {
  local container_suffix=$(removeQuotes "$1")
  shift
  local taffiCliArgs=$@
  if [[ "$dockerLog" != 1 ]]; then
    local logOpt="--rm -e DEBUG=taf:*"
  fi
  if [[ $dryRun ]]; then
    echo "docker run $logOpt --net=$taffiNetworkName --name tafficli_$container_suffix -e TAFFI_SERVER_URL=$(removeQuotes "$serverUrl") -v '$(removeQuotes "$cliConfigDir"):$taffiServerConfigDocker' $(removeQuotes $taffiCliImage) $taffiCliArgs | tee $(removeQuotes "$dockerLogdir")/tafficli_${container_suffix}_start.log"
    if [[ $dockerLog ]]; then
      echo "docker logs tafficli_$container_suffix | tee $(removeQuotes "$dockerLogdir")/tafficli_${container_suffix}_docker.log 2>&1"
      echo "docker rm tafficli_$container_suffix > /dev/null"
    fi
  else
    docker run $logOpt --net=$taffiNetworkName --name tafficli_$container_suffix -e TAFFI_SERVER_URL="$(removeQuotes "$serverUrl")" -v $(removeQuotes "$cliConfigDir"):$taffiServerConfigDocker $(removeQuotes $taffiCliImage) $taffiCliArgs | tee "$(removeQuotes "$dockerLogdir")/tafficli_${container_suffix}_start.log"
    if [[ $dockerLog ]]; then
      docker logs tafficli_$container_suffix > "$(removeQuotes "$dockerLogdir")/tafficli_${container_suffix}_docker.log" 2>&1
      docker rm tafficli_$container_suffix > /dev/null
    fi
  fi
}

stopServer() {
  if [[ $dryRun ]]; then
    echo "docker stop taffiserver > /dev/null"
  else
    docker stop taffiserver > /dev/null
  fi
  if [[ $dockerLog ]]; then
    if [[ $dryRun ]]; then
      echo "docker logs taffiserver > $(removeQuotes "$dockerLogdir")/taffiserver_docker.log 2>&1"
      echo "docker rm taffiserver > /dev/null"
    else
      docker logs taffiserver > "$(removeQuotes "$dockerLogdir")/taffiserver_docker.log" 2>&1
      docker rm taffiserver > /dev/null
    fi
  fi
}

rmFile() {
  local filePath=$(removeQuotes "$1")
  if [[ $dryRun ]]; then
    echo "rm \"$filePath\""
  else
    rm "$filePath"
  fi
}

createDirIfNotExist() {
  local dirPath=$(removeQuotes "$1")
  if [[ ! -d "$dirPath" ]]; then
    if [[ $dryRun ]]; then
      echo "mkdir -p \"$dirPath\""
    else
      mkdir -p "$dirPath"
    fi
  fi
  if [[ $dryRun ]]; then
    echo "chmod 777 \"$dirPath\""
  else
    chmod 777 "$dirPath"
  fi
}

# Handle commandline arguments
while [[ $# -gt 0 ]]; do
  key="$1"

  case $key in
    -h|--help)
      usage
      shift # past argument
      ;;
    -o|--output)
      showOutput=1
      shift # past argument
      ;;
    -r|--report)
      showReport=1
      shift # past argument
      ;;
    -s|--status)
      showStatus=1
      shift # past argument
      ;;
    -l|--log)
      dockerLog=1
      shift # past argument
      ;;
    -d|--dry-run)
      dryRun=1
      shift # past argument
      ;;
    -v|--verbose)
      set -v
      shift # past argument
      ;;
    -x|--show-executions)
      set -x
      shift # past argument
      ;;
    *)    # unknown option
      configFile="$1" # treat it as the config file
      shift # past argument
      ;;
  esac
done

if [[ ! "$configFile" ]]; then
  echo "Please give configuration file path as an argument."
  usage
elif [[ ! -f "$configFile" ]]; then
  echo "File \"$configFile\" does not exist."
  usage
fi

if [[ "$OSTYPE" =~ ^(msys)$ ]]; then
  export MSYS_NO_PATHCONV=1
fi

# Configurations
serverConfig=$(jq .serverConfig "$configFile")
if [[ $serverConfig == "null" ]]; then echo "serverConfig missing from $configFile"; exit 11; fi
cliConfig=$(jq .cliConfig "$configFile")
if [[ $cliConfig == "null" ]]; then cliConfig="{}"; fi
runConfig=$(jq .runConfig "$configFile")
if [[ $runConfig == "null" ]]; then echo "runConfig missing from $configFile"; exit 12; fi
taffiServerImage=$(echo $serverConfig | jq .dockerImage)
if [[ $taffiServerImage == "null" ]]; then echo "serverConfig.dockerImage missing from $configFile"; exit 13; fi
testDir=$(echo $serverConfig | jq .testDir)
if [[ $testDir == "null" ]]; then echo "serverConfig.testDir missing from $configFile"; exit 14; fi
serverConfigDir=$(echo $serverConfig | jq .configDir)
if [[ $serverConfigDir == "null" ]]; then echo "serverConfig.serverConfigDir missing from $configFile"; exit 15; fi
resultsDir=$(echo $serverConfig | jq .resultsDir)
taffiCliImage=$(echo $cliConfig | jq .dockerImage)
if [[ $taffiCliImage == "null" ]]; then echo "cliConfig.dockerImage missing from $configFile"; exit 16; fi
cliConfigDir=$(echo $cliConfig | jq .configDir)
if [[ $cliConfigDir == "null" ]]; then cliConfigDir=\"$(pwd)\"; fi
serverUrl=$(echo $cliConfig | jq .serverUrl)
if [[ $serverUrl == "null" ]]; then serverUrl='"http://taffiserver.taffinet:4000"'; fi
serverTimeout=$(echo $cliConfig | jq .serverTimeout)
if [[ $serverTimeout == "null" ]]; then serverTimeout=30; fi
declare -a serverDockerCmd="($(echo $serverConfig | jq -r '.cmd | @sh'))"
taffiServerConfigDocker="/taffi/config"
taffiNetworkName="taffinet"

if [[ $dryRun ]]; then
  echo "Configuration read from $configFile:"
  echo "  taffiServerImage=$taffiServerImage"
  echo "  testDir=$testDir"
  echo "  serverConfigDir=$serverConfigDir"
  echo "  resultsDir=$resultsDir"
  echo "  serverDockerCmd=${serverDockerCmd[@]}"
  echo "  taffiCliImage=$taffiCliImage"
  echo "  cliConfigDir=$cliConfigDir"
  echo "  serverUrl=$serverUrl"
  echo "  serverTimeout=$serverTimeout"
  echo "  dockerLog=$dockerLog"
fi

# Do the actual stuff
runConfigFileName=".runConfig.json"
if [[ $dryRun ]]; then
  echo "echo $runConfig > $(removeQuotes "$cliConfigDir")/$runConfigFileName"
else
  echo "$runConfig" > "$(removeQuotes "$cliConfigDir")/$runConfigFileName"
  if [[ $? != 0 ]]; then
    echo "Could not write temporary run config to file $(removeQuotes "$cliConfigDir")/$runConfigFileName"
    exit 100
  fi
fi

createDirIfNotExist "$resultsDir"
dockerLogdir="$(removeQuotes "$resultsDir")/docker"
createDirIfNotExist "$dockerLogdir"

createNetwork $taffiNetworkName

if [[ $serverDockerCmd == "null" ]]; then
  serverContainerId=$(startServer "$testDir" "$serverConfigDir" "$resultsDir")
else
  serverContainerId=$(startServer "$testDir" "$serverConfigDir" "$resultsDir" "${serverDockerCmd[@]}")
fi

if [[ $serverContainerId =~ Error: ]]; then
  echo "Error in launching TAFFi server"
  exit 101
fi
echo "$serverContainerId"

rc=$(poll_server http://localhost:4000 $serverTimeout)
if [[ $rc != "0" ]]; then
  echo "Error (retcode $rc): TAFFi server (http://localhost:4000) did not respond in $serverTimeout seconds"
  stopServer
  rmFile "$(removeQuotes "$cliConfigDir")/$runConfigFileName"
  exit 102
fi

# If the run config does not have runs-array, then this does not work as the tafficli container will stop immediately, while test run may be still ongoing on server
retCode=0
runCli run run "$taffiServerConfigDocker/$runConfigFileName"
retCode=$(runCli retcode show retcode all)
if [[ $showReport ]]; then
  runCli report show report all
fi
if [[ $showOutput ]]; then
  runCli output show output all
fi
if [[ $showStatus ]]; then
  runCli status show status all
fi

stopServer
rmFile "$(removeQuotes "$cliConfigDir")/$runConfigFileName"
if [[ $dryRun ]]; then
  retCode=0
fi
echo "Exiting with code: '$retCode'"
exit $retCode
