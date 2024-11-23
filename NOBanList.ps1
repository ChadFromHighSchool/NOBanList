# Temporarily set execution policy to Bypass to allow the script to run
Set-ExecutionPolicy -Scope Process -ExecutionPolicy Bypass -Force

# Public URL of the Google Doc
$publicDocUrl = "https://docs.google.com/document/d/e/2PACX-1vRRYsEtG7a-z03DPPDKPuZFMCJsfMTd7FprmTFhKnQA45G-o9O1MO1XHyMBcSaVre69KPcbOaB-W1sj/pub"

# Path to the blocklist file using $env:USERPROFILE
$blocklistPath = Join-Path -Path $env:USERPROFILE -ChildPath "AppData\LocalLow\Shockfront\NuclearOption\blocklist.txt"

# Regular expression pattern to match Steam IDs
$steamIdPattern = "\b7656119[0-9]{10}\b"

# Main script logic
Write-Output "Forcibly creating or overwriting blocklist at $blocklistPath..."

# Forcefully create or overwrite the blocklist file if it doesn't exist
try {
    if (-not (Test-Path -Path $blocklistPath)) {
        New-Item -Path $blocklistPath -ItemType File -Force
        Write-Output "File created at $blocklistPath."
    } else {
        Write-Output "Blocklist file already exists at $blocklistPath."
    }
} catch {
    Write-Error "Failed to create the blocklist file: $_"
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
$steamIds = [regex]::Matches($documentContent, $steamIdPattern) | ForEach-Object { $_.Value }

if ($steamIds.Count -gt 0) {
    Write-Output "Found $($steamIds.Count) Steam IDs."

    # Read existing IDs from the blocklist file
    $existingIds = @()
    if (Test-Path -Path $blocklistPath) {
        $existingIds = Get-Content -Path $blocklistPath
    }

    # Filter out any Steam IDs that already exist in the blocklist
    $newIds = $steamIds | Where-Object { $_ -notin $existingIds }

    if ($newIds.Count -gt 0) {
        # Append the new Steam IDs to the blocklist file
        try {
            if ((Get-Content $blocklistPath).Length -gt 0) {
                Add-Content -Path $blocklistPath -Value "`n"
            }
            Add-Content -Path $blocklistPath -Value ($newIds -join "`n")
            Write-Output "Successfully appended $($newIds.Count) new Steam IDs to $blocklistPath."
        } catch {
            Write-Error "Error appending to file: $_"
        }

        # Remove any extra blank lines from the blocklist file
        try {
            $content = Get-Content -Path $blocklistPath
            $content = $content | Where-Object { $_.Trim() -ne "" }
            Set-Content -Path $blocklistPath -Value ($content -join "`n")
            Write-Output "Cleaned the blocklist file, removed blank lines."
        } catch {
            Write-Error "Error cleaning up the blocklist file: $_"
        }
    } else {
        Write-Output "No new Steam IDs to append, all IDs already exist in the blocklist."
    }
} else {
    Write-Output "No Steam IDs found in the document."
}

# Remove any existing scheduled tasks related to Steam IDs
Write-Output "Removing any existing scheduled tasks with 'steamid' in the name..."
try {
    Get-ScheduledTask | Where-Object { $_.TaskName -match "steamid" } | ForEach-Object {
        Unregister-ScheduledTask -TaskName $_.TaskName -Confirm:$false
        Write-Output "Removed task: $($_.TaskName)"
    }
} catch {
    Write-Error "Error removing existing tasks: $_"
}

# Creating a scheduled task to run the script daily without a popup
$taskName = "RunSteamIDUpdate"
$scriptPath = $MyInvocation.MyCommand.Path

Write-Output "Creating scheduled task to run the script daily without a popup..."

# Define the action (running the PowerShell script in hidden mode)
$action = New-ScheduledTaskAction -Execute "powershell.exe" -Argument "-NoProfile -WindowStyle Hidden -File `"$scriptPath`""

# Define the trigger (daily at a specific time, e.g., 9 AM)
$trigger = New-ScheduledTaskTrigger -Daily -At "9:00AM"

# Define the task settings
$settings = New-ScheduledTaskSettingsSet

# Create the scheduled task
try {
    Register-ScheduledTask -Action $action -Trigger $trigger -TaskName $taskName -Description "Runs the script to update the blocklist daily without a popup."
    Write-Output "Scheduled task created successfully!"
} catch {
    Write-Error "Failed to create the scheduled task: $_"
}

# Move the script to the "NuclearOption" folder
Write-Output "Moving the script to the NuclearOption folder..."

# Get the current script path and define the destination path
$destinationFolder = Join-Path -Path $env:USERPROFILE -ChildPath "AppData\LocalLow\Shockfront\NuclearOption"
$destinationPath = Join-Path -Path $destinationFolder -ChildPath (Split-Path $scriptPath -Leaf)

# Check if the destination folder exists, create it if not
if (-not (Test-Path -Path $destinationFolder)) {
    New-Item -Path $destinationFolder -ItemType Directory -Force
}

# Move the script to the "NuclearOption" folder
try {
    Move-Item -Path $scriptPath -Destination $destinationPath -Force
    Write-Output "Script successfully moved to $destinationPath"
} catch {
    Write-Error "Failed to move the script: $_"
}
