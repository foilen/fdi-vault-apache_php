#!/bin/bash
set -e

# Validate required environment variables
required_vars=("VAULT_HOSTNAME" "VAULT_NAMESPACE" "VAULT_VERSION" "VAULT_FILE")
missing_vars=()

for var in "${required_vars[@]}"; do
  if [ -z "${!var}" ]; then
    missing_vars+=("$var")
  fi
done

if [ ${#missing_vars[@]} -ne 0 ]; then
  echo "ERROR: The following required environment variables are not set:"
  for var in "${missing_vars[@]}"; do
    echo "  - $var"
  done
  echo "Please set these variables and try again."
  exit 1
fi

# Get the user and pass if provided
VAULT_USER_PASS=""
if [ -n "$VAULT_USER" ]; then
  echo User $VAULT_USER will be used
  VAULT_USER_PASS="$VAULT_USER:$VAULT_PASSWORD@"
fi

# Check if VAULT_VERSION is a tag
echo "Checking if $VAULT_VERSION is a tag"
TAG_URL="https://${VAULT_USER_PASS}${VAULT_HOSTNAME}/${VAULT_NAMESPACE}/tags/${VAULT_VERSION}"
HTTP_CODE=$(curl -s -o /tmp/response.txt -w "%{http_code}" "$TAG_URL")
if [ "$HTTP_CODE" == "404" ]; then
  echo "$VAULT_VERSION is not a tag, treating as a specific version"
  VAULT_RESOLVED_VERSION="$VAULT_VERSION"
else
  echo "$VAULT_VERSION is a tag"
  # Get the resolved version for the tag
  VAULT_RESOLVED_VERSION=$(cat /tmp/response.txt)
  echo "Resolved version for tag $VAULT_VERSION is $VAULT_RESOLVED_VERSION"
fi

# Check if we need to download the file
NEED_DOWNLOAD=true
if [ -f "/site/currentAppVersion.txt" ]; then
  CURRENT_VERSION=$(cat /site/currentAppVersion.txt)
  if [ "$CURRENT_VERSION" = "$VAULT_RESOLVED_VERSION" ]; then
    echo "Current version $CURRENT_VERSION matches resolved version $VAULT_RESOLVED_VERSION, no need to download"
    NEED_DOWNLOAD=false
  else
    echo "Current version $CURRENT_VERSION differs from resolved version $VAULT_RESOLVED_VERSION, will download"
  fi
fi

# Download the file if needed
if [ "$NEED_DOWNLOAD" = true ]; then
  echo "Downloading application from vault"
  DOWNLOAD_URL="https://${VAULT_USER_PASS}${VAULT_HOSTNAME}/${VAULT_NAMESPACE}/${VAULT_VERSION}/${VAULT_FILE}"
  echo "Download URL: $DOWNLOAD_URL"

  # Create app directory if it doesn't exist
  mkdir -p /site

  # Download the file to /tmp
  TEMP_FILE="/tmp/${VAULT_FILE}"
  if curl -s -f -o "$TEMP_FILE" "$DOWNLOAD_URL"; then
    echo "Download successful"
    
    # Remove existing www-next directory if it exists
    rm -rf /site/www-next
    mkdir -p /site/www-next
    
    # Detect file type and extract accordingly
    case "${VAULT_FILE,,}" in
      *.tar.gz|*.tgz)
        echo "Extracting tar.gz file"
        tar -xzf "$TEMP_FILE" -C /site/www-next
        ;;
      *.tar.bz2|*.tbz|*.tbz2)
        echo "Extracting tar.bz2 file"
        tar -xjf "$TEMP_FILE" -C /site/www-next
        ;;
      *.tar)
        echo "Extracting tar file"
        tar -xf "$TEMP_FILE" -C /site/www-next
        ;;
      *.zip)
        echo "Extracting zip file"
        unzip -q "$TEMP_FILE" -d /site/www-next
        # For zip files, check if everything is in a single directory and flatten if needed
        SUBDIR_COUNT=$(find /site/www-next -maxdepth 1 -type d | wc -l)
        if [ "$SUBDIR_COUNT" -eq 2 ]; then  # Only the parent and one subdirectory
          SUBDIR=$(find /site/www-next -maxdepth 1 -type d ! -path /site/www-next)
          if [ -n "$SUBDIR" ]; then
            mv "$SUBDIR"/* /site/www-next/
            rmdir "$SUBDIR"
          fi
        fi
        ;;
      *)
        echo "Unknown file type, copying as-is"
        cp "$TEMP_FILE" /site/www-next/
        ;;
    esac
    
    # Atomic replacement
    if [ -d /site/www ]; then
      mv /site/www /site/www-old
    fi
    mv /site/www-next /site/www
    rm -rf /site/www-old
    
    # Clean up temporary file
    rm -f "$TEMP_FILE"
    
    # Update the version file
    echo "$VAULT_RESOLVED_VERSION" > /site/currentAppVersion.txt
    echo "Updated currentAppVersion.txt to $VAULT_RESOLVED_VERSION"
  else
    echo "ERROR: Failed to download the application"
    exit 1
  fi
fi

# Change www-data user id and group id
if [ -n "$USER_ID" ]; then
  echo Change www-data user id to $USER_ID
  usermod -u $USER_ID www-data
fi

if [ -n "$USER_GID" ]; then
  echo Change www-data user gid to $USER_GID
  groupmod -g $USER_GID www-data
fi

# Configure emails
echo "EMAIL_DEFAULT_FROM_ADDRESS : $EMAIL_DEFAULT_FROM_ADDRESS"
if [ -n "$EMAIL_DEFAULT_FROM_ADDRESS" ]; then
  echo "Create sendmail-to-msmtp config"
  cat > /etc/sendmail-to-msmtp.json << _EOF
{
  "defaultFrom" : "$EMAIL_DEFAULT_FROM_ADDRESS"
}
_EOF
fi

echo "EMAIL_HOSTNAME : $EMAIL_HOSTNAME"
echo "EMAIL_PORT : $EMAIL_PORT"
echo "EMAIL_USER : $EMAIL_USER"
if [ -n "$EMAIL_PASSWORD" ]; then
  echo "EMAIL_PASSWORD : --IS SET--"
else
  echo "EMAIL_PASSWORD : --IS NOT SET--"
fi
echo "Create msmtprc"
cat > /etc/msmtprc << _EOF
account default
host $EMAIL_HOSTNAME
port $EMAIL_PORT
auth on
user $EMAIL_USER
password $EMAIL_PASSWORD
tls on
tls_certcheck off
_EOF


echo "Configure PHP"

if [ -z "$PHP_MAX_EXECUTION_TIME_SEC" ]; then
  PHP_MAX_EXECUTION_TIME_SEC=300
fi
echo "PHP_MAX_EXECUTION_TIME_SEC : $PHP_MAX_EXECUTION_TIME_SEC"

if [ -z "$PHP_MAX_UPLOAD_FILESIZE_MB" ]; then
  PHP_MAX_UPLOAD_FILESIZE_MB=64
fi
echo "PHP_MAX_UPLOAD_FILESIZE_MB : $PHP_MAX_UPLOAD_FILESIZE_MB"

if [ -z "$PHP_MAX_MEMORY_LIMIT_MB" ]; then
  PHP_MAX_MEMORY_LIMIT_MB=192
fi
echo "PHP_MAX_MEMORY_LIMIT_MB (must be at least 3 times PHP_MAX_UPLOAD_FILESIZE_MB) : $PHP_MAX_MEMORY_LIMIT_MB"

PHP_CONFIG_FILES="/usr/local/etc/php/conf.d/99-cloud.ini"
for PHP_CONFIG_FILE in $PHP_CONFIG_FILES; do
echo Save PHP config file $PHP_CONFIG_FILE
cat > $PHP_CONFIG_FILE << _EOF
[PHP]
max_execution_time = $PHP_MAX_EXECUTION_TIME_SEC

upload_max_filesize = ${PHP_MAX_UPLOAD_FILESIZE_MB}M
post_max_size = 0
max_file_uploads = 100

memory_limit = ${PHP_MAX_MEMORY_LIMIT_MB}M
_EOF
done

echo "Configure cron"
CRONNAMES=${!CRON_@}
for CRONNAME in $CRONNAMES; do
  eval CRONVALUE=\$$CRONNAME
  echo "$CRONVALUE" | tee -a /etc/cron.d/custom
done

echo "Cron Start"
service cron start

echo "Apache Start"
service apache2 start

if [ -n "$CERTBOT_EMAIL" ] && [ -n "$CERTBOT_DOMAINS" ]; then
  echo "Configure Let's Encrypt"

  certbot --non-interactive --agree-tos --email $CERTBOT_EMAIL --apache --domains $CERTBOT_DOMAINS --expand
fi

APP_ID=$(cat /var/run/apache2/apache2.pid)
if [ -z "$APP_ID" ]; then
  echo apache is not running
  exit 1
fi

echo apache is running with pid $APP_PID and is ready to serve
while [ -d /proc/$APP_PID ]; do
  sleep 5s
done
