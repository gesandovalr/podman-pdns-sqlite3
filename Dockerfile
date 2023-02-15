# syntax=docker/dockerfile-upstream:master-labs 

FROM almalinux:latest

ARG pdns_local_address
ARG pdns_local_port
ARG pdns_api_key
ARG pdns_default_soa_name
ENV FLASK_APP=powerdnsadmin/__init__.py

## Install Repos and prequisites for PowerDNS / NGINX
RUN dnf update -y \
  && dnf install epel-release -y \
  && dnf install 'dnf-command(config-manager)' -y \
  && dnf install http://rpms.remirepo.net/enterprise/remi-release-8.rpm -y \
  && dnf module reset php -y \
  && dnf module enable php:remi-8.2 -y \
  && dnf config-manager --set-enabled powertools -y \
  && dnf install telnet -y \
  && dnf install bind-utils -y \
  && dnf install net-tools -y \
  && dnf install sqlite -y \
  && dnf install git -y \
  && dnf install supervisor -y \
  && dnf install pdns-backend-sqlite -y \
  && dnf install nginx -y \
  && curl --silent --location https://rpm.nodesource.com/setup_18.x | bash - \
  && dnf install nodejs -y \
  && curl --silent --location https://dl.yarnpkg.com/rpm/yarn.repo | tee /etc/yum.repos.d/yarn.repo \
  && rpm --import https://dl.yarnpkg.com/rpm/pubkey.gpg \
  && dnf install yarn  -y \
  && dnf install php82 -y \
  && dnf install php-fpm -y \
  && dnf install python3-pip -y \ 
  && dnf install gcc -y \
  && dnf install python3-devel -y \
  && dnf install openldap-devel -y \
  && dnf install mysql-devel -y \
  && dnf install git -y \
  && dnf install libtool-ltdl-devel -y \
  && dnf install xmlsec1-devel -y \
  && curl -o /etc/yum.repos.d/powerdns-auth-master.repo https://repo.powerdns.com/repo-files/centos-auth-master.repo \
  && curl -o /etc/yum.repos.d/powerdns-rec-master.repo https://repo.powerdns.com/repo-files/centos-rec-master.repo

## Install base packages for PowerDNS and PowerDNS Recursor
RUN dnf install pdns -y \
  && dnf install pdns-recursor -y

## Setup configuration files.
RUN mkdir -p /var/lib/pdns
RUN touch /etc/pdns/pdns.conf
RUN touch /etc/pdns/sqlite.conf
RUN touch /etc/pdns/api.conf
COPY /nginx/www.conf /etc/php-fpm.d/www.conf
RUN mkdir -p /run/php-fpm/
RUN touch /run/php-fpm/www.sock
RUN chown nginx:nginx /run/php-fpm/www.sock
RUN chmod 660 /run/php-fpm/www.sock
RUN mkdir -p run/powerdns-admin/
RUN mkdir -p run/pdns-recursor/
RUN touch /run/powerdns-admin/pid
RUN chown -R pdns:pdns /run/powerdns-admin
RUN touch /etc/pdns/recursor.conf

## Service Creation PDNS-Admin
RUN echo -e "\
[Install]\n\
WantedBy=multi-user.target\n\
\n\
[Unit]\n\
Description=PowerDNS-Admin\n\
Requires=powerdns-admin.socket\n\
After=network.target\n\
\n\
[Service]\n\
PIDFile=/run/powerdns-admin/pid\n\
User=pdns\n\
Group=pdns\n\
WorkingDirectory=/var/www/html/pdnspowerdns-admin\n\
ExecStart=gunicorn --pid /run/powerdns-admin/pid --bind unix:/run/powerdns-admin/socket 'powerdnsadmin:create_app()'\n\
ExecReload=/bin/kill -s HUP $MAINPID\n\
ExecStop=/bin/kill -s TERM $MAINPID\n\
PrivateTmp=true\n\
\n\
[Install]\n\
WantedBy=multi-user.target" > /etc/systemd/system/pdnsadmin.service

## Socket File Creation for powerdns Admin
RUN echo -e "\
[Unit]\n\
Description=PowerDNS-Admin socket\n\
\n\
[Socket]\n\
ListenStream=/run/powerdns-admin/socket\n\
\n\
[Install]\n\
WantedBy=sockets.target" > /etc/systemd/system/pdnsadmin.socket

