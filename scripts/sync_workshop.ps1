# sync_workshop.ps1 -- Sync Phobos PZ mods from Git repos to Workshop staging folders
#
# NOTE: The $ModRegistry paths below are specific to the author's dev machine.
#       Update RepoRoot and WorkshopMod values to match your local environment.
#
# PZ's built-in Workshop uploader uploads the ENTIRE Contents/ folder -- there is no
# ignore mechanism. This script populates each mod's staging folder using a WHITELIST
# approach: only game-relevant files are copied. Everything else (.git/, .claude/,
# .github/, docs/, markdown files, LICENSE, etc.) is excluded by never being touched.
#
# Usage:
#   pwsh -ExecutionPolicy Bypass -File "C:\SteamCMD\sync_workshop.ps1"
#   pwsh -ExecutionPolicy Bypass -File "C:\SteamCMD\sync_workshop.ps1" -ModName PCP
#   pwsh -ExecutionPolicy Bypass -File "C:\SteamCMD\sync_workshop.ps1" -DryRun
#
# Parameters:
#   -ModName   Sync only one mod: PCP, PhobosLib, EPRCleanup, PIP, or All (default: All)
#   -DryRun    Show what would be done without modifying anything

param(
    [ValidateSet("All", "PCP", "PhobosLib", "EPRCleanup", "PIP")]
    [string]$ModName = "All",

    [switch]$DryRun
)

$ErrorActionPreference = "Stop"

# -----------------------------------------------------------------------------
# Mod Registry -- single source of truth for all Phobos mods
# -----------------------------------------------------------------------------

$ModRegistry = [ordered]@{
    PCP = @{
        RepoRoot    = "D:\SynologyDrive\phobosdthorga\CloudStation Drive\Google Drive\Gekko-Data\Documents\GitHub\phobosdthorga\mod-pz-chemistry-pathways"
        WorkshopMod = "C:\Users\phobo\Zomboid\Workshop\PhobosChemistryPathways\Contents\mods\PhobosChemistryPathways"
        DisplayName = "PhobosChemistryPathways"
    }
    PhobosLib = @{
        RepoRoot    = "D:\SynologyDrive\phobosdthorga\CloudStation Drive\Google Drive\Gekko-Data\Documents\GitHub\phobosdthorga\mod-pz-phobos-lib"
        WorkshopMod = "C:\Users\phobo\Zomboid\Workshop\PhobosLib\Contents\mods\PhobosLib"
        DisplayName = "PhobosLib"
    }
    EPRCleanup = @{
        RepoRoot    = "D:\SynologyDrive\phobosdthorga\CloudStation Drive\Google Drive\Gekko-Data\Documents\GitHub\phobosdthorga\mod-pz-epr-cleanup"
        WorkshopMod = "C:\Users\phobo\Zomboid\Workshop\PhobosEPRCleanup\Contents\mods\PhobosEPRCleanup"
        DisplayName = "PhobosEPRCleanup"
    }
    PIP = @{
        RepoRoot    = "D:\SynologyDrive\phobosdthorga\CloudStation Drive\Google Drive\Gekko-Data\Documents\GitHub\phobosdthorga\mod-pz-industrial-pathology"
        WorkshopMod = "C:\Users\phobo\Zomboid\Workshop\PhobosIndustrialPathology\Contents\mods\PhobosIndustrialPathology"
        DisplayName = "PhobosIndustrialPathology"
    }
}

# Patterns that must NEVER appear in the staging folder
$ForbiddenPatterns = @(".git", ".claude", ".github", "docs", ".gitignore", ".gitattributes")
$ForbiddenExtensions = @("*.md")

# -----------------------------------------------------------------------------
# Helper: Copy a single file if it exists in the source
# -----------------------------------------------------------------------------

function Copy-IfExists {
    param(
        [string]$Source,
        [string]$Destination,
        [switch]$DryRun
    )
    $fileName = Split-Path $Source -Leaf
    if (Test-Path $Source) {
        if ($DryRun) {
            Write-Host "    [DRY RUN] Would copy: $fileName"
        } else {
            $destDir = Split-Path $Destination -Parent
            if (-not (Test-Path $destDir)) {
                New-Item -ItemType Directory -Path $destDir -Force | Out-Null
            }
            Copy-Item $Source $Destination -Force
            Write-Host "    Copied: $fileName"
        }
        return $true
    }
    return $false
}

# -----------------------------------------------------------------------------
# Helper: Snapshot all files in a directory (relative path -> size + timestamp)
# -----------------------------------------------------------------------------

