param(
  [string]$Html = "html\conselho-municipal-de-assistencia-social.html",
  [string]$PastaArquivos = "conselho",
  [string]$Saida = "html\conselho-municipal-de-assistencia-social-wordpress.html",
  [string]$Mapa = "scripts\wordpress-conselho-links.json",
  [string]$WpUrl = $env:WP_URL,
  [string]$WpUser = $env:WP_USER,
  [string]$WpAppPassword = $env:WP_APP_PASSWORD,
  [switch]$DryRun,
  [switch]$ForceUpload
)

$ErrorActionPreference = "Stop"

function Resolve-RepoPath {
  param([string]$Path)
  if ([System.IO.Path]::IsPathRooted($Path)) {
    return [System.IO.Path]::GetFullPath($Path)
  }
  return [System.IO.Path]::GetFullPath((Join-Path (Get-Location) $Path))
}

function Get-MimeType {
  param([string]$Path)
  switch ([System.IO.Path]::GetExtension($Path).ToLowerInvariant()) {
    ".pdf"  { "application/pdf"; break }
    ".zip"  { "application/zip"; break }
    ".doc"  { "application/msword"; break }
    ".docx" { "application/vnd.openxmlformats-officedocument.wordprocessingml.document"; break }
    ".xls"  { "application/vnd.ms-excel"; break }
    ".xlsx" { "application/vnd.openxmlformats-officedocument.spreadsheetml.sheet"; break }
    ".odt"  { "application/vnd.oasis.opendocument.text"; break }
    ".txt"  { "text/plain"; break }
    default { "application/octet-stream" }
  }
}

function ConvertTo-LinkMap {
  param($Object)
  $map = @{}
  if ($null -eq $Object) {
    return $map
  }
  foreach ($property in $Object.PSObject.Properties) {
    $map[$property.Name] = [string]$property.Value
  }
  return $map
}

function Save-LinkMap {
  param([hashtable]$Map, [string]$Path)
  $dir = Split-Path -Parent $Path
  if ($dir -and -not (Test-Path -LiteralPath $dir)) {
    New-Item -ItemType Directory -Path $dir | Out-Null
  }
  $ordered = [ordered]@{}
  foreach ($key in ($Map.Keys | Sort-Object)) {
    $ordered[$key] = $Map[$key]
  }
  $ordered | ConvertTo-Json -Depth 3 | Set-Content -LiteralPath $Path -Encoding UTF8
}

function Upload-WordPressMedia {
  param(
    [string]$FilePath,
    [string]$WpUrl,
    [string]$WpUser,
    [string]$WpAppPassword
  )

  $api = $WpUrl.TrimEnd("/") + "/wp-json/wp/v2/media"
  $fileName = [System.IO.Path]::GetFileName($FilePath)
  $mime = Get-MimeType -Path $FilePath
  $token = [Convert]::ToBase64String([Text.Encoding]::UTF8.GetBytes("${WpUser}:${WpAppPassword}"))
  $headers = @{
    Authorization = "Basic $token"
    "Content-Disposition" = "attachment; filename=""$fileName"""
  }

  $response = Invoke-RestMethod -Method Post -Uri $api -Headers $headers -ContentType $mime -InFile $FilePath
  if (-not $response.source_url) {
    throw "O WordPress respondeu sem source_url para $fileName."
  }
  return [string]$response.source_url
}

$htmlPath = Resolve-RepoPath $Html
$arquivosPath = Resolve-RepoPath $PastaArquivos
$saidaPath = Resolve-RepoPath $Saida
$mapaPath = Resolve-RepoPath $Mapa

if (-not (Test-Path -LiteralPath $htmlPath)) {
  throw "HTML nao encontrado: $htmlPath"
}
if (-not (Test-Path -LiteralPath $arquivosPath)) {
  throw "Pasta de arquivos nao encontrada: $arquivosPath"
}

