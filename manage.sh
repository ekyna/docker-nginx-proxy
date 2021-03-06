#!/bin/bash

if [[ ! -f "./.env" ]]
then
    printf "\e[31mPlease create the .env file based on .env.dist\e[0m\n"
    exit
fi

if [[ $(uname -s) = MINGW* ]];
then
  export MSYS_NO_PATHCONV=1;
  export COMPOSE_CONVERT_WINDOWS_PATHS=1
fi

cd "$( cd "$( dirname "${BASH_SOURCE[0]}" )" && pwd )" || exit

LOG_PATH="./docker_logs.txt"

source ./.env

if [[ -z ${SYSLOG_HOST+x} ]]; then printf "\e[31mSYSLOG_HOST env variable is not set.\e[0m\n"; exit; fi
if [[ -z ${SYSLOG_PORT+x} ]]; then printf "\e[31mSYSLOG_PORT env variable is not set.\e[0m\n"; exit; fi
if [[ -z ${REGISTRY_SECRET+x} ]]; then printf "\e[31mREGISTRY_SECRET env variable is not set.\e[0m\n"; exit; fi
if [[ -z ${REGISTRY_SECRET+x} ]]; then printf "\e[31mREGISTRY_SECRET env variable is not set.\e[0m\n"; exit; fi
if [[ -z ${REGISTRY_PORT+x} ]]; then printf "\e[31mREGISTRY_PORT env variable is not set.\e[0m\n"; exit; fi
if [[ -z ${REGISTRY_HOST+x} ]]; then printf "\e[31mREGISTRY_HOST env variable is not set.\e[0m\n"; exit; fi
if [[ -z ${REGISTRY_EMAIL+x} ]]; then printf "\e[31mREGISTRY_EMAIL env variable is not set.\e[0m\n"; exit; fi

# Clear logs
echo "" > ${LOG_PATH}

Success() {
    printf "\e[32m%s\e[0m\n" "$1"
}

Error() {
    printf "\e[31m%s\e[0m\n" "$1"
}

Warning() {
    printf "\e[31;43m%s\e[0m\n" "$1"
}

Comment() {
    printf "\e[36m%s\e[0m\n" "$1"
}

