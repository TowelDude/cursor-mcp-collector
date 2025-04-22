#!/bin/bash

# Get the currently logged-in user
CURRENT_USER=$(stat -f%Su /dev/console)

# Check if the logged-in user was identified
if [ -z "$CURRENT_USER" ]; then
    echo "No user is currently logged in. Exiting."
    exit 1
fi

# Define variables
USER_HOME=$(dscl . -read /Users/"$CURRENT_USER" NFSHomeDirectory | awk '{print $2}')

# Splunk settings
SPLUNK_ENABLED=true  # Set to false to disable Splunk integration
SPLUNK_URL="https://hec.example.com:8088"
SPLUNK_TOKEN="your-auth-token"
SPLUNK_INDEX="your-index"
SPLUNK_SOURCETYPE="your-sourcetype"

# Initialize counter for files sent to Splunk
FILES_SENT=0

# Get hostname
HOSTNAME=$(hostname)

# Create a temporary directory only if Splunk is disabled
if [ "$SPLUNK_ENABLED" = false ]; then
    COLLECTED_MCP_DIR=$(mktemp -d)
fi

# Function to send JSON to Splunk
send_to_splunk() {
    local json_file="$1"
    local workspace_name="$2"
    
    if [ "$SPLUNK_ENABLED" = true ]; then
        echo "Sending $json_file to Splunk..."
        if curl -sS "$SPLUNK_URL/services/collector/event" \
            -H "Authorization: Splunk $SPLUNK_TOKEN" \
            -d "{
                \"index\": \"$SPLUNK_INDEX\",
                \"sourcetype\": \"$SPLUNK_SOURCETYPE\",
                \"event\": {
                    \"host\": \"$HOSTNAME\",
                    \"workspace\": \"$workspace_name\",
                    \"content\": $(cat "$json_file")
                }
            }"; then
            FILES_SENT=$((FILES_SENT + 1))
        fi
        echo
    fi
}

# Function to check if a file exists and process it
process_file() {
    local source_file="$1"
    local dest_name="$2"
    local workspace_name="$3"
    
    if [ -f "$source_file" ]; then
        echo "Found mcp.json at: $source_file"
        if [ "$SPLUNK_ENABLED" = false ]; then
            cp "$source_file" "$COLLECTED_MCP_DIR/$dest_name"
        else
            send_to_splunk "$source_file" "$workspace_name"
        fi
    fi
}

# Function to extract and normalize workspace path from workspace.json
get_workspace_path() {
    local workspace_file="$1"
    grep -o '"folder": *"[^"]*"' "$workspace_file" | cut -d'"' -f4 | sed 's|^file://||'
}

# Function to check a workspace for mcp.json files
check_workspace() {
    local workspace_path="$1"
    local workspace_name=$(basename "$workspace_path")
    local app_name="$2"
    
    app_lowercase=$(echo "$app_name" | tr '[:upper:]' '[:lower:]')
    # Check for local settings in app's directory
    if [ -d "$workspace_path/.$app_lowercase" ]; then
        if [ -f "$workspace_path/.$app_lowercase/mcp.json" ]; then
            process_file "$workspace_path/.$app_lowercase/mcp.json" "mcp_${workspace_name}.json" "$workspace_name"
        fi
    fi
}

# Function to collect global settings
collect_cursor_global_settings() {
    local global_settings="$USER_HOME/.cursor/mcp.json"
    if [ -f "$global_settings" ]; then
        echo "Found global settings at: $global_settings"
        if [ "$SPLUNK_ENABLED" = false ]; then
            cp "$global_settings" "$COLLECTED_MCP_DIR/mcp_global.json"
        else
            send_to_splunk "$global_settings" "global"
        fi
    fi
}

# Function to collect Claude Desktop settings
collect_claude_desktop_settings() {
    local claude_desktop_settings="$USER_HOME/Library/Application Support/Claude/claude_desktop_config.json"
    if [ -f "$claude_desktop_settings" ]; then
        echo "Found Claude Desktop settings at: $claude_desktop_settings"
        if [ "$SPLUNK_ENABLED" = false ]; then
            cp "$claude_desktop_settings" "$COLLECTED_MCP_DIR/claude_desktop_config.json"
        else
            send_to_splunk "$claude_desktop_settings" "claude_desktop"
        fi
    fi
}

# Function to collect workspace settings
collect_workspace_settings() {
    local app_name=$1
    local workspace_storage="$USER_HOME/Library/Application Support/$app_name/User/workspaceStorage"
    
    if [ ! -d "$workspace_storage" ]; then
        echo "$app_name workspace storage not found at: $workspace_storage"
        return 1
    fi
    
    echo "Searching for workspaces in $app_name's storage..."
    
    # Process each workspace.json file
    while IFS= read -r workspace_file; do
        local workspace_path=$(get_workspace_path "$workspace_file")
        
        if [ ! -z "$workspace_path" ]; then
            echo "Found workspace at: $workspace_path"
            check_workspace "$workspace_path" "$app_name"
        fi
    done < <(find "$workspace_storage" -type f -name "workspace.json")
}

# Function to send "no files found" event to Splunk
send_no_files_event() {
    if [ "$SPLUNK_ENABLED" = true ]; then
        echo "Sending no-files-found event to Splunk..."
        curl -sS "$SPLUNK_URL/services/collector/event" \
            -H "Authorization: Splunk $SPLUNK_TOKEN" \
            -d "{
                \"index\": \"$SPLUNK_INDEX\",
                \"sourcetype\": \"$SPLUNK_SOURCETYPE\",
                \"event\": {
                    \"host\": \"$HOSTNAME\",
                    \"workspace\": \"global\",
                    \"content\": \"{\"error\":\"No mcp.json files were found for user $CURRENT_USER\"}\"
                }
            }"
        echo
    fi
}

# Main execution
echo "Starting mcp.json collection for user: $CURRENT_USER..."

# Collect cursor's global settings
collect_cursor_global_settings

# Collect Claude Desktop global settings
collect_claude_desktop_settings

# Collect workspace settings from Cursor and VSCode
collect_workspace_settings "Cursor"
collect_workspace_settings "Code"


# Create zip archive only if Splunk is disabled
if [ "$SPLUNK_ENABLED" = false ]; then
    echo "Creating zip archive..."
    cd "$COLLECTED_MCP_DIR"
    zip -r /tmp/collected_mcp.zip ./*
    echo "Collection complete. Check /tmp/collected_mcp.zip for the files."
    
    # Cleanup
    echo "Cleaning up temporary files..."
    rm -rf "$COLLECTED_MCP_DIR"
else
    if [ $FILES_SENT -gt 0 ]; then
        echo "Collection complete. $FILES_SENT files have been sent to Splunk."
    else
        echo "Collection complete. No mcp.json files were found to send to Splunk."
        send_no_files_event
    fi
fi

