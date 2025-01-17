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
    echo "Usage:"
    echo "  $0                          # Process all merge requests"
    echo "  $0 PROJECT_ID MR_IID        # Process a specific merge request"
    echo "  $0 --help                   # Show this help message"
    echo
    echo "Required environment variables:"
    echo "  GITLAB_TOKEN                # Your GitLab access token"
    echo "  GROUP_ID                    # ID of the GitLab group to monitor"
    echo "  GITLAB_URL                  # GitLab instance URL (e.g., https://gitlab.example.com)"
    echo
    echo "Optional environment variables:"
    echo "  APPROVAL_THRESHOLD          # Number of approvals required (default: 2)"
    echo "  APPROVAL_LABEL              # Label for approved MRs (default: double-approved)"
    echo "  READY_TO_MERGE_LABEL        # Label for MRs ready to merge (default: ready-to-be-merged)"
    echo "  BOT_USERNAME               # Username for bot comments (default: gitlab-bot)"
    exit 0
fi

# Configuration
GITLAB_URL="${GITLAB_URL}"
GITLAB_TOKEN="${GITLAB_TOKEN}"
GROUP_ID="${GROUP_ID}"

# Validate environment variables
if [ -z "$GITLAB_URL" ]; then
    echo "GitLab URL is not defined. Set the GITLAB_URL environment variable."
    echo "Example: GITLAB_URL=https://gitlab.example.com"
    echo "Use --help for more information."
    exit 1
fi

GITLAB_URL="${GITLAB_URL%/}"  # Remove trailing slash if it exists
APPROVAL_THRESHOLD="${APPROVAL_THRESHOLD:-2}"
APPROVAL_LABEL="${APPROVAL_LABEL:-double-approved}"
READY_TO_MERGE_LABEL="${READY_TO_MERGE_LABEL:-ready-to-be-merged}"
BOT_USERNAME="${BOT_USERNAME:-gitlab-bot}"  # Username used for bot comments

# Validate environment variables based on usage
validate_env_vars() {
    if [ -z "$GITLAB_TOKEN" ]; then
        echo "GitLab token is not defined. Set the GITLAB_TOKEN environment variable."
        echo "Use --help for more information."
        exit 1
    fi

    # GROUP_ID is only needed when processing all MRs
    if [ "$#" -eq 0 ] && [ -z "$GROUP_ID" ]; then
        echo "Group ID is not defined. Set the GROUP_ID environment variable."
        echo "Use --help for more information."
        exit 1
    fi
}

# Function to get all merge requests
get_merge_requests() {
    local page=1
    local all_mrs="[]"

    while true; do
        local response
        response=$(curl -s --header "PRIVATE-TOKEN: $GITLAB_TOKEN" \
            "$GITLAB_URL/api/v4/groups/$GROUP_ID/merge_requests?state=opened&per_page=100&page=$page&with_approval_rules=true")

        if [ -z "$response" ] || [ "$(echo "$response" | jq length)" -eq 0 ]; then
            break
        fi

        all_mrs=$(echo "$all_mrs $response" | jq -s 'add')
        ((page++))
    done

    echo "$all_mrs"
}

# Function to get a specific merge request
get_single_merge_request() {
    local project_id="$1"
    local mr_iid="$2"

    curl -s --header "PRIVATE-TOKEN: $GITLAB_TOKEN" \
        "$GITLAB_URL/api/v4/projects/$project_id/merge_requests/$mr_iid"
}

# Function to get merge request approvals
get_merge_request_approvals() {
    local project_id="$1"
    local mr_iid="$2"

    curl -s --header "PRIVATE-TOKEN: $GITLAB_TOKEN" \
        "$GITLAB_URL/api/v4/projects/$project_id/merge_requests/$mr_iid/approvals"
}

# Function to get discussions for a merge request
get_merge_request_discussions() {
    local project_id="$1"
    local mr_iid="$2"
    local page=1
    local all_discussions="[]"

    while true; do
        local response
        response=$(curl -s --header "PRIVATE-TOKEN: $GITLAB_TOKEN" \
            "$GITLAB_URL/api/v4/projects/$project_id/merge_requests/$mr_iid/discussions?per_page=100&page=$page")

        if [ -z "$response" ] || [ "$(echo "$response" | jq length)" -eq 0 ]; then
            break
        fi

        all_discussions=$(echo "$all_discussions $response" | jq -s 'add')
        ((page++))
    done

    echo "$all_discussions"
}

