#############################################################################################
# Script Name: shredops.sh
# Author: michael.quintero@rackspace.com
# Description: Tool to help clean up EBS volumes and/or snapshots based on a provided list
##############################################################################################

#!/bin/bash

SCRIPT_VERSION="2.8.5"

REGION=""
TICKET_ID=""
FILE_INPUT=""
ACCOUNT_TYPE="commercial"
VALID_ACCOUNT_TYPES=("commercial" "government")
COMMERCIAL_US_REGIONS=('us-east-1' 'us-east-2' 'us-west-1' 'us-west-2')
GOVERNMENT_US_REGIONS=('us-gov-west-1' 'us-gov-east-1')

# Exit on ANY error...undefined variable usage, or failed pipe
set -o errexit
set -o pipefail
set -o nounset

# Temp files to separate volume/snapshot IDs if the user wants them handled separately
FILTERED_FILE_VOLS=$(mktemp)
FILTERED_FILE_SNAPS=$(mktemp)

# Auto-clean temp files when script exits
trap 'rm -f "$FILTERED_FILE_VOLS" "$FILTERED_FILE_SNAPS"' EXIT
VALID_RESOURCES_FOUND=false

# The ever important usage instructions are doc'd here
usage() {
    echo "Usage: $0 [ -f file ] [ -r region ] [ -t ticket_id ] [ -c account_type ] [ -v ] [ -h ]"
    echo "   -f  Set the input file containing EBS volumes or snapshots"
    echo "   -r  Set the AWS region for the operation (leave blank to check all US regions)"
    echo "   -t  Add a ticket identifier for the operation"
    echo "   -c  Specify the account type (commercial or government, default: commercial)"
    echo "   -v  Show version information"
    echo "   -h  Show usage information"
    echo "Example: $0 -f FILE_WITH_EBS_VOLUMES.txt -r us-west-2 -t TICKET123 -c government"
    exit 1
}

version() {
    echo "$0 version $SCRIPT_VERSION"
    exit 0
}

while getopts ":f:r:t:c:vh" opt; do
  case ${opt} in
    f ) FILE_INPUT=$OPTARG ;;
    r ) REGION=$OPTARG ;;
    t ) TICKET_ID=$OPTARG ;;
    c )
        if [[ ! " ${VALID_ACCOUNT_TYPES[@]} " =~ " ${OPTARG} " ]]; then
            echo "Error: Invalid account type provided."
            usage
        else
            ACCOUNT_TYPE=$OPTARG
        fi ;;
    v ) version ;;
    h ) usage ;;
    \? ) usage ;;
  esac
done

if [ -z "$FILE_INPUT" ] || [ ! -f "$FILE_INPUT" ]; then
    echo "Error: Input file not provided or does not exist."
    usage
fi

# What am I working with here! Figures out what type of resources (volumes, snapshots, or both) are in the input file
has_vols=false
has_snaps=false
while read -r line; do
    if [[ "$line" == vol-* ]]; then
        has_vols=true
    elif [[ "$line" == snap-* ]]; then
        has_snaps=true
    fi
done < "$FILE_INPUT"

if [ "$has_vols" = true ]; then
    grep '^vol-' "$FILE_INPUT" > "$FILTERED_FILE_VOLS"
fi
if [ "$has_snaps" = true ]; then
    grep '^snap-' "$FILE_INPUT" > "$FILTERED_FILE_SNAPS"
fi

# Prompting user on how to proceed if both volumes & snapshots are found
if [ "$has_vols" = true ] && [ "$has_snaps" = true ]; then
    echo "\n⚠️ The file contains a mix of EBS Volumes and Snapshots."
    echo "Choose how you'd like to proceed:"
    echo "1) Volumes only"
    echo "2) Snapshots only"
    echo "3) All (both volumes and snapshots)"
    read -p "Enter your choice (1, 2, or 3): " choice
    case $choice in
        1) RESOURCE_TYPES=("volume") ;;
        2) RESOURCE_TYPES=("snapshot") ;;
        3) RESOURCE_TYPES=("volume" "snapshot") ;;
        *) echo "Invalid choice. Exiting."; exit 1;;
    esac
