#!/bin/sh

source $(pwd)/.env

export GO111MODULE=on

help() {
    local help="
        Usage: run.sh [command]
        commands:

        help                                                                        : this help
        install                                                                     : install all the dependencies and docker images
        start                                                                       : start the blockchain network and initialize it
        stop                                                                        : stop the blockchain network and remove all the docker containers

        channel create [channel_name]                                               : generate channel configuration file
        channel update [channel_name] [org]                                         : update channel with anchor peers
        channel join [channel_name]                                                 : run by a peer to join a channel

        generate cryptos [config_path] [cryptos_path]                               : generate all the crypto keys and certificates for the network
        generate genesis [base_path] [config_path]                                  : generate the genesis block for the ordering service
        generate channeltx [channel_name] [base_path] [config_path] [cryptos_path]  : generate channel configuration files
                           [network_profile] [channel_profile] [org_msp]            

        chaincode test [chaincode_path]                                             : run unit tests
        chaincode build [chaincode_path]                                            : run build and test against the binary file
        chaincode install [chaincode_name] [chaincode_version] [chaincode_path]     : install chaincode on a peer
        chaincode instantiate [chaincode_name] [chaincode_version] [channel_name]   : instantiate chaincode on a peer for an assigned channel
        chaincode upgrade [channel_name] [chaincode_name] [chaincode_version]       : upgrade chaincode with a new version
        chaincode query [channel_name] [chaincode_name] [data_in_json]              : run query in the format '{\"Args\":\"queryFunction\",\"key\"]}'
        chaincode invoke [channel_name] [chaincode_name] [data_in_json]             : run invoke in the format '{\"Args\":[\"invokeFunction\",\"key\",\"value\"]}'
        
        benchmark load [jobs] [entries]                                             : run benchmark bulk loading of [entries] per parallel [jobs] against a running network
        "
    echoc "$help" dark cyan
}

check_dependencies() {
    if [ "${1}" == "deploy" ]; then
        type docker >/dev/null 2>&1 || { echoc >&2 "docker required but it is not installed. Aborting." light red; exit 1; }
        type docker-compose >/dev/null 2>&1 || { echoc >&2 "docker-compose required but it is not installed. Aborting." light red; exit 1; }
    elif [ "${1}" == "test" ]; then
        type go >/dev/null 2>&1 || { echoc >&2 "Go binary is missing in your PATH. Running the dockerised version..." light yellow; echo $?; }
    fi
}

# echoc: Prints the user specified string to the screen using the specified colour.
#
# Parameters: ${1} - The string to print
#             ${2} - The intensity of the colour.
#             ${3} - The colour to use for printing the string.
#
#             NOTE: The following color options are available:
#
#                   [0|1]30, [dark|light] black
#                   [0|1]31, [dark|light] red
#                   [0|1]32, [dark|light] green
#                   [0|1]33, [dark|light] yellow
#                   [0|1]34, [dark|light] blue
#                   [0|1]35, [dark|light] purple
#                   [0|1]36, [dark|light] cyan
#
echoc() {
    if [[ ${#} != 3 ]]; then
        echo "usage: ${FUNCNAME} <string> [light|dark] [black|red|green|yellow|blue|pruple|cyan]"
        exit 1
    fi

    local message=${1}

    case $2 in
        dark) intensity=0 ;;
        light) intensity=1 ;;
    esac

    if [[ -z $intensity ]]; then
        echo "${2} intensity not recognised"
        exit 1
    fi

    case $3 in 
        black) colour_code=${intensity}30 ;;
        red) colour_code=${intensity}31 ;;
        green) colour_code=${intensity}32 ;;
        yellow) colour_code=${intensity}33 ;;
        blue) colour_code=${intensity}34 ;;
        purple) colour_code=${intensity}35 ;;
        cyan) colour_code=${intensity}36 ;;
    esac
        
    if [[ -z $colour_code ]]; then
        echo "${1} colour not recognised"
        exit 1
    fi

    colour_code=${colour_code:1}

    # Print out the message
    echo "${message}" | awk '{print "\033['${intensity}';'${colour_code}'m" $0 "\033[1;0m"}'
}

