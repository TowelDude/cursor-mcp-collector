#!/bin/bash

# Create a temporary directory for collecting files
COLLECTED_MCP_DIR=$(mktemp -d)

# Function to check if a file exists and copy it
copy_if_exists() {
    local source_file="$1"
    local dest_name="${2:-mcp_$(basename $(dirname "$source_file")).json}"
    
    if [ -f "$source_file" ]; then
        echo "Found mcp.json at: $source_file"
        cp "$source_file" "$COLLECTED_MCP_DIR/$dest_name"
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
    
    # Check for local settings in .cursor directory
    if [ -d "$workspace_path/.cursor" ]; then
        if [ -f "$workspace_path/.cursor/mcp.json" ]; then
            copy_if_exists "$workspace_path/.cursor/mcp.json"
        fi
    fi
}

# Function to collect global settings
collect_global_settings() {
    local global_settings="$HOME/.cursor/mcp.json"
    if [ -f "$global_settings" ]; then
        echo "Found global settings at: $global_settings"
        cp "$global_settings" "$COLLECTED_MCP_DIR/global_settings.json"
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

# Create zip archive
echo "Creating zip archive..."
zip -r /tmp/collected_mcp.zip "$COLLECTED_MCP_DIR"

# Cleanup
echo "Cleaning up temporary files..."
rm -rf "$COLLECTED_MCP_DIR"

echo "Collection complete. Check /tmp/collected_mcp.zip for the files."

