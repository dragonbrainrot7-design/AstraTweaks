Set-StrictMode -Version Latest
$script:Language = 'fr'
$script:English = @{}
$data = Get-Content -LiteralPath (Join-Path $PSScriptRoot 'translations.en.json') -Raw -Encoding UTF8 | ConvertFrom-Json
foreach ($property in $data.PSObject.Properties) { $script:English[$property.Name] = [string]$property.Value }
$script:Patterns = @($script:English.Keys | Where-Object { $_ -match '\{\d+\}' } | Sort-Object Length -Descending | ForEach-Object {
    $key = $_
    $pattern = [regex]::Escape($key)
    $pattern = [regex]::Replace($pattern, '\\\{(\d+)}', '(?<p$1>.*?)')
    [pscustomobject]@{ Regex = New-Object regex(('^' + $pattern + '$'), [Text.RegularExpressions.RegexOptions]::Singleline); Value = $script:English[$key] }
})

function Get-AstraLanguage { return $script:Language }
function Set-AstraLanguage { param([ValidateSet('fr','en')][string]$Language) $script:Language = $Language }
function Get-AstraText {
    param([AllowEmptyString()][string]$Text)
    if ($script:Language -eq 'fr' -or [string]::IsNullOrEmpty($Text)) { return $Text }
    if ($script:English.ContainsKey($Text)) { return $script:English[$Text] }
    foreach ($entry in $script:Patterns) {
        $match = $entry.Regex.Match($Text)
        if ($match.Success) {
            $values = @(); $index = 0
            while ($match.Groups['p'+$index].Success) { $values += Get-AstraText $match.Groups['p'+$index].Value; $index++ }
            return ($entry.Value -f $values)
        }
    }
    if ($Text.Contains("`n")) { return (($Text -split "`n" | ForEach-Object { Get-AstraText $_ }) -join "`n") }
    return $Text
}
function Get-AstraSavedLanguage {
    param([string]$Path = (Join-Path ([Environment]::GetFolderPath('LocalApplicationData')) 'AstraTweaks\preferences.json'))
    try { $prefs = Get-Content -LiteralPath $Path -Raw -Encoding UTF8 | ConvertFrom-Json; if ($prefs.language -in @('fr','en')) { return $prefs.language } } catch { }
    return 'fr'
}
function Save-AstraLanguage {
    param([ValidateSet('fr','en')][string]$Language,[string]$Path = (Join-Path ([Environment]::GetFolderPath('LocalApplicationData')) 'AstraTweaks\preferences.json'))
    $folder = Split-Path $Path -Parent
    [IO.Directory]::CreateDirectory($folder) | Out-Null
    $temporary = $Path + '.pending'
    [IO.File]::WriteAllText($temporary, (@{language=$Language} | ConvertTo-Json), (New-Object Text.UTF8Encoding($true)))
    if ([IO.File]::Exists($Path)) { [IO.File]::Replace($temporary,$Path,[NullString]::Value) } else { [IO.File]::Move($temporary,$Path) }
}
Export-ModuleMember -Function Get-AstraLanguage,Set-AstraLanguage,Get-AstraText,Get-AstraSavedLanguage,Save-AstraLanguage