install() {
    echoc "========================" dark cyan
	echoc "Installing dependencies" dark cyan
    echoc "========================" dark cyan
    echo
	echoc "Pulling Go docker image" light cyan
	docker pull ${GOLANG_DOCKER_IMAGE}:${GOLANG_DOCKER_TAG}

	__docker_fabric_pull
	__docker_third_party_images_pull
}

__docker_fabric_pull() {
  for image in peer orderer ca ccenv tools; do
      echoc "==> FABRIC IMAGE: $image" light cyan
      echo
      docker pull hyperledger/fabric-$image:${FABRIC_VERSION}
      docker tag hyperledger/fabric-$image:${FABRIC_VERSION} hyperledger/fabric-$image:latest
  done
}

__docker_third_party_images_pull() {
  for image in couchdb kafka zookeeper; do
      echoc "==> THIRDPARTY DOCKER IMAGE: $image" light cyan
      echo
      docker pull hyperledger/fabric-$image:$FABRIC_THIRDPARTY_IMAGE_VERSION
      docker tag hyperledger/fabric-$image:$FABRIC_THIRDPARTY_IMAGE_VERSION hyperledger/fabric-$image:latest
  done
}

start_network() {
	build_chaincode $CHAINCODE_NAME
    test_chaincode $CHAINCODE_NAME
    stop_network

    echoc "========================" dark cyan
	echoc "Starting Fabric network" dark cyan
    echoc "========================" dark cyan
    echo

	generate_cryptos $CONFIG_PATH $CRYPTOS_PATH
    generate_genesis $BASE_PATH $CONFIG_PATH $CRYPTOS_PATH $CONFIGTX_PROFILE_NETWORK
    generate_channeltx $CHANNEL_NAME $BASE_PATH $CONFIG_PATH $CRYPTOS_PATH $CONFIGTX_PROFILE_NETWORK $CONFIGTX_PROFILE_CHANNEL $ORG_MSP
    
    docker-compose -f ${ROOT}/docker-compose.yaml up -d
	
    sleep 5
	
    initialize_network
}

initialize_network() {
    echoc "============================" dark cyan
	echoc "Initializing Fabric network" dark cyan
    echoc "============================" dark cyan
    echo

	create_channel $CHANNEL_NAME
	join_channel $CHANNEL_NAME
	update_channel $CHANNEL_NAME $ORG_MSP
	install_chaincode $CHAINCODE_NAME $CHAINCODE_VERSION ${CHAINCODE_REMOTE_PATH}/${CHAINCODE_NAME}
	instantiate_chaincode $CHAINCODE_NAME $CHAINCODE_VERSION $CHANNEL_NAME
}

test_chaincode() {
    if [ -z "$1" ]; then
		echoc "Chaincode name missing" dark red
		exit 1
	fi

    local chaincode_name="${1}"

    echoc "===================" dark cyan
	echoc "Unit test chaincode" dakr cyan
    echoc "===================" dark cyan

    if [[ $(check_dependencies test) ]]; then
        (docker run --rm  -v ${CHAINCODE_PATH}:/usr/src/myapp -w /usr/src/myapp -e CGO_ENABLED=0 ${GOLANG_DOCKER_IMAGE}:${GOLANG_DOCKER_TAG} sh -c "go test ./${chaincode_name}/... -v") || exit 1
    else
	    (cd $CHAINCODE_PATH && CGO_ENABLED=0 go test ./${chaincode_name}/... -v) || exit 1
    fi

    echoc "Test passed!" light green
}

build_chaincode() {
    if [ -z "$1" ]; then
		echoc "Chaincode name" dark red
		exit 1
	fi

    local chaincode_name="${1}"

    echoc "==================" dark cyan
	echoc "Building chaincode" dakr cyan
    echoc "==================" dark cyan

    if [[ $(check_dependencies test) ]]; then
        (docker run --rm -v ${CHAINCODE_PATH}:/usr/src/myapp -w /usr/src/myapp/${chaincode_name} -e CGO_ENABLED=0 ${GOLANG_DOCKER_IMAGE}:${GOLANG_DOCKER_TAG} sh -c "go build -a -installsuffix nocgo ./... && rm -rf ./${chaincode_name} 2>/dev/null") || exit 1
    else
	    (cd $CHAINCODE_PATH/${chaincode_name} && CGO_ENABLED=0 go build -a -installsuffix nocgo ./... && rm -rf ./${chaincode_name} 2>/dev/null) || exit 1
    fi

    echoc "Build passed!" light green
}

