#############################################################################################
# Script Name: volume_snap_cleaner.sh
# Author: michael.quintero@rackspace.com
# Description: Tool to help clean up EBS volumes and/or snapshots based on a provided list
##############################################################################################

#!/bin/bash

SCRIPT_VERSION="1.1.2"

REGION=""
TICKET_ID=""
FILE_INPUT=""
ACCOUNT_TYPE="commercial"
VALID_ACCOUNT_TYPES=("commercial" "government")
COMMERCIAL_US_REGIONS=('us-east-1' 'us-east-2' 'us-west-1' 'us-west-2')
GOVERNMENT_US_REGIONS=('us-gov-west-1' 'us-gov-east-1')

set -o errexit
set -o pipefail
set -o nounset

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

echo "Choose the type of resource to delete:"
echo "1) EBS Volume"
echo "2) EBS Snapshot"
read -p "Enter your choice (1 or 2): " choice
case $choice in
    1) RESOURCE_TYPE="volume" ;;
    2) RESOURCE_TYPE="snapshot" ;;
    *) echo "Invalid choice. Exiting."; exit 1;;
esac

get_regions() {
    if [ "$ACCOUNT_TYPE" = "government" ]; then
        echo "${GOVERNMENT_US_REGIONS[@]}"
    else
        echo "${COMMERCIAL_US_REGIONS[@]}"
    fi
}

display_resources_status() {
    local region=$1
    local resources=$(cat $FILE_INPUT)

    echo "Resources and their current status in region $region:"

    set +e
    
    for resource_id in $resources; do
        if [ "$RESOURCE_TYPE" == "volume" ]; then
            # Attempt to describe the volume and check for success
            aws ec2 describe-volumes --volume-ids $resource_id --region $region --output text &> /dev/null
            if [ $? -eq 0 ]; then
                status=$(aws ec2 describe-volumes --volume-ids $resource_id --query 'Volumes[0].State' --region $region --output text)
                echo "Volume ID: $resource_id - Status: $status"
            else
                echo "Volume ID: $resource_id - Not found in region $region"
            fi
        elif [ "$RESOURCE_TYPE" == "snapshot" ]; then
            aws ec2 describe-snapshots --snapshot-ids $resource_id --region $region --output text &> /dev/null
            if [ $? -eq 0 ]; then
                status=$(aws ec2 describe-snapshots --snapshot-ids $resource_id --query 'Snapshots[0].State' --region $region --output text)
                echo "Snapshot ID: $resource_id - Status: $status"
            else
                echo "Snapshot ID: $resource_id - Not found in region $region"
            fi
        fi
    done

    set -e
}

delete_resources() {
    local region=$1
    local resources=$(cat $FILE_INPUT)
    
    set +e
    
    for resource_id in $resources; do
        if [ "$RESOURCE_TYPE" == "snapshot" ]; then
            delete_output=$(aws ec2 delete-snapshot --snapshot-id $resource_id --region $region 2>&1)
            delete_status=$?
            if [ $delete_status -eq 0 ]; then
                echo "Deleted EBS snapshot: $resource_id in region $region"
                echo "$resource_id" >> $REPORT_FILE
            else
                if [[ "$delete_output" =~ InvalidSnapshot.InUse ]]; then
                    local ami_id=$(echo "$delete_output" | grep -oP 'ami-[a-zA-Z0-9]+')
                    if [ -n "$ami_id" ]; then
                        echo "Snapshot $resource_id is in use by AMI $ami_id."
                        echo -n "Would you like to deregister the AMI and retry deletion? (y/n): "
                        read user_input
                        if [[ $user_input =~ ^[Yy]$ ]]; then
                            aws ec2 deregister-image --image-id $ami_id --region $region
                            echo "AMI $ami_id has been deregistered."
                            aws ec2 delete-snapshot --snapshot-id $resource_id --region $region
                            echo "Retried deleting snapshot $resource_id."
                            echo "$resource_id" >> $REPORT_FILE
                        else
                            echo "Snapshot deletion skipped."
                        fi
                    else
                        echo "Could not extract AMI ID from error message."
                    fi
                else
                    echo "Failed to delete snapshot: $resource_id - $delete_output"
                fi
            fi
        elif [ "$RESOURCE_TYPE" == "volume" ]; then
            delete_output=$(aws ec2 delete-volume --volume-id $resource_id --region $region 2>&1)
            delete_status=$?
            if [ $delete_status -eq 0 ]; then
                echo "Deleted EBS volume: $resource_id in region $region"
                echo "$resource_id" >> $REPORT_FILE
            else
                echo "Failed to delete volume: $resource_id - $delete_output"
            fi
        fi
    done

    set -e
}

echo "You are about to delete EBS $RESOURCE_TYPE(s) listed in $FILE_INPUT for account type $ACCOUNT_TYPE."
read -p "Would you like to display the current status of these resources? (y/n): " -n 1 -r
echo
if [[ $REPLY =~ ^[Yy]$ ]]; then
    REGIONS=$(get_regions)
    if [ -z "$REGION" ]; then
        for region in $REGIONS; do
            echo "Checking resources in $region..."
            display_resources_status $region
        done
    else
        display_resources_status $REGION
    fi
    echo "Continuing to deletion phase..."
fi

read -p "Are you sure you want to proceed with deletion? (y/n): " -n 1 -r
echo
if [[ ! $REPLY =~ ^[Yy]$ ]]
then
    [[ "$0" = "$BASH_SOURCE" ]] && exit 1 || return 1
fi

REPORT_FILE="report_${TICKET_ID}_$(date +%Y%m%d%H%M%S).txt"
echo "Deletion Report - Date: $(date)" > $REPORT_FILE
echo "Ticket ID: $TICKET_ID" >> $REPORT_FILE
echo "Deleted Resources:" >> $REPORT_FILE


REGIONS=$(get_regions)
if [ -z "$REGION" ]; then
    for region in $REGIONS; do
        echo "Checking resources in $region..."
        delete_resources $region
    done
else
    delete_resources $REGION
fi

echo "Report generated at: $REPORT_FILE"
echo "Deletion operation completed."
