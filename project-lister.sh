#!/bin/bash

# Check dependencies
if ! command -v jq &> /dev/null; then
    echo "jq is not installed. Please install it to run this script."
    exit 1
fi

if ! command -v curl &> /dev/null; then
    echo "curl is not installed. Please install it to run this script."
    exit 1
fi

# Show usage if --help is used
if [ "$1" = "--help" ]; then
    echo "Usage: $0 GROUP_ID"
    echo "Lists all projects (including those in subgroups) in a GitLab group."
    echo "Example: $0 123"
    echo
    echo "Required environment variables:"
    echo "  GITLAB_TOKEN                # Your GitLab access token"
    echo "  GITLAB_URL                  # GitLab instance URL (e.g., https://gitlab.example.com)"
    exit 0
fi

# Configuration
GITLAB_URL="${GITLAB_URL}"
GITLAB_TOKEN="${GITLAB_TOKEN}"

# Verify arguments
if [ "$#" -ne 1 ]; then
    echo "Usage: $0 GROUP_ID"
    echo "Example: $0 123"
    echo "Use --help for more information"
    exit 1
fi

GROUP_ID="$1"

# Validate required environment variables
if [ -z "$GITLAB_URL" ]; then
    echo "GitLab URL is not defined. Set the GITLAB_URL environment variable."
    echo "Example: GITLAB_URL=https://gitlab.example.com"
    echo "Use --help for more information."
    exit 1
fi

if [ -z "$GITLAB_TOKEN" ]; then
    echo "GitLab token is not defined. Set the GITLAB_TOKEN environment variable."
    echo "Use --help for more information."
    exit 1
fi

GITLAB_URL="${GITLAB_URL%/}"  # Remove trailing slash if it exists

# Function to log with timestamp
log_info() {
    echo "[$(date '+%Y-%m-%d %H:%M:%S')] $1"
}

# Log GitLab instance
log_info "Using GitLab instance: $GITLAB_URL"
log_info "Getting projects for group ID: $GROUP_ID"

# Function to get projects
get_projects() {
    local page=1
    local all_projects="[]"

    while true; do
        log_info "Fetching page $page..."
        local response
        response=$(curl -s --header "PRIVATE-TOKEN: $GITLAB_TOKEN" \
            "$GITLAB_URL/api/v4/groups/$GROUP_ID/projects?include_subgroups=true&page=$page&per_page=100")

        # Check if response is empty or invalid
        if [ -z "$response" ] || [ "$response" = "[]" ] || [ "$(echo "$response" | jq length)" -eq 0 ]; then
            break
        fi

        # Check for error message in response
        if [ "$(echo "$response" | jq 'type')" = "\"object\"" ] && [ "$(echo "$response" | jq 'has("message")')" = "true" ]; then
            error_message=$(echo "$response" | jq -r '.message')
            echo "Error: $error_message"
            echo "Check your configuration and use --help for more information"
            exit 1
        fi

        all_projects=$(echo "$all_projects $response" | jq -s 'add')
        ((page++))
    done

    # Sort and extract clone URLs
    echo "$all_projects" | jq -r 'sort_by(.path_with_namespace) | .[].http_url_to_repo'
}

# Main program
main() {
    local projects
    projects=$(get_projects)

    if [ $? -eq 0 ] && [ ! -z "$projects" ]; then
        echo "$projects"
    else
        log_info "No projects found or an error occurred"
        exit 1
    fi
}

# Error handling
set -e
trap 'echo "An error occurred on line $LINENO. Exit code: $?" >&2' ERR

# Start the script
main
