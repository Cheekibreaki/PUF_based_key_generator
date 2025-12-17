@echo off
REM Clean compilation script for new PUF/TRNG protocols

REM Remove old compiled files
if exist work rmdir /s /q work

REM Create work library
vlib work

REM Compile files in dependency order
echo Compiling fuzzyextractor.v...
vlog +acc fuzzyextractor.v
if errorlevel 1 goto error

echo Compiling secure_key_system.v...
vlog +acc secure_key_system.v
if errorlevel 1 goto error

echo Compiling HMAC files...
vlog +acc hmac_controller.v
if errorlevel 1 goto error

vlog +acc hmac_top.v
if errorlevel 1 goto error

echo Compiling Keccak/SHA3 files...
vlog +acc keccak_top.v
if errorlevel 1 goto error

vlog +acc keccak.v
if errorlevel 1 goto error

vlog +acc f_permutation.v
if errorlevel 1 goto error

vlog +acc round.v
if errorlevel 1 goto error

vlog +acc rconst.v
if errorlevel 1 goto error

vlog +acc padder.v
if errorlevel 1 goto error

vlog +acc padder1.v
if errorlevel 1 goto error

echo Compiling testbench...
vlog +acc secure_key_system_tb_new.v
if errorlevel 1 goto error

echo.
echo ===================================
echo Compilation successful!
echo ===================================
echo.
echo To run simulation, use:
echo   vsim -c secure_key_system_tb_new -do "run -all; quit"
echo.
goto end

:error
echo.
echo ===================================
echo Compilation FAILED!
echo ===================================
pause
exit /b 1

:end
