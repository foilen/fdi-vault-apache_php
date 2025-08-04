# Description

An Apache PHP image that will download the application on Simple File Vault (https://github.com/foilen/simple_file_vault) and run it. 

You can point to a specific version or a tag. If it is a tag and the previous files of the same version are already downloaded (if you keep the same volume between runs), it will not download them again.

It also has a lot of PHP extensions installed and also a sendmail replacement that supports a lot of different ways of sending emails with PHP.

The sendmail replacement is https://github.com/foilen/sendmail-to-msmtp .

The PHP header to tell the application that it is protected by HTTPS is set when the load-balancer tells it that it is protected.

# Build and test

```
./create-local-release.sh

mkdir -p _test/site _test/logs

docker run -ti --rm \
    -v $PWD/_test/site/:/site \
    -v $PWD/_test/logs/:/mount/logs \
    -p 80:80 -p 443:443 \
    -e USER_ID=$(id -u) \
    -e USER_GID=$(id -g) \
    -e VAULT_HOSTNAME=deploy.foilen.com \
    -e VAULT_NAMESPACE=test-vault-php \
    -e VAULT_VERSION=latest \
    -e VAULT_FILE=test-vault-php.tgz \
    --name allsites \
    fdi-vault-apache_php:main-SNAPSHOT

curl http://localhost

```

# Available environment config and their defaults

- USER_ID
- USER_GID

- PHP_MAX_EXECUTION_TIME_SEC=300
- PHP_MAX_UPLOAD_FILESIZE_MB=64
- PHP_MAX_MEMORY_LIMIT_MB=192
    - must be at least 3 times PHP_MAX_UPLOAD_FILESIZE_MB

- EMAIL_DEFAULT_FROM_ADDRESS
- EMAIL_HOSTNAME
- EMAIL_PORT
- EMAIL_USER
- EMAIL_PASSWORD

- CERTBOT_EMAIL
- CERTBOT_DOMAINS

- VAULT_HOSTNAME
- VAULT_USER
- VAULT_PASSWORD
- VAULT_NAMESPACE
- VAULT_VERSION
- VAULT_FILE

## Cron

You can provide cron lines with environment starting with "CRON_". Eg:
- 'CRON_1=* * * * * www-data echo yay | tee /tmp/yay_cron.log'

# Usage

## Example with Let's Encrypt

```
# Create directories
mkdir -p \
  $HOME/letsencrypt \
  $HOME/logs \
  $HOME/site

docker rm -f allsites ; \
docker run -d --restart always \
    -v $HOME/site/:/site \
    -v $HOME/logs/:/mount/logs \
    -v $HOME/logs/:/var/log/letsencrypt \
    -v $HOME/letsencrypt/:/etc/letsencrypt \
    -p 80:80 -p 443:443 \
    -e USER_ID=$(id -u) \
    -e USER_GID=$(id -g) \
    -e CERTBOT_EMAIL=test@foilen.com \
    -e CERTBOT_DOMAINS=test-wp.foilen.com \
    -e VAULT_HOSTNAME=$VAULT_HOSTNAME \
    -e VAULT_USER=$VAULT_USER \
    -e VAULT_PASSWORD=$VAULT_PASSWORD \
    -e VAULT_NAMESPACE=xxxxxxxxx \
    -e VAULT_VERSION=xxxxxxxxx \
    -e VAULT_FILE=xxxxxxxxx.jar \
    --name allsites \
    foilen/fdi-vault-apache_php:8.4.10-1 && \
docker logs -f allsites
```