$htmlConteudo = Get-Content -LiteralPath $htmlPath -Raw -Encoding UTF8
$matches = [regex]::Matches($htmlConteudo, 'href\s*=\s*(["''])(\.\./conselho/[^"'']+)\1', "IgnoreCase")
$links = @($matches | ForEach-Object { $_.Groups[2].Value } | Sort-Object -Unique)

if ($links.Count -eq 0) {
  Write-Host "Nenhum link ../conselho/ foi encontrado em $Html."
  exit 0
}

$mapaExistente = @{}
if (Test-Path -LiteralPath $mapaPath) {
  $mapaExistente = ConvertTo-LinkMap (Get-Content -LiteralPath $mapaPath -Raw -Encoding UTF8 | ConvertFrom-Json)
}

$pendentes = New-Object System.Collections.Generic.List[object]
$faltando = New-Object System.Collections.Generic.List[object]
$resolvidos = @{}

foreach ($link in $links) {
  $relativoCodificado = $link.Substring("../conselho/".Length)
  $relativo = [Uri]::UnescapeDataString($relativoCodificado).Replace("/", [System.IO.Path]::DirectorySeparatorChar)
  $arquivoLocal = Join-Path $arquivosPath $relativo

  if (-not (Test-Path -LiteralPath $arquivoLocal)) {
    $faltando.Add([pscustomobject]@{ Link = $link; Arquivo = $arquivoLocal }) | Out-Null
    continue
  }

  if (-not $ForceUpload -and $mapaExistente.ContainsKey($link)) {
    $resolvidos[$link] = $mapaExistente[$link]
    continue
  }

  $pendentes.Add([pscustomobject]@{ Link = $link; Arquivo = $arquivoLocal }) | Out-Null
}

Write-Host "Links encontrados: $($links.Count)"
Write-Host "Ja mapeados: $($resolvidos.Count)"
Write-Host "Para enviar: $($pendentes.Count)"
Write-Host "Nao encontrados: $($faltando.Count)"

if ($faltando.Count -gt 0) {
  Write-Host ""
  Write-Host "Arquivos faltando:"
  foreach ($item in $faltando) {
    Write-Host "- $($item.Link) -> $($item.Arquivo)"
  }
}

if ($DryRun) {
  Write-Host ""
  Write-Host "Simulacao concluida. Nenhum arquivo foi enviado e nenhum HTML foi gerado."
  exit 0
}

if ($pendentes.Count -gt 0) {
  if ([string]::IsNullOrWhiteSpace($WpUrl) -or [string]::IsNullOrWhiteSpace($WpUser) -or [string]::IsNullOrWhiteSpace($WpAppPassword)) {
    throw "Informe WP_URL, WP_USER e WP_APP_PASSWORD por variavel de ambiente ou parametros para enviar os arquivos."
  }
}

foreach ($item in $pendentes) {
  Write-Host "Enviando: $($item.Arquivo)"
  $url = Upload-WordPressMedia -FilePath $item.Arquivo -WpUrl $WpUrl -WpUser $WpUser -WpAppPassword $WpAppPassword
  $resolvidos[$item.Link] = $url
  $mapaExistente[$item.Link] = $url
  Save-LinkMap -Map $mapaExistente -Path $mapaPath
  Write-Host "  -> $url"
}

$htmlFinal = $htmlConteudo
foreach ($link in ($resolvidos.Keys | Sort-Object { $_.Length } -Descending)) {
  $htmlFinal = $htmlFinal.Replace($link, $resolvidos[$link])
}

$saidaDir = Split-Path -Parent $saidaPath
if ($saidaDir -and -not (Test-Path -LiteralPath $saidaDir)) {
  New-Item -ItemType Directory -Path $saidaDir | Out-Null
}
$htmlFinal | Set-Content -LiteralPath $saidaPath -Encoding UTF8

Write-Host ""
Write-Host "HTML gerado: $saidaPath"
Write-Host "Mapa salvo: $mapaPath"
