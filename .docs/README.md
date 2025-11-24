# .docs Directory - Proxmox VE Documentation Management

Scripts for managing Proxmox VE Administration Guide documentation.

## Usage

Download and convert latest guide:
```bash
./UpdatePVEGuide.sh
```

Generate diff between versions:
```bash
./GenerateContentDiff.sh V9-1-1_01_PVEGuide V9-1-1_02_PVEGuide output.md
```

## Versioning

Format: `VX-Y-Z_NN_PVEGuide/`

Examples:
- `V9-1-1_01_PVEGuide/` - First download of version 9.1.1
- `V9-1-1_02_PVEGuide/` - Minor update (same version, new timestamp)
- `V9-2-0_01_PVEGuide/` - Major version update

## For Contributors

After cloning the repository:
```bash
cd .docs/
./UpdatePVEGuide.sh
```
