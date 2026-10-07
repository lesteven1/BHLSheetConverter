# Sheet Machine

Sheet Machine is a native macOS automation for converting Squarespace Commerce order exports into weekday CSV reports.

## Features

- Watches the Downloads folder for new Squarespace order CSV files.
- Prompts for Monday through Friday.
- Includes the selected weekday and every `Order Every Day` item.
- Carries student information across multi-line orders.
- Sorts students alphabetically by first name.
- Calculates the total item quantity.
- Saves the finished report to the Desktop as `Monday.csv`, `Tuesday.csv`, and so on.
- Runs locally without uploading order or student data.

## Output

Each report contains a total quantity followed by these columns:

1. Name
2. Quantity
3. Student Number
4. Variant

## Requirements

- macOS 13 or later
- Apple silicon Mac
- Xcode Command Line Tools to build from source

## Build

```bash
chmod +x build_installer.command
./build_installer.command
```

The build creates `Sheet Machine Installer.zip`. Generated applications, archives, CSV files, and student data are excluded from Git.

## Install

Download the installer from the repository's Releases page, extract it, open `Install Sheet Machine`, and click **Install**.

The current release is not Apple-notarized. macOS may require approval under **System Settings → Privacy & Security → Open Anyway**.

## Privacy

Sheet Machine processes CSV files entirely on the Mac. Do not commit Squarespace exports because they may contain personal information.
