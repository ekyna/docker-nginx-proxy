ekyna/docker-nginx-proxy
===

#### Usage

1. Clone this repo: 

        git clone https://github.com/ekyna/docker-nginx-proxy.git
        cd ./docker-nginx-proxy

2. Configure syslog and log rotate:
    
        sudo cp ./etc/rsyslog.d/10-docker-container.conf /etc/rsyslog.d/10-docker-container.conf
        sudo cp ./etc/rsyslog.d/11-docker-daemon.conf /etc/rsyslog.d/11-docker-daemon.conf
        sudo cp ./etc/logrotate.d/docker /etc/logrotate.d/docker
        sudo service rsyslog restart

3. Launch the proxy: 

        ./manage.sh up

4. Configure your website: 
    
    _example with docker composer v2_

        version: '3'
        networks:
          default:
            external:
              name: example-network
        services:
          example:
            image: nginx
            environment:
              VIRTUAL_HOST: www.example.com
              VIRTUAL_NETWORK: example-network
              VIRTUAL_PORT: 80
              LETSENCRYPT_HOST: www.example.com
              LETSENCRYPT_EMAIL: email@example.com

5. Add your network to the proxy generator service:

        ./manage.sh connect example-network

6. Run your website:

       cd ./example-website
       docker-compose up -d 
                  

#### Registry 

    TODO

#### Fail2ban

    TODO

#### Resources:

https://github.com/jwilder/nginx-proxy
https://github.com/JrCs/docker-letsencrypt-nginx-proxy-companion
https://github.com/gilyes/docker-nginx-letsencrypt-sample

https://gist.github.com/denji/8359866