function Get-FileSnapshot {
    param([string]$Directory)
    $snapshot = @{}
    if ((Test-Path $Directory) -and (Get-ChildItem $Directory -Recurse -File -ErrorAction SilentlyContinue)) {
        foreach ($file in (Get-ChildItem $Directory -Recurse -File)) {
            $relPath = $file.FullName.Substring($Directory.Length).TrimStart('\')
            $snapshot[$relPath] = @{
                Size      = $file.Length
                LastWrite = $file.LastWriteTime.ToString("o")
            }
        }
    }
    return $snapshot
}

# -----------------------------------------------------------------------------
# Helper: Diff two snapshots and print a change summary
# -----------------------------------------------------------------------------

function Write-ChangeSummary {
    param(
        [hashtable]$Before,
        [hashtable]$After,
        [switch]$IsFirstRun
    )

    $maxPerCategory = 20

    # First-run shortcut: everything is "added", just show count
    if ($IsFirstRun) {
        $count = $After.Count
        Write-Host "  Changes: first sync (+$count files)" -ForegroundColor Cyan
        return
    }

    # Compute diff
    $added   = @()
    $changed = @()
    $removed = @()

    foreach ($key in $After.Keys) {
        if (-not $Before.ContainsKey($key)) {
            $added += $key
        } elseif ($Before[$key].Size -ne $After[$key].Size -or $Before[$key].LastWrite -ne $After[$key].LastWrite) {
            $changed += $key
        }
    }
    foreach ($key in $Before.Keys) {
        if (-not $After.ContainsKey($key)) {
            $removed += $key
        }
    }

    # No changes
    if ($added.Count -eq 0 -and $changed.Count -eq 0 -and $removed.Count -eq 0) {
        Write-Host "  Changes: no changes detected (up to date)" -ForegroundColor DarkGray
        return
    }

    # Summary line
    $parts = @()
    if ($added.Count   -gt 0) { $parts += "+$($added.Count) added" }
    if ($changed.Count -gt 0) { $parts += "~$($changed.Count) changed" }
    if ($removed.Count -gt 0) { $parts += "-$($removed.Count) removed" }
    Write-Host "  Changes: $($parts -join ', ')" -ForegroundColor White

    # Detail lines (capped)
    $added  | Sort-Object | Select-Object -First $maxPerCategory | ForEach-Object { Write-Host "    + $_" -ForegroundColor Green }
    if ($added.Count -gt $maxPerCategory) {
        Write-Host "    ... and $($added.Count - $maxPerCategory) more added" -ForegroundColor Green
    }

    $changed | Sort-Object | Select-Object -First $maxPerCategory | ForEach-Object { Write-Host "    ~ $_" -ForegroundColor Yellow }
    if ($changed.Count -gt $maxPerCategory) {
        Write-Host "    ... and $($changed.Count - $maxPerCategory) more changed" -ForegroundColor Yellow
    }

    $removed | Sort-Object | Select-Object -First $maxPerCategory | ForEach-Object { Write-Host "    - $_" -ForegroundColor Red }
    if ($removed.Count -gt $maxPerCategory) {
        Write-Host "    ... and $($removed.Count - $maxPerCategory) more removed" -ForegroundColor Red
    }
}

# -----------------------------------------------------------------------------
# Helper: robocopy /MIR wrapper with exit-code handling
# -----------------------------------------------------------------------------

function Mirror-Directory {
    param(
        [string]$Source,
        [string]$Destination,
        [string]$Label,
        [switch]$DryRun
    )
    if (-not (Test-Path $Source)) {
        return $true  # nothing to mirror is not an error
    }
    if ($DryRun) {
        Write-Host "  [DRY RUN] Would robocopy /MIR: $Label"
    } else {
        Write-Host "  Mirroring $Label ... " -NoNewline
        $robocopyArgs = @(
            $Source; $Destination
            "/MIR"
            "/NFL"; "/NDL"; "/NJH"; "/NJS"; "/NC"; "/NS"; "/NP"
        )
        & robocopy @robocopyArgs | Out-Null
        if ($LASTEXITCODE -ge 8) {
            Write-Host "FAILED (exit code $LASTEXITCODE)" -ForegroundColor Red
            return $false
        }
        Write-Host "done"
    }
    return $true
}

# -----------------------------------------------------------------------------
# Helper: Copy version-folder root files (mod.info, icon.png, poster.png)
# -----------------------------------------------------------------------------

function Copy-VersionFolderRootFiles {
    param(
        [string]$SourceDir,
        [string]$DestDir,
        [string]$Label,
        [switch]$DryRun
    )
    if (-not (Test-Path $SourceDir)) { return }
    Write-Host "  Copying $Label root files:"
    if (-not $DryRun) {
        New-Item -ItemType Directory -Path $DestDir -Force | Out-Null
    }
    Copy-IfExists "$SourceDir\mod.info"   "$DestDir\mod.info"   -DryRun:$DryRun | Out-Null
    Copy-IfExists "$SourceDir\poster.png" "$DestDir\poster.png" -DryRun:$DryRun | Out-Null
    Copy-IfExists "$SourceDir\icon.png"   "$DestDir\icon.png"   -DryRun:$DryRun | Out-Null
}

# -----------------------------------------------------------------------------
# Core: Sync a single mod from repo to Workshop staging
# -----------------------------------------------------------------------------

function Sync-PZMod {
    param(
        [string]$Key,
        [hashtable]$Mod,
        [int]$Index,
        [int]$Total,
        [switch]$DryRun
    )

    $repo = $Mod.RepoRoot
    $dest = $Mod.WorkshopMod
    $name = $Mod.DisplayName

    Write-Host ""
    Write-Host "[$Index/$Total] $name" -ForegroundColor Cyan
    Write-Host "  Source: $repo"
    Write-Host "  Target: $dest"

    # -- Detect folder layout --
    # Multi-version: common/ + 42.14/ + 42.15/ (PCP v1.7.0+, PhobosLib v1.20.0+)
    # Legacy:        42/ + optional common/    (EPRCleanup, older mods)
    $isMultiVersion = (Test-Path "$repo\42.14") -and (Test-Path "$repo\42.15")
    if ($isMultiVersion) {
        Write-Host "  Layout: multi-version (common + 42.14 + 42.15)" -ForegroundColor DarkGray
    } else {
        Write-Host "  Layout: legacy (42 + common)" -ForegroundColor DarkGray
    }

    # -- Step 0: Snapshot before state --
    $isFirstRun = -not (Test-Path $dest) -or
                  (Get-ChildItem $dest -Recurse -File -ErrorAction SilentlyContinue).Count -eq 0
    $beforeSnapshot = Get-FileSnapshot $dest

    # -- Step 1: Validate source --
    if (-not (Test-Path "$repo\mod.info")) {
        Write-Host "  ERROR: mod.info not found in repo!" -ForegroundColor Red
        return $false
    }

    # -- Step 2: Clean destination --
    if (Test-Path $dest) {
        if ($DryRun) {
            Write-Host "  [DRY RUN] Would delete: $dest"
        } else {
            Write-Host "  Cleaning target... " -NoNewline
            Remove-Item $dest -Recurse -Force
            Write-Host "done"
        }
    }

    if (-not $DryRun) {
        New-Item -ItemType Directory -Path $dest -Force | Out-Null
    }

    # -- Step 3: Copy root-level game files --
    Write-Host "  Copying root files:"
    Copy-IfExists "$repo\mod.info"    "$dest\mod.info"    -DryRun:$DryRun | Out-Null
    Copy-IfExists "$repo\poster.png"  "$dest\poster.png"  -DryRun:$DryRun | Out-Null
    Copy-IfExists "$repo\icon.png"    "$dest\icon.png"    -DryRun:$DryRun | Out-Null

    # -- Step 4: Copy content (layout-dependent) --
    if ($isMultiVersion) {
        # --- Multi-version layout: common/ + 42.14/ + 42.15/ ---

        # 4a: Mirror common/media/
        if (-not (Mirror-Directory "$repo\common\media" "$dest\common\media" "common\media\" -DryRun:$DryRun)) {
            return $false
        }

        # 4b: Copy 42.14/ root files + mirror media/
        Copy-VersionFolderRootFiles "$repo\42.14" "$dest\42.14" "42.14\" -DryRun:$DryRun
        if (-not (Mirror-Directory "$repo\42.14\media" "$dest\42.14\media" "42.14\media\" -DryRun:$DryRun)) {
            return $false
        }

        # 4c: Copy 42.15/ root files + mirror media/
        Copy-VersionFolderRootFiles "$repo\42.15" "$dest\42.15" "42.15\" -DryRun:$DryRun
        if (-not (Mirror-Directory "$repo\42.15\media" "$dest\42.15\media" "42.15\media\" -DryRun:$DryRun)) {
            return $false
        }
    } else {
        # --- Legacy layout: 42/ + optional common/ ---

        # 4a: Copy 42/ root files
        Copy-VersionFolderRootFiles "$repo\42" "$dest\42" "42\" -DryRun:$DryRun

        # 4b: Mirror 42/media/
        if (Test-Path "$repo\42\media") {
            if (-not (Mirror-Directory "$repo\42\media" "$dest\42\media" "42\media\" -DryRun:$DryRun)) {
                return $false
            }
        } else {
            Write-Host "  WARNING: 42\media\ not found in repo!" -ForegroundColor Yellow
        }

        # 4c: Mirror common/media/ if it exists
        if (Test-Path "$repo\common\media") {
            if (-not (Mirror-Directory "$repo\common\media" "$dest\common\media" "common\media\" -DryRun:$DryRun)) {
                return $false
            }
        } elseif (Test-Path "$repo\common") {
            # common/ exists but has no media/ — just create the directory
            if (-not $DryRun) {
                New-Item -ItemType Directory -Path "$dest\common" -Force | Out-Null
            }
            Write-Host "  Created: common\"
        }
    }

    # -- Step 5: Verification --
    if (-not $DryRun) {
        $fileCount = (Get-ChildItem $dest -Recurse -File).Count
        $forbidden = @()

        # Check for forbidden directories
        foreach ($pattern in $ForbiddenPatterns) {
            $found = Get-ChildItem $dest -Directory -Filter $pattern -Recurse -Force -ErrorAction SilentlyContinue
            if ($found) {
                $forbidden += $found.FullName
            }
        }

        # Check for forbidden file extensions (*.md)
        foreach ($ext in $ForbiddenExtensions) {
            $found = Get-ChildItem $dest -File -Filter $ext -Recurse -Force -ErrorAction SilentlyContinue
            if ($found) {
                $forbidden += $found.FullName
            }
        }

        if ($forbidden.Count -gt 0) {
            Write-Host "  Verification: $fileCount files, $($forbidden.Count) FORBIDDEN ITEMS" -ForegroundColor Red
            foreach ($f in $forbidden) {
                Write-Host "    !! $f" -ForegroundColor Red
            }
            return $false
        } else {
            Write-Host "  Verification: $fileCount files, 0 forbidden items" -ForegroundColor Green
        }
    } else {
        Write-Host "  [DRY RUN] Verification skipped"
    }

    # -- Step 6: Change summary --
    if (-not $DryRun) {
        $afterSnapshot = Get-FileSnapshot $dest
        Write-ChangeSummary -Before $beforeSnapshot -After $afterSnapshot -IsFirstRun:$isFirstRun
    } else {
        Write-Host "  [DRY RUN] Change summary skipped"
    }

    return $true
}

# -----------------------------------------------------------------------------
# Main
# -----------------------------------------------------------------------------

# Select which mods to sync
if ($ModName -eq "All") {
    $modsToSync = $ModRegistry.Keys
} else {
    if (-not $ModRegistry.Contains($ModName)) {
        Write-Error "Unknown mod: $ModName. Valid values: $($ModRegistry.Keys -join ', '), All"
        exit 1
    }
    $modsToSync = @($ModName)
}

$total = $modsToSync.Count

Write-Host "============================================" -ForegroundColor White
if ($DryRun) {
    Write-Host " Phobos Workshop Sync [DRY RUN] - $total mod(s)" -ForegroundColor Yellow
} else {
    Write-Host " Phobos Workshop Sync - $total mod(s)" -ForegroundColor White
}
Write-Host "============================================" -ForegroundColor White

$index = 0
$warnings = 0

foreach ($key in $modsToSync) {
    $index++
    $result = Sync-PZMod -Key $key -Mod $ModRegistry[$key] -Index $index -Total $total -DryRun:$DryRun
    if (-not $result) {
        $warnings++
    }
}

Write-Host ""
Write-Host "============================================" -ForegroundColor White
if ($warnings -gt 0) {
    Write-Host " Done. $warnings mod(s) had warnings!" -ForegroundColor Red
} else {
    Write-Host " All $total mod(s) synced successfully." -ForegroundColor Green
}
Write-Host ""
Write-Host " REMINDER: preview.png at each Workshop root" -ForegroundColor DarkGray
Write-Host " (e.g. Workshop\PhobosLib\preview.png) is NOT" -ForegroundColor DarkGray
Write-Host " managed by this script -- manually placed." -ForegroundColor DarkGray
Write-Host "============================================" -ForegroundColor White
