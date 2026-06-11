@echo off
REM APKTool wrapper for Windows — forwards all arguments to apktool.jar
set "SCRIPT_DIR=%~dp0"
java -jar "%SCRIPT_DIR%apktool.jar" %*
