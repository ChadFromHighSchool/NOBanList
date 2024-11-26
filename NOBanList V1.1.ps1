# Temporarily set execution policy to Bypass to allow the script to run
Set-ExecutionPolicy -Scope Process -ExecutionPolicy Bypass -Force

# Public URL of the Google Doc
$publicDocUrl = "https://docs.google.com/document/d/e/2PACX-1vRRYsEtG7a-z03DPPDKPuZFMCJsfMTd7FprmTFhKnQA45G-o9O1MO1XHyMBcSaVre69KPcbOaB-W1sj/pub"

# Path to the blocklist file using $env:USERPROFILE
$blocklistPath = Join-Path -Path $env:USERPROFILE -ChildPath "AppData\LocalLow\Shockfront\NuclearOption\blocklist.txt"

# Regular expression pattern to match Steam IDs
$steamIdPattern = "\b7656119[0-9]{10}\b"

# Scheduled task name
$taskName = "RunSteamIDUpdate"

# Remove existing scheduled tasks with similar names
Write-Output "Checking for and removing any existing tasks named like 'steamid'..."
try {
    Get-ScheduledTask | Where-Object { $_.TaskName -like "*steamid*" } | ForEach-Object {
        Unregister-ScheduledTask -TaskName $_.TaskName -Confirm:$false
        Write-Output "Removed scheduled task: $($_.TaskName)"
    }
} catch {
    Write-Output "No existing tasks with 'steamid' in the name found or error encountered: $_"
}

# Main script logic
Write-Output "Ensuring blocklist exists at $blocklistPath..."

# Ensure the blocklist file exists
try {
    if (-not (Test-Path -Path $blocklistPath)) {
        New-Item -Path $blocklistPath -ItemType File -Force
        Write-Output "File created at $blocklistPath."
    }
} catch {
    Write-Error "Failed to ensure blocklist file existence: $_"
}

# Fetch the document content
Write-Output "Fetching document content..."
try {
    $response = Invoke-WebRequest -Uri $publicDocUrl -Method Get
    if ($response.StatusCode -eq 200) {
        $documentContent = $response.Content
    } else {
        Write-Error "Failed to fetch document. HTTP Status Code: $($response.StatusCode)"
        return
    }
} catch {
    Write-Error "Error fetching document: $_"
    return
}

# Extract Steam IDs from the document content
Write-Output "Extracting Steam IDs..."
$docSteamIds = [regex]::Matches($documentContent, $steamIdPattern) | ForEach-Object { $_.Value }

if ($docSteamIds.Count -eq 0) {
    Write-Output "No Steam IDs found in the document."
    $docSteamIds = @() # Ensure it's an empty array
}

# Read existing IDs from the blocklist file
Write-Output "Reading existing blocklist IDs..."
$existingIds = @()
if (Test-Path -Path $blocklistPath) {
    $existingIds = Get-Content -Path $blocklistPath | Where-Object { $_.Trim() -ne "" }
}

# Compute the IDs to be removed and added
$idsToRemove = $existingIds | Where-Object { $_ -notin $docSteamIds }
$idsToAdd = $docSteamIds | Where-Object { $_ -notin $existingIds }

# Remove IDs no longer in the Google Doc
if ($idsToRemove.Count -gt 0) {
    Write-Output "Removing IDs no longer in the Google Doc..."
    $updatedIds = $existingIds | Where-Object { $_ -notin $idsToRemove }
} else {
    $updatedIds = $existingIds
}

# Add new IDs from the Google Doc
if ($idsToAdd.Count -gt 0) {
    Write-Output "Adding new IDs from the Google Doc..."
    $updatedIds += $idsToAdd
}

# Write the updated list back to the blocklist file
try {
    Set-Content -Path $blocklistPath -Value ($updatedIds -join "`n")
    Write-Output "Blocklist updated successfully with $(($updatedIds).Count) IDs."
} catch {
    Write-Error "Failed to update the blocklist file: $_"
}

# Move the script to the "NuclearOption" folder
Write-Output "Moving the script to the NuclearOption folder..."

# Get the current script path and define the destination path
$destinationFolder = Join-Path -Path $env:USERPROFILE -ChildPath "AppData\LocalLow\Shockfront\NuclearOption"
$destinationPath = Join-Path -Path $destinationFolder -ChildPath "NOBanList V1.1.ps1"
$oldScriptPath = Join-Path -Path $destinationFolder -ChildPath "NoBanList.ps1"

# Check if the destination folder exists, create it if not
if (-not (Test-Path -Path $destinationFolder)) {
    New-Item -Path $destinationFolder -ItemType Directory -Force
}

# Remove old script if it exists
if (Test-Path -Path $oldScriptPath) {
    try {
        Remove-Item -Path $oldScriptPath -Force
        Write-Output "Old script 'NoBanList.ps1' removed successfully."
    } catch {
        Write-Error "Failed to remove old script: $_"
    }
}

# Move the new script to the "NuclearOption" folder
try {
    Move-Item -Path $MyInvocation.MyCommand.Path -Destination $destinationPath -Force
    Write-Output "Script successfully moved to $destinationPath"
} catch {
    Write-Error "Failed to move the script: $_"
    return
}

# Create a new scheduled task to run the script daily
Write-Output "Creating a new scheduled task to run the script daily..."

# Define the action (running the PowerShell script in hidden mode)
$action = New-ScheduledTaskAction -Execute "powershell.exe" -Argument "-NoProfile -WindowStyle Hidden -File `"$destinationPath`""

# Define the trigger (daily at a specific time, e.g., 9 AM)
$trigger = New-ScheduledTaskTrigger -Daily -At "9:00AM"

# Define the task settings
$settings = New-ScheduledTaskSettingsSet

# Register the task
try {
    Register-ScheduledTask -Action $action -Trigger $trigger -TaskName $taskName -Description "Runs the script to update the blocklist daily."
    Write-Output "Scheduled task '$taskName' created successfully and targets the updated script!"
} catch {
    Write-Error "Failed to create the scheduled task: $_"
}
