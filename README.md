# GitLab Tools 🛠️

A collection of shell scripts to automate and streamline GitLab project management tasks. These tools help you monitor merge requests, track project activity, analyze contributions, and measure job performance.

## 📋 Requirements

- `bash` shell
- `curl` for API requests
- `jq` for JSON processing
- GitLab personal access token with appropriate permissions

## 🔧 Configuration

All scripts use environment variables for configuration.

**Required for all scripts:**
```bash
export GITLAB_URL="https://your-gitlab-instance.com"
export GITLAB_TOKEN="your-personal-access-token"
```

## 🚀 Available Scripts

### Pipeline Monitor

Real-time monitoring dashboard for pipeline statuses across all projects in a GitLab group.

```bash
# Basic usage - show only non-successful pipelines
./pipeline-monitor.sh GROUP_ID

# Show all pipelines including successful ones
SHOW_SUCCESSFUL=true ./pipeline-monitor.sh GROUP_ID

# Auto-refresh every 30 seconds
REFRESH=30 ./pipeline-monitor.sh GROUP_ID
```

**Additional configuration:**
```bash
export GROUP_ID="123"                # Required
export SHOW_SUCCESSFUL="true"        # Optional (default: false)
export REFRESH="30"                  # Optional (refresh interval in seconds)
export DEBUG="true"                  # Optional (enables debug logging)
```

Features:
- Color-coded status indicators (✓ Success, ✗ Failed, ⟳ Running, ⋯ Pending, ⊙ Manual)
- Auto-refresh capability
- Compact project name display
- Summary statistics
- Configurable display of successful pipelines

### Merge Requests Automator

Automates merge request workflows by monitoring approvals, managing labels, and sending notifications.

```bash
# Process all merge requests
./merge-requests-automator.sh

# Process a specific merge request
./merge-requests-automator.sh PROJECT_ID MR_IID
```

**Additional configuration:**
```bash
export GROUP_ID="123"                              # Required
export APPROVAL_THRESHOLD="2"                      # Optional (default: 2)
export APPROVAL_LABEL="double-approved"            # Optional
export READY_TO_MERGE_LABEL="ready-to-be-merged"  # Optional
export BOT_USERNAME="gitlab-bot"                  # Optional
```

### Personal Contributions

Generates a detailed Markdown report of a user's merge request contributions.

```bash
./personal-contributions.sh USERNAME
```

**Additional configuration:**
```bash
export GROUP_ID="123"                    # Required
export MONTHS="6"                        # Optional (default: 6)
export OUTPUT_FILE="contributions.md"    # Optional
```

### Merge Requests Stats

Analyzes merge request approval statistics and generates reviewer participation reports.

```bash
./merge-requests-stats.sh
```

**Additional configuration:**
```bash
export GROUP_ID="123"                            # Required
export MONTHS="3"                                # Optional (default: 3)
export EXCLUDE_BOTS="gitlab-bot"    # Optional
```

### Project Activity Tracker

Tracks project activity based on merge request history and ranks projects by activity level.

```bash
./project-activity-tracker.sh
```

**Additional configuration:**
```bash
export GROUP_ID="123"                    # Required
export MONTHS="3"                        # Optional (default: 3)
export EXCLUDE_BOTS="bot1 bot2"         # Optional
```

### Project Lister

Lists all projects in a GitLab group, including those in subgroups. Outputs clone URLs for easy access.

```bash
./project-lister.sh GROUP_ID
```

### Job Duration Analyzer

Calculate cumulative execution time of a specific job across all pipelines in a given period.

```bash
# Analyze a specific job for last month
GITLAB_TOKEN=glpat-xxx PROJECT_ID=123 JOB_NAME=fail-draft-mr ./gitlab-job-duration.sh

# Analyze for a custom period
GITLAB_TOKEN=glpat-xxx PROJECT_ID=123 JOB_NAME=build \
  START_DATE=2024-09-01 END_DATE=2024-09-30 \
  ./gitlab-job-duration.sh
```

**Additional configuration:**
```bash
export PROJECT_ID="123"                  # Required
export JOB_NAME="job-name"              # Required
export START_DATE="2024-09-01"          # Optional (default: beginning of last month)
export END_DATE="2024-09-30"            # Optional (default: end of last month)
```

Features:
- Searches across all branches and pipeline statuses
- Displays detailed job information (duration, status, branch, date)
- Calculates total and average execution times
- Supports custom date ranges

## 📝 Examples

### Monitor Pipeline Statuses
```bash
# Monitor pipelines with auto-refresh
export GITLAB_URL="https://gitlab.company.com"
export GITLAB_TOKEN="your-token"
export GROUP_ID="123"
export REFRESH="30"
./pipeline-monitor.sh
```

### Generate Your Monthly Contributions Report
```bash
export GITLAB_URL="https://gitlab.company.com"
export GITLAB_TOKEN="your-token"
export GROUP_ID="123"
export MONTHS="1"
./personal-contributions.sh your-username
```

### Monitor Active Projects
```bash
export GITLAB_URL="https://gitlab.company.com"
export GITLAB_TOKEN="your-token"
export GROUP_ID="123"
export EXCLUDE_BOTS="gitlab-bot"
./project-activity-tracker.sh
```

### Analyze Job Performance
```bash
export GITLAB_URL="https://gitlab.company.com"
export GITLAB_TOKEN="your-token"
export PROJECT_ID="456"
export JOB_NAME="test"
./gitlab-job-duration.sh
```

### Clone All Group Projects
```bash
export GITLAB_URL="https://gitlab.company.com"
export GITLAB_TOKEN="your-token"
./project-lister.sh 123 | while read url; do
    git clone "$url"
done
```

## 🔍 Help

All scripts support the `--help` flag which displays detailed usage information:
```bash
./script-name.sh --help
```

## 📌 Notes

- Scripts are designed to be non-destructive and read-only
- API pagination is handled automatically
- All timestamps are in UTC

## 🤝 Contributing

Contributions are welcome! Feel free to open issues or submit pull requests to improve these tools.

## 📄 License

This project is open source and available under the MIT License.