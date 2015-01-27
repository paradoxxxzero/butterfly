#!/bin/sh

# Set password
echo 'root:${PASSWORD}' | chpasswd

./butterfly.server.py --unsecure --host=0.0.0.0