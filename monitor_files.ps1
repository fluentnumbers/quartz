# Configuration
$sourceFolder = "C:\Users\andre\OneDrive\Documents\obsidian-notes"  # Replace with your source folder path
$targetFolder = "C:\Users\andre\Documents\repositories\quartz\content"  # Replace with your target folder path
$publishStrings = @('publish: "true"', 'publish: true')  # Both formats to search for
$unpublishStrings = @('publish: "false"', 'publish: false')  # Formats that indicate file should not be published
$logFile = "C:\Users\andre\Documents\repositories\quartz\content\monitor_log.txt"     # Replace with your desired log file path

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

# Function to handle file changes
function Handle-FileChange {
    param (
        [string]$FilePath,
        [string]$ChangeType
    )

    # Check if the path should be ignored
    if (Test-ShouldIgnorePath -Path $FilePath) {
        Write-Output "$(Get-Date): Ignoring $FilePath (excluded folder)" | Out-File -FilePath $logFile -Append
        return
    }

    # Only process files, not directories
    if (Test-Path $FilePath -PathType Leaf) {
        $relativePath = $FilePath.Substring($sourceFolder.Length)
        $targetFile = Join-Path $targetFolder $relativePath

        # Check if file should be published
        $shouldPublish = Test-ShouldPublish -FilePath $FilePath

        if ($shouldPublish) {
            # File should be published, copy it
            Copy-FileWithRelativePath -SourceFile $FilePath -SourceRoot $sourceFolder -TargetRoot $targetFolder
        } else {
            # File should not be published, delete it if it exists in target
            if (Test-Path $targetFile) {
                Remove-Item $targetFile -Force
                Write-Output "$(Get-Date): Deleted $targetFile (marked as unpublished or missing publish flag)" | Out-File -FilePath $logFile -Append

                # Clean up empty parent directories
                $parentDir = Split-Path $targetFile -Parent
                while ($parentDir -ne $targetFolder) {
                    if ((Get-ChildItem -Path $parentDir -Recurse -Force | Measure-Object).Count -eq 0) {
                        Remove-Item $parentDir -Force
                        Write-Output "$(Get-Date): Removed empty directory $parentDir" | Out-File -FilePath $logFile -Append
                        $parentDir = Split-Path $parentDir -Parent
                    } else {
                        break
                    }
                }
            }
        }
    }
}

# Create FileSystemWatcher
$watcher = New-Object System.IO.FileSystemWatcher
$watcher.Path = $sourceFolder
$watcher.IncludeSubdirectories = $true
$watcher.EnableRaisingEvents = $true

# Define the action to take when a file is created, changed, or deleted
$action = {
    $path = $Event.SourceEventArgs.FullPath
    $changeType = $Event.SourceEventArgs.ChangeType

    switch ($changeType) {
        'Created' {
            Handle-FileChange -FilePath $path -ChangeType 'Created'
        }
        'Changed' {
            Handle-FileChange -FilePath $path -ChangeType 'Changed'
        }
        'Deleted' {
            $relativePath = $path.Substring($sourceFolder.Length)
            $targetFile = Join-Path $targetFolder $relativePath
            if (Test-Path $targetFile) {
                Remove-Item $targetFile -Force
                Write-Output "$(Get-Date): Deleted $targetFile (source file deleted)" | Out-File -FilePath $logFile -Append

                # Clean up empty parent directories
                $parentDir = Split-Path $targetFile -Parent
                while ($parentDir -ne $targetFolder) {
                    if ((Get-ChildItem -Path $parentDir -Recurse -Force | Measure-Object).Count -eq 0) {
                        Remove-Item $parentDir -Force
                        Write-Output "$(Get-Date): Removed empty directory $parentDir" | Out-File -FilePath $logFile -Append
                        $parentDir = Split-Path $parentDir -Parent
                    } else {
                        break
                    }
                }
            }
        }
        'Renamed' {
            $oldPath = $Event.SourceEventArgs.OldFullPath
            $newPath = $Event.SourceEventArgs.FullPath

            # Delete old file from destination if it exists
            $oldRelativePath = $oldPath.Substring($sourceFolder.Length)
            $oldTargetFile = Join-Path $targetFolder $oldRelativePath
            if (Test-Path $oldTargetFile) {
                Remove-Item $oldTargetFile -Force
                Write-Output "$(Get-Date): Deleted $oldTargetFile (file renamed)" | Out-File -FilePath $logFile -Append
            }

            # Handle the new file
            Handle-FileChange -FilePath $newPath -ChangeType 'Renamed'
        }
    }
}

# Register the event handlers
Register-ObjectEvent -InputObject $watcher -EventName "Created" -Action $action
Register-ObjectEvent -InputObject $watcher -EventName "Changed" -Action $action
Register-ObjectEvent -InputObject $watcher -EventName "Deleted" -Action $action
Register-ObjectEvent -InputObject $watcher -EventName "Renamed" -Action $action

# Initial scan of existing files
Write-Output "$(Get-Date): Starting initial scan of existing files..." | Out-File -FilePath $logFile -Append
Get-ChildItem -Path $sourceFolder -Recurse -File | ForEach-Object {
    if (-not (Test-ShouldIgnorePath -Path $_.FullName)) {
        if (Test-ShouldPublish -FilePath $_.FullName) {
            Copy-FileWithRelativePath -SourceFile $_.FullName -SourceRoot $sourceFolder -TargetRoot $targetFolder
        }
    }
}

Write-Output "$(Get-Date): Monitoring started. Press Ctrl+C to stop." | Out-File -FilePath $logFile -Append

# Keep the script running
try {
    while ($true) {
        Start-Sleep -Seconds 1
    }
}
finally {
    # Cleanup
    $watcher.EnableRaisingEvents = $false
    $watcher.Dispose()
    Write-Output "$(Get-Date): Monitoring stopped." | Out-File -FilePath $logFile -Append
}
