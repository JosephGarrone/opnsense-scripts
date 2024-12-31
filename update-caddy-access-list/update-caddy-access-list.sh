#!/bin/bash

# Requires the following software to be installed on OPNsense
#     pkg install bash
#     pkg install jq

# Variables (defaults can be set here if needed)
EXTERNAL_DOMAIN="" # External domain to lookup (-ed) to allow access from (i.e. "www.google.com")
OPNSENSE_API_KEY="" # OPNsense API key (-key)
OPNSENSE_API_SECRET="" # OPNsense API secret (-secret)
OPNSENSE_API_URL="" # OPNsense API URL (-url) (i.e. https://<some-ip>/api)
ACCESS_LIST_NAME="" # Name of the HTTP Access list to update (From "Edit Access List" dialog -> "Access List Name")

# Constants
OLD_IP_FILE="update-caddy-access-list-old-ip" # File to store the old IP

# Parse parameters
while [[ "$#" -gt 0 ]]; do
  case "$1" in
    -ed|--external-domain)
      EXTERNAL_DOMAIN="$2"
      shift; shift
      ;;
    -al|--access-list)
      ACCESS_LIST_NAME="$2"
      shift; shift
      ;;
    -key|--api-key)
      OPNSENSE_API_KEY="$2"
      shift; shift
      ;;
    -secret|--api-secret)
      OPNSENSE_API_SECRET="$2"
      shift; shift
      ;;
    -url|--api-url)
      OPNSENSE_API_URL="$2"
      shift; shift
      ;;
    *)
      echo "[ERROR] Unknown parameter: $1"
      exit 1
      ;;
  esac
done

# Validate required parameters
if [[ -z "$EXTERNAL_DOMAIN" || -z "$ACCESS_LIST_NAME" || -z "$OPNSENSE_API_KEY" || -z "$OPNSENSE_API_SECRET" || -z "$OPNSENSE_API_URL" ]]; then
  echo "[ERROR] Missing required parameters. Ensure -ed, -al, -key, -secret, and -url are provided."
  exit 1
fi

# Function to fetch current IP of the domain
get_current_ip() {
  local domain=$1
  drill "$domain" | grep -Eo '([0-9]{1,3}\.){3}[0-9]{1,3}' | head -n1
}

# Function to fetch subdomain configuration
fetch_subdomain_config() {
  curl -s -u "$OPNSENSE_API_KEY:$OPNSENSE_API_SECRET" \
    -X GET "$OPNSENSE_API_URL/caddy/reverse_proxy/getSubdomain"
}

# Function to fetch access list by UUID
fetch_access_list() {
  local uuid=$1
  curl -s -u "$OPNSENSE_API_KEY:$OPNSENSE_API_SECRET" \
    -X GET "$OPNSENSE_API_URL/caddy/reverse_proxy/getAccessList/$uuid"
}

# Function to update the access list by UUID
update_access_list() {
  local uuid=$1
  local updated_config=$2
  result=$(curl -s -u "$OPNSENSE_API_KEY:$OPNSENSE_API_SECRET" \
    -X POST "$OPNSENSE_API_URL/caddy/reverse_proxy/setAccessList/$uuid" \
    -H 'Content-Type: application/json' \
    -d "$updated_config")
  expected_result='{"result":"saved"}'

  if [[ "$(echo "$result" | jq -c .)" == "$(echo "$expected_result" | jq -c .)" ]]; then
    return 0
  else
    return 1
  fi
}

# Validate the new config
validate_caddy_config() {
  result=$(curl -s -u "$OPNSENSE_API_KEY:$OPNSENSE_API_SECRET" \
    -X GET "$OPNSENSE_API_URL/caddy/service/validate")

    
  expected_result='{"status":"ok","message":"Caddy configuration is valid."}'
  if [[ "$(echo "$result" | jq -c .)" == "$(echo "$expected_result" | jq -c .)" ]]; then
    return 0
  else
    return 1
  fi
}


# Reconfigure caddy
reconfigure_caddy() {
  result=$(curl -s -u "$OPNSENSE_API_KEY:$OPNSENSE_API_SECRET" \
    -X POST "$OPNSENSE_API_URL/caddy/service/reconfigure" \
    -H 'Content-Type: application/json' \
    -d "{}")

  expected_result='{"status":"ok"}'
  if [[ "$(echo "$result" | jq -c .)" == "$(echo "$expected_result" | jq -c .)" ]]; then
    return 0
  else
    return 1
  fi
}



