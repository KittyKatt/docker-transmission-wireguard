#!/bin/bash

# Source our persisted env variables from container startup
. /etc/transmission/environment-variables.sh

# Wait for wireguard port to initialize
echo "[#] Waiting for wg0 to initialize and grab port forward"
sleep 5s

WG_IP="$(ip addr show wg0 | awk '/inet/ {gsub(/\/32/, \"\"); print $2}')"
PEER_PORT="${1}"

echo "Updating TRANSMISSION_BIND_ADDRESS_IPV4 to the ip of wg0 : ${WG_IP}"
export TRANSMISSION_BIND_ADDRESS_IPV4=${WG_IP}

echo "Updating TRANSMISSION_PEER_PORT to the given port : ${PEER_PORT}"
export TRANSMISSION_PEER_PORT=${PEER_PORT}

# Update Transmission UI if needed
if [[ "combustion" = "$TRANSMISSION_WEB_UI" ]]; then
  echo "Using Combustion UI, overriding TRANSMISSION_WEB_HOME"
  export TRANSMISSION_WEB_HOME=/opt/transmission-ui/combustion-release
fi
if [[ "kettu" = "$TRANSMISSION_WEB_UI" ]]; then
  echo "Using Kettu UI, overriding TRANSMISSION_WEB_HOME"
  export TRANSMISSION_WEB_HOME=/opt/transmission-ui/kettu
fi
if [[ "transmission-web-control" = "$TRANSMISSION_WEB_UI" ]]; then
  echo "Using Transmission Web Control  UI, overriding TRANSMISSION_WEB_HOME"
  export TRANSMISSION_WEB_HOME=/opt/transmission-ui/transmission-web-control
fi

echo "Generating transmission settings.json from env variables"
# Ensure TRANSMISSION_HOME is created
mkdir -p ${TRANSMISSION_HOME}
dockerize -template /etc/transmission/settings.tmpl:${TRANSMISSION_HOME}/settings.json

echo "sed'ing True to true"
sed -i 's/True/true/g' ${TRANSMISSION_HOME}/settings.json

if [[ ! -e "/dev/random" ]]; then
  # Avoid "Fatal: no entropy gathering module detected" error
  echo "INFO: /dev/random not found - symlink to /dev/urandom"
  ln -s /dev/urandom /dev/random
fi

# Setting up Transmission user
. /etc/transmission/userSetup.sh

# Setting logfile to local file
LOGFILE=${TRANSMISSION_HOME}/transmission.log

echo "STARTING TRANSMISSION"
exec su --preserve-environment ${RUN_AS} -s /bin/bash -c "/usr/bin/transmission-daemon -g ${TRANSMISSION_HOME} --logfile $LOGFILE" &

echo "Transmission startup script complete."