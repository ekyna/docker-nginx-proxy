ekyna/docker-nginx-proxy
===

#### Usage

1. Clone and run this stack: 

        git clone https://github.com/ekyna/docker-nginx-proxy.git
        cd ./docker-nginx-proxy
        ./manage.sh up

2. Configure your website: 
    
    _example with docker composer v2_

        version: '2'
        networks:
            default:
                external:
                    name: example-network
        services:
          example:
            image: nginx
            environment:
              - VIRTUAL_HOST=www.example.com
              - VIRTUAL_NETWORK=example-network
              - VIRTUAL_PORT=80
              - LETSENCRYPT_HOST=www.example.com
              - LETSENCRYPT_EMAIL=email@example.com

3. Add your network to generator services:

        ./manage.sh connect example-network

4. Run your website:

       cd ./example-website
       docker-compose up -d 

#### Resources:

https://github.com/jwilder/nginx-proxy
https://github.com/JrCs/docker-letsencrypt-nginx-proxy-companion
https://github.com/gilyes/docker-nginx-letsencrypt-sample