# Get the script location
SCRIPT_DIR=$( cd -- "$( dirname -- "${BASH_SOURCE[0]}" )" &> /dev/null && pwd )
pushd $SCRIPT_DIR > /dev/null 2>&1

# Get the current IP of the external domain
new_ip=$(get_current_ip "$EXTERNAL_DOMAIN")
if [[ -z "$new_ip" ]]; then
  echo "[ERROR] Failed to resolve IP for $EXTERNAL_DOMAIN. Exiting."
  exit 1
fi

echo "[INFO] Resolved $EXTERNAL_DOMAIN to $new_ip."

# Parse the old IP from the file or access list
if [[ -f "$OLD_IP_FILE" ]]; then
  old_ip=$(cat "$OLD_IP_FILE")
else
  echo "[ERROR] Old IP address must be set first in the file $OLD_IP_FILE, adjacent to this script."
  exit 1
fi

if [[ -z "$old_ip" ]]; then
  echo "[ERROR] No existing IP found in the access list or file for $EXTERNAL_DOMAIN. Exiting."
  exit 1
fi

echo "[INFO] Found old IP $old_ip in the access list."

# Check if we have changed
if [[ $old_ip == $new_ip ]]; then
  echo "[INFO] Old IP $old_ip matches new IP $new_ip. Exiting."
  exit 1
fi

# Fetch the subdomain configuration
subdomain_config=$(fetch_subdomain_config)
if [[ -z "$subdomain_config" ]]; then
  echo "[ERROR] Failed to fetch subdomain configuration. Exiting."
  exit 1
fi

# Extract the UUID for the specified access list name
access_list_uuid=$(echo "$subdomain_config" | jq -r ".subdomain.accesslist | to_entries[] | select(.value.value | contains(\"$ACCESS_LIST_NAME\")) | .key")
if [[ -z "$access_list_uuid" ]]; then
  echo "[ERROR] Failed to find UUID for the access list '$ACCESS_LIST_NAME'. Exiting."
  exit 1
fi

echo "[INFO] Found UUID for access list '$ACCESS_LIST_NAME': $access_list_uuid."

# Fetch the access list details
access_list_details=$(fetch_access_list "$access_list_uuid")
if [[ -z "$access_list_details" ]]; then
  echo "[ERROR] Failed to fetch access list details. Exiting."
  exit 1
fi

# Replace the old IP with the new IP in the access list
updated_access_list=$(echo "$access_list_details" | jq --arg old "$old_ip" --arg new "$new_ip" \
  '.accesslist.clientIps |= 
    with_entries(
      if .key == $old then 
        {key: $new, value: {value: $new, selected: .value.selected}} 
      else . end
    )')
    
# Update the access list with the new configuration
transformed_updated_access_list=$(echo "$updated_access_list" | jq '{
  accesslist: {
    accesslistName: .accesslist.accesslistName,
    clientIps: ( .accesslist.clientIps | to_entries | map(.value.value) | join(",") ),
    accesslistInvert: .accesslist.accesslistInvert,
    HttpResponseCode: "",
    HttpResponseMessage: "",
    description: .accesslist.description
  }
}')
update_response=$(update_access_list "$access_list_uuid" "$transformed_updated_access_list")
if [[ $? -ne 0 ]]; then
  echo "[ERROR] Failed to update the access list. Exiting."
  exit 1
fi

echo "[INFO] Successfully updated the access list: replaced $old_ip with $new_ip."

# Validate the configuration
validate_config=$(validate_caddy_config)
if [[ $? -ne 0 ]]; then
  echo "[ERROR] Failed to validate Caddy configuration. Exiting."
  exit 1
fi

echo  "[INFO] Caddy configuration validated successfully."

# Reconfigure caddy
reconfigured=$(reconfigure_caddy)
if [[ $? -ne 0 ]]; then
  echo "[ERROR] Failed to apply changes to Caddy configuration. Exiting."
  exit 1
fi

echo "[INFO] Configuration changes to Caddy have been applied."

# Store the new IP in the file for future reference
echo "$new_ip" > "$OLD_IP_FILE"
echo "[INFO] Old IP was saved to $OLD_IP_FILE."

echo "[INFO] Successfully executed. Exiting."
