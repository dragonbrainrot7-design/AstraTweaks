param([switch]$SmokeTest, [string]$RenderPath, [ValidateSet('fr','en')][string]$Language, [switch]$RenderLanguagePage)
Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'
Add-Type -AssemblyName PresentationFramework,PresentationCore,WindowsBase
Import-Module (Join-Path $PSScriptRoot 'Astra.Engine.psm1') -Force -DisableNameChecking
Import-Module (Join-Path $PSScriptRoot 'Astra.Localization.psm1') -Force -DisableNameChecking
if (-not $Language) { $Language=Get-AstraSavedLanguage }
Set-AstraLanguage $Language
function T($Text) { return Get-AstraText ([string]$Text) }
$script:SystemReport = $null
$script:BenchA = $null; $script:BenchB = $null
$script:Choices = @{}
$mutex = New-Object Threading.Mutex($false, ('Local\AstraTweaks-' + [Security.Principal.WindowsIdentity]::GetCurrent().User.Value))
$ownsMutex = $false
try {
    try { $ownsMutex = $mutex.WaitOne(0) } catch [Threading.AbandonedMutexException] { $ownsMutex = $true }
    if (-not $ownsMutex) { [Windows.MessageBox]::Show((T 'ASTRA est déjà ouvert pour cet utilisateur.'),'ASTRA TWEAKS') | Out-Null; return }
    [xml]$xaml = Get-Content -LiteralPath (Join-Path $PSScriptRoot 'Astra.xaml') -Raw -Encoding UTF8
    $reader = New-Object Xml.XmlNodeReader $xaml
    $script:Window = [Windows.Markup.XamlReader]::Load($reader)
    $names = @('PageHome','PageTweaks','PagePower','PageDiagnostics','PageRestore','NavHome','NavTweaks','NavPower','NavDiagnostics','NavRestore','HomeTweaks','CpuStat','RamStat','RamTotal','SystemText','Analyze','TweakList','ApplyTweaks','SelectRecommended','ClearSelection','PowerPerformance','PowerBalanced','PowerEco','PingTarget','RunPing','PingResult','ImportBefore','ImportAfter','BenchmarkResult','Startup','OpenStartup','OpenGraphics','OpenStorage','ExportReport','StartupResult','RefreshHistory','HistoryList','Status')
    $names += @('PageLanguage','NavLanguage','LanguageSelector','HeaderLanguage')
    $script:Ui = @{}; foreach ($name in $names) { $script:Ui[$name] = $script:Window.FindName($name); if ($null -eq $script:Ui[$name]) { throw ('Contrôle XAML manquant : ' + $name) } }

    $script:RawUi=@{}; foreach ($name in @('CpuStat','RamStat','RamTotal','SystemText','PingResult','BenchmarkResult','StartupResult','Status')) { $script:RawUi[$name]=[string]$script:Ui[$name].Text }
    $script:StaticLabels=New-Object 'System.Collections.Generic.List[object]'
    function Cache-Labels($Node) {
        if ($Node -is [Windows.Controls.TextBlock] -and -not $script:RawUi.ContainsKey($Node.Name)) { $script:StaticLabels.Add([pscustomobject]@{Control=$Node;Property='Text';Original=$Node.Text}) }
        elseif ($Node -is [Windows.Controls.Button] -and $Node.Content -is [string]) { $script:StaticLabels.Add([pscustomobject]@{Control=$Node;Property='Content';Original=$Node.Content}) }
        if ($Node -is [Windows.DependencyObject]) { foreach ($child in [Windows.LogicalTreeHelper]::GetChildren($Node)) { if ($child -is [Windows.DependencyObject]) { Cache-Labels $child } } }
    }
    Cache-Labels $script:Window
    $script:Ui.LanguageSelector.SelectedIndex=if ($Language -eq 'en') {1} else {0}
    function Set-UiText($Name,$Text) { $script:RawUi[$Name]=[string]$Text; $script:Ui[$Name].Text=T $Text }
    function Set-Status($Text) { Set-UiText 'Status' $Text }
    function Apply-Language {
        foreach ($entry in $script:StaticLabels) { $entry.Control.($entry.Property)=T $entry.Original }
        foreach ($name in $script:RawUi.Keys) { $script:Ui[$name].Text=T $script:RawUi[$name] }
        $script:Window.Title=T 'ASTRA TWEAKS · 0.1.0 bêta'
        $script:Window.Language=[Windows.Markup.XmlLanguage]::GetLanguage($(if ((Get-AstraLanguage) -eq 'en') {'en-US'} else {'fr-FR'}))
        Update-Tweaks; Update-History
    }
    function Show-Error($ErrorRecord) { Set-Status $ErrorRecord.Exception.Message; [Windows.MessageBox]::Show($script:Window, (T $ErrorRecord.Exception.Message), (T 'ASTRA · Opération interrompue'),'OK','Warning') | Out-Null }
    function Confirm-Astra($Text) { return [Windows.MessageBox]::Show($script:Window, (T $Text), (T 'ASTRA · Vérifier les changements'),'YesNo','Question') -eq 'Yes' }
    function New-Text($Text,$Size=14,$Color='#F2F0FA') { $t=New-Object Windows.Controls.TextBlock; $t.Text=T $Text; $t.FontSize=$Size; $t.Foreground=$Color; $t.TextWrapping='Wrap'; return $t }
    function New-Card { $b=New-Object Windows.Controls.Border; $b.Style=$script:Window.Resources['Card']; $b.Margin='0,0,0,12'; return $b }
    function Show-Page($Name) {
        foreach ($page in @('Home','Tweaks','Power','Diagnostics','Restore','Language')) { $script:Ui[('Page'+$page)].Visibility=if ($page -eq $Name) {'Visible'} else {'Collapsed'}; $script:Ui[('Nav'+$page)].Background=if ($page -eq $Name) {'#30213F'} else {'Transparent'} }
        if ($Name -eq 'Tweaks') { Update-Tweaks }
        if ($Name -eq 'Restore') { Update-History }
    }
    function Update-Tweaks {
        $selected=@{}; foreach ($id in $script:Choices.Keys) { $selected[$id]=[bool]$script:Choices[$id].IsChecked }
        $script:Ui.TweakList.Children.Clear(); $script:Choices=@{}
        foreach ($tweak in Get-AstraCatalog) {
            $state=Get-AstraTweakState $tweak
            $card=New-Card; $stack=New-Object Windows.Controls.StackPanel
            $check=New-Object Windows.Controls.CheckBox; $check.Content=T $tweak.title; $check.Tag=$tweak.id; $check.IsEnabled=($state -eq 'Disponible'); $check.IsChecked=($check.IsEnabled -and $selected[$tweak.id])
            $script:Choices[$tweak.id]=$check
            $stack.Children.Add($check) | Out-Null
            $meta=New-Text ($tweak.id+'  /  '+$tweak.category+'  /  '+$state) 10 '#BDA0E9'; $meta.Margin='0,10,0,8'; $stack.Children.Add($meta) | Out-Null
            $desc=New-Text $tweak.description 12 '#A5A1B7'; $stack.Children.Add($desc) | Out-Null
            $restart=New-Text ('Prise en compte : '+$tweak.restart) 11 '#7E778F'; $restart.Margin='0,8,0,0'; $stack.Children.Add($restart) | Out-Null
            $card.Child=$stack; $script:Ui.TweakList.Children.Add($card) | Out-Null
        }
    }
    function Update-History {
        $script:Ui.HistoryList.Children.Clear()
        $history=@(Get-AstraHistory); $restorable=@($history | Where-Object { $_.State -in @('Applied','Prepared','Applying','RollbackFailed','RestoreFailed','Restoring') })
        if (-not $history.Count) { $script:Ui.HistoryList.Children.Add((New-Text 'Aucune modification ASTRA enregistrée.' 14 '#A5A1B7')) | Out-Null }
        foreach ($op in $history) {
            $card=New-Card; $stack=New-Object Windows.Controls.StackPanel
            $stack.Children.Add((New-Text $op.Title 16)) | Out-Null
            $meta=New-Text ($op.Time+'  ·  '+$op.State) 12 '#BDA0E9'; $meta.Margin='0,8,0,8'; $stack.Children.Add($meta) | Out-Null
            if ($op.Error) { $stack.Children.Add((New-Text $op.Error 12 '#EBBE9E')) | Out-Null }
            if ($restorable.Count -and $op.Id -eq $restorable[0].Id) {
                $button=New-Object Windows.Controls.Button; $button.Content=T 'Restaurer cette opération'; $button.Tag=$op.Id; $button.HorizontalAlignment='Left'; $button.Margin='0,12,0,0'
                $button.Add_Click({param($sender,$eventArgs) try { if (Confirm-Astra 'Restaurer les valeurs sauvegardées pour cette opération ? Les réglages externes conflictuels seront préservés et signalés.') { $result=Restore-AstraOperation -Id ([string]$sender.Tag); Set-Status ('Restauration vérifiée : '+$result.Id); Update-History } } catch { Show-Error $_; Update-History } })
                $stack.Children.Add($button) | Out-Null
            }
            $card.Child=$stack; $script:Ui.HistoryList.Children.Add($card) | Out-Null
        }
    }
    function Update-System {
        Set-Status 'Analyse locale en cours…'; $script:Window.Cursor='Wait'
        try {
            $s=Get-AstraSystem; $script:SystemReport=$s
            Set-UiText 'CpuStat' ([string]$s.CpuLoad+' %'); Set-UiText 'RamStat' ([string]$s.RamFreeGB+' Go'); Set-UiText 'RamTotal' ('sur '+$s.RamTotalGB+' Go détectés')
            $gpus=($s.GPU | ForEach-Object { $_.Name+' · pilote '+$_.DriverVersion+' · '+$_.CurrentRefreshRate+' Hz (WMI)' }) -join "`n"
            $disks=($s.Disks | ForEach-Object { $_.DeviceID+' '+$_.FreeGB+' / '+$_.TotalGB+' Go libres' }) -join "`n"
            Set-UiText 'SystemText' ($s.CPU+"`n"+$s.Cores+' cœurs · '+$s.Threads+" threads`n"+$gpus+"`n"+$s.Windows+' · build '+$s.Build+"`n"+$disks+"`nDefender : "+$s.Defender+' · Pare-feu : '+$s.Firewall+"`nPlan actif : "+$s.ActivePlan)
            Set-Status ('Instantané relevé à '+$s.MeasuredAt+' · températures / charge GPU non mesurées par cette bêta.')
        } finally { $script:Window.Cursor=$null }
    }
    function Select-Benchmark($Slot) {
        $dialog=New-Object Microsoft.Win32.OpenFileDialog; $dialog.Filter='Frametimes CSV (*.csv)|*.csv'
        if ($dialog.ShowDialog($script:Window)) {
            $result=Import-AstraFrameTimes -Path $dialog.FileName
            if ($Slot -eq 'A') { $script:BenchA=$result } else { $script:BenchB=$result }
            $lines=@()
            foreach ($key in @('A','B')) { $r=if ($key -eq 'A') {$script:BenchA} else {$script:BenchB}; if ($null -ne $r) { $lines += $key+' : '+$r.AverageFPS+' FPS · 1 % low '+$r.Low1Percent+' · 0,1 % low '+$r.Low01Percent+' · '+$r.Frames+' images / '+$r.DurationSeconds+' s' } }
            if ($null -ne $script:BenchA -and $null -ne $script:BenchB) { $change=[math]::Round(100*($script:BenchB.AverageFPS/$script:BenchA.AverageFPS-1),1); $lines += 'Écart moyen B / A : '+$change+' % (corrélation, pas preuve de causalité).' }
            $lines += $result.Definition; Set-UiText 'BenchmarkResult' ($lines -join "`n")
        }
    }
    foreach ($page in @('Home','Tweaks','Power','Diagnostics','Restore','Language')) { $script:Ui[('Nav'+$page)].Tag=$page; $script:Ui[('Nav'+$page)].Add_Click({ param($sender,$eventArgs) Show-Page ([string]$sender.Tag) }) }
    $script:Ui.HeaderLanguage.Add_Click({Show-Page 'Language'})
    $script:Ui.LanguageSelector.Add_SelectionChanged({
        if ($null -eq $script:Ui.LanguageSelector.SelectedItem) { return }
        $chosen=[string]$script:Ui.LanguageSelector.SelectedItem.Tag
        Set-AstraLanguage $chosen; Apply-Language
        try { if (-not $SmokeTest) { Save-AstraLanguage $chosen }; Set-Status 'Langue modifiée et mémorisée.' }
        catch { Set-Status ('La langue a changé, mais la préférence n''a pas pu être enregistrée : '+$_.Exception.Message) }
    })
    $script:Ui.HomeTweaks.Add_Click({ Show-Page 'Tweaks' })
    $script:Ui.Analyze.Add_Click({ try { Update-System } catch { Show-Error $_ } })
    $script:Ui.SelectRecommended.Add_Click({ foreach ($t in Get-AstraCatalog) { $c=$script:Choices[$t.id]; $c.IsChecked=($c.IsEnabled -and $t.recommended) } })
    $script:Ui.ClearSelection.Add_Click({ foreach ($c in $script:Choices.Values) { $c.IsChecked=$false } })
    $script:Ui.ApplyTweaks.Add_Click({
        try {
            $ids=@($script:Choices.Keys | Where-Object { $script:Choices[$_].IsChecked } | Sort-Object)
            if (-not $ids.Count) { throw 'Sélectionnez au moins un réglage disponible.' }
            $preview=@(Get-AstraTweakPreview $ids)
            $text=($preview | ForEach-Object { (T $_.Title)+"`n"+$_.Path+'\'+$_.Name+"`n"+(T $_.Before)+' → '+$_.After+"`n"+(T ('Prise en compte : '+$_.Restart)) }) -join "`n`n"
            # A scrollable, explicit review remains usable with all twelve tweaks selected.
            $review=New-Object Windows.Window; $review.Title=T 'ASTRA · Votre sélection'; $review.Owner=$script:Window; $review.Width=720; $review.Height=560; $review.WindowStartupLocation='CenterOwner'; $review.Background='#14131D'; $review.Foreground='#F2F0FA'
            $dock=New-Object Windows.Controls.DockPanel; $dock.Margin='24'
            $ok=New-Object Windows.Controls.Button; $ok.Content=T 'Sauvegarder et appliquer ces changements'; $ok.Margin='0,18,0,0'; $ok.Padding='14,12'; $ok.Background='#8750DE'; $ok.Foreground='White'; [Windows.Controls.DockPanel]::SetDock($ok,'Bottom')
            $ok.Add_Click({ param($sender,$eventArgs) $thisWindow=[Windows.Window]::GetWindow($sender); $thisWindow.DialogResult=$true }); $dock.Children.Add($ok) | Out-Null
            $scroll=New-Object Windows.Controls.ScrollViewer; $scroll.VerticalScrollBarVisibility='Auto'; $scroll.Content=(New-Text $text 12 '#D1C7E0'); $dock.Children.Add($scroll) | Out-Null; $review.Content=$dock
            if ($review.ShowDialog()) { $result=Invoke-AstraTweaks -Ids $ids; Set-Status ('Modifications sauvegardées et vérifiées : '+$result.Id); Update-Tweaks }
        } catch { Show-Error $_ }
    })
    foreach ($profile in @('Performance','Balanced','Eco')) {
        $script:Ui[('Power'+$profile)].Tag=$profile
        $script:Ui[('Power'+$profile)].Add_Click({ param($sender,$eventArgs) try { $chosen=[string]$sender.Tag; if (Confirm-Astra ('Créer et activer ASTRA '+$chosen+' ? Les limites affichées seront appliquées à une copie de votre plan actuel. Le plan précédent sera sauvegardé.')) { $result=Invoke-AstraPowerProfile -Profile $chosen; Set-Status ('Profil actif et sauvegardé : '+$result.Title) } } catch { Show-Error $_ } })
    }
    $script:Ui.RunPing.Add_Click({ try { $script:Ui.RunPing.IsEnabled=$false; Set-Status 'Mesure ICMP en cours (jusqu''à 5 secondes)…'; $r=Measure-AstraNetwork -Target $script:Ui.PingTarget.Text; Set-UiText 'PingResult' ('Moyenne : '+$r.AverageMs+' ms · Gigue : '+$r.JitterMs+' ms · Perte ICMP : '+$r.LossPercent+" %`n"+$r.Note); Set-Status 'Mesure réseau terminée.' } catch { Show-Error $_ } finally { $script:Ui.RunPing.IsEnabled=$true } })
    $script:Ui.ImportBefore.Add_Click({ try { Select-Benchmark 'A' } catch { Show-Error $_ } })
    $script:Ui.ImportAfter.Add_Click({ try { Select-Benchmark 'B' } catch { Show-Error $_ } })
    $script:Ui.Startup.Add_Click({ try { $items=@(Get-AstraStartup); Set-UiText 'StartupResult' (($items | ForEach-Object { $_.Name+' · '+$_.Location }) -join "`n"); Set-Status ('Démarrage : '+$items.Count+' éléments. Lecture seule ; utilisez les paramètres Windows pour les modifier.') } catch { Show-Error $_ } })
    $script:Ui.OpenStartup.Add_Click({ Start-Process 'ms-settings:startupapps' })
    $script:Ui.OpenGraphics.Add_Click({ Start-Process 'ms-settings:display-advancedgraphics' })
    $script:Ui.OpenStorage.Add_Click({ Start-Process 'ms-settings:storagesense' })
    $script:Ui.ExportReport.Add_Click({ try { if ($null -eq $script:SystemReport) { Update-System }; $dialog=New-Object Microsoft.Win32.SaveFileDialog; $dialog.FileName='astra-rapport.json'; $dialog.Filter=T 'Rapport JSON (*.json)|*.json'; if ($dialog.ShowDialog($script:Window)) { $script:SystemReport | ConvertTo-Json -Depth 8 | Set-Content -LiteralPath $dialog.FileName -Encoding UTF8; Set-Status 'Rapport enregistré localement. Il contient les noms du matériel et des processus.' } } catch { Show-Error $_ } })
    $script:Ui.RefreshHistory.Add_Click({ try { Update-History } catch { Show-Error $_ } })
    Apply-Language
    Show-Page 'Home'
    $incomplete=@(Get-AstraHistory | Where-Object { $_.State -in @('Prepared','Applying','RollbackFailed','RestoreFailed','Restoring') })
    if ($incomplete.Count) { Show-Page 'Restore'; Set-Status 'Une opération incomplète nécessite votre attention.' }
    if ($SmokeTest) {
        $initialLanguage=Get-AstraLanguage
        $script:Ui.LanguageSelector.SelectedIndex=0
        if ($script:Ui.NavHome.Content -notmatch 'ensemble') { throw 'French language selection failed.' }
        $script:Ui.LanguageSelector.SelectedIndex=1
        if ($script:Ui.NavHome.Content -notmatch 'Overview' -or $script:Ui.Analyze.Content -ne 'Analyze / Refresh') { throw 'English language selection failed.' }
        $script:Ui.LanguageSelector.SelectedIndex=if ($initialLanguage -eq 'en') {1} else {0}
        foreach ($page in @('Tweaks','Power','Diagnostics','Restore','Language','Home')) {
            $script:Ui[('Nav'+$page)].RaiseEvent((New-Object Windows.RoutedEventArgs([Windows.Controls.Button]::ClickEvent)))
            if ($script:Ui[('Page'+$page)].Visibility -ne 'Visible') { throw ('Navigation cassée : '+$page) }
        }
        if ($RenderPath) {
            if ($RenderLanguagePage) { Show-Page 'Language' }
            $visual=$script:Window.Content; $visual.Resources=$script:Window.Resources; $script:Window.Content=$null; $visual.Background='#0B0B12'
            $visual.SetValue([Windows.Documents.TextElement]::ForegroundProperty,([Windows.Media.BrushConverter]::new().ConvertFromString('#F2F0FA')))
            $visual.Measure((New-Object Windows.Size(1180,800))); $visual.Arrange((New-Object Windows.Rect(0,0,1180,800))); $visual.UpdateLayout()
            $bitmap=New-Object Windows.Media.Imaging.RenderTargetBitmap(1180,800,96,96,[Windows.Media.PixelFormats]::Pbgra32); $bitmap.Render($visual)
            $encoder=New-Object Windows.Media.Imaging.PngBitmapEncoder; $encoder.Frames.Add([Windows.Media.Imaging.BitmapFrame]::Create($bitmap)); $file=[IO.File]::Create($RenderPath); try { $encoder.Save($file) } finally { $file.Dispose() }
        }
        Write-Output ('ASTRA UI smoke test OK · '+$names.Count+' contrôles · '+@(Get-AstraCatalog).Count+' réglages')
        $script:Window.Close()
    } else { $script:Window.ShowDialog() | Out-Null }
} catch {
    if ($SmokeTest) { throw }
    [Windows.MessageBox]::Show((T $_.Exception.Message),(T 'ASTRA · Impossible de démarrer'),'OK','Error') | Out-Null
} finally { if ($ownsMutex) { $mutex.ReleaseMutex() }; $mutex.Dispose() }
