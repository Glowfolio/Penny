#!/bin/bash

if git fetch origin; then
    echo "Successfully fetched changes from remote"
else
    echo "ERROR: Failed to fetch changes from remote"
    exit 1
fi

# Check if there are updates available
LOCAL=$(git rev-parse HEAD)
REMOTE=$(git rev-parse "origin/$CURRENT_BRANCH")

if [ "$LOCAL" = "$REMOTE" ]; then
    echo "Repository is already up to date"
    return 0
fi

# Pull the latest changes
echo "Pulling latest changes..."
if git pull origin "$CURRENT_BRANCH"; then
    echo "Successfully updated repository"
    echo "Updated from commit $LOCAL to $REMOTE"
else
    echo "ERROR: Failed to pull changes"
    exit 1
fi