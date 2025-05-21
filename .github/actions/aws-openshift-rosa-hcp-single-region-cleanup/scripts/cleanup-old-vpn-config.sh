#!/bin/bash

# Description:
# This script lists folders in an S3 bucket and deletes those older than a specified age.
# It includes a dry run option to simulate the deletion without actually deleting.
#
# Usage:
# ./cleanup-old-vpn-config.sh <BUCKET_NAME> <BUCKET_REGION> <BUCKET_PREFIX> <MIN_AGE_IN_HOURS> <ID_OR_ALL> [--dry-run]
#
# Arguments:
#   BUCKET_NAME: The name of the S3 bucket.
#   BUCKET_REGION: The region of the S3 bucket.
#   BUCKET_PREFIX: The prefix for the folders in the S3 bucket.
#   MIN_AGE_IN_HOURS: The minimum age (in hours) of folders to be deleted.
#   ID_OR_ALL: The specific ID suffix to filter objects, or "all" to destroy all objects.
#   --dry-run: Optional flag to simulate the deletion without actually deleting.
#
# Example:
# ./cleanup-old-vpn-config.sh tests-ra-aws-rosa-hcp-tf-state-eu-central-1 eu-central-1 aws/vpn-configs/ 24 all
# ./cleanup-old-vpn-config.sh tests-ra-aws-rosa-hcp-tf-state-eu-central-1 eu-central-1 aws/vpn-configs/ 24 specific-id --dry-run

# Check for required arguments
if [ "$#" -lt 5 ] || [ "$#" -gt 6 ]; then
  echo "Usage: $0 <BUCKET_NAME> <BUCKET_REGION> <BUCKET_PREFIX> <MIN_AGE_IN_HOURS> <ID_OR_ALL> [--dry-run]"
  exit 1
fi

# Variables
BUCKET=$1
AWS_REGION=$2
PREFIX=$3
MIN_AGE_IN_HOURS=$4
ID_OR_ALL=$5
DRY_RUN=false

# Check for dry run flag
if [ "$#" -eq 6 ] && [ "$6" == "--dry-run" ]; then
  DRY_RUN=true
fi

# Detect operating system and set the appropriate date command
if [[ "$(uname)" == "Darwin" ]]; then
    date_command="gdate"
else
    date_command="date"
fi

# Get current timestamp
current_timestamp=$($date_command +%s)

echo "AWS_REGION of the bucket set on $AWS_REGION"

# List objects in the S3 bucket and parse the folder names
if [ "$ID_OR_ALL" == "all" ]; then
  folders=$(aws s3 ls "s3://$BUCKET/$PREFIX" | awk '{print $2}')
else
  folders=$(aws s3 ls "s3://$BUCKET/$PREFIX" | awk -v id="$ID_OR_ALL" '$2 ~ id {print $2}')
fi

if [ -z "$folders" ]; then
  echo "No folders found in the S3 bucket. Exiting script." >&2
  exit 0
fi

for folder in $folders; do
  echo "Processing: s3://$BUCKET/$PREFIX$folder"

  # Get the list of files in the folder
  files=$(aws s3 ls "s3://$BUCKET/${PREFIX}${folder}" | awk '{print $4}')

  if [ -z "$files" ]; then
    echo "Warning: No files found in folder $folder, skipping."
    continue
  fi

  # Initialize variables to find the most recent file
  latest_timestamp=0
  latest_file=""

  # Iterate over each file to find the most recent one
  for file in $files; do
    # Construct the full path to the file
    full_file_path="${PREFIX}${folder}${file}"

    # Check if the file exists
    if ! aws s3api head-object --bucket "$BUCKET" --key "$full_file_path" --output json >/dev/null 2>&1; then
      echo "Warning: File $full_file_path does not exist, skipping."
      continue
    fi

    last_modified=$(aws s3api head-object --bucket "$BUCKET" --key "$full_file_path" --output json | grep LastModified | awk -F '"' '{print $4}')
    if [ -z "$last_modified" ]; then
      echo "Warning: Could not retrieve last modified timestamp for $full_file_path, skipping."
      continue
    fi

    last_modified_timestamp=$($date_command -d "$last_modified" +%s)
    if [ -z "$last_modified_timestamp" ]; then
      echo "Error: Failed to convert last modified timestamp for $full_file_path"
      exit 1
    fi

    if [ "$last_modified_timestamp" -gt "$latest_timestamp" ]; then
      latest_timestamp=$last_modified_timestamp
      latest_file=$full_file_path
    fi
  done

  if [ -z "$latest_file" ]; then
    echo "Warning: No valid files found in folder $folder, skipping."
    continue
  fi

  # Calculate the age of the folder in hours
  file_age_hours=$(( (current_timestamp - latest_timestamp) / 3600 ))
  if [ -z "$file_age_hours" ]; then
    echo "Error: Failed to calculate file age in hours for $latest_file"
    exit 1
  fi

  echo "Folder $folder is $file_age_hours hours old"

  if [ $file_age_hours -ge "$MIN_AGE_IN_HOURS" ]; then
    if [ "$DRY_RUN" = true ]; then
      echo "[Dry Run] Would delete folder $folder"
    else
      echo "Deleting folder $folder"
      if ! aws s3 rm "s3://$BUCKET/${PREFIX}${folder}" --recursive; then
        echo "Error deleting folder $folder"
        exit 1
      fi
    fi
  else
    echo "Skipping $folder as it does not meet the minimum age requirement of $MIN_AGE_IN_HOURS hours"
  fi
done

echo "All operations completed successfully."
exit 0
