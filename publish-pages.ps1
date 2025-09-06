param(
  [string]$Owner="rodrigoautokm",
  [string]$Repo ="genes",
  [string]$Branch="main",
  [string]$Path ="/"        # "/" ou "/docs"
)

function Have-GH { $null -ne (Get-Command gh -ErrorAction SilentlyContinue) }

# Valida
git rev-parse --is-inside-work-tree *> $null
if ($LASTEXITCODE -ne 0) { Write-Host "[ERRO] Rode dentro do clone do repo." ; exit 1 }
if (-not (Test-Path "pages_by_gene")) { Write-Host "[ERRO] Pasta 'pages_by_gene' nao encontrada." ; exit 1 }

# Branch
$cur = (git rev-parse --abbrev-ref HEAD).Trim()
if ($cur -ne $Branch) {
  git rev-parse --verify $Branch *> $null
  if ($LASTEXITCODE -ne 0) { git checkout -b $Branch } else { git checkout $Branch }
  if ($LASTEXITCODE -ne 0) { Write-Host "[ERRO] Nao foi possivel trocar/criar $Branch." ; exit 1 }
}

# index.html raiz + .nojekyll
if (-not (Test-Path ".\index.html")) {
  @'
<!doctype html><html lang="pt-br"><head>
<meta charset="utf-8"><meta http-equiv="refresh" content="0; url=pages_by_gene/index.html">
<title>Genes</title></head><body>
<p>Redirecionando para <a href="pages_by_gene/index.html">pages_by_gene/index.html</a>…</p>
</body></html>
'@ | Out-File ".\index.html" -Encoding UTF8 ; git add .\index.html | Out-Null
}
if (-not (Test-Path ".\.nojekyll")) { New-Item .\.nojekyll -ItemType File -Force | Out-Null ; git add .\.nojekyll | Out-Null }

# Commit/push se houver mudancas
git add pages_by_gene\index.html 2>$null | Out-Null
if (git status --porcelain) { git commit -m "Enable Pages: index + nojekyll" | Out-Null ; git push origin $Branch | Out-Null }

# Ativar/atualizar Pages
$site = $null
if (Have-GH) {
  gh api -X GET "repos/$Owner/$Repo/pages" *> $null
  if ($LASTEXITCODE -eq 0) {
    gh api -X PUT  "repos/$Owner/$Repo/pages" -F "source[branch]=$Branch" -F "source[path]=$Path" -F "build_type=legacy" | Out-Null
  } else {
    gh api -X POST "repos/$Owner/$Repo/pages" -F "source[branch]=$Branch" -F "source[path]=$Path" -F "build_type=legacy" | Out-Null
  }
  $site = gh api "repos/$Owner/$Repo/pages" | ConvertFrom-Json
} else {
  if (-not $env:GITHUB_TOKEN) { Write-Host "[ERRO] Defina GITHUB_TOKEN ou use 'gh auth login'." ; exit 1 }
  $H=@{ "Accept"="application/vnd.github+json"; "Authorization"=("Bearer "+$env:GITHUB_TOKEN); "X-GitHub-Api-Version"="2022-11-28" }
  $uri = "https://api.github.com/repos/$Owner/$Repo/pages"
  $legacy   = @{ source=@{ branch=$Branch; path=$Path }; build_type="legacy" }   | ConvertTo-Json
  $workflow = @{ source=@{ branch=$Branch; path=$Path }; build_type="workflow" } | ConvertTo-Json
  $exists=$true; try { Invoke-RestMethod -Method GET -Uri $uri -Headers $H -ErrorAction Stop | Out-Null } catch { $exists=$false }
  if (-not $exists) {
    try { Invoke-RestMethod -Method POST -Uri $uri -Headers $H -Body $legacy -ErrorAction Stop | Out-Null }
    catch { Invoke-RestMethod -Method POST -Uri $uri -Headers $H -Body $workflow | Out-Null ; Invoke-RestMethod -Method PUT -Uri $uri -Headers $H -Body $legacy | Out-Null }
  } else {
    Invoke-RestMethod -Method PUT -Uri $uri -Headers $H -Body $legacy | Out-Null
  }
  $site = Invoke-RestMethod -Method GET -Uri $uri -Headers $H
}

$base = if ($site.html_url) { $site.html_url } else { "https://$Owner.github.io/$Repo/" }
Write-Host ("Site: {0}" -f $base)

# Dispara build e testa
if (Have-GH) { gh api -X POST "repos/$Owner/$Repo/pages/builds" | Out-Null }
elseif ($env:GITHUB_TOKEN) {
  $H=@{ "Accept"="application/vnd.github+json"; "Authorization"=("Bearer "+$env:GITHUB_TOKEN); "X-GitHub-Api-Version"="2022-11-28" }
  Invoke-RestMethod -Method POST -Uri "https://api.github.com/repos/$Owner/$Repo/pages/builds" -Headers $H | Out-Null
}
$probe = ($base.TrimEnd('/') + "/pages_by_gene/index.html")
Write-Host ("Testando: {0}" -f $probe)
$ok=$false; 1..20 | % { try { $r=Invoke-WebRequest -UseBasicParsing -Uri $probe -TimeoutSec 10; if ($r.StatusCode -ge 200 -and $r.StatusCode -lt 400){$ok=$true;break} } catch {} ; Start-Sleep 6 }
if ($ok) { Write-Host "Publicado! $probe" } else { Write-Host "Ativado. Primeiro publish pode demorar alguns minutos. Tente depois: $probe" }