elif [ "$has_vols" = true ]; then
    RESOURCE_TYPES=("volume")
    echo "Detected only EBS volumes in file. Proceeding with volume deletion."
elif [ "$has_snaps" = true ]; then
    RESOURCE_TYPES=("snapshot")
    echo "Detected only EBS snapshots in file. Proceeding with snapshot deletion."
else
    echo "Error: No valid EBS volume or snapshot IDs found in the file."
    exit 1
fi

# Returns the AWS regions based on the selected account type
get_regions() {
    if [ "$ACCOUNT_TYPE" = "government" ]; then
        echo "${GOVERNMENT_US_REGIONS[@]}"
    else
        echo "${COMMERCIAL_US_REGIONS[@]}"
    fi
}

# Shows the current status of each volume or snapshot in the specified region. Important if they are in-use!
display_resources_status() {
    local region=$1
    local resource_file=$2
    local resource_type=$3
    local resources=$(cat "$resource_file")
    local found_any=false

    echo "Resources and their current status in region $region:"
    set +e # Temp disable exit-on-error to allow resource checks :)

    for resource_id in $resources; do
        if [ "$resource_type" == "volume" ]; then
            # Checking if the volume even exists in the defined region
            aws ec2 describe-volumes --volume-ids "$resource_id" --region "$region" --output text &> /dev/null
            if [ $? -eq 0 ]; then
               # If it DOES exist, what's its status?
                status=$(aws ec2 describe-volumes --volume-ids "$resource_id" --query 'Volumes[0].State' --region "$region" --output text)
                echo "Volume ID: $resource_id - Status: $status"
                found_any=true
            else
                echo "Volume ID: $resource_id - Not found in region $region"
            fi
        elif [ "$resource_type" == "snapshot" ]; then
            aws ec2 describe-snapshots --snapshot-ids "$resource_id" --region "$region" --output text &> /dev/null
            if [ $? -eq 0 ]; then
                status=$(aws ec2 describe-snapshots --snapshot-ids "$resource_id" --query 'Snapshots[0].State' --region "$region" --output text)
                echo "Snapshot ID: $resource_id - Status: $status"
                found_any=true
            else
                echo "Snapshot ID: $resource_id - Not found in region $region"
            fi
        fi
    done

    set -e # Re-enable exit-on-error :O

    if [ "$found_any" = true ]; then
        VALID_RESOURCES_FOUND=true
    fi
}

