# ============================================================================
# Euro-Office Portable - lanceur
#
# Euro-Office (Qt/CEF) enregistre ses données dans :
#   %LOCALAPPDATA%\Euro-Office\DesktopEditors   (cache, polices, récupération, cookies)
#   HKCU\Software\Euro-Office\DesktopEditors    (langue, thème, options)
#
# Qt résout %LOCALAPPDATA% via l'API Windows (et non via la variable
# d'environnement) : on ne peut donc pas simplement la rediriger. Ce lanceur :
#   1. met de côté les données d'un Euro-Office installé sur le PC (s'il y en a) ;
#   2. crée une jonction %LOCALAPPDATA%\Euro-Office\DesktopEditors -> Data\DesktopEditors
#      (repli : copie aller-retour si la jonction est impossible) ;
#   3. importe les réglages du registre depuis Data\registry.reg ;
#   4. lance Euro-Office et attend la fermeture de tous ses processus ;
#   5. sauvegarde les réglages dans Data\, supprime la jonction et rétablit
#      l'état d'origine du PC.
# ============================================================================

# 'Continue' : sous Windows PowerShell 5.1, 'Stop' rendrait fatale la moindre
# sortie d'erreur de reg.exe ou robocopy. Les étapes critiques sont vérifiées
# explicitement.
$ErrorActionPreference = 'Continue'

$Root         = Split-Path -Parent $PSScriptRoot
$AppDir       = Join-Path $Root 'App'
$DataDir      = Join-Path $Root 'Data'
$PortableData = Join-Path $DataDir 'DesktopEditors'
$RegFile      = Join-Path $DataDir 'registry.reg'
$LogFile      = Join-Path $DataDir 'launcher.log'

$HostParent = Join-Path $env:LOCALAPPDATA 'Euro-Office'
$HostData   = Join-Path $HostParent 'DesktopEditors'
$HostBackup = Join-Path $HostParent 'DesktopEditors.portable-backup'
$RegKey     = 'HKCU\Software\Euro-Office\DesktopEditors'
$RegBackup  = Join-Path $env:TEMP 'euro-office-host-registry.reg'

function Write-Log([string]$Message) {
    $line = '{0}  {1}' -f (Get-Date -Format 'yyyy-MM-dd HH:mm:ss'), $Message
    Add-Content -LiteralPath $LogFile -Value $line -Encoding UTF8
}

function Stop-WithError([string]$Message) {
    Write-Log "ERREUR : $Message"
    Add-Type -AssemblyName System.Windows.Forms
    [System.Windows.Forms.MessageBox]::Show($Message, 'Euro-Office Portable', 'OK', 'Error') | Out-Null
    exit 1
}

function Test-Junction([string]$Path) {
    if (-not (Test-Path -LiteralPath $Path)) { return $false }
    $item = Get-Item -LiteralPath $Path -Force
    return [bool]($item.Attributes -band [IO.FileAttributes]::ReparsePoint)
}

function Remove-Junction([string]$Path) {
    # Supprime uniquement le lien, jamais le contenu de sa cible.
    if (Test-Junction $Path) { [IO.Directory]::Delete($Path, $false) }
}

function Test-RegKey {
    & reg.exe query $RegKey *> $null
    return ($LASTEXITCODE -eq 0)
}

function Get-AppProcess {
    # Processus lancés depuis le dossier App (application, CEF, convertisseur).
    Get-Process -ErrorAction SilentlyContinue |
        Where-Object { $_.Path -and $_.Path.StartsWith($AppPrefix, [StringComparison]::OrdinalIgnoreCase) }
}

function Start-EuroOffice {
    # Windows PowerShell 5.1 refuse un -ArgumentList vide : on ne le passe
    # que s'il y a des documents à ouvrir, chacun entre guillemets.
    $params = @{ FilePath = $Exe.FullName; WorkingDirectory = $Exe.DirectoryName }
    if ($DocumentArgs.Count -gt 0) {
        $params.ArgumentList = ($DocumentArgs | ForEach-Object { '"{0}"' -f $_ }) -join ' '
    }
    Start-Process @params -ErrorAction Stop | Out-Null
}

$DocumentArgs = @($args)

New-Item -ItemType Directory -Force -Path $DataDir, $PortableData | Out-Null