stop_network() {
    echoc "===========================" dark cyan
	echoc "Tearing Fabric network down" dark cyan
    echoc "===========================" dark cyan

    docker-compose -f ${ROOT}/docker-compose.yaml down

    echoc "Cleaning docker leftovers containers and images" light green
    docker rm -f $(docker ps -a | awk '($2 ~ /fabric|dev-/) {print $1}') 2>/dev/null
    docker rmi -f $(docker images -qf "dangling=true") 2>/dev/null
    docker rmi -f $(docker images | awk '($1 ~ /^<none>|dev-/) {print $3}') 2>/dev/null

    data_path="${ROOT}/data"
    if [ -d "$data_path" ]; then
        echoc "!!!!! ATTENTION !!!!!" light red
        echoc "Found data directory: ${data_path}" light red
		read -p "Do you wish to remove this data? [yes/no] " yn
		case $yn in
			[YyEeSs]* ) rm -rf $data_path ;;
			* ) return 0
    	esac
    fi
}

# generate genesis block
# $1: base path
# $2: config path
# $3: cryptos directory
# $4: network profile name
generate_genesis() {
    if [ -z "$1" ]; then
		echoc "Base path missing" dark red
		exit 1
	fi
    if [ -z "$2" ]; then
		echoc "Config path missing" dark red
		exit 1
	fi
    if [ -z "$3" ]; then
		echoc "Crypto material path missing" dark red
		exit 1
	fi
    if [ -z "$4" ]; then
		echoc "Network profile name" dark red
		exit 1
	fi

    local base_path="$1"
    local config_path="$2"
    local channel_dir="${base_path}/channels/orderer-system-channel"
    local cryptos_path="$3"
    local network_profile="$4"

    if [ -d "$channel_dir" ]; then
        echoc "Channel directory ${channel_dir} already exists" light yellow
		read -p "Do you wish to re-generate channel config? [yes/no] " yn
		case $yn in
			[YyEeSs]* ) ;;
			* ) return 0
    	esac
        rm -rf $channel_dir
        mkdir -p $channel_dir
    fi

    echoc "========================" dark cyan
    echoc "Generating genesis block" dark cyan
    echoc "========================" dark cyan
    echo
	echoc "Base path: $base_path" light cyan
	echoc "Config path: $config_path" light cyan
	echoc "Cryptos path: $cryptos_path" light cyan
	echoc "Network profile: $network_profile" light cyan

    # generate genesis block for orderer
	docker run --rm -v ${config_path}/configtx.yaml:/configtx.yaml \
                    -v ${channel_dir}:/channels/orderer-system-channel \
                    -v ${cryptos_path}:/crypto-config \
                    -e FABRIC_CFG_PATH=/ \
                    hyperledger/fabric-tools:${FABRIC_VERSION} \
                    bash -c " \
                        configtxgen -profile $network_profile -channelID orderer-system-channel -outputBlock /channels/orderer-system-channel/genesis_block.pb /configtx.yaml;
                        configtxgen -inspectBlock /channels/orderer-system-channel/genesis_block.pb
                    "
	if [ "$?" -ne 0 ]; then
		echoc "Failed to generate orderer genesis block..." dark red
		exit 1
	fi
}