# Where the deletion magic for EBS volumes/snapshots happens then logs results
delete_resources() {
    local region=$1
    local resource_file=$2
    local resource_type=$3
    local resources=$(cat "$resource_file")
    local deleted_count=0
    local skipped_count=0

    set +e # Hi again! Don’t exit script if a deletion fails...

    for resource_id in $resources; do
        if [ "$resource_type" == "snapshot" ]; then
           # TRY deleting the snapshot
            delete_output=$(aws ec2 delete-snapshot --snapshot-id "$resource_id" --region "$region" 2>&1)
            delete_status=$?

            if [ $delete_status -eq 0 ]; then
                echo "Deleted EBS snapshot: $resource_id in region $region"
                echo "$resource_id" >> "$REPORT_FILE"
                ((deleted_count++))
            else
                # If the snapshot is in use by an AMI, we will ask the user if they want to deregister the AMI. This will effectively remove the AMI image in order to clear the snapshot!
                if [[ "$delete_output" =~ InvalidSnapshot.InUse ]]; then
                    ami_id=$(echo "$delete_output" | grep -oP 'ami-[a-zA-Z0-9]+')
                    if [ -n "$ami_id" ]; then
                        echo "Snapshot $resource_id is in use by AMI $ami_id."
                        read -p "Would you like to deregister the AMI and retry deleting the snapshot? (y/n): " user_input
                        if [[ $user_input =~ ^[Yy]$ ]]; then
                            aws ec2 deregister-image --image-id "$ami_id" --region "$region"
                            echo "AMI $ami_id has been deregistered. Retrying snapshot deletion..."
                            delete_output=$(aws ec2 delete-snapshot --snapshot-id "$resource_id" --region "$region" 2>&1)
                            delete_status=$?
                            if [ $delete_status -eq 0 ]; then
                                echo "Deleted EBS snapshot: $resource_id in region $region"
                                echo "$resource_id" >> "$REPORT_FILE"
                                ((deleted_count++))
                                continue
                            else
                                echo "Failed to delete snapshot: $resource_id after AMI deregistration - $delete_output"
                            fi
                        else
                            echo "User opted not to deregister AMI. Skipping deletion of snapshot $resource_id."
                        fi
                    else
                        echo "Could not extract AMI ID from error message."
                    fi
                else
                    echo "Failed to delete snapshot: $resource_id - $delete_output"
                fi
                ((skipped_count++))
            fi

        elif [ "$resource_type" == "volume" ]; then
            # TRY deleting the volume
            delete_output=$(aws ec2 delete-volume --volume-id "$resource_id" --region "$region" 2>&1)
            delete_status=$?

            if [ $delete_status -eq 0 ]; then
                echo "Deleted EBS volume: $resource_id in region $region"
                echo "$resource_id" >> "$REPORT_FILE"
                ((deleted_count++))
            else
                if [[ "$delete_output" =~ VolumeInUse ]]; then
                    instance_id=$(echo "$delete_output" | grep -oP '\{(i-[a-zA-Z0-9]+)\}' | tr -d '{}')
                    echo "Volume $resource_id is currently in use by instance $instance_id. Skipping deletion."
                else
                    echo "Failed to delete volume: $resource_id - $delete_output"
                fi
                ((skipped_count++))
            fi
        fi
    done

    echo "Waiting 120 seconds to allow CloudTrail logs to propagate..."
    sleep 120 # Wait so we can find the log entries afterward. This could potentially take way longer, but I found 2 mins as a good amount of time to allow for deletion of at least 10 resources with no issues

    echo -e "\nSummary for region $region (resource type: $resource_type):"
    echo "  ✅ Deleted: $deleted_count"
    echo "  ⚠️ Skipped: $skipped_count"

    # Check 'n log CT events for auditing as required by many agencies/customers
    for resource_id in $resources; do
        if [ "$resource_type" == "snapshot" ]; then
            log_cloudtrail_event "$resource_id" "DeleteSnapshot" "$region"
        elif [ "$resource_type" == "volume" ]; then
            log_cloudtrail_event "$resource_id" "DeleteVolume" "$region"
        fi
    done

    set -e
}

