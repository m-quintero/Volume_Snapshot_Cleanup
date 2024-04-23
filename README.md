```markdown
# AWS Volume Cleanup Script

## Description
The `volume_snap_cleaner.sh` script is designed to automate the deletion of unused AWS EBS volumes or snapshots. It allows users to specify whether they are deleting an EBS volume or a snapshot, choose the AWS region, set the account type (commercial or government), and add a ticket identifier for operation tracking.

## Features
- **Resource Type Selection**: Users can choose to delete either EBS volumes or snapshots.
- **Region Selection**: Users can specify an AWS region for the operation. If no region is specified, the script checks all US regions (commercial or government based on the account type).
- **Account Type**: Supports both commercial and government account types.
- **Ticket Identifier**: Allows adding a ticket identifier for operation tracking.
- **Status Check**: Before deletion, the script displays the current status of the resources and asks for user confirmation.
- **Deletion Report**: Generates a report after deletion with details of the deleted resources.
- **Safety Checks**: The script includes confirmation prompts to prevent accidental deletions.

## Prerequisites
- AWS CLI must be installed and configured with the necessary permissions to manage EBS volumes and snapshots.
- Bash environment to run the script.

## Usage
```bash
./volume_snap_cleaner.sh [OPTIONS]
```

### Options
- `-f FILE`: Set the input file containing EBS volumes or snapshots (required).
- `-r REGION`: Set the AWS region for the operation (default: checks all US regions).
- `-t TICKET_ID`: Add a ticket identifier for the operation.
- `-c ACCOUNT_TYPE`: Specify the account type (commercial or government, default: commercial).
- `-v`: Show version information.
- `-h`: Show usage information.

### Example
```bash
./volume_snap_cleaner.sh -f resources_to_be_deleted.txt -r us-west-1 -t TICKET123 -c commercial
```

## Versioning
- Version: 1.1.1
- Author: Michael Quintero

## Disclaimer
Use this script at your own risk! Always ensure that you have backups of your data and test the script in a non-production environment before running it in production. I am not responsible for any data loss or other consequences that may arise from the use of this script.
