#Requires -Version 5.1

<#
.SYNOPSIS
    Adds timestamps and location data to TeslaCam videos.

.DESCRIPTION
    This script processes a directory of TeslaCam footage. It reads event metadata to get GPS coordinates,
    retrieves the corresponding address, and then uses FFmpeg to burn the timestamp and location
    onto each video file.

.PARAMETER Directory
    The root directory containing the TeslaCam folders (e.g., "C:\TeslaCam").
    The script will search for subdirectories with a date-time name format like "YYYY-MM-DD_HH-MM-SS".

.EXAMPLE
    PS C:\> .\add_timestamp.ps1 -Directory "D:\TeslaCam Videos"
    This command will process all compatible video folders found in "D:\TeslaCam Videos".
#>

param(
    [Parameter(Mandatory=$true)]
    [string]$Directory
)

# --- Configuration ---
# Set the font path for the timestamp. Choose a font available on your system.
# Examples: "C:/Windows/Fonts/arial.ttf", "C:/Windows/Fonts/msyh.ttc" (Microsoft YaHei)
$fontPath = "C:/Windows/Fonts/arial.ttf"

# --- Script Body ---

# Path for the local ffmpeg executable
$localFfmpegPath = Join-Path $PSScriptRoot "ffmpeg\bin\ffmpeg.exe"
$ffmpegExecutable = "ffmpeg" # Default to assuming it's in PATH

# Function to check for required commands
function Test-CommandExists {
    param ([string]$command)
    return [bool](Get-Command $command -ErrorAction SilentlyContinue)
}

# Check for dependencies
if (-not (Test-CommandExists "ffmpeg")) {
    if (Test-Path $localFfmpegPath) {
        Write-Host "Found local ffmpeg instance."
        $ffmpegExecutable = $localFfmpegPath
    } else {
        Write-Warning "ffmpeg is required but not found in PATH or locally."
        $choice = Read-Host "Do you want to download and set up ffmpeg automatically? (y/n)"
        if ($choice -eq 'y') {
            Write-Host "Downloading ffmpeg (essentials build from gyan.dev)..."
            $downloadUrl = "https://www.gyan.dev/ffmpeg/builds/ffmpeg-release-essentials.zip"
            $zipPath = Join-Path $PSScriptRoot "ffmpeg.zip"
            $extractPath = $PSScriptRoot

            try {
                Invoke-WebRequest -Uri $downloadUrl -OutFile $zipPath
                Write-Host "Download complete. Extracting..."
                Expand-Archive -Path $zipPath -DestinationPath $extractPath -Force
                
                # Find the extracted directory (e.g., ffmpeg-6.0-essentials_build)
                $extractedDir = Get-ChildItem -Path $extractPath -Directory | Where-Object { $_.Name -like 'ffmpeg-*' } | Select-Object -First 1
                if ($null -eq $extractedDir) {
                    throw "Could not find the extracted ffmpeg directory."
                }

                # Rename it to a consistent name 'ffmpeg'
                $finalFfmpegDir = Join-Path $PSScriptRoot "ffmpeg"
                if (Test-Path $finalFfmpegDir) { Remove-Item -Recurse -Force $finalFfmpegDir }
                Rename-Item -Path $extractedDir.FullName -NewName "ffmpeg"

                Write-Host "Extraction complete. Cleaning up..."
                Remove-Item $zipPath

                $ffmpegExecutable = $localFfmpegPath
                Write-Host "ffmpeg is now set up at $ffmpegExecutable. Continuing script execution..."
            } catch {
                Write-Error "An error occurred during ffmpeg download or setup. Error: $_"
                Write-Host "Please install ffmpeg manually and ensure it's in your system's PATH."
                exit 1
            }
        } else {
            Write-Error "User cancelled setup. Please install ffmpeg manually to proceed."
            exit 1
        }
    }
}

