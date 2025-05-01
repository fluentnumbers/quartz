# Configuration
$sourceFolder = "C:\Users\andre\OneDrive\Documents\obsidian-notes"  # Replace with your source folder path
$targetFolder = "C:\Users\andre\Documents\repositories\quartz\content"  # Replace with your target folder path
$publishStrings = @('publish: "true"', 'publish: true')  # Both formats to search for
$unpublishStrings = @('publish: "false"', 'publish: false')  # Formats that indicate file should not be published
$logFile = "C:\Users\andre\Documents\repositories\quartz\content\sync_log.txt"     # Replace with your desired log file path

# List of folders to ignore (relative to sourceFolder)
$ignoreFolders = @(
    ".git",
    ".obsidian",
    "node_modules",
    "temp",
    "cache",
    ".trash",
    ".obsidian.mobile",
    ".smart-connections",
    ".obsidian-mobile"
)

# List of files to preserve in destination (relative to targetFolder)
$preserveFiles = @(
    "index.md",
    "tags.md",
    "search.md",
    "assets/logo.png",
    "assets/favicon.ico",
    "assets/icons/*",
    "assets/profile.png"
)

# Create target folder if it doesn't exist
if (-not (Test-Path $targetFolder)) {
    New-Item -ItemType Directory -Path $targetFolder -Force | Out-Null
}

# Function to check if a path should be ignored
function Test-ShouldIgnorePath {
    param (
        [string]$Path
    )
    foreach ($ignoreFolder in $ignoreFolders) {
        $ignorePattern = [regex]::Escape($ignoreFolder)
        if ($Path -match "\\$ignorePattern\\" -or $Path -match "\\$ignorePattern$") {
            return $true
        }
    }
    return $false
}

# Function to check if file is in assets/published directory
function Test-IsPublishedAsset {
    param (
        [string]$Path
    )
    return $Path -match "\\assets\\published\\"
}

# Function to check if file should be preserved
function Test-ShouldPreserve {
    param (
        [string]$Path
    )
    $relativePath = $Path.Substring($targetFolder.Length)
    foreach ($preserveFile in $preserveFiles) {
        if ($preserveFile -like "*") {
            # Handle wildcard patterns
            $pattern = $preserveFile -replace "\*", ".*"
            if ($relativePath -match "^$pattern$") {
                return $true
            }
        } else {
            # Handle exact matches
            if ($preserveFiles -contains $relativePath) {
                return $true
            }
        }
    }
    return $false
}

# Function to check if file contains any of the search strings
function Test-FileContainsString {
    param (
        [string]$FilePath,
        [string[]]$SearchStrings
    )
    try {
        $content = Get-Content -Path $FilePath -Raw -ErrorAction Stop
        foreach ($searchString in $SearchStrings) {
            if ($content -match [regex]::Escape($searchString)) {
                return $true
            }
        }
        return $false
    }
    catch {
        Write-Output "Error reading file $FilePath : $_" | Out-File -FilePath $logFile -Append
        return $false
    }
}

# Function to check if file should be published
function Test-ShouldPublish {
    param (
        [string]$FilePath
    )
    # Always publish files from assets/published
    if (Test-IsPublishedAsset -Path $FilePath) {
        return $true
    }
    # First check if file contains unpublish flag
    if (Test-FileContainsString -FilePath $FilePath -SearchStrings $unpublishStrings) {
        return $false
    }
    # Then check if file contains publish flag
    return (Test-FileContainsString -FilePath $FilePath -SearchStrings $publishStrings)
}

# Function to copy file while maintaining relative path
function Copy-FileWithRelativePath {
    param (
        [string]$SourceFile,
        [string]$SourceRoot,
        [string]$TargetRoot
    )

    $relativePath = $SourceFile.Substring($SourceRoot.Length)
    $targetPath = Join-Path $TargetRoot $relativePath
    $targetDir = Split-Path $targetPath -Parent

    # Create target directory if it doesn't exist
    if (-not (Test-Path $targetDir)) {
        New-Item -ItemType Directory -Path $targetDir -Force | Out-Null
    }

    # Copy the file
    Copy-Item -Path $SourceFile -Destination $targetPath -Force
    Write-Output "$(Get-Date): Copied $SourceFile to $targetPath" | Out-File -FilePath $logFile -Append
}

# Function to get all files that should be in the destination
function Get-SourceFiles {
    param (
        [string]$Path
    )
    $files = @()
    Get-ChildItem -Path $Path -Recurse -File | ForEach-Object {
        if (-not (Test-ShouldIgnorePath -Path $_.FullName)) {
            if (Test-ShouldPublish -FilePath $_.FullName) {
                $relativePath = $_.FullName.Substring($sourceFolder.Length)
                $files += $relativePath
            }
        }
    }
    return $files
}

