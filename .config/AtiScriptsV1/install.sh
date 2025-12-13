#!/bin/bash

# Make all files in the current directory executable, except install.sh
for f in *; do
	if [ "$f" != "install.sh" ]; then
		chmod +x "$f"
	fi
done

# Copy all files to /usr/local/bin except install.sh
for f in *; do
	if [ "$f" != "install.sh" ]; then
		sudo cp "$f" /usr/local/bin/
	fi
done

echo "All scripts are now executable and installed globally, except install.sh."
