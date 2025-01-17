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
    echo "Usage: $0 USERNAME [OPTIONS]"
    echo "Generates a detailed report of merge request contributions by a specific user."
    echo
    echo "Required environment variables:"
    echo "  GITLAB_TOKEN                # Your GitLab access token"
    echo "  GROUP_ID                    # ID of the GitLab group to analyze"
    echo "  GITLAB_URL                  # GitLab instance URL (e.g., https://gitlab.example.com)"
    echo
    echo "Optional environment variables:"
    echo "  MONTHS                      # Number of months to analyze (default: 6)"
    echo "  OUTPUT_FILE                 # Output file name (default: contributions.md)"
    exit 0
fi

# Verify arguments
if [ "$#" -ne 1 ]; then
    echo "Usage: $0 USERNAME"
    echo "Example: $0 johndoe"
    echo "Use --help for more information"
    exit 1
fi

USERNAME="$1"

# Colors and formatting
GREEN='\033[0;32m'
BLUE='\033[0;34m'
YELLOW='\033[1;33m'
RED='\033[0;31m'
GRAY='\033[0;90m'
BOLD='\033[1m'
NC='\033[0m'

# Configuration
GITLAB_URL="${GITLAB_URL}"
GITLAB_TOKEN="${GITLAB_TOKEN}"
GROUP_ID="${GROUP_ID}"
MONTHS="${MONTHS:-6}"
OUTPUT_FILE="${OUTPUT_FILE:-contributions.md}"

# Validate environment variables
if [ -z "$GITLAB_URL" ]; then
    echo -e "${RED}GitLab URL is not defined. Set the GITLAB_URL environment variable.${NC}"
    echo -e "Example: ${GRAY}GITLAB_URL=https://gitlab.example.com${NC}"
    echo -e "Use ${BOLD}--help${NC} for more information"
    exit 1
fi

if [ -z "$GITLAB_TOKEN" ]; then
    echo -e "${RED}GitLab token is not defined. Set the GITLAB_TOKEN environment variable.${NC}"
    echo -e "Use ${BOLD}--help${NC} for more information"
    exit 1
fi

if [ -z "$GROUP_ID" ]; then
    echo -e "${RED}Group ID is not defined. Set the GROUP_ID environment variable.${NC}"
    echo -e "Use ${BOLD}--help${NC} for more information"
    exit 1
fi

GITLAB_URL="${GITLAB_URL%/}"  # Remove trailing slash if it exists

# Calculate date limit
DATE_LIMIT=$(date -d "$MONTHS months ago" +%Y-%m-%dT%H:%M:%SZ)

# Display functions
print_separator() {
    echo -e "${GRAY}────────────────────────────────────────────────────────────${NC}"
}

print_header() {
    echo -e "\n${BOLD}${BLUE}$1${NC}"
    print_separator
}

print_success() {
    echo -e "${GREEN}✓${NC} $1"
}

print_progress() {
    echo -e "${YELLOW}→${NC} $1"
}

print_error() {
    echo -e "${RED}✗${NC} $1" >&2
}

# Function to get merge requests
get_merge_requests() {
    local page=1
    local all_mrs="[]"

    while true; do
        local response
        response=$(curl -s --header "PRIVATE-TOKEN: $GITLAB_TOKEN" \
            "$GITLAB_URL/api/v4/groups/$GROUP_ID/merge_requests?created_after=$DATE_LIMIT&state=merged&per_page=100&page=$page&scope=all&author_username=$USERNAME")

        if [ $? -ne 0 ]; then
            print_error "Error during API request"
            print_error "Check your configuration and use --help for more information"
            return 1
        fi

        if [ -z "$response" ] || [ "$response" = "[]" ] || [ "$(echo "$response" | jq length)" -eq 0 ]; then
            break
        fi

        if ! echo "$response" | jq . >/dev/null 2>&1; then
            print_error "Invalid API response"
            print_error "Check your configuration and use --help for more information"
            return 1
        fi

        all_mrs=$(echo "$all_mrs $response" | jq -s 'add')
        ((page++))
    done

    echo "$all_mrs"
}

# Function to get merge request changes
get_merge_request_changes() {
    local project_id="$1"
    local mr_iid="$2"

    curl -s --header "PRIVATE-TOKEN: $GITLAB_TOKEN" \
        "$GITLAB_URL/api/v4/projects/$project_id/merge_requests/$mr_iid/changes"
}

