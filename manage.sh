#!/bin/bash

if [[ ! -f "./.env" ]]
then
    printf "Please create the .env file based on .env.dist"
    exit
fi

DIR="$( cd "$( dirname "${BASH_SOURCE[0]}" )" && pwd )"
LOG_PATH="$DIR/docker_logs.txt"

source ./.env

if [[ "" == "${COMPOSE_PROJECT_NAME}" ]]
then
    printf "\e[31mCOMPOSE_PROJECT_NAME env variable is not set.\e[0m\n"
    exit
fi
if [[ "" == "${REGISTRY_PORT}" ]]
then
    printf "\e[31mREGISTRY_PORT env variable is not set.\e[0m\n"
    exit
fi
if [[ "" == "${REGISTRY_HOST}" ]]
then
    printf "\e[31mREGISTRY_HOST env variable is not set.\e[0m\n"
    exit
fi
if [[ "" == "${REGISTRY_EMAIL}" ]]
then
    printf "\e[31mREGISTRY_EMAIL env variable is not set.\e[0m\n"
    exit
fi

Help() {
    printf "\e[2m$1\e[0m\n";
}

IsUpAndRunning() {
    if [[ "$(docker ps | grep $1)" ]]
    then
        return 1
    fi
    return 0
}

ProxyUp() {
    IsUpAndRunning "${COMPOSE_PROJECT_NAME}_nginx"
    if [[ $? -eq 1 ]]
    then
        printf "\e[31mAlready up and running.\e[0m\n"
        exit 1
    fi

    printf "Starting \e[1;33mproxy\e[0m ... "
    cd ${DIR} && \
        docker-compose -f ./compose/proxy.yml up -d >> ${LOG_PATH} 2>&1 \
            && printf "\e[32mdone\e[0m\n" \
            || (printf "\e[31merror\e[0m\n" && exit 1)
}

ProxyDown() {
    printf "Stopping \e[1;33mproxy\e[0m ... "
    cd ${DIR} && \
        docker-compose -f ./compose/proxy.yml -f ./compose/registry.yml down -v --remove-orphans >> ${LOG_PATH} 2>&1 \
            && printf "\e[32mdone\e[0m\n" \
            || (printf "\e[31merror\e[0m\n" && exit 1)
}

Execute() {
    IsUpAndRunning "${COMPOSE_PROJECT_NAME}_nginx"
    if [[ $? -eq 0 ]]
    then
        printf "\e[31mNot up and running.\e[0m\n"
        exit 1
    fi

    printf "Executing $1\n"
    printf "\n"
    docker exec -it ${COMPOSE_PROJECT_NAME}_nginx $1
    printf "\n"
}

Connect() {
    if [[ "$(docker network ls | grep $1)" == "" ]]
    then
        printf "\e[31mNetwork '$1' does not exist.\e[0m\n"
        exit
    fi

    docker network connect $1 ${COMPOSE_PROJECT_NAME}_nginx
    docker network connect $1 ${COMPOSE_PROJECT_NAME}_generator
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
    mkdir ./volumes/auth
    docker run --entrypoint htpasswd registry:2 -Bbn $1 $2 > ./volumes/auth/htpasswd
}

# RegistryUp
RegistryUp() {
    if [[ ! -f "./volumes/auth/htpasswd" ]]
    then
        printf "\e[31mPlease run the create-user command first.\e[0m\n"
        exit
    fi

    printf "Starting \e[1;33mregistry\e[0m ... "
    cd ${DIR} && \
        docker-compose -f ./compose/registry.yml up -d >> ${LOG_PATH} 2>&1 \
            && printf "\e[32mdone\e[0m\n" \
            || (printf "\e[31merror\e[0m\n" && exit 1)
}

# RegistryDown
RegistryDown() {
    IsUpAndRunning "${COMPOSE_PROJECT_NAME}_registry"
    if [[ $? -eq 0 ]]
    then
        printf "\e[31mRegistry are not up.\e[0m\n"
        exit 1
    fi

    printf "Stopping \e[1;33mregistry\e[0m ... "
    cd ${DIR} && \
        docker-compose -f ./compose/registry.yml down -v >> ${LOG_PATH} 2>&1 \
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
        IsUpAndRunning "${COMPOSE_PROJECT_NAME}_nginx"
        if [[ $? -eq 0 ]]
        then
            printf "\e[31mProxy is not up.\e[0m\n"
            exit 1
        fi

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

 - \e[0mup\e[2m\t\t Start the proxy.
 - \e[0mdown\e[2m\t\t Stop the proxy.
 - \e[0mconnect\e[2m name\t Connect the proxy to [name] network.
 - \e[0mdump\e[2m name\t Dump nginx config.
 - \e[0mcreate-user\e[2m user pwd\t Create the registry user.
 - \e[0mregistry\e[2m up|down\t Start or stop the registry.
"
    ;;
esac

printf "\n"