# generate channel config
# $1: channel_name
# $2: base path
# $3: configtx.yml file path
# $4: cryptos directory
# $5: network profile name
# $6: channel profile name
# $7: org msp
generate_channeltx() {
    if [ -z "$1" ]; then
		echoc "Channel name missing" dark red
		exit 1
	fi
    if [ -z "$2" ]; then
		echoc "Base path missing" dark red
		exit 1
	fi
    if [ -z "$3" ]; then
		echoc "Config path missing" dark red
		exit 1
	fi
    if [ -z "$4" ]; then
		echoc "Crypto material path missing" dark red
		exit 1
	fi
    if [ -z "$5" ]; then
		echoc "Network profile missing" dark red
		exit 1
	fi
    if [ -z "$6" ]; then
		echoc "Channel profile missing" dark red
		exit 1
	fi
    if [ -z "$7" ]; then
		echoc "MSP missing" dark red
		exit 1
	fi

	local channel_name="$1"
    local base_path="$2"
    local config_path="$3"
    local cryptos_path="$4"
    local channel_dir="${base_path}/channels/${channel_name}"
    local network_profile="$5"
    local channel_profile="$6"
    local org_msp="$7"

    if [ -d "$channel_dir" ]; then
        echoc "Channel directory ${channel_dir} already exists" light yellow
		read -p "Do you wish to re-generate channel config? [yes/no] " yn
		case $yn in
			[YyEeSs]* ) ;;
			* ) return 0
    	esac
        rm -rf $channel_dir
        mkdir -p $channel_dir
    fi 

    echoc "=========================" dark cyan
    echoc "Generating channel config" dark cyan
    echoc "=========================" dark cyan
    echo
	echoc "Channel: $channel_name" light cyan
	echoc "Base path: $base_path" light cyan
	echoc "Config path: $config_path" light cyan
	echoc "Cryptos path: $cryptos_path" light cyan
	echoc "Channel dir: $channel_dir" light cyan
	echoc "Network profile: $network_profile" light cyan
	echoc "Channel profile: $channel_profile" light cyan
	echoc "Org MSP: $org_msp" light cyan

	# generate channel configuration transaction
	docker run --rm -v ${config_path}/configtx.yaml:/configtx.yaml \
                    -v ${channel_dir}:/channels/${channel_name} \
                    -v ${cryptos_path}:/crypto-config \
                    -e FABRIC_CFG_PATH=/ \
                    hyperledger/fabric-tools:${FABRIC_VERSION} \
                    bash -c " \
                        configtxgen -profile $channel_profile -outputCreateChannelTx /channels/${channel_name}/${channel_name}_tx.pb -channelID $channel_name /configtx.yaml;
                        configtxgen -inspectChannelCreateTx /channels/${channel_name}/${channel_name}_tx.pb
                    "
	if [ "$?" -ne 0 ]; then
		echoc "Failed to generate channel configuration transaction..." dark red
		exit 1
	fi

	# generate anchor peer transaction
	docker run --rm -v ${config_path}/configtx.yaml:/configtx.yaml \
                    -v ${channel_dir}:/channels/${channel_name} \
                    -v ${cryptos_path}:/crypto-config \
                    -e FABRIC_CFG_PATH=/ \
                    hyperledger/fabric-tools:${FABRIC_VERSION} \
                    configtxgen -profile $channel_profile -outputAnchorPeersUpdate /channels/${channel_name}/${org_msp}_anchors_tx.pb -channelID $channel_name -asOrg $org_msp /configtx.yaml
	if [ "$?" -ne 0 ]; then
		echoc "Failed to generate anchor peer update for $org_msp..." dark red
		exit 1
	fi
}

# generate crypto config
# $1: crypto-config.yml file path
# $2: certificates output directory
generate_cryptos() {
    if [ -z "$1" ]; then
		echoc "Config path missing" dark red
		exit 1
	fi
    if [ -z "$2" ]; then
		echoc "Cryptos path missing" dark red
		exit 1
	fi

    local config_path="$1"
    local cryptos_path="$2"

    if [ -d "$cryptos_path" ]; then
        echoc "crypto-config already exists" light yellow
		read -p "Do you wish to re-generate crypto-config? [yes/no] " yn
		case $yn in
			[YyEeSs]* ) ;;
			* ) return 0
    	esac
        rm -rf $cryptos_path
        mkdir -p $cryptos_path
    fi

    echoc "==================" dark cyan
    echoc "Generating cryptos" dark cyan
    echoc "==================" dark cyan
    echo
	echoc "Config path: $config_path" light cyan
	echoc "Cryptos path: $cryptos_path" light cyan

	# generate crypto material
	docker run --rm -v ${config_path}/crypto-config.yaml:/crypto-config.yaml \
                    -v ${cryptos_path}:/crypto-config \
                    hyperledger/fabric-tools:${FABRIC_VERSION} \
                    cryptogen generate --config=/crypto-config.yaml --output=/crypto-config
	if [ "$?" -ne 0 ]; then
		echoc "Failed to generate crypto material..." dark red
		exit 1
	fi
}

