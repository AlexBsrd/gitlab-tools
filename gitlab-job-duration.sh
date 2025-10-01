#!/bin/bash

# Script: gitlab-job-duration.sh
# Description: Calculate cumulative execution time of a specific job across all pipelines in a given period

# Configuration
GITLAB_URL="${GITLAB_URL:-https://gitlab.com}"

# Check required parameters
if [ -z "$GITLAB_TOKEN" ]; then
    echo "❌ Error: GITLAB_TOKEN not defined"
    echo ""
    echo "Usage:"
    echo "  export GITLAB_TOKEN=your-token"
    echo "  export PROJECT_ID=your-project-id"
    echo "  export JOB_NAME=job-name"
    echo "  ./gitlab-job-duration.sh"
    echo ""
    echo "Or:"
    echo "  GITLAB_TOKEN=glpat-xxx PROJECT_ID=123 JOB_NAME=my-job ./gitlab-job-duration.sh"
    echo ""
    echo "Optional variables:"
    echo "  GITLAB_URL     - GitLab instance URL (default: https://gitlab.com)"
    echo "  START_DATE     - Start date in YYYY-MM-DD format (default: beginning of last month)"
    echo "  END_DATE       - End date in YYYY-MM-DD format (default: end of last month)"
    echo ""
    echo "Examples:"
    echo "  GITLAB_TOKEN=glpat-xxx PROJECT_ID=123 JOB_NAME=fail-draft-mr ./gitlab-job-duration.sh"
    echo "  GITLAB_TOKEN=glpat-xxx PROJECT_ID=123 JOB_NAME=build START_DATE=2024-09-01 END_DATE=2024-09-30 ./gitlab-job-duration.sh"
    exit 1
fi

if [ -z "$PROJECT_ID" ]; then
    echo "❌ Error: PROJECT_ID not defined"
    echo ""
    echo "Usage:"
    echo "  export GITLAB_TOKEN=your-token"
    echo "  export PROJECT_ID=your-project-id"
    echo "  export JOB_NAME=job-name"
    echo "  ./gitlab-job-duration.sh"
    echo ""
    echo "Or:"
    echo "  GITLAB_TOKEN=glpat-xxx PROJECT_ID=123 JOB_NAME=my-job ./gitlab-job-duration.sh"
    exit 1
fi

if [ -z "$JOB_NAME" ]; then
    echo "❌ Error: JOB_NAME not defined"
    echo ""
    echo "Usage:"
    echo "  export GITLAB_TOKEN=your-token"
    echo "  export PROJECT_ID=your-project-id"
    echo "  export JOB_NAME=job-name"
    echo "  ./gitlab-job-duration.sh"
    echo ""
    echo "Or:"
    echo "  GITLAB_TOKEN=glpat-xxx PROJECT_ID=123 JOB_NAME=my-job ./gitlab-job-duration.sh"
    echo ""
    echo "Example:"
    echo "  GITLAB_TOKEN=glpat-xxx PROJECT_ID=123 JOB_NAME=fail-draft-mr ./gitlab-job-duration.sh"
    exit 1
fi

# Calculate dates (last month by default)
if [ -z "$START_DATE" ]; then
    START_DATE=$(date -d "last month" +%Y-%m-01)
fi

if [ -z "$END_DATE" ]; then
    END_DATE=$(date -d "$START_DATE +1 month -1 day" +%Y-%m-%d)
fi

echo "================================================================"
echo "GitLab Job Analysis"
echo "================================================================"
echo "Project ID: $PROJECT_ID"
echo "Job name: $JOB_NAME"
echo "Period: $START_DATE to $END_DATE"
echo "================================================================"
echo ""

# Statistics variables
total_duration=0
job_count=0
page=1
per_page=100

# Pagination loop to retrieve all pipelines
while true; do
    # Retrieve pipelines for the period (all branches, all statuses)
    response=$(curl -s --header "PRIVATE-TOKEN: $GITLAB_TOKEN" \
        "$GITLAB_URL/api/v4/projects/$PROJECT_ID/pipelines?per_page=$per_page&page=$page&updated_after=${START_DATE}T00:00:00Z&updated_before=${END_DATE}T23:59:59Z")
    
    # Check if response is empty
    if [ "$(echo "$response" | jq '. | length')" -eq 0 ]; then
        break
    fi
    
    # Extract pipeline IDs
    pipeline_ids=$(echo "$response" | jq -r '.[].id')
    
    # For each pipeline, search for the specific job
    for pipeline_id in $pipeline_ids; do
        echo -n "."  # Progress indicator
        
        # Retrieve jobs from the pipeline
        jobs=$(curl -s --header "PRIVATE-TOKEN: $GITLAB_TOKEN" \
            "$GITLAB_URL/api/v4/projects/$PROJECT_ID/pipelines/$pipeline_id/jobs")
        
        # Filter job by name
        job_info=$(echo "$jobs" | jq -r ".[] | select(.name == \"$JOB_NAME\")")
        
        if [ -n "$job_info" ]; then
            job_id=$(echo "$job_info" | jq -r '.id')
            duration=$(echo "$job_info" | jq -r '.duration // 0')
            created_at=$(echo "$job_info" | jq -r '.created_at')
            status=$(echo "$job_info" | jq -r '.status')
            ref=$(echo "$job_info" | jq -r '.ref')
            stage=$(echo "$job_info" | jq -r '.stage')
            
            if [ "$duration" != "null" ] && [ "$duration" != "0" ]; then
                # Convert duration to integer (round)
                duration_int=$(printf "%.0f" "$duration")
                total_duration=$((total_duration + duration_int))
                job_count=$((job_count + 1))
                echo ""
                echo "  Pipeline #$pipeline_id | Job #$job_id | Stage: $stage | Branch: $ref"
                echo "    → Duration: ${duration_int}s | Status: $status | Date: $created_at"
            fi
        fi
    done
    
    page=$((page + 1))
done

echo ""
echo ""
echo "================================================================"
echo "RESULTS"
echo "================================================================"
echo "Number of jobs found: $job_count"
echo "Total duration: $total_duration seconds"
echo "Total duration: $((total_duration / 60)) minutes ($((total_duration / 3600)) hours)"

if [ $job_count -gt 0 ]; then
    avg_duration=$((total_duration / job_count))
    echo "Average duration per job: ${avg_duration} seconds"
else
    echo "Average duration per job: 0 seconds"
fi

echo "================================================================"