# Cursor MCP Collector

A script to automatically collect and process Cursor's `mcp.json` configuration files from all workspaces. The script can either package the files into a zip archive or send them directly to a Splunk HTTP Event Collector (HEC).

## Features

- Automatically discovers all Cursor workspaces
- Collects both global and workspace-specific `mcp.json` files
- Two operation modes:
  - Zip collection: Packages all found files into a zip archive
  - Splunk integration: Sends files directly to Splunk HEC

## Prerequisites

- Bash shell
- `curl` (for Splunk integration)
- `zip` (for zip collection mode)

## Configuration

Edit the following settings at the top of the script:

```bash
# Splunk settings
SPLUNK_ENABLED=true  # Set to false to disable Splunk integration
SPLUNK_URL="https://hec.example.com:8088"
SPLUNK_TOKEN="your-auth-token"
SPLUNK_INDEX="your-index"
SPLUNK_SOURCETYPE="your-sourcetype"
```

## Operation Modes

### Zip Collection Mode
When `SPLUNK_ENABLED=false`:
- Creates a temporary directory
- Collects all `mcp.json` files
- Packages them into `/tmp/collected_mcp.zip`
- Cleans up temporary files

### Splunk Integration Mode
When `SPLUNK_ENABLED=true`:
- Discovers all `mcp.json` files
- Sends each file directly to Splunk HEC
- Includes workspace information in the event data
- No temporary files or zip archive created


For more details about manual collection, see [manual-collection.md](manual-collection.md).