# Function to check if there are any open threads in discussions
has_open_threads() {
    local discussions="$1"

    echo "$discussions" | jq -r '
        any(
            .notes |
            select(length > 0) |
            map(
                select(.system == false and .resolvable == true and .resolved == false)
            ) |
            length > 0
        )
    ' | grep -q "true" && echo "true" || echo "false"
}

# Function to get merge request comments
get_merge_request_comments() {
    local project_id="$1"
    local mr_iid="$2"

    curl -s --header "PRIVATE-TOKEN: $GITLAB_TOKEN" \
        "$GITLAB_URL/api/v4/projects/$project_id/merge_requests/$mr_iid/notes"
}

# Function to check if we should send a reminder
should_send_reminder() {
    local project_id="$1"
    local mr_iid="$2"

    local comments=$(get_merge_request_comments "$project_id" "$mr_iid")
    local last_bot_comment=$(echo "$comments" | jq -r ".[] | select(.author.username == \"$BOT_USERNAME\") | select(.body | contains(\"ready to be merged\")) | .created_at" | sort -r | head -1)

    if [ -z "$last_bot_comment" ]; then
        # No previous reminder found
        echo "first"
    else
        # Calculate days since last reminder
        local last_comment_date=$(date -d "$last_bot_comment" +%s)
        local current_date=$(date +%s)
        local days_diff=$(( (current_date - last_comment_date) / (60*60*24) ))

        if [ "$days_diff" -ge 7 ]; then
            echo "reminder"
        else
            echo "none"
        fi
    fi
}

# Function to add a comment to a merge request
add_merge_request_comment() {
    local project_id="$1"
    local mr_iid="$2"
    local author_username="$3"
    local is_reminder="$4"

    local message
    if [ "$is_reminder" = "reminder" ]; then
        message="Hey @$author_username 👋 This is a friendly follow-up reminder! This merge request still seems ready to be merged. All approvals are in place and there are no open discussions. Don't hesitate if you need any help! 🚀"
    else
        message="Hey @$author_username 👋 Just a friendly reminder that this merge request seems ready to be merged! All approvals are in place and there are no open discussions. 🚀"
    fi

    curl -s --request POST \
        --header "PRIVATE-TOKEN: $GITLAB_TOKEN" \
        --header "Content-Type: application/json" \
        --data "{\"body\": \"$message\"}" \
        "$GITLAB_URL/api/v4/projects/$project_id/merge_requests/$mr_iid/notes"
}

# Function to update merge request labels
update_merge_request_labels() {
    local project_id="$1"
    local mr_iid="$2"
    local labels="$3"

    curl -s --request PUT \
        --header "PRIVATE-TOKEN: $GITLAB_TOKEN" \
        --header "Content-Type: application/json" \
        --data "{\"labels\": $labels}" \
        "$GITLAB_URL/api/v4/projects/$project_id/merge_requests/$mr_iid" > /dev/null
}

# Function to print a separator line
print_separator() {
    echo "----------------------------------------"
}

# Function to log with timestamp
log_info() {
    echo "[$(date '+%Y-%m-%d %H:%M:%S')] $1"
}