# Function to process each video directory
function Process-TeslaCamDirectory {
    param ([string]$DirPath)

    # $event_file = Join-Path $DirPath "event.json"
    # $location = "Location not available"
    # # Get location information from event.json
    # if (Test-Path $event_file) {
    #     try {
    #         $eventData = Get-Content $event_file | ConvertFrom-Json
    #         $lat = $eventData.est_lat
    #         $lon = $eventData.est_lon
    #
    #         if ($lat -and $lon) {
    #             Write-Host "Fetching location for $lat, $lon..."
    #             try {
    #                 # Using OpenStreetMap's Nominatim API
    #                 $url = "https://nominatim.openstreetmap.org/reverse?format=json&lat=$lat&lon=$lon"
    #                 $response = Invoke-RestMethod -Uri $url -TimeoutSec 5 -UseBasicParsing
    #                 if ($response.display_name) {
    #                     $location = "$($response.display_name) ($lat, $lon)"
    #                 } else {
    #                     $location = "Location: $($lat)°N, $($lon)°E"
    #                 }
    #             } catch {
    #                 Write-Warning "Failed to fetch address from API. Error: $_"
    #                 $location = "Location: $($lat)°N, $($lon)°E"
    #             }
    #             Write-Host "Location found: $location"
    #         }
    #     } catch {
    #         Write-Warning "Could not parse event.json at $event_file. Error: $_"
    #         $location = "event.json invalid"
    #     }
    # } else {
    #     $location = "event.json not found"
    # }

    # Process video files in the directory
    Get-ChildItem -Path $DirPath -Filter *.mp4 | ForEach-Object {
        $video = $_.FullName
        $filename = $_.Name

        if ($filename -match '(\d{4}-\d{2}-\d{2})_(\d{2}-\d{2}-\d{2})') {
            $dateStr = $matches[1]
            $timeStr = $matches[2].Replace('-', ':')
            $fullDateTimeStr = "$dateStr $timeStr"

            try {
                # Convert file timestamp to a .NET DateTime object, then to Unix epoch seconds for ffmpeg
                $dateTime = [datetime]::ParseExact($fullDateTimeStr, 'yyyy-MM-dd HH:mm:ss', $null)
                $unixTimestamp = [int64]($dateTime.ToUniversalTime() - (Get-Date "1970-01-01")).TotalSeconds

                $output = $video.Replace('.mp4', '_timestamped.mp4')

                Write-Host "Processing: $filename"

                # Escape the font path for ffmpeg on Windows to handle the drive letter colon (e.g., C:)
                $escapedFontPath = $fontPath.Replace(':', '\:')

                # FFmpeg command for Windows.
                # -hwaccel can be changed for hardware acceleration if your ffmpeg build supports it.
                # For NVIDIA: -hwaccel cuda -c:v h264_nvenc
                # For Intel:  -hwaccel qsv -c:v h264_qsv
                # For AMD:    -hwaccel d3d11va -c:v h264_amf
                # Using software encoding (libx264) for broad compatibility.
                $ffmpegArgs = @(
                    '-i', "$video",
                    '-vf', "drawtext=fontfile='$escapedFontPath':text='%{pts\:localtime\:$unixTimestamp}':x=10:y=10:fontsize=50:fontcolor=white:box=1:boxcolor=black@0.5",
                    '-c:v', 'libx264', # Software encoder for compatibility
                    '-preset', 'fast', # Encoding speed/quality trade-off
                    '-crf', '22', # Constant Rate Factor for quality (lower is better)
                    '-pix_fmt', 'yuv420p',
                    '-movflags', '+faststart',
                    '-c:a', 'copy',
                    "$output"
                )
                
                & $ffmpegExecutable @ffmpegArgs

                Write-Host "Finished: $output"
            } catch {
                Write-Warning "Failed to process video $filename. Error: $_"
            }
        }
    }
}

# --- Main Execution ---

if (-not (Test-Path $Directory -PathType Container)) {
    Write-Error "Directory not found: $Directory"
    exit 1
}

$dirInfo = Get-Item -Path $Directory

# Check if the provided directory itself is a TeslaCam directory
if ($dirInfo.Name -match '^\d{4}-\d{2}-\d{2}_\d{2}-\d{2}-\d{2}$') {
    Write-Host "-- Processing single directory: $($dirInfo.FullName) --"
    Process-TeslaCamDirectory -DirPath $dirInfo.FullName
} else {
    # Find all subdirectories matching the TeslaCam format and process them
    Write-Host "Starting to search for directories in $Directory..."
    $subDirs = Get-ChildItem -Path $Directory -Directory -Recurse | Where-Object { $_.Name -match '^\d{4}-\d{2}-\d{2}_\d{2}-\d{2}-\d{2}$' }
    
    if ($null -eq $subDirs) {
        Write-Host "No subdirectories matching the TeslaCam format (YYYY-MM-DD_HH-MM-SS) were found in '$Directory'."
    } else {
        $subDirs | ForEach-Object {
            Write-Host "-- Found directory: $($_.FullName) --"
            Process-TeslaCamDirectory -DirPath $_.FullName
        }
    }
}

Write-Host "All videos processed."
