# Manual Collection of mcp.json Files

This document describes how to manually collect mcp.json files from Cursor workspaces.

## Global Settings

The global settings file is located at:
- macOS: `$HOME/.cursor/mcp.json`

## Workspace Settings

Workspace-specific settings are stored in the `.cursor` directory within each workspace:
- `workspace_path/.cursor/mcp.json`

## Workspace Storage Location

Cursor stores workspace information at:
- macOS: `$HOME/Library/Application Support/Cursor/User/workspaceStorage`

Each workspace has a unique identifier and a `workspace.json` file that contains the workspace path. 