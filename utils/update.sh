#!/bin/bash

if git fetch origin; then
    echo "Successfully fetched changes from remote"
else
    echo "ERROR: Failed to fetch changes from remote"
    exit 1
fi

git reset --hard
git checkout main

# Pull the latest changes
echo "Pulling latest changes..."
if git pull; then
    echo "Successfully updated repository"
    echo "Updated from commit $LOCAL to $REMOTE"
else
    echo "ERROR: Failed to pull changes"
    exit 1
fi

chmod +x /etc/penny/utils/update.sh
chmod +x /etc/penny/utils/install.sh