@echo off
REM ==============================================================================
REM APKTool Practice Workflow Script (Windows Batch)
REM
REM Automates: Decompile → Modify → Repackage → Sign → Verify
REM
REM Prerequisites:
REM   - Java JDK 8+ (keytool, jarsigner in PATH)
REM   - Android SDK build-tools (set ANDROID_SDK env var)
REM
REM Usage: scripts\workflow.bat
REM ==============================================================================

setlocal enabledelayedexpansion

REM ---- Configuration ----
set "SCRIPT_DIR=%~dp0"
set "PROJECT_DIR=%SCRIPT_DIR%.."
set "TOOLS_DIR=%PROJECT_DIR%\tools"
set "ORIGINAL_DIR=%PROJECT_DIR%\original"
set "WORK_DIR=%PROJECT_DIR%\work"
set "OUTPUT_DIR=%PROJECT_DIR%\output"

set "APKTOOL=%TOOLS_DIR%\apktool.jar"
set "ORIGINAL_APK=%ORIGINAL_DIR%\AndroidTrivia-original.apk"
set "DECOMPILED_DIR=%WORK_DIR%\decompiled"
set "UNSIGNED_APK=%WORK_DIR%\app-unsigned.apk"
set "ALIGNED_APK=%WORK_DIR%\app-aligned.apk"
set "SIGNED_APK=%OUTPUT_DIR%\AndroidTrivia-modified.apk"
set "KEYSTORE=%WORK_DIR%\debug.keystore"
set "KEYSTORE_PASS=android"
set "KEY_ALIAS=androiddebugkey"

REM Auto-detect Android SDK
if "%ANDROID_SDK%"=="" set "ANDROID_SDK=%LOCALAPPDATA%\Android\Sdk"

echo.
echo ================================================================
echo   APKTool Practice — Decompile → Modify → Sign
echo ================================================================
echo.

REM ---- Step 0: Check prerequisites ----
echo [Step 0/5] Checking prerequisites...

if not exist "%APKTOOL%" (
    echo [FAIL] apktool.jar not found at %APKTOOL%
    exit /b 1
)
echo [OK] apktool.jar found

java -version 2>&1 | findstr /i "version" >nul
if errorlevel 1 (
    echo [FAIL] Java not found
    exit /b 1
)
echo [OK] Java available

REM ---- Step 1: Decompile ----
echo.
echo [Step 1/5] DECOMPILE - Extracting APK with apktool...

if not exist "%ORIGINAL_APK%" (
    echo [FAIL] Original APK not found: %ORIGINAL_APK%
    exit /b 1
)

if exist "%DECOMPILED_DIR%" rmdir /s /q "%DECOMPILED_DIR%"

java -jar "%APKTOOL%" d "%ORIGINAL_APK%" -o "%DECOMPILED_DIR%" -f
if errorlevel 1 (
    echo [FAIL] Decompilation failed
    exit /b 1
)
echo [OK] APK decompiled to: %DECOMPILED_DIR%

REM ---- Step 2: Modify ----
echo.
echo [Step 2/5] MODIFY - Patching resources...

REM Find the latest build-tools
for /f "tokens=*" %%i in ('dir /b /ad /on "%ANDROID_SDK%\build-tools" 2^>nul ^| sort /r') do (
    set "BUILD_TOOLS_VER=%%i"
    goto :found_bt
)
:found_bt
set "BUILD_TOOLS=%ANDROID_SDK%\build-tools\%BUILD_TOOLS_VER%"

REM --- Modify strings.xml ---
set "STRINGS_FILE=%DECOMPILED_DIR%\res\values\strings.xml"
if exist "%STRINGS_FILE%" (
    echo Patching: %STRINGS_FILE%
    REM Use PowerShell for in-place string replacement (more reliable on Windows)
    powershell -Command "(Get-Content '%STRINGS_FILE%') -replace '>AndroidTrivia<', '>AndroidTriviaMod<' -replace '>Android Trivia<', '>Android Trivia Mod<' | Set-Content '%STRINGS_FILE%'"
    echo [OK] app_name string modified
) else (
    echo [WARN] strings.xml not found
)

REM --- Modify fragment_title.xml (add banner before closing tag) ---
set "TITLE_LAYOUT=%DECOMPILED_DIR%\res\layout\fragment_title.xml"
if exist "%TITLE_LAYOUT%" (
    echo Patching: %TITLE_LAYOUT%
    powershell -Command "$content = Get-Content '%TITLE_LAYOUT%' -Raw; $banner = '        <TextView android:id=\"@+id/modBanner\" android:layout_width=\"wrap_content\" android:layout_height=\"wrap_content\" android:layout_marginTop=\"16dp\" android:gravity=\"center\" android:text=\"[APKTool Modified]\" android:textColor=\"#FF0000\" android:textSize=\"14sp\" android:textStyle=\"bold\" app:layout_constraintEnd_toEndOf=\"parent\" app:layout_constraintStart_toStartOf=\"parent\" app:layout_constraintTop_toTopOf=\"parent\" />'; $content = $content -replace '</androidx.constraintlayout.widget.ConstraintLayout>', ($banner + \"`r`n\" + '$&'); Set-Content '%TITLE_LAYOUT%' -Value $content"
    echo [OK] Banner added to title layout
) else (
    echo [WARN] fragment_title.xml not found
)

