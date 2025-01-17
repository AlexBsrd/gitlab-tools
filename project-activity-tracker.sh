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

if ! command -v date &> /dev/null; then
    echo "date is not installed. Please install it to run this script."
    exit 1
fi

# Show usage if --help is used
if [ "$1" = "--help" ]; then
    echo "Usage: $0 [OPTIONS]"
    echo "Analyzes project activity based on merge requests over a specified time period."
    echo
    echo "Required environment variables:"
    echo "  GITLAB_TOKEN                # Your GitLab access token"
    echo "  GROUP_ID                    # ID of the GitLab group to analyze"
    echo "  GITLAB_URL                  # GitLab instance URL (e.g., https://gitlab.example.com)"
    echo
    echo "Optional environment variables:"
    echo "  MONTHS                      # Number of months to analyze (default: 3)"
    echo "  EXCLUDE_BOTS                # Space-separated list of bot usernames to exclude"
    exit 0
fi

# Configuration
GITLAB_URL="${GITLAB_URL}"
GITLAB_TOKEN="${GITLAB_TOKEN}"
GROUP_ID="${GROUP_ID}"
MONTHS="${MONTHS:-3}"
EXCLUDE_BOTS="${EXCLUDE_BOTS:-}"  # No default bots - let users specify their own

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

if [ -z "$GROUP_ID" ]; then
    echo "Group ID is not defined. Set the GROUP_ID environment variable."
    echo "Use --help for more information."
    exit 1
fi

GITLAB_URL="${GITLAB_URL%/}"  # Remove trailing slash if it exists

# Calculate date for the time period in ISO 8601 format
PERIOD_START=$(date -d "$MONTHS months ago" -u +"%Y-%m-%dT%H:%M:%SZ")

# Function to log with timestamp
log_info() {
    echo "[$(date '+%Y-%m-%d %H:%M:%S')] $1"
}

# Log GitLab instance
log_info "Using GitLab instance: $GITLAB_URL"

# Function to get all merge requests for the specified period
get_merge_requests() {
    local page=1
    local all_mrs="[]"

    while true; do
        local response
        response=$(curl -s --header "PRIVATE-TOKEN: $GITLAB_TOKEN" \
            "$GITLAB_URL/api/v4/groups/$GROUP_ID/merge_requests?state=merged&per_page=100&page=$page&updated_after=$PERIOD_START")

        # Check if response is empty or invalid
        if [ -z "$response" ] || [ "$(echo "$response" | jq length)" -eq 0 ]; then
            break
        fi

        # Filter out bot MRs if EXCLUDE_BOTS is set
        if [ -n "$EXCLUDE_BOTS" ]; then
            local bots_array=$(echo "$EXCLUDE_BOTS" | jq -R 'split(" ")')
            local exclude_filter="[.[] | select(.author.username as \$author | ($bots_array | index(\$author) | not))]"
            filtered_response=$(echo "$response" | jq --argjson bots "$bots_array" "$exclude_filter")
        else
            filtered_response="$response"
        fi
        all_mrs=$(echo "$all_mrs $filtered_response" | jq -s 'add')
        ((page++))
    done

    echo "$all_mrs"
}

# Function to get project name from its ID
get_project_name() {
    local project_id="$1"

    local project_info
    project_info=$(curl -s --header "PRIVATE-TOKEN: $GITLAB_TOKEN" \
        "$GITLAB_URL/api/v4/projects/$project_id")

    if [ $? -ne 0 ]; then
        echo "Error fetching project info"
        return 1
    fi

    echo "$project_info" | jq -r '.name'
}

# Print a nicely formatted count with padding
print_count() {
    local project_name="$1"
    local count="$2"
    printf "%-40s : %3d MRs\n" "$project_name" "$count"
}

# Main program
main() {
    log_info "Analyzing merge requests from the last $MONTHS months..."
    merge_requests=$(get_merge_requests)
    if [ $? -ne 0 ]; then
        echo "Error fetching merge requests. Check your configuration."
        echo "Use --help for more information."
        exit 1
    fi

    total_mrs=$(echo "$merge_requests" | jq length)
    log_info "Found $total_mrs merge requests to analyze..."

    # Group MRs by project and count them
    log_info "Counting MRs by project..."
    project_counts=$(echo "$merge_requests" | jq -r '
        group_by(.project_id) |
        map({
            project_id: .[0].project_id,
            count: length
        }) |
        sort_by(-.count)'
    )

    # Display results
    echo -e "\nProject Rankings by Merge Request Count"
    echo "====================================="
    echo

    # If no MRs found
    if [ "$total_mrs" -eq 0 ]; then
        echo "No merge requests found in the specified time period."
        exit 0
    fi

    echo "$project_counts" | jq -c '.[]' | while read -r entry; do
        project_id=$(echo "$entry" | jq -r '.project_id')
        count=$(echo "$entry" | jq -r '.count')
        project_name=$(get_project_name "$project_id")

        if [ $? -eq 0 ]; then
            print_count "$project_name" "$count"
        else
            log_info "Skipping project ID $project_id due to error"
            continue
        fi
    done

    # Display summary
    echo -e "\nSummary:"
    echo "- Time period: Last $MONTHS months (since $(date -d "$PERIOD_START" '+%Y-%m-%d'))"
    echo "- Total merge requests: $total_mrs"
    echo "- Projects with activity: $(echo "$project_counts" | jq length)"
}

# Error handling
set -e
trap 'echo "An error occurred on line $LINENO. Exit code: $?" >&2' ERR

# Start the script
main