## Dump Configuration Files PowerDNS & define variables
RUN echo -e "\
launch=gsqlite3\n\
gsqlite3-database=/var/lib/pdns/pdns.sqlite3\n\
gsqlite3-dnssec=off\n\
api=yes\n\
api-key=${pdns_api_key}\n\
webserver=yes\n\
webserver-port=8081\n\
webserver-address=0.0.0.0\n\
webserver-allow-from=0.0.0.0/0\n\
local-address=${pdns_local_address}\n\
local-port=${pdns_local_port}\n\
webserver-address=0.0.0.0\n\
webserver-allow-from=0.0.0.0/0\n\
default-ttl=3600\n\
disable-axfr=yes\n\
log-dns-details=on\n\
loglevel=3\n\
master=yes\n\
allow-dnsupdate-from=${allow_dnsupdate_from}\n\
version-string=anonymous\n\
cache-ttl=10" > /etc/pdns/pdns.conf

## Dump Recursor Configuration
#RUN echo -e "\
#forward-zones-recurse=.=8.8.8.8 \n\
#local-address=127.0.0.1\n\
#local-port=5678" > /etc/pdns-recursor/recursor.conf

# Database Configuration Files & Permissions
RUN sqlite3 /var/lib/pdns/pdns.sqlite3 < /usr/share/doc/pdns-backend-sqlite/schema.sqlite3.sql
RUN chown -R pdns:pdns /var/lib/pdns
RUN chown 700 /var/lib/pdns/pdns.sqlite3

## PIP Upgrade 
RUN pip3 install --upgrade pip

## Install PDNS-admin 
RUN mkdir /data
WORKDIR /data
RUN pip3 install virtualenv 
RUN pip3 install wheel 
RUN git clone https://github.com/ngoduykhanh/PowerDNS-Admin.git
RUN mkdir -p /var/www/html/pdns/
RUN mv ./PowerDNS-Admin/* /var/www/html/pdns
WORKDIR /var/www/html/pdns/
RUN virtualenv -p python3 flask

#RUN pip3 install flask
RUN source ./flask/bin/activate
RUN pip3 install --upgrade pip
RUN pip3 install -r requirements.txt
RUN yarn install --pure-lockfile
RUN mv /var/www/html/pdns/node_modules /var/www/html/pdns/powerdnsadmin/static

## Configuring services through Supervisor
RUN echo -e "\
import os\n\
import urllib.parse\n\
basedir = os.path.abspath(os.path.dirname(__file__))\n\
\n\
### BASIC APP CONFIG\n\
SALT = '2b.12!yLUMTIfl21FKJQpTkRQXCu' \n\
SECRET_KEY = 'e951e5a1f4b94151b360f47edf596dd2'\n\
BIND_ADDRESS = '0.0.0.0'\n\
PORT = 9191\n\
HSTS_ENABLED = False\n\
FILESYSTEM_SESSIONS_ENABLED = False\n\
SESSION_COOKIE_SAMESITE = 'Lax'\n\
CSRF_COOKIE_HTTPONLY = True\n\
\n\
### DATABASE - SQLite\n\
SQLALCHEMY_DATABASE_URI = 'sqlite:///' + os.path.join(basedir, 'pdns.db')\n\
\n\
# SAML Authnetication\n\
SAML_ENABLED = False\n\
SAML_ASSERTION_ENCRYPTED = True" > /var/www/html/pdns/powerdnsadmin/default_config.py

## Run Flash Tasks
RUN flask assets build
RUN flask db upgrade
RUN flask db migrate -m "Init DB"

## Copy NGINX Configuration files
COPY ./nginx/nginx.conf /etc/nginx/nginx.conf
COPY ./nginx/powerdns-admin.conf /etc/nginx/conf.d/

## NGINX Permissions for webserver.
RUN chown -R nginx:nginx /var/www/html/pdns

## Create and start services.
RUN mkdir -p /var/log/supervisor
COPY supervisord.conf /etc/supervisord.conf
CMD ["/usr/bin/supervisord", "-c", "/etc/supervisord.conf"]