@echo off
setlocal EnableExtensions EnableDelayedExpansion

REM === CONFIG ===
set "BRANCH=main"
set "BASE_DIR=pages_by_gene"
set "MAX_FILES=100"
set "MANIFEST=.genes_manifest.txt"
set "OFFSET_FILE=.genes_offset.txt"
set "COMMIT_MSG=Lote pages_by_gene (ate %MAX_FILES% arquivos)"

REM === VALIDACOES ===
git rev-parse --is-inside-work-tree >nul 2>&1 || (echo [ERRO] Nao e repo Git.&pause&exit /b)
if not exist "%BASE_DIR%" (echo [ERRO] Pasta nao encontrada: %BASE_DIR%&pause&exit /b)

REM === GARANTIR BRANCH ===
for /f "tokens=*" %%i in ('git rev-parse --abbrev-ref HEAD') do set CUR_BRANCH=%%i
if /I not "%CUR_BRANCH%"=="%BRANCH%" (
  git rev-parse --verify %BRANCH% >nul 2>&1 || git checkout -b %BRANCH%
  git checkout %BRANCH% || (echo [ERRO] Nao foi possivel trocar p/ %BRANCH%.&pause&exit /b)
)

REM === (RE)GERA MANIFESTO LIMPO: 1 nome por linha, sem aspas, ordenado ===
(for /f "delims=" %%F in ('dir /b /on "%BASE_DIR%\*.html"') do @echo %%F) > "%MANIFEST%"

REM === LER OFFSET ===
set "OFFSET=0"
if exist "%OFFSET_FILE%" (set /p OFFSET=<"%OFFSET_FILE%")
if not defined OFFSET set "OFFSET=0"

set /a BATCH_NO=(OFFSET / MAX_FILES) + 1
echo Lote: !BATCH_NO!  OFFSET=!OFFSET!  TAM=%MAX_FILES%

REM === limpar staging e garantir index.html cedo
git reset >nul 2>&1
if exist "%BASE_DIR%\index.html" git add "%BASE_DIR%\index.html" >nul 2>&1

REM === Adicionar ate MAX_FILES a partir do OFFSET (sem skip/more)
set /a ADDED=0
set /a INDEX=0
for /f "usebackq delims=" %%L in ("%MANIFEST%") do (
  if !INDEX! geq !OFFSET! if !ADDED! lss %MAX_FILES% (
    set "LINE=%%~L"
    call :SANITIZE_LINE LINE
    call :ADD_ONE "%BASE_DIR%\!LINE!"
    if not errorlevel 1 set /a ADDED+=1
  )
  set /a INDEX+=1
)

if %ADDED% EQU 0 (
  echo [INFO] Nada para enviar (terminou?). Apague %OFFSET_FILE% p/ reiniciar.
  pause
  exit /b
)

git commit -m "%COMMIT_MSG% (lote !BATCH_NO!)" || (echo [ERRO] Commit falhou.&pause&exit /b)
git push origin %BRANCH% || (echo [ERRO] Push falhou.&pause&exit /b)
git pull origin %BRANCH% || (echo [ERRO] Pull falhou.&pause&exit /b)

set /a NEW_OFFSET=OFFSET + ADDED
> "%OFFSET_FILE%" echo %NEW_OFFSET%
echo OK! Proximo OFFSET: %NEW_OFFSET%
pause
exit /b

:SANITIZE_LINE
REM Remove + iniciais, espaços iniciais e TODAS as aspas da variavel passada (%1)
set "TMP=!%1!"
:strip
if "!TMP:~0,1!"=="+" set "TMP=!TMP:~1!" & goto strip
if "!TMP:~0,1!"==" " set "TMP=!TMP:~1!" & goto strip
set "TMP=!TMP:"=!"
set "%1=!TMP!"
exit /b 0

:ADD_ONE
REM Adiciona caminho relativo ao repo se existir
set "P=%~1"
if exist "%P%" (
  echo + "%P%"
  git add "%P%" >nul 2>&1
  exit /b %ERRORLEVEL%
)
echo [AVISO] Nao encontrado: %~1
exit /b 1