create_channel() {
	if [ -z "$1" ]; then
		echoc "Incorrect usage of $FUNCNAME. Please consult the help: ./run.sh help" dark red
		exit 1
	fi

	local channel_name="$1"

	echoc "Creating channel $channel_name using configuration file $CHANNELS_CONFIG_PATH/$channel_name/${channel_name}_tx.pb" light cyan
	docker exec $CHAINCODE_UTIL_CONTAINER peer channel create -o $ORDERER_ADDRESS -c $channel_name -f $CHANNELS_CONFIG_PATH/$channel_name/${channel_name}_tx.pb --outputBlock $CHANNELS_CONFIG_PATH/$channel_name/${channel_name}.block
}

join_channel() {
 	if [ -z "$1" ]; then
		echoc "Incorrect usage of $FUNCNAME. Please consult the help: ./run.sh help" dark red
		exit 1
	fi

	local channel_name="$1"

	echoc "Joining channel $channel_name" light cyan
    docker exec $CHAINCODE_UTIL_CONTAINER peer channel join -b $CHANNELS_CONFIG_PATH/${channel_name}/${channel_name}.block
}

update_channel() {
	if [ -z "$1" ] || [ -z "$2" ]; then
		echoc "Incorrect usage of $FUNCNAME. Please consult the help: ./run.sh help" dark red
		exit 1
	fi

	local channel_name="$1"
    local org_msp="$2"

	echoc "Updating anchors peers $channel_name using configuration file $CHANNELS_CONFIG_PATH/$channel_name/${org_msp}_anchors.tx" light cyan
	docker exec $CHAINCODE_UTIL_CONTAINER peer channel update -o $ORDERER_ADDRESS -c $channel_name -f $CHANNELS_CONFIG_PATH/${channel_name}/${org_msp}_anchors_tx.pb
}

install_chaincode() {
	if [ -z "$1" ] || [ -z "$2" ] || [ -z "$3" ]; then
		echoc "Incorrect usage of $FUNCNAME. Please consult the help: ./run.sh help" dark red
		exit 1
	fi

	local chaincode_name="$1"
	local chaincode_version="$2"
	local chaincode_path="$3"

    echoc "Installig chaincode $chaincode_name version $chaincode_version from path $chaincode_path" light cyan
    docker exec $CHAINCODE_UTIL_CONTAINER peer chaincode install -n $chaincode_name -v $chaincode_version -p $chaincode_path
}

instantiate_chaincode() {
	if [ -z "$1" ] || [ -z "$2" ] || [ -z "$3" ]; then
		echoc "Incorrect usage of $FUNCNAME. Please consult the help: ./run.sh help" dark red
		exit 1
	fi

	local chaincode_name="$1"
	local chaincode_version="$2"
	local channel_name="$3"

    echoc "Instantiating chaincode $chaincode_name version $chaincode_version into channel $channel_name" light cyan
	docker exec $CHAINCODE_UTIL_CONTAINER peer chaincode instantiate -n $chaincode_name -v $chaincode_version -C $channel_name -c '{"Args":[]}'
}

upgrade_chaincode() {
	if [ -z "$1" ] || [ -z "$2" ] || [ -z "$3" ]; then
		echoc "Incorrect usage of $FUNCNAME. Please consult the help: ./run.sh help" dark red
		exit 1
	fi

	local chaincode_name="$1"
	local chaincode_version="$2"
	local channel_name="$3"

	build_chaincode
	test_chaincode
	install_chaincode $chaincode_name $chaincode_version $channel_name

    echoc "Upgrading chaincode $chaincode_name to version $chaincode_version into channel $chainnel_name" light cyan
	docker exec $CHAINCODE_UTIL_CONTAINER peer chaincode upgrade -n $chaincode_name -v $chaincode_version -C $channel_name -c '{"Args":[]}'
}