# Function to process a single merge request
process_merge_request() {
    local mr="$1"

    local project_id=$(echo "$mr" | jq -r '.project_id')
    local mr_iid=$(echo "$mr" | jq -r '.iid')
    local title=$(echo "$mr" | jq -r '.title')
    local web_url=$(echo "$mr" | jq -r '.web_url')
    local current_labels=$(echo "$mr" | jq -r '.labels')
    local author_username=$(echo "$mr" | jq -r '.author.username')

    print_separator
    log_info "Starting process for MR #$mr_iid"
    log_info "Title: $title"
    log_info "URL: $web_url"
    log_info "Current labels: $(echo $current_labels | jq -r 'join(", ")')"

    # Skip draft MRs
    if echo "$current_labels" | jq -e "index(\"draft\")" > /dev/null; then
        log_info "💤 Skipping MR #$mr_iid - marked as draft"
        print_separator
        return
    fi

    # Get approvals
    local approvals=$(get_merge_request_approvals "$project_id" "$mr_iid")
    local approved_by_count=$(echo "$approvals" | jq '.approved_by | length')
    local approvers=$(echo "$approvals" | jq -r '.approved_by[].user.username' | paste -sd "," -)

    log_info "Approvals count: $approved_by_count (needed: $APPROVAL_THRESHOLD)"
    [ ! -z "$approvers" ] && log_info "Approved by: $approvers"

    # Handle approval labels
    if [ "$approved_by_count" -ge "$APPROVAL_THRESHOLD" ]; then
        if ! echo "$current_labels" | jq -e "index(\"$APPROVAL_LABEL\")" > /dev/null && \
           ! echo "$current_labels" | jq -e "index(\"$READY_TO_MERGE_LABEL\")" > /dev/null; then
            log_info "✨ Adding $APPROVAL_LABEL label (sufficient approvals and no existing status labels)"
            new_labels=$(echo "$current_labels" | jq ". + [\"$APPROVAL_LABEL\"]")
            update_merge_request_labels "$project_id" "$mr_iid" "$new_labels"
            current_labels="$new_labels"
            log_info "Updated labels: $(echo $new_labels | jq -r 'join(", ")')"
        else
            log_info "ℹ️  Not adding $APPROVAL_LABEL - MR already has status labels"
        fi
    else
        if echo "$current_labels" | jq -e "index(\"$APPROVAL_LABEL\")" > /dev/null; then
            log_info "🔄 Removing $APPROVAL_LABEL label (insufficient approvals)"
            new_labels=$(echo "$current_labels" | jq "[ .[] | select(. != \"$APPROVAL_LABEL\") ]")
            update_merge_request_labels "$project_id" "$mr_iid" "$new_labels"
            current_labels="$new_labels"
            log_info "Updated labels: $(echo $new_labels | jq -r 'join(", ")')"
        fi
    fi

    # Handle ready-to-merge notification and reminders
    if (echo "$current_labels" | jq -e "index(\"$APPROVAL_LABEL\")" > /dev/null && \
        ! echo "$current_labels" | jq -e "index(\"$READY_TO_MERGE_LABEL\")" > /dev/null) || \
       (echo "$current_labels" | jq -e "index(\"$READY_TO_MERGE_LABEL\")" > /dev/null); then

        log_info "Checking for open discussions..."
        # Check for open discussions
        discussions=$(get_merge_request_discussions "$project_id" "$mr_iid")
        if [ "$(has_open_threads "$discussions")" = "false" ]; then
            log_info "🚀 MR is ready to be merged! No open discussions found"

            # Check if we should send a reminder
            local reminder_status=$(should_send_reminder "$project_id" "$mr_iid")

            case "$reminder_status" in
                "none")
                    log_info "ℹ️ Recent reminder exists, skipping notification"
                    ;;
                "reminder")
                    log_info "📬 Sending follow-up reminder to @$author_username"
                    add_merge_request_comment "$project_id" "$mr_iid" "$author_username" "reminder"
                    ;;
                "first")
                    log_info "📬 Sending first notification to @$author_username"
                    add_merge_request_comment "$project_id" "$mr_iid" "$author_username" "first"
                    ;;
            esac

            # If MR has double-approved, replace it with ready-to-be-merged
            if echo "$current_labels" | jq -e "index(\"$APPROVAL_LABEL\")" > /dev/null; then
                log_info "Replacing $APPROVAL_LABEL with $READY_TO_MERGE_LABEL"
                new_labels=$(echo "$current_labels" | jq "[ .[] | select(. != \"$APPROVAL_LABEL\") ] + [\"$READY_TO_MERGE_LABEL\"]")
                update_merge_request_labels "$project_id" "$mr_iid" "$new_labels"
                log_info "Updated labels: $(echo $new_labels | jq -r 'join(", ")')"
            fi
        else
            log_info "⏳ Found open discussions - MR not yet ready to be merged"
        fi
    fi

    log_info "Processing complete for MR #$mr_iid"
    print_separator
}

# Main program
main() {
    # Validate environment variables based on context
    validate_env_vars "$@"

    if [ "$#" -eq 2 ]; then
        project_id="$1"
        mr_iid="$2"
        log_info "Using GitLab instance: $GITLAB_URL"
        log_info "Processing single merge request: Project $project_id, MR #$mr_iid"
        merge_request=$(get_single_merge_request "$project_id" "$mr_iid")
        [ -z "$merge_request" ] && echo "MR not found" && exit 1
        process_merge_request "$merge_request"
    else
        log_info "Using GitLab instance: $GITLAB_URL"
        log_info "Retrieving all merge requests..."
        merge_requests=$(get_merge_requests)
        total_mrs=$(echo "$merge_requests" | jq length)
        log_info "Processing $total_mrs merge requests..."

        echo "$merge_requests" | jq -c '.[]' | while read -r mr; do
            process_merge_request "$mr"
        done
    fi
}

set -e
trap 'echo "An error occurred on line $LINENO. Exit code: $?" >&2' ERR

main "$@"