# Function to get all files currently in the destination
function Get-DestinationFiles {
    param (
        [string]$Path
    )
    $files = @()
    if (Test-Path $Path) {
        Get-ChildItem -Path $Path -Recurse -File | ForEach-Object {
            $relativePath = $_.FullName.Substring($targetFolder.Length)
            $files += $relativePath
        }
    }
    return $files
}

# Function to perform sync
function Sync-Files {
    # Get lists of files
    $sourceFiles = Get-SourceFiles -Path $sourceFolder
    $destinationFiles = Get-DestinationFiles -Path $targetFolder

    # Check all files in destination against source
    foreach ($file in $destinationFiles) {
        $sourceFile = Join-Path $sourceFolder $file
        $targetFile = Join-Path $targetFolder $file

        # Skip if file should be preserved
        if (Test-ShouldPreserve -Path $targetFile) {
            Write-Output "$(Get-Date): Preserving $targetFile (protected file)" | Out-File -FilePath $logFile -Append
            continue
        }

        if (Test-Path $sourceFile) {
            # File exists in source, check if it should be published
            if (-not (Test-ShouldPublish -FilePath $sourceFile)) {
                # File exists but should not be published
                Remove-Item $targetFile -Force
                Write-Output "$(Get-Date): Deleted $targetFile (marked as unpublished or missing publish flag)" | Out-File -FilePath $logFile -Append
            }
        } else {
            # File doesn't exist in source, delete it
            Remove-Item $targetFile -Force
            Write-Output "$(Get-Date): Deleted $targetFile (no longer exists in source)" | Out-File -FilePath $logFile -Append
        }
    }

    # Copy new and updated files
    foreach ($file in $sourceFiles) {
        $sourceFile = Join-Path $sourceFolder $file
        $targetFile = Join-Path $targetFolder $file
        Copy-FileWithRelativePath -SourceFile $sourceFile -SourceRoot $sourceFolder -TargetRoot $targetFolder
    }

    # Clean up empty directories in destination
    Get-ChildItem -Path $targetFolder -Recurse -Directory | Sort-Object -Property FullName -Descending | ForEach-Object {
        if ((Get-ChildItem -Path $_.FullName -Recurse -Force | Measure-Object).Count -eq 0) {
            Remove-Item $_.FullName -Force
            Write-Output "$(Get-Date): Removed empty directory $($_.FullName)" | Out-File -FilePath $logFile -Append
        }
    }
}

# Initial sync
Write-Output "$(Get-Date): Starting initial sync..." | Out-File -FilePath $logFile -Append
Sync-Files
Write-Output "$(Get-Date): Initial sync completed." | Out-File -FilePath $logFile -Append

# Set up file system watcher
$watcher = New-Object System.IO.FileSystemWatcher
$watcher.Path = $sourceFolder
$watcher.IncludeSubdirectories = $true
$watcher.EnableRaisingEvents = $true

# Define the action to take when a file is changed
$action = {
    $path = $Event.SourceEventArgs.FullPath
    $changeType = $Event.SourceEventArgs.ChangeType
    $timestamp = (Get-Date).ToString("yyyy-MM-dd HH:mm:ss")

    # Check if the path should be ignored
    $shouldIgnore = $false
    foreach ($ignoreFolder in $ignoreFolders) {
        if ($path -match [regex]::Escape($ignoreFolder)) {
            $shouldIgnore = $true
            break
        }
    }

    if (-not $shouldIgnore) {
        Write-Output "$timestamp : $changeType detected in $path" | Out-File -FilePath $logFile -Append
        Sync-Files
    }
}

# Register the event handlers
Register-ObjectEvent -InputObject $watcher -EventName Created -Action $action
Register-ObjectEvent -InputObject $watcher -EventName Changed -Action $action
Register-ObjectEvent -InputObject $watcher -EventName Deleted -Action $action
Register-ObjectEvent -InputObject $watcher -EventName Renamed -Action $action

Write-Output "$(Get-Date): File monitoring started. Press Ctrl+C to stop." | Out-File -FilePath $logFile -Append

# Keep the script running
try {
    while ($true) { Start-Sleep -Seconds 1 }
}
finally {
    # Cleanup
    $watcher.EnableRaisingEvents = $false
    $watcher.Dispose()
    Write-Output "$(Get-Date): File monitoring stopped." | Out-File -FilePath $logFile -Append
}