# --- Exécutable ---------------------------------------------------------------
$Exe = Get-Item -LiteralPath (Join-Path $AppDir 'DesktopEditors.exe') -ErrorAction SilentlyContinue
if (-not $Exe) {
    $Exe = Get-ChildItem -LiteralPath $AppDir -Recurse -Filter 'DesktopEditors.exe' -ErrorAction SilentlyContinue |
           Select-Object -First 1
}
if (-not $Exe) {
    Stop-WithError "DesktopEditors.exe est introuvable dans :`n$AppDir`n`nCopiez le contenu du ZIP portable d'Euro-Office dans ce dossier."
}
$AppPrefix = $AppDir.TrimEnd('\') + '\'

# --- Déjà lancé ? -------------------------------------------------------------
if (Get-AppProcess) {
    # L'instance portable est déjà ouverte : on lui transmet simplement les documents.
    try { Start-EuroOffice } catch { Stop-WithError "Impossible de lancer Euro-Office :`n$($_.Exception.Message)" }
    exit 0
}

Write-Log "Démarrage ($($Exe.FullName))"

# --- 1. Données d'une installation locale -------------------------------------
New-Item -ItemType Directory -Force -Path $HostParent | Out-Null

if (Test-Junction $HostData) {
    # Jonction laissée par une session précédente interrompue.
    Remove-Junction $HostData
}
if ((Test-Path -LiteralPath $HostData) -and -not (Test-Path -LiteralPath $HostBackup)) {
    Write-Log "Mise de côté des données locales -> $HostBackup"
    Rename-Item -LiteralPath $HostData -NewName (Split-Path -Leaf $HostBackup)
}
if (Test-Path -LiteralPath $HostData) {
    Stop-WithError "Impossible de libérer :`n$HostData`n`nUn Euro-Office installé sur ce PC est-il ouvert ? Fermez-le puis réessayez."
}

# --- 2. Jonction (ou copie) ---------------------------------------------------
$Mode = 'jonction'
& cmd.exe /c mklink /J "$HostData" "$PortableData" *> $null
if ($LASTEXITCODE -ne 0 -or -not (Test-Junction $HostData)) {
    Write-Log 'Jonction impossible : passage en mode copie.'
    $Mode = 'copie'
    New-Item -ItemType Directory -Force -Path $HostData | Out-Null
    & robocopy.exe $PortableData $HostData /E /R:1 /W:1 /NFL /NDL /NJH /NJS /NP *> $null
}
Write-Log "Mode : $Mode"

# --- 3. Registre --------------------------------------------------------------
$HadHostReg = Test-RegKey
if ($HadHostReg) {
    & reg.exe export $RegKey $RegBackup /y *> $null
    & reg.exe delete $RegKey /f *> $null
}
if (Test-Path -LiteralPath $RegFile) {
    & reg.exe import $RegFile *> $null
}

# --- 4. Lancement -------------------------------------------------------------
try {
    try {
        Start-EuroOffice
    } catch {
        Stop-WithError "Impossible de lancer Euro-Office :`n$($_.Exception.Message)"
    }

    # Euro-Office lance plusieurs processus (CEF, convertisseur) : on attend
    # qu'aucun processus du dossier App ne tourne plus.
    Start-Sleep -Seconds 3
    while (Get-AppProcess) {
        Start-Sleep -Seconds 2
    }
}
finally {
    # --- 5. Sauvegarde et restauration ----------------------------------------
    Write-Log 'Fermeture : sauvegarde des réglages.'

    if (Test-RegKey) {
        & reg.exe export $RegKey $RegFile /y *> $null
        & reg.exe delete $RegKey /f *> $null
    }
    if ($HadHostReg -and (Test-Path -LiteralPath $RegBackup)) {
        & reg.exe import $RegBackup *> $null
        Remove-Item -LiteralPath $RegBackup -Force
    }

    if ($Mode -eq 'jonction') {
        Remove-Junction $HostData
    } else {
        & robocopy.exe $HostData $PortableData /MIR /R:1 /W:1 /NFL /NDL /NJH /NJS /NP *> $null
        Remove-Item -LiteralPath $HostData -Recurse -Force -ErrorAction SilentlyContinue
    }

    if (Test-Path -LiteralPath $HostBackup) {
        Rename-Item -LiteralPath $HostBackup -NewName (Split-Path -Leaf $HostData)
    } elseif (-not (Get-ChildItem -LiteralPath $HostParent -Force -ErrorAction SilentlyContinue)) {
        Remove-Item -LiteralPath $HostParent -Force -ErrorAction SilentlyContinue
    }

    Write-Log 'Terminé.'
}
