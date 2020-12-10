FROM php:7.4-apache
LABEL maintainer="opnmind <opnmind@mailbox.org>"

ENV GRAV_VERSION=latest

# Enable Apache Rewrite + Expires Module
RUN a2enmod rewrite expires && \
    sed -i 's/ServerTokens OS/ServerTokens ProductOnly/g' \
    /etc/apache2/conf-available/security.conf

# Install dependencies
RUN DEBIAN_FRONTEND=noninteractive apt-get update && apt-get install -y --no-install-recommends \
    unzip \
    libfreetype6-dev \
    libjpeg62-turbo-dev \
    libpng-dev \
    libyaml-dev \
    libzip4 \
    libzip-dev \
    zlib1g-dev \
    libicu-dev \
    libldap-2.4-2 \
    libldap2-dev \
    g++ \
    git \
    cron \
    wget \
    && docker-php-ext-install opcache \
    && docker-php-ext-configure intl \
    && docker-php-ext-install intl \
    && docker-php-ext-configure gd \ 
    --with-freetype=/usr/include/ \
    --with-jpeg=/usr/include/ \
    && docker-php-ext-install -j$(nproc) gd \
    && docker-php-ext-install zip \
    && docker-php-ext-install ldap \
    && rm -rf /var/lib/apt/lists/*

# set recommended PHP.ini settings
# see https://secure.php.net/manual/en/opcache.installation.php
RUN { \
    echo 'opcache.memory_consumption=128'; \
    echo 'opcache.interned_strings_buffer=8'; \
    echo 'opcache.max_accelerated_files=4000'; \
    echo 'opcache.revalidate_freq=2'; \
    echo 'opcache.fast_shutdown=1'; \
    echo 'opcache.enable_cli=1'; \
    echo 'upload_max_filesize=128M'; \
    echo 'post_max_size=128M'; \
    echo 'expose_php=off'; \
    } > /usr/local/etc/php/conf.d/php-recommended.ini

RUN printf '\n' | bash pecl -q install apcu 
RUN printf '\n' | bash pecl -q install yaml-2.0.4
RUN docker-php-ext-enable apcu yaml


# Set user to www-data
RUN chown www-data:www-data /var/www
USER www-data

WORKDIR /var/www

RUN curl -o grav-admin.zip -SL https://getgrav.org/download/core/grav-admin/${GRAV_VERSION} && \
    unzip grav-admin.zip && \
    mv -T /var/www/grav-admin /var/www/html && \
    rm -f grav-admin.zip

WORKDIR /var/www/html

RUN bin/gpm update -y
RUN bin/gpm install -y shortcode-ui
RUN bin/gpm install -y datatables
RUN bin/gpm install -y table-importer

# Create cron job for Grav maintenance scripts
RUN (crontab -l; echo "* * * * * cd /var/www/html;/usr/local/bin/php bin/grav scheduler 1>> /dev/null 2>&1") | crontab -

# Return to root user
USER root

# provide container inside image for data persistence
VOLUME ["/var/www/html"]

EXPOSE 80

HEALTHCHECK \
    --start-period=10s \
    --interval=5m \
    --timeout=3s \
    --retries=5 \
    CMD wget --no-verbose --tries=1 --spider http://localhost || exit 1

CMD ["sh", "-c", "cron && apache2-foreground"]
