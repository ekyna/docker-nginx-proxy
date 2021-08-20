ekyna/docker-nginx-proxy
===

#### Usage

1. Clone this repo: 

        git clone https://github.com/ekyna/docker-nginx-proxy.git proxy
        cd ./proxy

2. Copy _.env.dist_ to _.env_ and provide environment variables:

        REGISTRY_VERSION=2.7.1
        REGISTRY_SECRET=0123456789
        REGISTRY_HOST=registry.example.org  # FQDN (used by proxy/letsencrypt)
        REGISTRY_PORT=5000
        REGISTRY_EMAIL=registry@example.org # Email for letsencrypt

3. Launch the proxy: 

        ./manage.sh up

4. Configure your website: 
    
    _docker compose example_

        version: '3'

        services:
          example:
            image: your-web-server
            environment:
              VIRTUAL_HOST: www.example.com
              VIRTUAL_NETWORK: example-network
              VIRTUAL_PORT: 80
              LETSENCRYPT_HOST: www.example.com
              LETSENCRYPT_EMAIL: email@example.com

6. Run your website:

       cd ./example-website
       docker-compose up -d 
                  

#### Registry 

This repo embed a private secured (with letsencrypt) docker registry.

Create a user for authentication: 

    ./manage.sh create-user <user> <password>

Launch the proxy:
     
    ./manage.sh registry up

#### Resources:

* https://github.com/nginx-proxy/nginx-proxy
* https://github.com/nginx-proxy/acme-companion
* https://github.com/denji/nginx-tuning
