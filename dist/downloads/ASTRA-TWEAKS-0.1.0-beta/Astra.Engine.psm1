Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'
$script:Catalog = (Get-Content -LiteralPath (Join-Path $PSScriptRoot 'catalog.json') -Raw -Encoding UTF8 | ConvertFrom-Json)
$script:DataRoot = Join-Path ([Environment]::GetFolderPath('LocalApplicationData')) 'AstraTweaks'
$script:Version = '0.1.0-beta'

function Get-AstraCatalog { return $script:Catalog }
function Get-AstraBuild { return [Environment]::OSVersion.Version.Build }
function Get-AstraSid { return [Security.Principal.WindowsIdentity]::GetCurrent().User.Value }

function Read-AstraRegistry($Path, $Name) {
    $key = [Microsoft.Win32.Registry]::CurrentUser.OpenSubKey($Path, $false)
    try {
        if ($null -eq $key -or $key.GetValueNames() -notcontains $Name) {
            return [pscustomobject]@{ Exists = $false; Kind = 'DWord'; Value = $null }
        }
        return [pscustomobject]@{ Exists = $true; Kind = $key.GetValueKind($Name).ToString(); Value = $key.GetValue($Name, $null, [Microsoft.Win32.RegistryValueOptions]::DoNotExpandEnvironmentNames) }
    } finally { if ($null -ne $key) { $key.Dispose() } }
}

function Test-AstraKey($Path) {
    try {
        $key = [Microsoft.Win32.Registry]::CurrentUser.OpenSubKey($Path, $false)
        if ($null -eq $key) { return $false }
        $key.Dispose(); return $true
    } catch { return $false }
}

function Write-AstraRegistry($Path, $Name, $State) {
    $key = [Microsoft.Win32.Registry]::CurrentUser.CreateSubKey($Path)
    try {
        if ($State.Exists) { $key.SetValue($Name, $State.Value, [Microsoft.Win32.RegistryValueKind]$State.Kind) }
        else { $key.DeleteValue($Name, $false) }
    } finally { $key.Dispose() }
}

function Test-AstraEqual($A, $B) {
    if ([bool]$A.Exists -ne [bool]$B.Exists) { return $false }
    if (-not $A.Exists) { return $true }
    return ($A.Kind -ceq $B.Kind -and (ConvertTo-Json -InputObject $A.Value -Compress) -ceq (ConvertTo-Json -InputObject $B.Value -Compress))
}

function Get-AstraTweakState($Tweak) {
    if ((Get-AstraBuild) -lt $Tweak.minBuild) { return 'Indisponible' }
    $equal = $true
    foreach ($setting in $Tweak.settings) {
        if (-not (Test-AstraKey $setting.path)) { return 'Indisponible' }
        $expected = [pscustomobject]@{ Exists = $true; Kind = $setting.kind; Value = $setting.value }
        if (-not (Test-AstraEqual (Read-AstraRegistry $setting.path $setting.name) $expected)) { $equal = $false }
    }
    if ($equal) { return 'Déjà configuré' }
    return 'Disponible'
}

