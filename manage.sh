#!/bin/bash

cd "$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)" || exit

if [[ ! -f ".env" ]]
then
    printf "\e[31mPlease create the .env file based on .env.dist\e[0m\n"
    exit
fi

LOG_PATH="docker_logs.txt"

source ./.env

if [[ -z ${REGISTRY_VERSION+x} ]]; then printf "\e[31mREGISTRY_VERSION env variable is not set.\e[0m\n"; exit; fi
if [[ -z ${REGISTRY_SECRET+x} ]]; then printf "\e[31mREGISTRY_SECRET env variable is not set.\e[0m\n"; exit; fi
if [[ -z ${REGISTRY_HOST+x} ]]; then printf "\e[31mREGISTRY_HOST env variable is not set.\e[0m\n"; exit; fi
if [[ -z ${REGISTRY_PORT+x} ]]; then printf "\e[31mREGISTRY_PORT env variable is not set.\e[0m\n"; exit; fi
if [[ -z ${REGISTRY_EMAIL+x} ]]; then printf "\e[31mREGISTRY_EMAIL env variable is not set.\e[0m\n"; exit; fi

# Clear logs
echo "" > ${LOG_PATH}

Help() {
    printf "\e[2m%s\e[0m\n" "$1"
}

Success() {
    printf "\e[32m%s\e[0m\n" "$1"
}

Error() {
    printf "\e[31m%s\e[0m\n" "$1"
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

ProxyUp() {
    if IsUpAndRunning proxy_nginx
    then
        printf "\e[31mAlready up and running.\e[0m\n"
        exit 1
    fi

    printf "Starting \e[1;33mproxy\e[0m ... "
    docker-compose -p proxy -f ./compose/proxy.yml --env-file=.env up -d >> ${LOG_PATH} 2>&1
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
    docker-compose -p proxy -f ./compose/proxy.yml --env-file=.env -f ./compose/registry.yml down --remove-orphans >> ${LOG_PATH} 2>&1
    DoneOrError $?
}

Execute() {
    CheckProxyUpAndRunning

    printf "Executing %s\n" "$1"
    printf "\n"
    docker exec -it proxy_nginx "$1"
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

    (docker network connect "${NETWORK}" proxy_nginx >> ${LOG_PATH} 2>&1) || (printf "\e[31merror\e[0m\n" && exit 1)
    (docker network connect "${NETWORK}" proxy_generator >> ${LOG_PATH} 2>&1) || (printf "\e[31merror\e[0m\n" && exit 1)

    printf "\e[32mdone\e[0m\n"

    if [[ -f ./networks.list ]];
    then
        if grep -q "${NETWORK}" < ./networks.list; then return 0; fi
    fi

    echo "$1" >> ./networks.list
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

    docker run --rm --entrypoint htpasswd "registry:${REGISTRY_VERSION}" -Bbn "$1" "$2" > ./volumes/auth/htpasswd
    DoneOrError $?
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
#        Connect registry_network
    fi

    printf "Starting \e[1;33mregistry\e[0m ... "
    docker-compose -p registry -f ./compose/registry.yml --env-file=.env up -d >> ${LOG_PATH} 2>&1
    DoneOrError $?
}

RegistryDown() {
    if ! IsUpAndRunning "registry_registry"
    then
        printf "\e[31mRegistry is not up and running.\e[0m\n"
        exit 1
    fi

    printf "Stopping \e[1;33mregistry\e[0m ... "
    docker-compose -p registry -f ./compose/registry.yml --env-file=.env down >> ${LOG_PATH} 2>&1
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
        printf "\e[2mUsage:  ./manage.sh [action] [options]

    \e[0mup\e[2m                      Starts the proxy.
    \e[0mdown\e[2m                    Stops the proxy.
    \e[0mconnect\e[2m name            Connects the proxy to the [name] network.
    \e[0mrestart\e[2m                 Restarts the nginx container.
    \e[0mtest\e[2m                    Tests the nginx config.
    \e[0mdump\e[2m                    Dumps the nginx config.
    \e[0mcreate-user\e[2m user pwd    Creates the registry user.
    \e[0mregistry\e[2m up|down        Starts or stops the registry.
\e[0m\n"
    ;;
esac

printf "\n"
