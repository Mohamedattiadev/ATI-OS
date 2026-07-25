#!/bin/bash

# Make every regular file executable, skip directories + install.sh.
for f in *; do
    [[ -d "$f" ]] && continue
    [[ "$f" == "install.sh" ]] && continue
    chmod +x "$f"
done

# Copy every regular file to /usr/local/bin, skip directories + install.sh.
for f in *; do
    [[ -d "$f" ]] && continue
    [[ "$f" == "install.sh" ]] && continue
    sudo cp "$f" /usr/local/bin/
done

echo "All scripts are now executable and installed globally, except install.sh."
