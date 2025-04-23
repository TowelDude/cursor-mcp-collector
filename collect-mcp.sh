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
    local app_type="$3"
    
    if [ "$SPLUNK_ENABLED" = true ]; then
        if curl -sS "$SPLUNK_URL/services/collector/event" \
            -H "Authorization: Splunk $SPLUNK_TOKEN" \
            -d "{
                \"index\": \"$SPLUNK_INDEX\",
                \"sourcetype\": \"$SPLUNK_SOURCETYPE\",
                \"source\": \"$json_file\",
                \"event\": {
                    \"host\": \"$HOSTNAME\",
                    \"workspace\": \"$workspace_name\",
                    \"app\": \"$app_type\",
                    \"content\": $(cat "$json_file")
                }
            }"; then
            FILES_SENT=$((FILES_SENT + 1))
            echo "Successfully sent $app_type settings from $json_file to Splunk"
        else
            echo "Failed to send $app_type settings from $json_file to Splunk"
        fi
    fi
}

# Function to check if a file exists and process it
process_file() {
    local source_file="$1"
    local dest_name="$2"
    local workspace_name="$3"
    local app_type="$4"
    
    if [ -f "$source_file" ]; then
        if [ "$SPLUNK_ENABLED" = false ]; then
            cp "$source_file" "$COLLECTED_MCP_DIR/$dest_name"
            echo "Collected $app_type settings from $source_file to $COLLECTED_MCP_DIR/$dest_name"
        else
            send_to_splunk "$source_file" "$workspace_name" "$app_type"
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
            process_file "$workspace_path/.$app_lowercase/mcp.json" "mcp_${workspace_name}.json" "$workspace_name" "${app_name}_workspace"
        fi
    fi
}

# Function to collect global settings
collect_cursor_global_settings() {
    local global_settings="$USER_HOME/.cursor/mcp.json"
    if [ -f "$global_settings" ]; then
        process_file "$global_settings" "cursor_mcp_global.json" "global" "Cursor_global"
    fi
}

collect_code_global_settings() {
    local global_settings="$USER_HOME/Library/Application Support/Code/User/settings.json"
    if [ -f "$global_settings" ]; then
        if grep -q '"mcp":' "$global_settings"; then
            process_file "$global_settings" "code_mcp_global.json" "global" "Code_global"
        fi
    fi
}

# Function to collect Claude Desktop settings
collect_claude_desktop_settings() {
    local claude_desktop_settings="$USER_HOME/Library/Application Support/Claude/claude_desktop_config.json"
    if [ -f "$claude_desktop_settings" ]; then
        process_file "$claude_desktop_settings" "claude_desktop_config.json" "global" "Claude_global"
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
            check_workspace "$workspace_path" "$app_name"
        fi
    done < <(find "$workspace_storage" -type f -name "workspace.json")
}

# Function to send "no files found" event to Splunk
send_no_files_event() {
    if [ "$SPLUNK_ENABLED" = true ]; then
        if curl -sS "$SPLUNK_URL/services/collector/event" \
            -H "Authorization: Splunk $SPLUNK_TOKEN" \
            -d "{
                \"index\": \"$SPLUNK_INDEX\",
                \"sourcetype\": \"$SPLUNK_SOURCETYPE\",
                \"source\": \"mcp_collector\",
                \"event\": {
                    \"host\": \"$HOSTNAME\",
                    \"workspace\": \"global\",
                    \"app\": \"all\",
                    \"content\": \"{\"error\":\"No mcp.json files were found for user $CURRENT_USER\"}\"
                }
            }"; then
            echo "Sent no-files-found notification to Splunk for user $CURRENT_USER"
        else
            echo "Failed to send no-files-found notification to Splunk"
        fi
    fi
}

collect_intellij_global_settings() {
    local global_settings=$(find "$USER_HOME/Library/Application Support/JetBrains" -name "llm.mcpServers.xml" -type f | head -n 1)
    if [ -f "$global_settings" ]; then
        process_file "$global_settings" "intellij_mcp_global.xml" "global" "IntelliJ_global"
    fi
}

collect_intellij_workspace_settings() {
    local recentProjects=$(find "$USER_HOME/Library/Application Support/JetBrains/IntelliJIdea*/options/recentProjects.xml" -type f | head -n 1)
    local sent_files=0

    # Process each recent project
    while IFS= read -r project_path; do
        # Extract project name from path
        local project_name=$(basename "$project_path")

        # only supported variable is $USER_HOME$. replace it with the actual path
        project_path="${project_path/\$USER_HOME\$/$USER_HOME}"

        if [ -f "$project_path/.idea/workspace.xml" ]; then
            if grep -q 'McpProject' "$project_path/.idea/workspace.xml"; then
                process_file "$project_path/.idea/workspace.xml" "intellij_workspace_${project_name}.xml" "$project_name" "IntelliJ_workspace"
                sent_files=$((sent_files + 1))
            fi
        fi

    done < <(grep -o '<entry key="[^"]*"' "$recentProjects" | cut -d'"' -f2)

    # fallback if previous method failed, assume root of all workspaces is at $USER_HOME/IdeaProjects/<project_name>/
    if [ $sent_files -eq 0 ]; then
        local project_path="$USER_HOME/IdeaProjects"
        local workspace_configuration_file=".idea/workspace.xml"
        
        if [ -d "$project_path" ]; then
            for project_name in $(ls "$project_path"); do
                local project_dir="$project_path/$project_name"
                local workspace_configuration_path="$project_dir/$workspace_configuration_file"
                
                if [ -d "$project_dir" ]; then
                    if [ -f "$workspace_configuration_path" ]; then
                        if grep -q 'McpProject' "$workspace_configuration_path"; then
                            process_file "$workspace_configuration_path" "intellij_workspace_${project_name}.xml" "$project_name" "IntelliJ_workspace"
                            sent_files=$((sent_files + 1))
                        fi
                    fi
                fi
            done
        fi
    fi

    if [ $sent_files -eq 0 ]; then
        echo "No IntelliJ workspaces found"
    fi
}

# Main execution
echo "Starting mcp.json collection for user: $CURRENT_USER..."

# Collect cursor's global settings
collect_cursor_global_settings

# Collect Claude Desktop global settings
collect_claude_desktop_settings

# Collect global settings from VSCode
collect_code_global_settings

collect_intellij_global_settings


# Collect workspace settings from Cursor and VSCode
collect_workspace_settings "Cursor"
collect_workspace_settings "Code"

# Collect workspace settings from IntelliJ
collect_intellij_workspace_settings

# Create zip archive only if Splunk is disabled
if [ "$SPLUNK_ENABLED" = false ]; then
    if [ -d "$COLLECTED_MCP_DIR" ] && [ "$(ls -A "$COLLECTED_MCP_DIR")" ]; then
        echo "Creating zip archive from collected files..."
        cd "$COLLECTED_MCP_DIR"
        zip -r /tmp/collected_mcp.zip ./*
        echo "Collection complete. Check /tmp/collected_mcp.zip for the files."
        
        # Cleanup
        echo "Cleaning up temporary files..."
        rm -rf "$COLLECTED_MCP_DIR"
    else
        echo "No files were collected to create zip archive."
    fi
else
    if [ $FILES_SENT -gt 0 ]; then
        echo "Collection complete. Successfully sent $FILES_SENT files to Splunk."
    else
        echo "Collection complete. No mcp.json files were found to send to Splunk."
        send_no_files_event
    fi
fi

