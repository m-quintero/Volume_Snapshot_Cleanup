# AWS Volume Cleanup Script

## Description
The `volume_snap_cleaner.sh` script is designed to automate the deletion of unused AWS EBS volumes or snapshots. It supports input files containing mixed resource types and includes auditing features via CloudTrail to track deletion actions.

## Features
- **Mixed Input Support**: Detects and prompts for EBS volume or snapshot processing if input file includes both.
- **Region Selection**: Operates in a specified AWS region or across all supported US regions.
- **Account Type**: Supports both commercial and government account types.
- **Dry Run Mode**: Safely simulate deletions before executing them.
- **Ticket Identifier**: Adds a tracking ID to the deletion report.
- **Safety Checks**: The script includes confirmation prompts to prevent accidental deletions.
- **Status Check**: Before deletion, the script displays the current status of the resources and asks for user confirmation.
- **CloudTrail Auditing**: Captures and logs the most recent CloudTrail event for each deleted resource.
- **Report Generation**: Creates a detailed report post-deletion and displays it on-screen.
- **Error Handling**: Provides feedback for missing resources, AMI conflicts, and permission issues.

## Prerequisites
- AWS CLI must be installed and configured with required permissions to manage EBS and query CloudTrail.
- jq must be installed to parse JSON responses
- Bash environment to run the script.

## Usage
```bash
./volume_snap_cleaner.sh [OPTIONS]
```

### Options
- `-f FILE`: Set the input file containing EBS volumes or snapshots (required).
- `-r REGION`: Set the AWS region for the operation (default: checks all US regions).
- `-t TICKET_ID`: Add a ticket identifier for the operation. (optional).
- `-c ACCOUNT_TYPE`: Account type: commercial or government (default: commercial).
- `-d`: Dry-run mode (no resources will be deleted).
- `-v`: Show version information.
- `-h`: Show usage information.

### Example
```bash
./volume_snap_cleaner.sh -f resources_to_be_deleted.txt -r us-west-1 -t TICKET123 -c commercial
```

## Versioning
- Version: 2.0

## Disclaimer
Use this script at your own risk! Always ensure that you have backups of your data and test the script in a non-production environment before running it in production. I am not responsible for any data loss or other consequences that may arise from the use of this script.
