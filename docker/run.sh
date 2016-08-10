#!/bin/sh -x

# Set password
echo "root:${PASSWORD}" | chpasswd

/opt/app/butterfly.server.py $@
