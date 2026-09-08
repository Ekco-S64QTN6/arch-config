#!/bin/bash
cd ~/github/Kaiacord/ || { echo "Kaiacord directory not found"; exit 1; }
source venv/bin/activate
python Kaiacord.py
exec bash