# Where we look up associated CloudTrail logs to find details about the who/what/when/where deleted the resource
log_cloudtrail_event() {
    local resource_id=$1
    local action=$2
    local region=$3

    # Defining the time range to search in CT
    local end_time
    local start_time
    end_time=$(date -u +"%Y-%m-%dT%H:%M:%SZ")
    start_time=$(date -u -d "-20 minutes" +"%Y-%m-%dT%H:%M:%SZ")  # Extended lookup window

    local parsed_event=""
    local attempt=1
    local max_attempts=5
    local sleep_between_attempts=30

    while [ $attempt -le $max_attempts ]; do
        local trail_event
        trail_event=$(aws cloudtrail lookup-events \
            --lookup-attributes AttributeKey=EventName,AttributeValue=$action \
            --start-time "$start_time" \
            --end-time "$end_time" \
            --region "$region" \
            --max-results 100 \
            --output json)

        parsed_event=$(echo "$trail_event" | jq -c --arg rid "$resource_id" '
            .Events
            | map(
                .CloudTrailEvent as $evt_raw
                | ($evt_raw | fromjson) as $evt
                | select(
                    ($evt.eventName == "DeleteVolume" and $evt.requestParameters.volumeId? == $rid) or
                    ($evt.eventName == "DeleteSnapshot" and $evt.requestParameters.snapshotId? == $rid)
                )
                | {
                    eventTime: $evt.eventTime,
                    user: ($evt.userIdentity.arn // $evt.userIdentity.userName // "Unknown"),
                    eventName: $evt.eventName,
                    eventID: .EventId
                }
            )
            | sort_by(.eventTime)
            | reverse
            | .[0]
        ')

        if [ -n "$parsed_event" ] && [ "$parsed_event" != "null" ]; then
            break
        else
            echo "⏳ Waiting for CloudTrail event for $resource_id (attempt $attempt/$max_attempts)..."
            sleep $sleep_between_attempts
            attempt=$((attempt + 1))
        fi
    done

    # Write up those details to the report if event found (better be), or note failure :(
    if [ -n "$parsed_event" ] && [ "$parsed_event" != "null" ]; then
        local event_time
        local user_name
        local event_name
        local event_id

        event_time=$(echo "$parsed_event" | jq -r '.eventTime // ""')
        user_name=$(echo "$parsed_event" | jq -r '.user // "Unknown"')
        event_name=$(echo "$parsed_event" | jq -r '.eventName // ""')
        event_id=$(echo "$parsed_event" | jq -r '.eventID // ""')

        echo "  CloudTrail Record:" >> "$REPORT_FILE"
        echo "    Time:       $event_time" >> "$REPORT_FILE"
        echo "    User:       $user_name" >> "$REPORT_FILE"
        echo "    Action:     $event_name" >> "$REPORT_FILE"
        echo "    Event ID:   $event_id" >> "$REPORT_FILE"
    else
        echo "  No CloudTrail event found for $resource_id after $max_attempts attempts." >> "$REPORT_FILE"
    fi
}

# Inform the user & confirm if they want to check current resource statuses
echo "You are about to delete EBS ${RESOURCE_TYPES[*]} resource(s) listed in $FILE_INPUT for account type $ACCOUNT_TYPE."
read -p "Would you like to display the current status of these resources? (y/n): " -n 1 -r
echo
if [[ $REPLY =~ ^[Yy]$ ]]; then
    REGIONS=$(get_regions)
    for resource_type in "${RESOURCE_TYPES[@]}"; do
        resource_file=$( [ "$resource_type" == "volume" ] && echo "$FILTERED_FILE_VOLS" || echo "$FILTERED_FILE_SNAPS" )
        for region in ${REGION:-$(get_regions)}; do
            echo "Checking $resource_type resources in $region..."
            display_resources_status "$region" "$resource_file" "$resource_type"
        done
    done

    if [ "$VALID_RESOURCES_FOUND" = false ]; then
        echo "The resources indicated in the referenced file are not found in region $REGION, nothing to do."
        exit 0
    fi

    echo "Continuing to deletion phase..."
fi

# One final confirmation before deletion
read -p "Are you sure you want to proceed with deletion? (y/n): " -n 1 -r
echo
if [[ ! $REPLY =~ ^[Yy]$ ]]; then
    exit 1
fi

# Create the report file using the ticket ID the user assigned as a flag & timestamp. Thinking of swapping to Unix epoch time in the near future.
REPORT_FILE="report_${TICKET_ID}_$(date +%Y%m%d%H%M%S).txt"
echo "Deletion Report - Date: $(date)" > "$REPORT_FILE"
echo "Ticket ID: $TICKET_ID" >> "$REPORT_FILE"
echo "Deleted Resources (with CloudTrail audit logs):" >> "$REPORT_FILE"

for resource_type in "${RESOURCE_TYPES[@]}"; do
    resource_file=$( [ "$resource_type" == "volume" ] && echo "$FILTERED_FILE_VOLS" || echo "$FILTERED_FILE_SNAPS" )
    for region in ${REGION:-$(get_regions)}; do
        echo "Deleting $resource_type resources in $region..."
        delete_resources "$region" "$resource_file" "$resource_type"
    done
    echo -e "\n--- Report Summary for $resource_type ---" >> "$REPORT_FILE"
done

# Output the final report path and contents
echo "Report generated at: $REPORT_FILE"
echo
cat "$REPORT_FILE"

