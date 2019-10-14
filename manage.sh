#!/bin/bash

cd "$( cd "$( dirname "${BASH_SOURCE[0]}" )" && pwd )"

if [[ ! -f ./.env ]]
then
    printf "\e[31mPlease create the .env file based on .env.dist\e[0m\n"
    exit 1
fi

DIR="$( cd "$( dirname "${BASH_SOURCE[0]}" )" && pwd )"
LOG_PATH="./docker_logs.txt"

source ./.env

if [[ "" == "${CERT_MODE}" ]]; then printf "\e[31mCERT_MODE env variable is not set.\e[0m\n"; exit 1; fi
if [[ "" == "${SYSLOG_HOST}" ]]; then printf "\e[31mSYSLOG_HOST env variable is not set.\e[0m\n"; exit 1; fi
if [[ "" == "${SYSLOG_PORT}" ]]; then printf "\e[31mSYSLOG_PORT env variable is not set.\e[0m\n"; exit 1; fi
if [[ "" == "${REGISTRY_SECRET}" ]]; then printf "\e[31mREGISTRY_SECRET env variable is not set.\e[0m\n"; exit 1; fi
if [[ "" == "${REGISTRY_SECRET}" ]]; then printf "\e[31mREGISTRY_SECRET env variable is not set.\e[0m\n"; exit 1; fi
if [[ "" == "${REGISTRY_PORT}" ]]; then printf "\e[31mREGISTRY_PORT env variable is not set.\e[0m\n"; exit 1; fi
if [[ "" == "${REGISTRY_HOST}" ]]; then printf "\e[31mREGISTRY_HOST env variable is not set.\e[0m\n"; exit 1; fi
if [[ "" == "${REGISTRY_EMAIL}" ]]; then printf "\e[31mREGISTRY_EMAIL env variable is not set.\e[0m\n"; exit 1; fi

if [[ "dns" == "${CERT_MODE}" ]]
then
    if [[ ! -f ./.dns.env ]]
    then
        printf "\e[31mPlease create the .dns.env file based on .dns.env.dist\e[0m\n"
        exit 1
    fi

    if [[ ! -f ./volumes/certs/domains.conf ]]
    then
        printf "\e[31mFile 'volumes/certs/domains.conf' does not exists\e[0m\n"
        exit 1
    fi

    if [[ ! -f ./volumes/certs/lexicon.yml ]]
    then
        printf "\e[31mFile 'volumes/certs/lexicon.yml' does not exists\e[0m\n"
        exit 1
    fi

elif [[ "acme" == "${CERT_MODE}" ]]
then
    printf "\e[31mInvalid CERT_MODE, expected 'acme' or 'dns'\e[0m\n"
fi

PROXY_PATHS="-f ./compose/proxy.yaml -f ./compose/${CERT_MODE}.yaml"

# Clear logs
echo "" > ${LOG_PATH}

Success() {
    printf "\e[32m$1\e[0m\n"
}

Error() {
    printf "\e[31m$1\e[0m\n"
}

Warning() {
    printf "\e[31;43m$1\e[0m\n"
}

Comment() {
    printf "\e[36m$1\e[0m\n"
}

Help() {
    printf "\e[2m$1\e[0m\n"
}

Ln() {
    printf "\n"
}

DoneOrError() {
    if [[ $1 -eq 0 ]]
    then
        Success 'done'
    else
        Error 'error'
        exit 1
    fi
}

IsUpAndRunning() {
    if [[ "$(docker ps --format '{{.Names}}' | grep $1\$)" ]]
    then
        return 0
    fi
    return 1
}

CheckProxyUpAndRunning() {
    if ! IsUpAndRunning "proxy_nginx"
    then
        Error "Proxy is not up and running"
        exit 1
    fi
}

NetworkExists() {
    if [[ "$(docker network ls --format '{{.Name}}' | grep $1\$)" ]]
    then
        return 0
    fi
    return 1
}

NetworkCreate() {
    printf "Creating network \e[1;33m$1\e[0m ... "
    if ! NetworkExists $1
    then
        docker network create $1 >> ${LOG_PATH} 2>&1
        DoneOrError
    else
        Comment "exists"
    fi
}

NetworkRemove() {
    printf "Removing network \e[1;33m$1\e[0m ... "
    if NetworkExists $1
    then
        docker network rm $1 >> ${LOG_PATH} 2>&1
        DoneOrError
    else
        Comment "unknown"
    fi
}

