#!/bin/bash

if git fetch origin; then
    echo "Successfully fetched changes from remote"
else
    echo "ERROR: Failed to fetch changes from remote"
    exit 1
fi