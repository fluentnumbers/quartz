$watcher.Renamed += {
    $relativePath = $_.FullPath.Substring($sourcePath.Length + 1)
    $destinationFile = Join-Path $destinationPath $relativePath

    # Create destination directory if it doesn't exist
    $destinationDir = Split-Path $destinationFile -Parent
    if (-not (Test-Path $destinationDir)) {
        New-Item -ItemType Directory -Path $destinationDir -Force | Out-Null
    }

    # Delete the old file from destination if it exists
    $oldRelativePath = $_.OldFullPath.Substring($sourcePath.Length + 1)
    $oldDestinationFile = Join-Path $destinationPath $oldRelativePath
    if (Test-Path $oldDestinationFile) {
        Remove-Item $oldDestinationFile -Force
        Write-Host "Removed old file: $oldDestinationFile"
    }

    # Copy the new file
    Copy-Item $_.FullPath $destinationFile -Force
    Write-Host "Moved file: $relativePath"
}
