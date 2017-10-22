#!/bin/bash

if [[ ! -f "./.env" ]]
then
    printf "\e[31mPlease create the .env file based on .env.dist\e[0m\n"
    exit
fi

DIR="$( cd "$( dirname "${BASH_SOURCE[0]}" )" && pwd )"
LOG_PATH="$DIR/docker_logs.txt"

source ./.env

if [[ "" == "${SYSLOG_HOST}" ]]; then printf "\e[31mSYSLOG_HOST env variable is not set.\e[0m\n"; exit; fi
if [[ "" == "${SYSLOG_PORT}" ]]; then printf "\e[31mSYSLOG_PORT env variable is not set.\e[0m\n"; exit; fi
if [[ "" == "${REGISTRY_SECRET}" ]]; then printf "\e[31mREGISTRY_SECRET env variable is not set.\e[0m\n"; exit; fi
if [[ "" == "${REGISTRY_SECRET}" ]]; then printf "\e[31mREGISTRY_SECRET env variable is not set.\e[0m\n"; exit; fi
if [[ "" == "${REGISTRY_PORT}" ]]; then printf "\e[31mREGISTRY_PORT env variable is not set.\e[0m\n"; exit; fi
if [[ "" == "${REGISTRY_HOST}" ]]; then printf "\e[31mREGISTRY_HOST env variable is not set.\e[0m\n"; exit; fi
if [[ "" == "${REGISTRY_EMAIL}" ]]; then printf "\e[31mREGISTRY_EMAIL env variable is not set.\e[0m\n"; exit; fi

# Clear logs
echo "" > ${LOG_PATH}


Help() {
    printf "\e[2m$1\e[0m\n";
}

IsUpAndRunning() {
    if [[ "$(docker ps | grep $1)" ]]
    then
        return 0
    fi
    return 1
}

CheckProxyUpAndRunning() {
    if ! IsUpAndRunning "proxy_nginx"
    then
        printf "\e[31mProxy is not up and running.\e[0m\n"
        exit 1
    fi
}

NetworkExists() {
    if [[ "$(docker network ls | grep $1)" ]]
    then
        return 0
    fi
    return 1
}

NetworkCreate() {
    printf "Creating network \e[1;33m$1\e[0m ... "
    if NetworkExists $1
    then
        printf "\e[36mexists\e[0m\n"
    else
        docker network create $1 >> ${LOG_PATH} 2>&1 \
            && printf "\e[32mcreated\e[0m\n" \
            || (printf "\e[31merror\e[0m\n" && exit 1)
    fi
}

NetworkRemove() {
    printf "Removing network \e[1;33m$1\e[0m ... "
    if NetworkExists $1
    then
        docker network rm $1 >> ${LOG_PATH} 2>&1 \
            && printf "\e[32mremoved\e[0m\n" \
            || (printf "\e[31merror\e[0m\n" && exit 1)
    else
        printf "\e[35munknown\e[0m\n"
    fi
}

ProxyUp() {
    if IsUpAndRunning "proxy_nginx"
    then
        printf "\e[31mAlready up and running.\e[0m\n"
        exit 1
    fi

    if ! NetworkExists proxy_network
    then
        NetworkCreate proxy_network
    fi

    printf "Starting \e[1;33mproxy\e[0m ... "
    cd ${DIR} && \
        docker-compose -p proxy -f ./compose/proxy.yml up -d >> ${LOG_PATH} 2>&1 \
            && printf "\e[32mdone\e[0m\n" \
            || (printf "\e[31merror\e[0m\n" && exit 1)

    if [[ -f ./networks.list ]]
    then
        while IFS='' read -r NETWORK || [[ -n "$NETWORK" ]]; do
            if [[ "" != "${NETWORK}" ]]
            then
                Connect ${NETWORK}
            fi
        done < ./networks.list
    fi
}

ProxyDown() {
    printf "Stopping \e[1;33mproxy\e[0m ... "
    cd ${DIR} && \
        docker-compose -p proxy -f ./compose/proxy.yml -f ./compose/registry.yml down -v --remove-orphans >> ${LOG_PATH} 2>&1 \
            && printf "\e[32mdone\e[0m\n" \
            || (printf "\e[31merror\e[0m\n" && exit 1)
}

Execute() {
    CheckProxyUpAndRunning

    printf "Executing $1\n"
    printf "\n"
    docker exec -it proxy_nginx $1
    printf "\n"
}

Connect() {
    CheckProxyUpAndRunning

    NETWORK="$(echo -e "$1" | sed -e 's/^[[:space:]]*//' -e 's/[[:space:]]*$//')"

    if ! NetworkExists ${NETWORK}
    then
        printf "\e[31mNetwork '${NETWORK}' does not exist.\e[0m\n"
        exit
    fi

    if [[ -f ./networks.list ]];
    then
        if [[ "$(cat ./networks.list | grep ${NETWORK})" ]]
        then
            printf "\e[31mNetwork ${NETWORK} is already registered\e[0m\n"
            exit
        fi
    fi

    printf "Connecting to \e[1;33m${NETWORK} network\e[0m ... "

    docker network connect ${NETWORK} proxy_nginx >> ${LOG_PATH} 2>&1 || (printf "\e[31merror\e[0m\n" && exit 1)
    docker network connect ${NETWORK} proxy_generator >> ${LOG_PATH} 2>&1 || (printf "\e[31merror\e[0m\n" && exit 1)

    echo $1 >> ./networks.list

    printf "\e[32mdone\e[0m\n"
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

    cd ${DIR}
    if [[ ! -d "./volumes/auth" ]]; then mkdir ./volumes/auth; fi
    docker run --rm --entrypoint htpasswd registry:2.5.2 -Bbn $1 $2 > ./volumes/auth/htpasswd
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
    cd ${DIR} && \
        docker-compose -p registry -f ./compose/registry.yml up -d >> ${LOG_PATH} 2>&1 \
            && printf "\e[32mdone\e[0m\n" \
            || (printf "\e[31merror\e[0m\n" && exit 1)
}

RegistryDown() {
    if ! IsUpAndRunning "registry_registry"
    then
        printf "\e[31mRegistry is not up and running.\e[0m\n"
        exit 1
    fi

    printf "Stopping \e[1;33mregistry\e[0m ... "
    cd ${DIR} && \
        docker-compose -p registry -f ./compose/registry.yml down -v >> ${LOG_PATH} 2>&1 \
            && printf "\e[32mdone\e[0m\n" \
            || (printf "\e[31merror\e[0m\n" && exit 1)
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
    dump)
        Execute "cat /etc/nginx/conf.d/default.conf"
    ;;
    create-user)
        CreateUser $2 $3
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
    \e[0mdump\e[2m                    Dumps the nginx config.
    \e[0mcreate-user\e[2m user pwd    Creates the registry user.
    \e[0mregistry\e[2m up|down        Starts or stops the registry.
"
    ;;
esac

printf "\n"
