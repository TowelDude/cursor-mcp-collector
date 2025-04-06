#!/bin/bash

# Splunk settings
SPLUNK_ENABLED=true  # Set to false to disable Splunk integration
SPLUNK_URL="https://hec.example.com:8088"
SPLUNK_TOKEN="your-auth-token"
SPLUNK_INDEX="your-index"
SPLUNK_SOURCETYPE="your-sourcetype"

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
        curl -s "$SPLUNK_URL/services/collector/event" \
            -H "Authorization: Splunk $SPLUNK_TOKEN" \
            -d "{
                \"index\": \"$SPLUNK_INDEX\",
                \"sourcetype\": \"$SPLUNK_SOURCETYPE\",
                \"event\": {
                    \"workspace\": \"$workspace_name\",
                    \"content\": $(cat "$json_file")
                }
            }"
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
    
    # Check for local settings in .cursor directory
    if [ -d "$workspace_path/.cursor" ]; then
        if [ -f "$workspace_path/.cursor/mcp.json" ]; then
            process_file "$workspace_path/.cursor/mcp.json" "mcp_${workspace_name}.json" "$workspace_name"
        fi
    fi
}

# Function to collect global settings
collect_global_settings() {
    local global_settings="$HOME/.cursor/mcp.json"
    if [ -f "$global_settings" ]; then
        echo "Found global settings at: $global_settings"
        if [ "$SPLUNK_ENABLED" = false ]; then
            cp "$global_settings" "$COLLECTED_MCP_DIR/mcp_global.json"
        else
            send_to_splunk "$global_settings" "global"
        fi
    fi
}

# Function to collect workspace settings
collect_workspace_settings() {
    local workspace_storage="$HOME/Library/Application Support/Cursor/User/workspaceStorage"
    
    if [ ! -d "$workspace_storage" ]; then
        echo "Cursor workspace storage not found at: $workspace_storage"
        return 1
    fi
    
    echo "Searching for workspaces in Cursor's storage..."
    
    # Find all workspace.json files and process them
    find "$workspace_storage" -type f -name "workspace.json" | while read -r workspace_file; do
        local workspace_path=$(get_workspace_path "$workspace_file")
        
        if [ ! -z "$workspace_path" ]; then
            echo "Found workspace at: $workspace_path"
            check_workspace "$workspace_path"
        fi
    done
}

# Main execution
echo "Starting mcp.json collection..."

# Collect global settings
collect_global_settings

# Collect workspace settings
collect_workspace_settings

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
    echo "Collection complete. Files have been sent to Splunk."
fi

