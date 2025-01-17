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
    echo "Analyzes merge request approvals statistics over a specified time period."
    echo
    echo "Required environment variables:"
    echo "  GITLAB_TOKEN                # Your GitLab access token"
    echo "  GROUP_ID                    # ID of the GitLab group to analyze"
    echo "  GITLAB_URL                  # GitLab instance URL (e.g., https://gitlab.example.com)"
    echo
    echo "Optional environment variables:"
    echo "  MONTHS                      # Number of months to analyze (default: 3)"
    echo "  EXCLUDE_BOTS                # Space-separated list of bot usernames to exclude"
    echo "                              # (default: 'gitlab-bot')"
    exit 0
fi

# Configuration
GITLAB_URL="${GITLAB_URL}"
GITLAB_TOKEN="${GITLAB_TOKEN}"
GROUP_ID="${GROUP_ID}"
MONTHS="${MONTHS:-3}"
EXCLUDE_BOTS="${EXCLUDE_BOTS:-gitlab-bot}"

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

# Function to log with timestamp
log_info() {
    echo "[$(date '+%Y-%m-%d %H:%M:%S')] $1"
}

# Log GitLab instance
log_info "Using GitLab instance: $GITLAB_URL"

# Calculate date limit
DATE_LIMIT=$(date -d "-${MONTHS} months" -u +"%Y-%m-%dT%H:%M:%SZ")
log_info "Starting merge request analysis from ${DATE_LIMIT}"

# Initialize variables
page=1
total_mrs=0
declare -A approvers_count

# Main loop to fetch and analyze merge requests
while true; do
    log_info "Analyzing page ${page}..."

    # Fetch merge requests
    mrs_response=$(curl -s --header "PRIVATE-TOKEN: $GITLAB_TOKEN" \
        "${GITLAB_URL}/api/v4/groups/${GROUP_ID}/merge_requests?state=merged&updated_after=${DATE_LIMIT}&per_page=100&page=${page}")

    # Check if response is empty
    if [ "$(echo "$mrs_response" | jq '. | length')" = "0" ]; then
        break
    fi

    # Process merge requests
    while read -r mr; do
        author=$(echo "$mr" | jq -r '.author.username')

        # Skip if author is a bot
        if echo "$EXCLUDE_BOTS" | grep -qw "$author"; then
            continue
        fi

        ((total_mrs++))
        title=$(echo "$mr" | jq -r '.title' | cut -c1-50)
        log_info "Analyzing MR #${total_mrs} - ${title}..."

        # Get approvals
        project_id=$(echo "$mr" | jq -r '.project_id')
        mr_iid=$(echo "$mr" | jq -r '.iid')
        approvals_response=$(curl -s --header "PRIVATE-TOKEN: $GITLAB_TOKEN" \
            "${GITLAB_URL}/api/v4/projects/${project_id}/merge_requests/${mr_iid}/approvals")

        # Count approvals
        while read -r username; do
            if [ ! -z "$username" ] && [ "$username" != "null" ]; then
                ((approvers_count[$username]=${approvers_count[$username]:-0}+1))
            fi
        done < <(echo "$approvals_response" | jq -r '.approved_by[].user.username')

    done < <(echo "$mrs_response" | jq -c '.[]')

    ((page++))
done

log_info "Analysis complete. Processed ${total_mrs} merge requests."

# Display results (top 10 approvers)
echo -e "\nTop 10 Approvers:"
echo "=================="
for username in "${!approvers_count[@]}"; do
    echo "${username} ${approvers_count[$username]}"
done | sort -rn -k2 | head -n 10 | while read -r username count; do
    printf "%-20s : %d approvals\n" "$username" "$count"
done

# Display summary
echo -e "\nSummary:"
echo "- Time period: Last $MONTHS months (since $(date -d "$DATE_LIMIT" '+%Y-%m-%d'))"
echo "- Total analyzed MRs: $total_mrs"
echo "- Total unique approvers: ${#approvers_count[@]}"

# Error handling
set -e
trap 'echo "An error occurred on line $LINENO. Exit code: $?" >&2' ERR
