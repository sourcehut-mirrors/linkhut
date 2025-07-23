# Installing on Debian Based Distributions

## Installation

This guide will assume you are on Debian 12 (“bookworm”) or later. It also assumes that you have administrative rights, either as root or a user with sudo permissions.

## Required dependencies

* PostgreSQL >=11.0
* Elixir >=1.14.0 <1.17
* Erlang OTP >=23.0.0 (supported: <27)

### Prepare the system

* First update the system, if not already done:

```shell
sudo apt update
sudo apt full-upgrade
```

* Install some of the above mentioned programs:

```shell
sudo apt install git build-essential postgresql postgresql-contrib
```

### Install Elixir and Erlang

* Install Elixir and Erlang (you might need to use backports or [asdf](https://github.com/asdf-vm/asdf) on old systems):

```shell
sudo apt update
sudo apt install elixir erlang-dev erlang-nox
```

### Install linkhut

* Add a new system user for the linkhut service:

```shell
sudo useradd -r -s /bin/false -m -d /var/lib/linkhut -U linkhut
```

**Note**: To execute a single command as the linkhut system user, use `sudo -Hu linkhut command`. You can also switch to a shell by using `sudo -Hu linkhut $SHELL`. If you don’t have and want `sudo` on your system, you can use `su` as root user (UID 0) for a single command by using `su -l linkhut -s $SHELL -c 'command'` and `su -l linkhut -s $SHELL` for starting a shell.

* Git clone the linkhut repository and make the linkhut user the owner of the directory:

```shell
sudo mkdir -p /opt/linkhut
sudo chown -R linkhut:linkhut /opt/linkhut
sudo -Hu linkhut git clone https://git.sr.ht/~mlb/linkhut /opt/linkhut
```

* Change to the new directory:

```shell
cd /opt/linkhut
```

* Install the dependencies for linkhut and answer with `yes` if it asks you to install `Hex`:

```shell
sudo -Hu linkhut mix deps.get
```

* Generate the configuration:

```shell
cat << EOF > /var/lib/linkhut.env
SECRET_KEY_BASE="<secret_key>"
DATABASE_URL="ecto://<db_user>:<db_pass>@localhost/linkhut"
LINKHUT_HOST="<service_host>"
SMTP_HOST="<smtp_host>"
SMTP_PORT="<smtp_port>"
SMTP_USERNAME="<smtp_user>"
SMTP_PASSWORD="<smtp_pass>"
SMTP_DKIM_SELECTOR="<dkim_selector>"
SMTP_DKIM_DOMAIN="<dkim_domain>"
SMTP_DKIM_PRIVATE_KEY="<dkim_pkey>"
EMAIL_FROM_NAME="<email_from_name>"
EMAIL_FROM_ADDRESS="<email_from_mail>"
EOF
```

* Now run the database migration:

```shell
sudo -Hu linkhut MIX_ENV=prod mix ecto.setup
sudo -Hu linkhut MIX_ENV=prod mix ecto.migrate
```

* Now you can start linkhut already

```shell
sudo -Hu linkhut MIX_ENV=prod mix phx.server
```

### Finalize installation

If you want to open your newly installed instance to the world, you should run Apache or some other webserver/proxy in front of linkhut and you should consider to create a systemd service file for linkhut.

#### Apache

* Copy the example Apache configuration and activate it:

```shell
sudo cat << EOF > /etc/apache2/sites-available/linkhut.conf
# default Apache site config for linkhut
#
# needed modules: define headers proxy proxy_http ssl
#
# Simple installation instructions:
# 1. Install your TLS certificate, possibly using Let's Encrypt.
# 2. Replace 'example.tld' with your instance's domain wherever it appears.
# 3. This assumes a Debian style Apache config. Copy this file to
#    /etc/apache2/sites-available/ and then add a symlink to it in
#    /etc/apache2/sites-enabled/ by running 'a2ensite linkhut-apache.conf', then restart Apache.

Define sitename example.com

<VirtualHost *:80 [::]:80>
    ServerName ${sitename}
    Redirect permanent / https://${sitename}/
</VirtualHost>
<VirtualHost *:443 [::]:443>
    ServerName ${sitename}

    AllowEncodedSlashes NoDecode

    RewriteEngine on

    RewriteCond %{HTTP:Connection} Upgrade [NC]
    RewriteCond %{HTTP:Upgrade} websocket [NC]
    RewriteRule /(.*) ws://[::1]:4000/$1 [P,L]

    SSLEngine on
    SSLCertificateFile      /etc/letsencrypt/live/${sitename}/cert.pem
    SSLCertificateKeyFile   /etc/letsencrypt/live/${sitename}/privkey.pem
    SSLCertificateChainFile /etc/letsencrypt/live/${sitename}/fullchain.pem

    ProxyRequests off
    ProxyTimeout 300
    ProxyPass / http://[::1]:4000/
    ProxyPassReverse / http://[::1]:4000/

    ProxyPass "/live/" "wss://[::1]:4000/"

    RequestHeader set Host ${sitename}
    ProxyPreserveHost On
</VirtualHost>
EOF
```

```shell
sudo ln -s /etc/apache2/sites-available/linkhut.conf /etc/apache2/sites-enabled/linkhut.conf
```

* Before starting apache edit the configuration and change it to your needs (e.g. change servername, change cert paths)

#### Systemd service

* Copy example service file

```shell
sudo cat << EOF > /etc/systemd/system/linkhut.service
[Unit]
Description=linkhut social network
After=network.target postgresql.service

[Service]
ExecReload=/bin/kill $MAINPID
KillMode=process
Restart=on-failure

# Name of the user that runs the linkhut service.
User=linkhut
# Declares that linkhut runs in production mode.
Environment="MIX_ENV=prod"

# Make sure that all paths fit your installation.
# Path to the home directory of the user running the linkhut service.
Environment="HOME=/var/lib/linkhut"
# Path to the environment variables.
EnvironmentFile=/var/lib/linkhut/linkhut.env
# Path to the folder containing the linkhut installation.
WorkingDirectory=/opt/linkhut
# Path to the Mix binary.
ExecStart=/usr/bin/mix phx.server

# Some security directives.
# Use private /tmp and /var/tmp folders inside a new file system namespace, which are discarded after the process stops.
PrivateTmp=true
# The /home, /root, and /run/user folders can not be accessed by this service anymore. If your linkhut user has its home folder in one of the restricted places, or use one of these folders as its working directory, you have to set this to false.
ProtectHome=true
# Mount /usr, /boot, and /etc as read-only for processes invoked by this service.
ProtectSystem=full
# Sets up a new /dev mount for the process and only adds API pseudo devices like /dev/null, /dev/zero or /dev/random but not physical devices. Disabled by default because it may not work on devices like the Raspberry Pi.
PrivateDevices=false
# Drops the sysadmin capability from the daemon.
CapabilityBoundingSet=~CAP_SYS_ADMIN

[Install]
WantedBy=multi-user.target
EOF
```

* Enable and start `linkhut.service`:

```shell
sudo systemctl enable --now linkhut.service
```