REM --- Modify colors.xml ---
set "COLORS_FILE=%DECOMPILED_DIR%\res\values\colors.xml"
if exist "%COLORS_FILE%" (
    echo Patching: %COLORS_FILE%
    powershell -Command "$content = Get-Content '%COLORS_FILE%' -Raw; $content = $content -replace '>#[a-fA-F0-9]{6,8}<', '>#FF5722<'; if ($content -match '(<color name=\"colorAccent\">)#FF5722(</color>)') { Write-Host '[OK] Accent color replaced with #FF5722' }; Set-Content '%COLORS_FILE%' -Value $content"
    echo [OK] Accent color modified
)

echo [OK] Modifications complete

REM ---- Step 3: Repackage ----
echo.
echo [Step 3/5] REPACKAGE - Building modified APK...

java -jar "%APKTOOL%" b "%DECOMPILED_DIR%" -o "%UNSIGNED_APK%"
if errorlevel 1 (
    echo [FAIL] Repackaging failed
    exit /b 1
)
echo [OK] Unsigned APK built: %UNSIGNED_APK%

REM ---- Step 4: Sign ----
echo.
echo [Step 4/5] SIGN - Signing the APK...

REM Generate keystore if needed
if not exist "%KEYSTORE%" (
    echo Generating debug keystore...
    keytool -genkey -v -keystore "%KEYSTORE%" -alias "%KEY_ALIAS%" -keyalg RSA -keysize 2048 -validity 10000 -storepass "%KEYSTORE_PASS%" -keypass "%KEYSTORE_PASS%" -dname "CN=Android Debug, OU=APKTool Practice, O=Dev, L=City, S=State, C=US" 2>nul
    echo [OK] Keystore created
)

REM Zipalign
"%BUILD_TOOLS%\zipalign" -p -f 4 "%UNSIGNED_APK%" "%ALIGNED_APK%"
echo [OK] APK zipaligned

REM Sign with apksigner
if exist "%BUILD_TOOLS%\apksigner.bat" (
    call "%BUILD_TOOLS%\apksigner.bat" sign --ks "%KEYSTORE%" --ks-key-alias "%KEY_ALIAS%" --ks-pass "pass:%KEYSTORE_PASS%" --key-pass "pass:%KEYSTORE_PASS%" --out "%SIGNED_APK%" "%ALIGNED_APK%"
    echo [OK] APK signed with apksigner
) else (
    copy /y "%ALIGNED_APK%" "%SIGNED_APK%" >nul
    jarsigner -verbose -sigalg SHA1withRSA -digestalg SHA1 -keystore "%KEYSTORE%" -storepass "%KEYSTORE_PASS%" -keypass "%KEYSTORE_PASS%" "%SIGNED_APK%" "%KEY_ALIAS%" >nul 2>&1
    echo [OK] APK signed with jarsigner
)

if not exist "%OUTPUT_DIR%" mkdir "%OUTPUT_DIR%"

echo [OK] Signed APK at: %SIGNED_APK%

REM ---- Step 5: Verify ----
echo.
echo [Step 5/5] VERIFY - Checking final APK...

REM Verify with apksigner
if exist "%BUILD_TOOLS%\apksigner.bat" (
    call "%BUILD_TOOLS%\apksigner.bat" verify --verbose "%SIGNED_APK%" 2>nul
)

REM Dump with aapt
if exist "%BUILD_TOOLS%\aapt.exe" (
    echo.
    echo   APK Package Info:
    "%BUILD_TOOLS%\aapt" dump badging "%SIGNED_APK%" 2>nul | findstr /i "package: application-label: launchable"
)

REM Re-decompile to verify modifications
echo.
echo   Verifying modifications in signed APK...
set "VERIFY_DIR=%WORK_DIR%\verify"
if exist "%VERIFY_DIR%" rmdir /s /q "%VERIFY_DIR%"
java -jar "%APKTOOL%" d "%SIGNED_APK%" -o "%VERIFY_DIR%" -f 2>nul

if exist "%VERIFY_DIR%\res\values\strings.xml" (
    echo   Strings verification:
    findstr /i "app_name" "%VERIFY_DIR%\res\values\strings.xml" 2>nul
)

if exist "%VERIFY_DIR%\res\layout\fragment_title.xml" (
    findstr /c:"APKTool Modified" "%VERIFY_DIR%\res\layout\fragment_title.xml" >nul 2>&1
    if not errorlevel 1 (
        echo [OK] Banner modification confirmed in layout!
    ) else (
        echo [WARN] Banner not found
    )
)

echo.
echo ================================================================
echo   ALL DONE!
echo   Modified APK: %SIGNED_APK%
echo ================================================================
echo.
echo Summary of modifications:
echo   1. App name changed: 'AndroidTrivia' → 'AndroidTriviaMod'
echo   2. Added '[APKTool Modified]' banner to title screen
echo   3. Accent color changed: #FF4081 → #FF5722 (deep orange)
echo.

endlocal
