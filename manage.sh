#!/bin/bash

if [[ ! -f "./.env" ]]
then
    printf "\e[31mPlease create the .env file based on .env.dist\e[0m\n"
    exit
fi

DIR="$( cd "$( dirname "${BASH_SOURCE[0]}" )" && pwd )"
LOG_PATH="$DIR/docker_logs.txt"
echo "" > ${LOG_PATH}

source ./.env

if [[ "" == "${REGISTRY_SECRET}" ]]; then printf "\e[31mREGISTRY_SECRET env variable is not set.\e[0m\n"; exit; fi
if [[ "" == "${REGISTRY_PORT}" ]]; then printf "\e[31mREGISTRY_PORT env variable is not set.\e[0m\n"; exit; fi
if [[ "" == "${REGISTRY_HOST}" ]]; then printf "\e[31mREGISTRY_HOST env variable is not set.\e[0m\n"; exit; fi
if [[ "" == "${REGISTRY_EMAIL}" ]]; then printf "\e[31mREGISTRY_EMAIL env variable is not set.\e[0m\n"; exit; fi

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

    printf "Starting \e[1;33mproxy\e[0m ... "
    cd ${DIR} && \
        docker-compose -p proxy -f ./compose/proxy.yml up -d >> ${LOG_PATH} 2>&1 \
            && printf "\e[32mdone\e[0m\n" \
            || (printf "\e[31merror\e[0m\n" && exit 1)
}

ProxyDown() {
    printf "Stopping \e[1;33mproxy\e[0m ... "
    cd ${DIR} && \
        docker-compose -p proxy -f ./compose/proxy.yml -f ./compose/registry.yml down -v --remove-orphans >> ${LOG_PATH} 2>&1 \
            && printf "\e[32mdone\e[0m\n" \
            || (printf "\e[31merror\e[0m\n" && exit 1)
}

Execute() {
    if ! IsUpAndRunning "proxy_nginx"
    then
        printf "\e[31mNot up and running.\e[0m\n"
        exit 1
    fi

    printf "Executing $1\n"
    printf "\n"
    docker exec -it proxy_nginx $1
    printf "\n"
}

Connect() {
    if NetworkExists $1
    then
        docker network connect $1 proxy_nginx
        docker network connect $1 proxy_generator
    else
        printf "\e[31mNetwork '$1' does not exist.\e[0m\n"
        exit
    fi
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
    cd ${DIR} && \
        docker run -d --rm --entrypoint htpasswd registry:2 -Bbn $1 $2 > ./volumes/auth/htpasswd
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
        docker-compose -p registry -f ./compose/registry.yml up -d >> ${LOG_PATH} 2>&1 \
            && printf "\e[32mdone\e[0m\n" \
            || (printf "\e[31merror\e[0m\n" && exit 1)
}

# RegistryDown
RegistryDown() {
    if ! IsUpAndRunning "registry_registry"
    then
        printf "\e[31mRegistry are not up.\e[0m\n"
        exit 1
    fi

    printf "Stopping \e[1;33mregistry\e[0m ... "
    cd ${DIR} && \
        docker-compose -p registry -f ./compose/registry.yml down -v >> ${LOG_PATH} 2>&1 \
            && printf "\e[32mdone\e[0m\n" \
            || (printf "\e[31merror\e[0m\n" && exit 1)
}

# ----------------------------- INIT -----------------------------

if ! NetworkExists proxy-network
then
    NetworkCreate proxy-network
fi
if ! NetworkExists registry-network
then
    NetworkCreate registry-network
fi

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
        if ! IsUpAndRunning "proxy_nginx"
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