Help() {
    printf "\e[2m%s\e[0m\n" "$1";
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

Confirm () {
    Ln

    choice=""
    while [[ "$choice" != "n" ]] && [[ "$choice" != "y" ]]
    do
        printf "Do you want to continue ? (N/Y)"
        read -r choice
        choice=$(echo "${choice}" | tr '[:upper:]' '[:lower:]')
    done

    if [[ "$choice" = "n" ]]; then
        Warning "Abort by user"
        exit 0
    fi

    Ln
}

IsUpAndRunning() {
    if docker ps --format '{{.Names}}' | grep -q "$1\$"
    then
        return 0
    fi
    return 1
}

CheckProxyUpAndRunning() {
    if ! IsUpAndRunning proxy_nginx
    then
        printf "\e[31mProxy is not up and running.\e[0m\n"
        exit 1
    fi
}

NetworkExists() {
    if docker network ls --format '{{.Name}}' | grep -q "$1\$"
    then
        return 0
    fi
    return 1
}


NetworkCreate() {
    printf "Creating network \e[1;33m%s\e[0m ... " "$1"
    if ! NetworkExists "$1"
    then
        if ! docker network create "$1" >> "${LOG_PATH}" 2>&1
        then
            Error "error"
            exit 1
        fi

        Success "created"
    else
        Comment "exists"
    fi
}

NetworkRemove() {
    printf "Removing network \e[1;33m%s\e[0m ... " "$1"
    if NetworkExists "$1"
    then
        if ! docker network rm "$1" >> "${LOG_PATH}" 2>&1
        then
            Error "error"
            exit 1
        fi

        Success "removed"
    else
        Comment "unknown"
    fi
}

DockerCompose() {
  # shellcheck disable=SC2086
  eval "$(grep -Ev '^#' ./.env | xargs)" docker-compose ${*:1}
}

ProxyUp() {
    if IsUpAndRunning "proxy_nginx"
    then
        Warning "Already up and running."
        exit 1
    fi

    if ! NetworkExists proxy_network
    then
        NetworkCreate proxy_network
    fi

    printf "Starting \e[1;33mproxy\e[0m ... "
    DockerCompose -p proxy -f ./compose/proxy.yml up -d >> ${LOG_PATH} 2>&1
    DoneOrError $?

    if [[ -f ./networks.list ]]
    then
        while IFS='' read -r NETWORK || [[ -n "$NETWORK" ]]; do
            if [[ "" != "${NETWORK}" ]]
            then
                Connect "${NETWORK}"
            fi
        done < ./networks.list

        sleep 1
        docker restart proxy_nginx
    fi
}

ProxyDown() {
    printf "Stopping \e[1;33mproxy\e[0m ... "
    DockerCompose -p proxy -f ./compose/proxy.yml -f ./compose/registry.yml down -v --remove-orphans >> ${LOG_PATH} 2>&1
    DoneOrError $?
}

Execute() {
    CheckProxyUpAndRunning

    printf "Executing %s \n" "$1"
    printf "\n"
    # shellcheck disable=SC2086
    docker exec -it proxy_nginx $1
    printf "\n"
}

Connect() {
    CheckProxyUpAndRunning

    NETWORK="$(echo -e "$1" | sed -e 's/^[[:space:]]*//' -e 's/[[:space:]]*$//')"

    if ! NetworkExists "${NETWORK}"
    then
        printf "\e[31mNetwork '%s' does not exist.\e[0m\n" "${NETWORK}"
        exit
    fi

    printf "Connecting to \e[1;33m%s\e[0m network ... " "${NETWORK}"

    docker network connect "${NETWORK}" proxy_nginx >> ${LOG_PATH} 2>&1
    DoneOrError $?
    docker network connect "${NETWORK}" proxy_generator >> ${LOG_PATH} 2>&1
    DoneOrError $?

    printf "\e[32mdone\e[0m\n"

    if [[ -f ./networks.list ]];
    then
        if cat ./networks.list | grep -q "${NETWORK}"; then return 0; fi
    fi

    echo $1 >> ./networks.list
}

# ----------------------------- REGISTRY -----------------------------

CreateUser() {
    if [[ "" == "$1" ]]
    then
        printf "\e[31mPlease provide a user name.\e[0m\n"
        exit
    fi
    if [[ "" == "$2" ]]
    then
        printf "\e[31mPlease provide a password.\e[0m\n"
        exit
    fi

    if [[ ! -d "./volumes/auth" ]]; then mkdir ./volumes/auth; fi
    docker run --rm --entrypoint htpasswd registry:2.5.2 -Bbn "$1" "$2" > ./volumes/auth/htpasswd
}

RegistryUp() {
    CheckProxyUpAndRunning

    if [[ ! -f "./volumes/auth/htpasswd" ]]
    then
        printf "\e[31mPlease run './manage.sh create-user <name> <password>' command first.\e[0m\n"
        exit
    fi

    if ! NetworkExists registry_network
    then
        NetworkCreate registry_network
        Connect registry_network
    fi

    printf "Starting \e[1;33mregistry\e[0m ... "
    DockerCompose -p registry -f ./compose/registry.yml up -d >> ${LOG_PATH} 2>&1
    DoneOrError $?
}

RegistryDown() {
    if ! IsUpAndRunning "registry_registry"
    then
        printf "\e[31mRegistry is not up and running.\e[0m\n"
        exit 1
    fi

    printf "Stopping \e[1;33mregistry\e[0m ... "
    DockerCompose -p registry -f ./compose/registry.yml down -v >> ${LOG_PATH} 2>&1
    DoneOrError $?
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
        Connect "$2"
    ;;
    restart)
        if ! IsUpAndRunning nginx
        then
            printf "\e[31mNot up and running.\e[0m\n"
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
        CreateUser "$2" "$3"
    ;;
    registry)
        if [[ ! $2 =~ ^up|down$ ]]
        then
            printf "\e[31mExpected 'up' or 'down'\e[0m\n"
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

printf "\n"
