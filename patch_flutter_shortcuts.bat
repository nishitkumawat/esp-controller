@echo off
REM Patch flutter_shortcuts library to add namespace

SET PLUGIN_DIR=%USERPROFILE%\.pub-cache\hosted\pub.dev\flutter_shortcuts-1.3.0\android

IF EXIST "%PLUGIN_DIR%\build.gradle" (
    echo Patching flutter_shortcuts build.gradle...
    powershell -Command "(Get-Content '%PLUGIN_DIR%\build.gradle') -replace '(android \{)', 'android {`n    namespace \"dev.nish.flutter_shortcuts\"' | Set-Content '%PLUGIN_DIR%\build.gradle'"
    echo Done.
) ELSE (
    echo build.gradle not found in %PLUGIN_DIR%
)
pause