ProxyUp() {
    if IsUpAndRunning "proxy_nginx"
    then
        Error "Already up and running"
        exit 1
    fi

    if ! NetworkExists proxy_network
    then
        NetworkCreate proxy_network
    fi

    printf "Starting \e[1;33mproxy\e[0m ... "
    docker-compose -p proxy ${PROXY_PATHS} up -d >> ${LOG_PATH} 2>&1
    DoneOrError

    if [[ -f ./networks.list ]]
    then
        while IFS='' read -r NETWORK || [[ -n "$NETWORK" ]]; do
            if [[ "" != "${NETWORK}" ]]
            then
                Connect ${NETWORK}
            fi
        done < ./networks.list

        sleep 1
        docker restart proxy_nginx
    fi
}

ProxyDown() {
    printf "Stopping \e[1;33mproxy\e[0m ... "
    docker-compose -p proxy ${PROXY_PATHS} -f ./compose/registry.yaml down -v --remove-orphans >> ${LOG_PATH} 2>&1
    DoneOrError
}

Execute() {
    CheckProxyUpAndRunning

    printf "Executing $1\n"
    Ln
    docker exec -it proxy_nginx $1
    Ln
}

Connect() {
    CheckProxyUpAndRunning

    NETWORK="$(echo -e "$1" | sed -e 's/^[[:space:]]*//' -e 's/[[:space:]]*$//')"

    if ! NetworkExists ${NETWORK}
    then
        Error "Network '${NETWORK}' does not exist"
        exit
    fi

    printf "Connecting to \e[1;33m${NETWORK}\e[0m network ... "

    docker network connect ${NETWORK} proxy_nginx >> ${LOG_PATH} 2>&1
    if [[ $? -ne 0 ]]
    then
        Error "error"
        exit 1
    fi

    docker network connect ${NETWORK} proxy_generator >> ${LOG_PATH} 2>&1
    if [[ $? -ne 0 ]]
    then
        Error "error"
        exit 1
    fi

    Success "done"

    if [[ -f ./networks.list ]];
    then
        if [[ "$(cat ./networks.list | grep ${NETWORK})" ]]; then return 0; fi
    fi

    echo $1 >> ./networks.list
}

# ----------------------------- REGISTRY -----------------------------

CreateUser() {
    if [[ "" == "$1" ]]
    then
        Error "Please provide a user name"
        exit 1
    fi
    if [[ "" == "$2" ]]
    then
        Error "Please provide a password"
        exit 1
    fi

    if [[ ! -d "./volumes/auth" ]]; then mkdir ./volumes/auth; fi
    docker run --rm --entrypoint htpasswd registry:2.5.2 -Bbn $1 $2 > ./volumes/auth/htpasswd
}

RegistryUp() {
    CheckProxyUpAndRunning

    if [[ ! -f "./volumes/auth/htpasswd" ]]
    then
        Error "Please run './manage.sh create-user <name> <password>' command first"
        exit
    fi

    if ! NetworkExists registry_network
    then
        NetworkCreate registry_network
        Connect registry_network
    fi

    printf "Starting \e[1;33mregistry\e[0m ... "
    docker-compose -p registry -f ./compose/registry.yaml up -d >> ${LOG_PATH} 2>&1
    DoneOrError
}

RegistryDown() {
    if ! IsUpAndRunning "registry_registry"
    then
        Error "Registry is not up and running"
        exit 1
    fi

    printf "Stopping \e[1;33mregistry\e[0m ... "
    docker-compose -p registry -f ./compose/registry.yaml down -v >> ${LOG_PATH} 2>&1
    DoneOrError
}

# ----------------------------- EXEC -----------------------------

case $1 in
    up)
        ProxyUp
    ;;
    down)
        ProxyDown
    ;;
    connect)
        Connect $2
    ;;
    restart)
        if ! IsUpAndRunning "proxy_nginx"
        then
            Error "Not up and running"
            exit 1
        fi

        docker restart proxy_nginx
    ;;
    test)
        docker exec proxy_nginx nginx -t
    ;;
    dump)
        cat ./volumes/conf.d/default.conf
    ;;
    create-user)
        CreateUser $2 $3
    ;;
    registry)
        if [[ ! $2 =~ ^up|down$ ]]
        then
            Error "Expected 'up' or 'down'"
            exit 1
        fi

        if [[ $2 == 'up' ]]
        then
            RegistryUp
        else
            RegistryDown
        fi
    ;;
    *)
        Help "Usage:  ./manage.sh [action] [options]

    \e[0mup\e[2m                      Starts the proxy.
    \e[0mdown\e[2m                    Stops the proxy.
    \e[0mconnect\e[2m name            Connects the proxy to the [name] network.
    \e[0mrestart\e[2m                 Restarts the nginx container.
    \e[0mtest\e[2m                    Tests the nginx config.
    \e[0mdump\e[2m                    Dumps the nginx config.
    \e[0mcreate-user\e[2m user pwd    Creates the registry user.
    \e[0mregistry\e[2m up|down        Starts or stops the registry.
"
    ;;
esac

Ln
