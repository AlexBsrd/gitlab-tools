#!/bin/bash

# Check dependencies
command -v jq >/dev/null 2>&1 || { echo "jq required"; exit 1; }
command -v curl >/dev/null 2>&1 || { echo "curl required"; exit 1; }

# Display help
display_help() {
    cat << EOF
Pipeline Monitor - A GitLab pipeline status monitoring tool

Usage:
    $(basename "$0") [options]

Options:
    --help          Show this help message

Environment variables:
    GITLAB_URL      Required. URL of your GitLab instance
    GITLAB_TOKEN    Required. Your GitLab personal access token
    GROUP_ID        Required. ID of the GitLab group to monitor
    SHOW_SUCCESSFUL Optional. Show successful pipelines (default: false)
    REFRESH         Optional. Auto-refresh interval in seconds (default: 0)
    DEBUG           Optional. Enable debug logging (default: false)

Examples:
    # Basic usage
    GITLAB_URL="https://gitlab.company.com" GITLAB_TOKEN="token" GROUP_ID="123" ./$(basename "$0")

    # Show successful pipelines with auto-refresh
    GITLAB_URL="https://gitlab.company.com" GITLAB_TOKEN="token" GROUP_ID="123" SHOW_SUCCESSFUL=true REFRESH=30 ./$(basename "$0")
EOF
}

# Check for help flag
if [ "$1" = "--help" ]; then
    display_help
    exit 0
fi

# Configuration
GITLAB_URL="${GITLAB_URL}"
GITLAB_TOKEN="${GITLAB_TOKEN}"
GROUP_ID="${GROUP_ID}"
SHOW_SUCCESSFUL="${SHOW_SUCCESSFUL:-false}"
REFRESH="${REFRESH:-0}"
DEBUG="${DEBUG:-false}"

# Colors
GREEN='\033[0;32m'
RED='\033[0;31m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
PURPLE='\033[0;35m'
GRAY='\033[0;90m'
BOLD='\033[1m'
NC='\033[0m'

# Debug function
debug() {
    if [ "$DEBUG" = "true" ]; then
        echo -e "${GRAY}[DEBUG] $1${NC}" >&2
    fi
}

# Validate required variables
if [ -z "$GITLAB_URL" ]; then
    echo "Error: GITLAB_URL is required"
    exit 1
fi

if [ -z "$GITLAB_TOKEN" ]; then
    echo "Error: GITLAB_TOKEN is required"
    exit 1
fi

if [ -z "$GROUP_ID" ]; then
    echo "Error: GROUP_ID is required"
    exit 1
fi

# Display function
display_status() {
    # Clear screen if refresh mode is active
    [ "$REFRESH" -gt 0 ] && clear

    # Header
    echo -e "${BOLD}GitLab Pipeline Monitor${NC}"
    echo "Instance: $GITLAB_URL"
    echo "Group: $GROUP_ID"
    echo

    # Get projects
    debug "Fetching projects..."
    projects=$(curl -s --header "PRIVATE-TOKEN: $GITLAB_TOKEN" \
        "$GITLAB_URL/api/v4/groups/$GROUP_ID/projects?include_subgroups=true&per_page=100")

    if [ -z "$projects" ]; then
        echo "Error: No projects found"
        exit 1
    fi

    # Print header
    printf "${BOLD}%-60s %-20s %-15s %s${NC}\n" "PROJECT" "STATUS" "BRANCH" "LAST UPDATE"
    printf "%0.s─" {1..120}
    echo

    # Initialize counters
    success_count=0
    failed_count=0
    running_count=0
    pending_count=0
    manual_count=0

    # Get total count
    total_count=$(echo "$projects" | jq length)

    # Process each project
    echo "$projects" | jq -c '.[]' | while read -r project; do
        name=$(echo "$project" | jq -r '.path_with_namespace')
        id=$(echo "$project" | jq -r '.id')
        default_branch=$(echo "$project" | jq -r '.default_branch')

        # Get latest pipeline
        pipeline=$(curl -s --header "PRIVATE-TOKEN: $GITLAB_TOKEN" \
            "$GITLAB_URL/api/v4/projects/$id/pipelines?ref=$default_branch&per_page=1")

        if [ -n "$pipeline" ] && [ "$pipeline" != "[]" ]; then
            status=$(echo "$pipeline" | jq -r '.[0].status')
            created_at=$(echo "$pipeline" | jq -r '.[0].created_at')

            # Format date
            if [ -n "$created_at" ] && [ "$created_at" != "null" ]; then
                formatted_date=$(date -d "$created_at" '+%Y-%m-%d %H:%M' 2>/dev/null || echo "$created_at")
            else
                formatted_date="N/A"
            fi

            # Format status with color
            case $status in
                "success")
                    echo -ne "${GREEN}✓ Success${NC}" > /tmp/status
                    ((success_count++))
                    ;;
                "manual")
                    echo -ne "${PURPLE}⊙ Manual${NC}" > /tmp/status
                    ((manual_count++))
                    ;;
                "failed")
                    echo -ne "${RED}✗ Failed${NC}" > /tmp/status
                    ((failed_count++))
                    ;;
                "running")
                    echo -ne "${BLUE}⟳ Running${NC}" > /tmp/status
                    ((running_count++))
                    ;;
                "pending")
                    echo -ne "${YELLOW}⋯ Pending${NC}" > /tmp/status
                    ((pending_count++))
                    ;;
                *)
                    echo -ne "${GRAY}${status}${NC}" > /tmp/status
                    ;;
            esac

            # Ne pas afficher les pipelines manual et success quand SHOW_SUCCESSFUL est false
            if ([ "$status" != "success" ] && [ "$status" != "manual" ]) || [ "$SHOW_SUCCESSFUL" = "true" ]; then
                printf "%-60s %-20s %-15s %s\n" \
                    "${name:0:57}..." \
                    "$(cat /tmp/status)" \
                    "$default_branch" \
                    "$formatted_date"
            fi
        fi
    done

    # Print summary
    echo
    printf "%0.s─" {1..120}
    echo -e "\n${BOLD}Summary:${NC}"
    echo "Total projects: $total_count"
    [ "$running_count" -gt 0 ] && echo -e "${BLUE}⟳ Running:  $running_count${NC}"
    [ "$pending_count" -gt 0 ] && echo -e "${YELLOW}⋯ Pending:  $pending_count${NC}"
    [ "$failed_count" -gt 0 ] && echo -e "${RED}✗ Failed:   $failed_count${NC}"
    [ "$manual_count" -gt 0 ] && echo -e "${PURPLE}⊙ Manual:   $manual_count${NC}"
    # Afficher le nombre total de succès (success + manual) si SHOW_SUCCESSFUL est true
    if [ "$SHOW_SUCCESSFUL" = "true" ] && [ "$((success_count + manual_count))" -gt 0 ]; then
        echo -e "${GREEN}✓ Success:  $((success_count + manual_count))${NC}"
    fi

    if [ "$REFRESH" -gt 0 ]; then
        echo -e "\nRefreshing every ${REFRESH}s... Press Ctrl+C to stop"
    fi
}

# Main loop
while true; do
    display_status
    [ "$REFRESH" -eq 0 ] && break
    sleep "$REFRESH"
done

# Cleanup
rm -f /tmp/status