# Function to write to file
write_to_file() {
    local mr="$1"
    local changes="$2"
    local output_file="$3"

    local title=$(echo "$mr" | jq -r '.title')
    local description=$(echo "$mr" | jq -r '.description')
    local created_at=$(echo "$mr" | jq -r '.created_at')
    local web_url=$(echo "$mr" | jq -r '.web_url')
    local project_name=$(echo "$mr" | jq -r '.references.full')
    local formatted_date=$(date -d "$created_at" "+%d/%m/%Y")

    # Extract change statistics
    local changes_summary=$(echo "$changes" | jq -r '.changes | map(select(.new_file or .deleted_file or .renamed_file)) | length')
    local total_additions=$(echo "$changes" | jq -r '.changes | map(.diff | split("\n") | map(select(startswith("+"))) | length) | add')
    local total_deletions=$(echo "$changes" | jq -r '.changes | map(.diff | split("\n") | map(select(startswith("-"))) | length) | add')

    # Extract file details
    local new_files=$(echo "$changes" | jq -r '.changes | map(select(.new_file) | .new_path) | join("\n- ")')
    local deleted_files=$(echo "$changes" | jq -r '.changes | map(select(.deleted_file) | .old_path) | join("\n- ")')
    local modified_files=$(echo "$changes" | jq -r '.changes | map(select(.new_file|not) | select(.deleted_file|not) | select(.renamed_file|not) | .new_path) | join("\n- ")')
    local renamed_files=$(echo "$changes" | jq -r '.changes | map(select(.renamed_file) | [.old_path, .new_path] | join(" → ")) | join("\n- ")')

    {
        echo "## $title"
        echo "- **Date:** $formatted_date"
        echo "- **Project:** $project_name"
        echo "- **URL:** $web_url"
        echo
        echo "### Description"
        if [ "$description" != "null" ] && [ -n "$description" ]; then
            echo "$description"
        else
            echo "*No description provided*"
        fi
        echo
        echo "### Impact"
        echo "- Total files affected: $changes_summary"
        echo "- Lines added: $total_additions"
        echo "- Lines deleted: $total_deletions"
        echo

        if [ -n "$new_files" ]; then
            echo "#### ✨ New Files"
            echo "- $new_files"
            echo
        fi

        if [ -n "$deleted_files" ]; then
            echo "#### 🗑️ Deleted Files"
            echo "- $deleted_files"
            echo
        fi

        if [ -n "$renamed_files" ]; then
            echo "#### 📝 Renamed Files"
            echo "- $renamed_files"
            echo
        fi

        if [ -n "$modified_files" ]; then
            echo "#### 🔄 Modified Files"
            echo "- $modified_files"
            echo
        fi

        echo "---"
        echo
    } >> "$output_file"
}

# Main program
main() {
    print_header "🚀 Extracting Contributions for $USERNAME"
    echo -e "${BLUE}GitLab Instance:${NC} $GITLAB_URL"
    echo -e "📅 Period: ${BOLD}$(date -d "$DATE_LIMIT" "+%d/%m/%Y") - $(date "+%d/%m/%Y")${NC}\n"

    # Initialize output file
    echo "# Contribution Report" > "$OUTPUT_FILE"
    echo "Period: $(date -d "$DATE_LIMIT" "+%d/%m/%Y") - $(date "+%d/%m/%Y")" >> "$OUTPUT_FILE"
    echo "User: $USERNAME" >> "$OUTPUT_FILE"
    echo >> "$OUTPUT_FILE"

    # Fetch merge requests
    print_progress "Fetching merge requests from group $GROUP_ID..."
    local merge_requests
    merge_requests=$(get_merge_requests)
    if [ $? -ne 0 ]; then
        print_error "Error fetching merge requests"
        print_error "Check your configuration and use --help for more information"
        exit 1
    fi

    local total_mrs
    total_mrs=$(echo "$merge_requests" | jq length)
    print_success "Found $total_mrs merge requests to analyze"

    if [ "$total_mrs" -eq 0 ]; then
        print_progress "No merge requests found for the specified period"
        exit 0
    fi

    print_separator

    # Process merge requests
    local counter=0
    echo "$merge_requests" | jq -c '.[]' | while IFS= read -r mr; do
        ((counter++)) || true
        local project_id=$(echo "$mr" | jq -r '.project_id')
        local mr_iid=$(echo "$mr" | jq -r '.iid')
        local title=$(echo "$mr" | jq -r '.title')
        local created_at=$(date -d "$(echo "$mr" | jq -r '.created_at')" "+%d/%m/%Y")
        local project_name=$(echo "$mr" | jq -r '.references.full')

        echo -e "${BOLD}[$counter/$total_mrs]${NC} Processing MR: ${BLUE}$title${NC}"
        echo -e "${GRAY}└── Project: $project_name${NC}"
        echo -e "${GRAY}└── Date   : $created_at${NC}"

        local changes
        changes=$(get_merge_request_changes "$project_id" "$mr_iid")
        if [ $? -ne 0 ]; then
            print_error "Error getting changes for MR"
            print_error "Check your configuration and use --help for more information"
            continue
        fi

        local changes_count
        changes_count=$(echo "$changes" | jq -r '.changes | length')
        write_to_file "$mr" "$changes" "$OUTPUT_FILE"
        if [ $? -eq 0 ]; then
            print_success "MR analyzed ($changes_count files changed)"
        else
            print_error "Error writing to output file"
        fi
        echo
    done

    # Final verification
    if [ ! -s "$OUTPUT_FILE" ]; then
        print_error "No data was written to output file"
        print_error "Check your configuration and use --help for more information"
        exit 1
    fi

    print_separator
    print_success "Report generated successfully in ${BOLD}$OUTPUT_FILE${NC}"
}

# Error handling
set -e
trap 'echo -e "\n${RED}An error occurred on line $LINENO. Exit code: $?${NC}" >&2' ERR

# Start the script
main
