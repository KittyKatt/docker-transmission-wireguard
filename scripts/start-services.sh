#!/bin/bash

# Takes a single argument:
#   $1 == Forwarded port of wireguard w/ PIA

WG_IP=$(ip addr show wg0 | awk '/inet/ {gsub(/\/32/, ""); print $2}')
PEER_PORT="${1}"

# Persist transmission settings for use by transmission-daemon
echo "[#] Creating environment-variables.sh from template file."
dockerize -template /opt/transmission/environment-variables.tmpl:/etc/transmission/environment-variables.sh

# Source our persisted env variables from container startup
. /etc/transmission/environment-variables.sh

##############################
#### Transmission Startup ####
##############################

echo "[$(date)]  Initializing Transmission Daemon."

# Wait for wireguard port to initialize
echo "[#] Waiting for wg0 to initialize and grab port forward"
sleep 5s

echo "[#] Updating TRANSMISSION_BIND_ADDRESS_IPV4 to the ip of wg0 : ${WG_IP}"
export TRANSMISSION_BIND_ADDRESS_IPV4=${WG_IP}

echo "[#] Updating TRANSMISSION_PEER_PORT to the given port : ${PEER_PORT}"
export TRANSMISSION_PEER_PORT=${PEER_PORT}

# Update Transmission UI if needed
case $TRANSMISSION_UI in
    "combustion")
        echo "[#] Using Combustion UI, overriding TRANSMISSION_WEB_HOME"
        export TRANSMISSION_WEB_HOME=/opt/transmission-ui/combustion-release
        ;;
    "kettu")
        echo "[#] Using Kettu UI, overriding TRANSMISSION_WEB_HOME"
        export TRANSMISSION_WEB_HOME=/opt/transmission-ui/kettu
        ;;
    "transmission-web-control")
        echo "[#] Using Transmission Web Control  UI, overriding TRANSMISSION_WEB_HOME"
        export TRANSMISSION_WEB_HOME=/opt/transmission-ui/transmission-web-control
        ;;
esac

# Setting logfile to local file and set log level if specified
if [[ ! -n "${TRANSMISSION_LOG_LEVEL}" ]]; then
    case ${TRANSMISSION_LOG_LEVEL} in
        "none")
            echo "[#] Setting Transmission log level to none (0)."
            export TRANSMISSION_MESSAGE_LEVEL=0
            ;;
        "error")
            echo "[#] Setting Transmission log level to error (1)."
            export TRANSMISSION_MESSAGE_LEVEL=1
            ;;
        "info")
            echo "[#] Setting Transmission log level to info (2)."
            export TRANSMISSION_MESSAGE_LEVEL=2
            ;;
        "debug")
            echo "[#] Setting Transmission log level to debug (3)."
            export TRANSMISSION_MESSAGE_LEVEL=3
            ;;
    esac
fi
LOGFILE=${TRANSMISSION_HOME}/transmission.log

echo "[#] Generating transmission settings.json from env variables"
# Ensure TRANSMISSION_HOME is created
mkdir -p ${TRANSMISSION_HOME}
echo "[#] Creating Transmission settings.json from template file."
dockerize -template /opt/transmission/settings.tmpl:${TRANSMISSION_HOME}/settings.json

echo "[#] sed'ing True to true"
sed -i 's/True/true/g' ${TRANSMISSION_HOME}/settings.json

if [[ ! -e "/dev/random" ]]; then
    # Avoid "Fatal: no entropy gathering module detected" error
    echo "[#] INFO: /dev/random not found - symlink to /dev/urandom"
    ln -s /dev/urandom /dev/random
fi

# Setting up Transmission user
. /opt/transmission/userSetup.sh

echo "[#] STARTING TRANSMISSION"
exec su --preserve-environment ${RUN_AS} -s /bin/bash -c "/usr/bin/transmission-daemon -g ${TRANSMISSION_HOME} --logfile $LOGFILE" &

echo "[#] Transmission startup script complete."

#############################
##### TinyProxy Startup #####
#############################
find_proxy_conf() {
    if [[ -f /etc/tinyproxy.conf ]]; then
        PROXY_CONF='/etc/tinyproxy.conf'
    elif [[ -f /etc/tinyproxy/tinyproxy.conf ]]; then
        PROXY_CONF='/etc/tinyproxy/tinyproxy.conf'
    else
        echo "[!] ERROR: Could not find tinyproxy config file. Exiting..."
        exit 1
    fi
}
set_proxy_port() {
    expr ${1} + 0 1>/dev/null 2>&1
    status=$?
    if test ${status} -gt 1
    then
        echo "[!] Port [${1}]: Not a number." >&2; exit 1
    fi

    # Port: Specify the port which tinyproxy will listen on.    Please note
    # that should you choose to run on a port lower than 1024 you will need
    # to start tinyproxy using root.

    if test ${1} -lt 1024
    then
        echo "[!] tinyproxy: ${1} is lower than 1024. Ports below 1024 are not permitted.";
        exit 1
    fi

    echo "[#] Setting tinyproxy port to ${1}.";
    sed -i -e"s,^Port .*,Port ${1}," ${2}
}

set_proxy_authentication() {
    echo "[#] Setting tinyproxy basic auth.";
    echo "BasicAuth ${1} ${2}" >> ${3}
}

set_proxy_bind_ip() {
    echo "[#] Set proxy bind IP to ${WG_IP}."
    sed -i -e "s,^#Bind .*,Bind ${1}," ${2}
}

if [[ "${WEBPROXY_ENABLED}" = "true" ]]; then
    echo "[$(date)]  Initializing Tinyproxy."

    find_proxy_conf
    echo "[#] Found config file $PROXY_CONF, updating settings."

    if [[ ! -z "${WEBPROXY_PORT}" ]]; then
        set_proxy_port ${WEBPROXY_PORT} ${PROXY_CONF}
    fi
    
    set_proxy_bind_ip ${WG_IP} ${PROXY_CONF}

    if [[ ! -z "${WEBPROXY_USERNAME}" ]] && [[ ! -z "${WEBPROXY_PASSWORD}" ]]; then
        set_proxy_authentication ${WEBPROXY_USERNAME} ${WEBPROXY_PASSWORD} ${PROXY_CONF}
    fi

    # Allow all clients
    sed -i -e"s/^Allow /#Allow /" ${PROXY_CONF}

    # Disable Via Header for privacy (leaks that you're using a proxy)
    sed -i -e "s/#DisableViaHeader/DisableViaHeader/" ${PROXY_CONF}

    # Lower log level for privacy (writes dns names by default)
    sed -i -e "s/LogLevel Info/LogLevel Critical/" ${PROXY_CONF}

    tinyproxy -d -c ${PROXY_CONF}
    echo "[#] Tinyproxy startup script complete."
fi