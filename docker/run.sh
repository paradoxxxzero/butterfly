#!/bin/sh

# Set password
echo "root:${PASSWORD}" | chpasswd

/opt/app/butterfly.server.py --unsecure --host=0.0.0.0