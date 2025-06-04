````markdown
# AWS Volume Cleanup Script

## Description
The `volume_snap_cleaner.sh` script is designed to automate the deletion of unused AWS EBS volumes and snapshots. It supports input files containing mixed resource types and includes CloudTrail-based auditing for secure, accountable operations.

## Features

- **Dual Resource Deletion**: Supports deleting both EBS volumes and snapshots in a single run.
- **Region Selection**: Operates in a specified AWS region or across all supported US regions.
- **Account Type Support**: Compatible with both commercial and government AWS accounts.
- **Ticket Identifier**: Adds a tracking ID to the deletion report for traceability.
- **Status Checks**: Displays current resource status before deletion with user confirmation.
- **Volume Attachment Detection**: Detects if a volume is attached to an instance and skips deletion safely.
- **AMI Dependency Handling**: If a snapshot is in use by an AMI, prompts user to deregister and retry deletion.
- **CloudTrail Auditing**: Logs the most recent relevant deletion event for each resource with retry logic.
- **Report Generation**: Produces a detailed report including deletion outcomes and audit logs.
- **Robust Error Handling**: Provides descriptive output for failures and reasons (e.g., `VolumeInUse`, `InvalidSnapshot.InUse`).

## Prerequisites

- AWS CLI must be installed and configured with permissions to manage EBS and access CloudTrail.
- `jq` must be installed to parse JSON responses.
- Bash environment (Linux or macOS) to run the script.

## Usage

```bash
./volume_snap_cleaner.sh [OPTIONS]
````

### Options

* `-f FILE` : Input file containing EBS volume and/or snapshot IDs (required).
* `-r REGION` : AWS region to target (optional; checks all supported US regions if omitted).
* `-t TICKET_ID` : Ticket or change ID for audit traceability.
* `-c ACCOUNT_TYPE` : AWS account type: `commercial` or `government` (default: `commercial`).
* `-v` : Display script version.
* `-h` : Show usage instructions.

### Example

```bash
./volume_snap_cleaner.sh -f resources_to_be_deleted.txt -r us-west-2 -t CHG45678 -c government
```

## Output

* A `report_<ticket_id>_<timestamp>.txt` file is generated containing:

  * List of deleted resources.
  * CloudTrail audit records for each deletion.
  * Summary counts by region and resource type.

## Versioning

* **Current Version**: `2.8.5`

## Disclaimer

> Use this script at your own risk. Always ensure that you have proper backups and test in a non-production environment. The author assumes no responsibility for data loss or unintended consequences resulting from the use of this script.
