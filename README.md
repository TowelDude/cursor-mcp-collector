# Guide: Locating mcp.json Files on MacOS

This guide explains where to find `mcp.json` files in Cursor workspaces on MacOS.

## File Locations

### Global Settings
The global settings file can be found at:
```
~/Library/Application Support/Cursor/User/settings.json
```

### Workspace Settings
Each workspace can have its own settings in the `.cursor` directory:
```
<WORKSPACE_PATH>/.cursor/mcp.json
```

## How to Find All Workspaces

1. Open Finder
2. Press `Cmd + Shift + G`
3. Enter this path:
   ```
   ~/Library/Application Support/Cursor/User/workspaceStorage
   ```
4. Look for folders containing `workspace.json` files
5. Open each `workspace.json` file in a text editor
6. Look for the `"folder"` property to find the actual workspace path
   - The path may be prefixed with `file://`
   - Example: `"folder": "file:///Users/username/Projects/my-project"`

## Notes
- Some workspaces may not have local settings
- The global settings file may not exist if no global settings have been saved