function Get-AstraTweakPreview([string[]]$Ids) {
    foreach ($id in $Ids) {
        $tweak = @($script:Catalog | Where-Object id -CEQ $id)
        if ($tweak.Count -ne 1) { throw 'Réglage inconnu.' }
        foreach ($s in $tweak[0].settings) {
            $before = Read-AstraRegistry $s.path $s.name
            [pscustomobject]@{ Id=$id; Title=$tweak[0].title; Path=('HKCU\' + $s.path); Name=$s.name; Before=$(if ($before.Exists) { [string]$before.Value + ' (' + $before.Kind + ')' } else { '(valeur absente)' }); After=([string]$s.value + ' (' + $s.kind + ')'); Restart=$tweak[0].restart }
        }
    }
}

function Initialize-AstraStore {
    if (-not (Test-Path -LiteralPath $script:DataRoot)) { New-Item -ItemType Directory -Path $script:DataRoot -Force | Out-Null }
}

function Save-AstraOperation($Operation) {
    Initialize-AstraStore
    $path = Join-Path $script:DataRoot ($Operation.Id + '.json')
    $temp = $path + '.pending'
    $bytes = [Text.Encoding]::UTF8.GetBytes(($Operation | ConvertTo-Json -Depth 16))
    $stream = [IO.File]::Open($temp, [IO.FileMode]::Create, [IO.FileAccess]::Write, [IO.FileShare]::None)
    try { $stream.Write($bytes, 0, $bytes.Length); $stream.Flush($true) } finally { $stream.Dispose() }
    if ([IO.File]::Exists($path)) { [IO.File]::Replace($temp, $path, [NullString]::Value) }
    else { [IO.File]::Move($temp, $path) }
}

function Get-AstraHistory {
    if (-not (Test-Path -LiteralPath $script:DataRoot)) { return @() }
    $items = @(Get-ChildItem -LiteralPath $script:DataRoot -Filter '*.json' | Where-Object BaseName -Match '^\d{8}T\d{9}Z-[a-f0-9]{8}$' | ForEach-Object {
        try { Get-Content -LiteralPath $_.FullName -Raw -Encoding UTF8 | ConvertFrom-Json } catch { Write-Warning ('Journal illisible : ' + $_.Name) }
    })
    return @($items | Sort-Object Id -Descending)
}

function New-AstraOperation($Kind, $Title) {
    return [pscustomobject]@{
        Id = ([DateTime]::UtcNow.ToString('yyyyMMddTHHmmssfffZ') + '-' + [guid]::NewGuid().ToString('N').Substring(0,8))
        Time = [DateTime]::Now.ToString('yyyy-MM-dd HH:mm:ss'); Version = $script:Version
        Sid = Get-AstraSid; Kind = $Kind; Title = $Title; State = 'Prepared'
        Entries = @(); PreviousPlan = ''; CreatedPlan = ''; Error = ''
    }
}

function Assert-AstraNoPending {
    $pending = @(Get-AstraHistory | Where-Object { $_.State -in @('Prepared','Applying','RollbackFailed','RestoreFailed','Restoring') })
    if ($pending.Count) { throw 'Une opération incomplète doit être restaurée dans le Centre de restauration avant de continuer.' }
}

function Invoke-AstraTweaks {
    param([Parameter(Mandatory)][string[]]$Ids)
    Assert-AstraNoPending
    $selected = @($Ids | Select-Object -Unique)
    if (-not $selected.Count) { throw 'Sélectionnez au moins un réglage.' }
    $op = New-AstraOperation 'Registry' ('Réglages : ' + ($selected -join ', '))
    foreach ($id in $selected) {
        $tweak = @($script:Catalog | Where-Object id -CEQ $id)
        if ($tweak.Count -ne 1) { throw ('Réglage inconnu : ' + $id) }
        if ((Get-AstraTweakState $tweak[0]) -eq 'Indisponible') { throw ('Réglage non pris en charge : ' + $id) }
        foreach ($s in $tweak[0].settings) {
            $before = Read-AstraRegistry $s.path $s.name
            $after = [pscustomobject]@{ Exists = $true; Kind = $s.kind; Value = $s.value }
            if ($before.Exists -and $before.Kind -notin @('DWord','String')) { throw ('Type inattendu : ' + $id) }
            if (-not (Test-AstraEqual $before $after)) {
                $op.Entries += [pscustomobject]@{ TweakId = $id; Path = $s.path; Name = $s.name; Before = $before; After = $after; Attempted = $false; Restored = $false }
            }
        }
    }
    if (-not $op.Entries.Count) { throw 'Les réglages sélectionnés sont déjà configurés.' }
    Save-AstraOperation $op
    try {
        $op.State = 'Applying'; Save-AstraOperation $op
        foreach ($entry in $op.Entries) {
            if (-not (Test-AstraEqual (Read-AstraRegistry $entry.Path $entry.Name) $entry.Before)) { throw 'Une valeur a changé pendant la préparation. Opération annulée.' }
            $entry.Attempted = $true; Save-AstraOperation $op
            Write-AstraRegistry $entry.Path $entry.Name $entry.After
            if (-not (Test-AstraEqual (Read-AstraRegistry $entry.Path $entry.Name) $entry.After)) { throw ('Échec de vérification : ' + $entry.TweakId) }
        }
        $op.State = 'Applied'; Save-AstraOperation $op
    } catch {
        $op.Error = $_.Exception.Message
        try { Undo-AstraRegistry $op; $op.State = 'RolledBack' } catch { $op.State = 'RollbackFailed'; $op.Error += ' | ' + $_.Exception.Message }
        Save-AstraOperation $op
        throw ('Application interrompue. État : ' + $op.State + '. ' + $op.Error)
    }
    return $op
}

function Assert-AstraEntry($Entry) {
    $allowed = @($script:Catalog | Where-Object id -CEQ $Entry.TweakId | ForEach-Object settings | Where-Object { $_.path -ceq $Entry.Path -and $_.name -ceq $Entry.Name })
    if ($allowed.Count -ne 1) { throw 'Le journal contient une cible non autorisée.' }
    $expected = [pscustomobject]@{ Exists = $true; Kind = $allowed[0].kind; Value = $allowed[0].value }
    if (-not (Test-AstraEqual $Entry.After $expected)) { throw 'La valeur cible du journal est invalide.' }
    if ($Entry.Before.Exists -and $Entry.Before.Kind -notin @('DWord','String')) { throw 'Type de sauvegarde non pris en charge.' }
}

function Undo-AstraRegistry($Operation) {
    $entries = @($Operation.Entries); [array]::Reverse($entries)
    foreach ($entry in $entries) {
        Assert-AstraEntry $entry
        if (-not $entry.Attempted -or $entry.Restored) { continue }
        $current = Read-AstraRegistry $entry.Path $entry.Name
        if (-not (Test-AstraEqual $current $entry.After) -and -not (Test-AstraEqual $current $entry.Before)) { throw ('Conflit sur ' + $entry.TweakId + ' : valeur modifiée depuis ASTRA. Restauration arrêtée pour préserver ce changement.') }
        Write-AstraRegistry $entry.Path $entry.Name $entry.Before
        if (-not (Test-AstraEqual (Read-AstraRegistry $entry.Path $entry.Name) $entry.Before)) { throw ('Échec de restauration : ' + $entry.TweakId) }
        $entry.Restored = $true; Save-AstraOperation $Operation
    }
}

function Invoke-AstraPowerCfg([string[]]$Arguments) {
    $exe = Join-Path $env:SystemRoot 'System32\powercfg.exe'
    $result = & $exe @Arguments 2>&1
    if ($LASTEXITCODE -ne 0) { throw ('powercfg : ' + ($result -join ' ')) }
    return ($result -join "`n")
}

function Get-AstraActivePlan {
    $text = Invoke-AstraPowerCfg @('/getactivescheme')
    $match = [regex]::Match($text, '[a-fA-F0-9]{8}(-[a-fA-F0-9]{4}){3}-[a-fA-F0-9]{12}')
    if (-not $match.Success) { throw 'Impossible de lire le plan actif.' }
    return $match.Value.ToLowerInvariant()
}

function Test-AstraPlan($Id) {
    if ($Id -notmatch '^[a-f0-9]{8}(-[a-f0-9]{4}){3}-[a-f0-9]{12}$') { throw 'Identifiant de plan invalide.' }
}

function Get-AstraPowerValue($Plan, $Setting) {
    $query = Invoke-AstraPowerCfg @('/qh',$Plan,'SUB_PROCESSOR',$Setting)
    $matches = [regex]::Matches($query, '0x[0-9a-fA-F]{8}')
    if ($matches.Count -lt 2) { throw ('Impossible de vérifier le réglage d''alimentation : ' + $Setting) }
    # The documented query emits current AC and DC indexes last, regardless of display language.
    return [pscustomobject]@{ AC=[Convert]::ToInt32($matches[$matches.Count-2].Value.Substring(2),16); DC=[Convert]::ToInt32($matches[$matches.Count-1].Value.Substring(2),16) }
}

function Invoke-AstraPowerProfile {
    param([ValidateSet('Performance','Balanced','Eco')][string]$Profile)
    Assert-AstraNoPending
    $op = New-AstraOperation 'Power' ('ASTRA ' + $Profile)
    $op.PreviousPlan = Get-AstraActivePlan
    $op.CreatedPlan = [guid]::NewGuid().ToString()
    Save-AstraOperation $op
    try {
        $op.State = 'Applying'; Save-AstraOperation $op
        # Duplicate the user's current plan: manufacturer-specific settings stay intact.
        Invoke-AstraPowerCfg @('/duplicatescheme', $op.PreviousPlan, $op.CreatedPlan) | Out-Null
        Invoke-AstraPowerCfg @('/changename', $op.CreatedPlan, ('ASTRA ' + $Profile)) | Out-Null
        $epp = @{ Performance = 25; Balanced = 50; Eco = 80 }[$Profile]
        $maximum = if ($Profile -eq 'Eco') { '80' } else { '100' }
        # Keep idle behavior and battery limits modest; never force CPU minimum to 100%.
        foreach ($source in @('/setacvalueindex','/setdcvalueindex')) {
            Invoke-AstraPowerCfg @($source,$op.CreatedPlan,'SUB_PROCESSOR','PROCTHROTTLEMIN','5') | Out-Null
            Invoke-AstraPowerCfg @($source,$op.CreatedPlan,'SUB_PROCESSOR','PROCTHROTTLEMAX',$(if ($source -eq '/setdcvalueindex') { '80' } else { $maximum })) | Out-Null
        }
        # EPP support is hardware-dependent; do not claim compatibility when powercfg rejects it.
        Invoke-AstraPowerCfg @('/setacvalueindex',$op.CreatedPlan,'SUB_PROCESSOR','PERFEPP',[string]$epp) | Out-Null
        $minimum = Get-AstraPowerValue $op.CreatedPlan 'PROCTHROTTLEMIN'
        $maxValue = Get-AstraPowerValue $op.CreatedPlan 'PROCTHROTTLEMAX'
        $preference = Get-AstraPowerValue $op.CreatedPlan 'PERFEPP'
        if ($minimum.AC -ne 5 -or $minimum.DC -ne 5 -or $maxValue.AC -ne [int]$maximum -or $maxValue.DC -ne 80 -or $preference.AC -ne $epp) { throw 'La relecture du profil ne correspond pas aux valeurs demandées.' }
        Invoke-AstraPowerCfg @('/setactive',$op.CreatedPlan) | Out-Null
        if ((Get-AstraActivePlan) -ne $op.CreatedPlan) { throw 'Le profil actif ne correspond pas au profil créé.' }
        $op.State = 'Applied'; Save-AstraOperation $op
    } catch {
        $op.Error = $_.Exception.Message
        try { Undo-AstraPower $op; $op.State = 'RolledBack' } catch { $op.State = 'RollbackFailed'; $op.Error += ' | ' + $_.Exception.Message }
        Save-AstraOperation $op
        throw ('Profil non appliqué. ' + $op.Error)
    }
    return $op
}

function Undo-AstraPower($Operation) {
    Test-AstraPlan $Operation.PreviousPlan; Test-AstraPlan $Operation.CreatedPlan
    $current = Get-AstraActivePlan
    if ($current -eq $Operation.CreatedPlan) {
        Invoke-AstraPowerCfg @('/setactive',$Operation.PreviousPlan) | Out-Null
        if ((Get-AstraActivePlan) -ne $Operation.PreviousPlan) { throw 'Échec de restauration du plan précédent.' }
    } elseif ($current -ne $Operation.PreviousPlan) { throw 'Le plan actif a changé en dehors de cette opération. Restaurez manuellement le plan précédent puis réessayez.' }
    $plans = Invoke-AstraPowerCfg @('/list')
    if ($plans -match [regex]::Escape($Operation.CreatedPlan)) { Invoke-AstraPowerCfg @('/delete',$Operation.CreatedPlan) | Out-Null }
}

function Restore-AstraOperation {
    param([Parameter(Mandatory)][string]$Id)
    $history = @(Get-AstraHistory)
    $active = @($history | Where-Object { $_.State -in @('Applied','Prepared','Applying','RollbackFailed','RestoreFailed','Restoring') })
    if (-not $active.Count -or $active[0].Id -cne $Id) { throw 'Restaurez les opérations dans l''ordre inverse de leur application.' }
    $op = $active[0]
    if ($op.Sid -cne (Get-AstraSid)) { throw 'Cette sauvegarde appartient à un autre utilisateur Windows.' }
    $op.State = 'Restoring'; Save-AstraOperation $op
    try {
        if ($op.Kind -eq 'Registry') { Undo-AstraRegistry $op }
        elseif ($op.Kind -eq 'Power') { Undo-AstraPower $op }
        else { throw 'Type de journal inconnu.' }
        $op.State = 'Restored'; Save-AstraOperation $op
    } catch { $op.State = 'RestoreFailed'; $op.Error = $_.Exception.Message; Save-AstraOperation $op; throw }
    return $op
}

function Get-AstraSystem {
    $os = Get-CimInstance Win32_OperatingSystem
    $cpu = @(Get-CimInstance Win32_Processor)
    $gpu = @(Get-CimInstance Win32_VideoController | Select-Object Name,DriverVersion,CurrentRefreshRate)
    $disks = @(Get-CimInstance Win32_LogicalDisk -Filter 'DriveType=3' | Select-Object DeviceID,@{n='TotalGB';e={[math]::Round($_.Size/1GB,1)}},@{n='FreeGB';e={[math]::Round($_.FreeSpace/1GB,1)}})
    $defender = 'Non disponible'
    try { $mp = Get-MpComputerStatus -ErrorAction Stop; $defender = if ($mp.RealTimeProtectionEnabled) { 'Protection active' } else { 'Protection inactive ou autre antivirus' } } catch { }
    $firewall = 'Non disponible'
    try { $profiles = @(Get-NetFirewallProfile -ErrorAction Stop); $firewall = if (@($profiles | Where-Object { -not $_.Enabled }).Count) { 'Un profil est désactivé' } else { 'Profils actifs' } } catch { }
    return [pscustomobject]@{
        Version = $script:Version; Windows = $os.Caption; Build = $os.BuildNumber
        CPU = ($cpu.Name -join ', '); CpuLoad = [math]::Round(($cpu | Measure-Object LoadPercentage -Average).Average)
        Cores = ($cpu | Measure-Object NumberOfCores -Sum).Sum; Threads = ($cpu | Measure-Object NumberOfLogicalProcessors -Sum).Sum
        RamTotalGB = [math]::Round($os.TotalVisibleMemorySize/1MB,1); RamFreeGB = [math]::Round($os.FreePhysicalMemory/1MB,1)
        GPU = $gpu; Disks = $disks; Defender = $defender; Firewall = $firewall; ActivePlan = Get-AstraActivePlan
        Processes = @(Get-Process | Sort-Object WorkingSet64 -Descending | Select-Object -First 8 ProcessName,Id,@{n='MemoryMB';e={[math]::Round($_.WorkingSet64/1MB)}})
        MeasuredAt = [DateTime]::Now.ToString('s')
    }
}

function Get-AstraStartup {
    return @(Get-CimInstance Win32_StartupCommand | Select-Object Name,Command,Location,User)
}

function Measure-AstraNetwork {
    param([string]$Target = '1.1.1.1', [ValidateRange(4,30)][int]$Count = 6)
    $ip = $null
    if (-not [Net.IPAddress]::TryParse($Target, [ref]$ip)) { throw 'Saisissez une adresse IP (IPv4 ou IPv6), pas une commande ni une URL.' }
    $ping = New-Object Net.NetworkInformation.Ping
    $times = New-Object 'System.Collections.Generic.List[double]'
    $failures = 0
    try {
        for ($i=0; $i -lt $Count; $i++) {
            try { $reply = $ping.Send($ip, 800); if ($reply.Status -eq 'Success') { $times.Add([double]$reply.RoundtripTime) } else { $failures++ } }
            catch { $failures++ }
        }
    } finally { $ping.Dispose() }
    if (-not $times.Count) { return [pscustomobject]@{ Target=$Target; Samples=$Count; AverageMs=$null; JitterMs=$null; LossPercent=100; Note='Aucune réponse ICMP. Un pare-feu peut filtrer ce test.' } }
    $delta = @(); for ($i=1; $i -lt $times.Count; $i++) { $delta += [math]::Abs($times[$i]-$times[$i-1]) }
    return [pscustomobject]@{ Target=$Target; Samples=$Count; AverageMs=[math]::Round(($times | Measure-Object -Average).Average,2); JitterMs=$(if ($delta.Count) {[math]::Round(($delta | Measure-Object -Average).Average,2)} else {$null}); LossPercent=[math]::Round(100*$failures/$Count,1); Note='ICMP vers cette IP uniquement. Ne mesure pas la latence d''un serveur de jeu.' }
}

function Import-AstraFrameTimes {
    param([Parameter(Mandatory)][string]$Path)
    if ((Get-Item -LiteralPath $Path).Length -gt 20MB) { throw 'CSV limité à 20 Mo.' }
    $rows = @(Import-Csv -LiteralPath $Path)
    if ($rows.Count -lt 100) { throw 'Au moins 100 images sont nécessaires.' }
    $values = New-Object 'System.Collections.Generic.List[double]'
    foreach ($row in $rows) {
        $property = $row.PSObject.Properties['MsBetweenPresents']
        if ($null -eq $property) { $property = $row.PSObject.Properties['FrameTimeMs'] }
        $value = 0.0
        if ($null -eq $property -or -not [double]::TryParse([string]$property.Value,[Globalization.NumberStyles]::Float,[Globalization.CultureInfo]::InvariantCulture,[ref]$value) -or $value -le 0 -or [double]::IsInfinity($value) -or [double]::IsNaN($value)) { throw 'CSV invalide : colonne FrameTimeMs ou MsBetweenPresents, valeurs positives en millisecondes, décimales avec un point.' }
        $values.Add($value)
    }
    $sorted = @($values | Sort-Object -Descending)
    $one = [math]::Max(1,[math]::Ceiling($values.Count*0.01)); $pointOne = [math]::Max(1,[math]::Ceiling($values.Count*0.001))
    return [pscustomobject]@{
        Frames=$values.Count; AverageFPS=[math]::Round(1000/($values | Measure-Object -Average).Average,1)
        Low1Percent=[math]::Round(1000/($sorted | Select-Object -First $one | Measure-Object -Average).Average,1)
        Low01Percent=[math]::Round(1000/($sorted | Select-Object -First $pointOne | Measure-Object -Average).Average,1)
        DurationSeconds=[math]::Round(($values | Measure-Object -Sum).Sum/1000,2)
        Definition='Low = 1000 / moyenne des frametimes les plus lents (1 % ou 0,1 %). Comparer même scène, durée et réglages.'
    }
}

Export-ModuleMember -Function Get-AstraCatalog,Get-AstraTweakState,Get-AstraTweakPreview,Invoke-AstraTweaks,Get-AstraHistory,Restore-AstraOperation,Invoke-AstraPowerProfile,Get-AstraSystem,Get-AstraStartup,Measure-AstraNetwork,Import-AstraFrameTimes
