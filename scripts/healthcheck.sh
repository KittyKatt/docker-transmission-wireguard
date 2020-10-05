#!/bin/bash

if [[ -z "$HEALTH_CHECK_HOST" ]]; then
    echo "[#] Health check host not set, defaulting to google.com."
    HEALTH_CHECK_HOST="google.com"
fi

ping -c 1 ${HEALTH_CHECK_HOST}
STATUS=$?
if [[ ${STATUS} -ne 0 ]]; then
    echo "[!] WireGuard connection is down. Attempting to reset..."
    wg-quick down wg0
    wg-quick up wg0
    sleep 20
fi

ping -c 1 ${HEALTH_CHECK_HOST}
STATUS=$?
if [[ ${STATUS} -ne 0 ]]; then
    echo "[!] WireGuard connectivity is still down, exiting..."
    exit 1
else
    echo "[#] WireGuard connectivity has been restored."
fi

TRANSMISSION=$(pgrep transmission | wc -l)

if [[ ${TRANSMISSION} -ne 1 ]]; then
    echo "[!] Transmission Daemon is not running. Starting..."
    /scripts/start-transmission.sh
    sleep 20
    TRANSMISSION2=$(pgrep transmission | wc -l)
    if [[ ${TRANSMISSION2} -ne 1 ]]; then
        echo "[!] Transmission is still not started, exiting..."
        exit 1
    else
        echo "[#] Transmission now running."
    fi
fi

# Transmission open port test.
TRANSMISSION_PORT=$(transmission-remote localhost:9091 -pt | awk '{gsub("Port is open: ", ""); print}')
if [[ "${TRANSMISSION_PORT}" == "No" ]]; then
    echo "[!] Transmission port is closed. Restarting Transmission...."
    /scripts/start-transmission.sh $(cat /pia-shared/port.dat)
    sleep 20
    TRANSMISSION_PORT2=$(transmission-remote localhost:9091 -pt | awk '{gsub("Port is open: ", ""); print}')
    if [[ "${TRANSMISSION_PORT}" == "No" ]]; then
        echo "[!] Transmission port is still closed, exiting..."
        exit 1
    else
        echo "[#] Transmission restarted and port is open."
    fi
fi

echo "[#] Transmission and WireGuard are functioning properly."
exit 0