#!/bin/sh

# Set password
echo "root:${PASSWORD}" | chpasswd

if [ -z ${PORT} ]
then
  echo "Starting on default port: 57575"
  /usr/src/app/butterfly.server.py --unsecure --host=0.0.0.0
else
  echo "Starting on port: ${PORT}"
  /usr/src/app/butterfly.server.py --unsecure --host=0.0.0.0 --port=${PORT}
fi