invoke() {
	if [ -z "$1" ] || [ -z "$2" ] || [ -z "$3" ]; then
		echoc "Incorrect usage of $FUNCNAME. Please consult the help: ./run.sh help" dark red
		exit 1
	fi

	local channel_name="$1"
	local chaincode_name="$2"
	local request="$3"

	docker exec $CHAINCODE_UTIL_CONTAINER peer chaincode invoke -o $ORDERER_ADDRESS -C $channel_name -n $chaincode_name -c $request
}

query() {
	if [ -z "$1" ] || [ -z "$2" ] || [ -z "$3" ]; then
		echoc "Incorrect usage of $FUNCNAME. Please consult the help: ./run.sh help" dark red
		exit 1
	fi

	local channel_name="$1"
	local chaincode_name="$2"
	local request="$3"

	docker exec $CHAINCODE_UTIL_CONTAINER peer chaincode query -o $ORDERER_ADDRESS -C $channel_name -n $chaincode_name -c $request	
}

__exec_jobs() {
    local jobs=$1
    local entries=$2

    if [ -z "$jobs" ]; then
        echo "Provide a number of jobs to run in parallel"
        exit 1
    fi
    if [ -z "$entries" ]; then
        echo "Provide a number of entries per job"
        exit 1
    fi

    echoc "Running in parallel:
    Jobs: $jobs
    Entries: $entries
    " light cyan

    start_time="$(date -u +%s)"
    
    for i in $(seq 1 $jobs); do
        __loader $entries & 
    done

    for job in $(jobs -p); do
        wait $job
    done 

    end_time="$(date -u +%s)"

    elapsed="$(($end_time - $start_time))"
    echoc "Total of $elapsed seconds elapsed for process" light yellow

    echoc "$(( $jobs * $entries )) entries added" light green
}

__loader() {
    export LC_CTYPE=C

    for i in $(seq 1 $1); do 
        key=$(cat /dev/urandom | tr -cd 'A-Z0-9' | fold -w 14 | head -n 1)
        value="$i"

        invoke mychannel mychaincode "{\"Args\":[\"put\",\"${key}\",\"${value}\"]}" &>/dev/null
    done
}

readonly func="$1"
shift

if [ "$func" == "install" ]; then
    check_dependencies deploy
    install
elif [ "$func" == "start" ]; then
    check_dependencies deploy
    start_network
elif [ "$func" == "stop" ]; then
    stop_network
elif [ "$func" == "chaincode" ]; then
    readonly param="$1"
    shift
    if [ "$param" == "install" ]; then
        install_chaincode $@
    elif [ "$param" == "instantiate" ]; then
        instantiate_chaincode $@
    elif [ "$param" == "upgrade" ]; then
        upgrade_chaincode $@
    elif [ "$param" == "test" ]; then
        test_chaincode $@
    elif [ "$param" == "build" ]; then
        build_chaincode $@
    elif [ "$param" == "query" ]; then
        query $@
    elif [ "$param" == "invoke" ]; then
        invoke $@
    fi
elif [ "$func" == "generate_cryptos" ]; then
    readonly param="$1"
    shift
    if [ "$param" == "cryptos" ]; then
        generate_cryptos $@
    elif [ "$param" == "genesis" ]; then
        generate_genesis $@
    elif [ "$param" == "channeltx" ]; then
        generate_channeltx $@
    fi
elif [ "$func" == "channel" ]; then
    readonly param="$1"
    shift
    if [ "$param" == "create" ]; then
        create_channel $@
    elif [ "$param" == "update" ]; then
        update_channel $@
    elif [ "$param" == "join" ]; then
        join_channel $@
    fi
elif [ "$func" == "benchmark" ]; then
    readonly param="$1"
    shift
    if [ "$param" == "load" ]; then
        check_dependencies deploy
        __exec_jobs $@
    fi
else
    help
    exit 1
fi