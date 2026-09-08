#!/bin/bash

echo "Attempting to stop speech-dispatcher service..."
# The SOCKET is what is enabled; stopping only the service lets the socket
# re-activate it immediately, so the "stop" did not actually stop anything.
systemctl --user stop speech-dispatcher.socket speech-dispatcher.service

echo "Killing any lingering speech-dispatcher processes..."
# -x matches the process NAME. 'pkill -f' matched full command lines, so it
# could hit unrelated processes that merely mentioned the string.
pkill -x speech-dispatcher

echo "Starting speech-dispatcher service..."
systemctl --user start speech-dispatcher.socket

echo "Checking speech-dispatcher service status:"
systemctl --user status speech-dispatcher --no-pager # --no-pager prevents long output from requiring user interaction

echo "Speech Dispatcher restart process complete."
