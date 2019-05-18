# Hyperledger Fabric Chaincode Boilerplate 

A basic and simple boilerplate which contains utilities for efficiently writing chaincode and test it in a running network.

# Purpose

The codebase of this repository is meant to serve the following scopes:

- as a starting point for any new project which will use a Hyperledger Fabric native chaincode
- as an open project shared across all the development teams which are asked to participate and contribute following the common issue tracking system and merge request procedure
- as a space where to define coding standards and best practices through a process of peer reviewing and features proposing (working as a discussion forum)

## Prerequisites

- [Go](https://golang.org/dl/)
- [Docker](https://www.docker.com/get-started)
- [Docker-compose](https://www.docker.com/get-started)

## Install

Install all the docker images needed:
```bash
./run.sh install
```

## Run the blockchain network

The following command will spin a Hyperledger Fabric network up, generating _channel_ and _crypto_ config at runtime:

```bash
./run.sh start
```

It will execute the following functions:

- Build and test the chaincode
- Run unit tests
- Generate crypto materials
- Generate genesis block
- Generate default channel configuration files
- Add default peer to join the channel
- Update the channel with anchor peers
- Install the default chaincode into the default peer
- Instantiate the chaincode on the default peer

Afterwards, the network will be ready to accept `invoke` and `query` functions.

Run `./run.sh help` for the complete list of functionalities.

## Upgrade chaincode

Run the following command in order to install and instantiate a new version of the chaincode:

```bash
./run.sh chaincode upgrade [chaincode_name] [chaincode_version] [channel_name]
```

Be sure the `chaincode_version` is unique and never used before (otherwise an error will be prompted).

## Invoke and query

It is possible to use the CLI to run and test functionalities.

**Note:** The function appearing as a string in the first place of the array `Args` needs to be defined in the chaincode and the `request` should be provided as a JSON wrapped into single quotes `'`.

### Invoke

```bash
./run.sh chaincode invoke [channel_name] [chaincode_name] [request]

# e.g.
./run.sh chaincode invoke mychannel mychaincode '{"Args":["put","key1","10"]}'
```

### Query

```bash
./run.sh chaincode query [channel_name] [chaincode_name] [request]

# e.g.
./run.sh chaincode query mychannel mychaincode '{"Args":["get","key1"]}'
```

## Register and enroll users

todo

## Cleanup the environment

### Tear blockchain network down

It will stop and remove all the blockchain network containers including the `dev-peer*` tagged chaincode ones.

```bash
./run.sh stop
```

## Benchmarks

The repository provides also a simple implementation of a bulk load function in order to benchmark the general speed of the network in terms of tps (transactions-per-second).

```bash
./run.sh benchmark [jobs] [entries]

# e.g.
./run.sh benchmark 5 1000
```

The example above will do a bulk load of 1000 entries times 5 parallel jobs, for a total of 5000 entries. At the completion of all the jobs it will be prompted on screen the elapsed time of the total task.

**Note: Maintain the number of jobs not superior to your CPU cores in order to obtain the best results. This implementation does not provides a complete parallelisation.**

To achieve the optimal result it is recommended to install [Gnu Parallel](https://www.gnu.org/software/parallel/) and use as it follows:

```bash
time (parallel ./benchmarks.sh {} ::: [entries])

# e.g.
time (parallel ./benchmarks.sh {} ::: 20)
# 8.613 total against 29.893 total
# ~4 times lower than running jobs with "&"
```