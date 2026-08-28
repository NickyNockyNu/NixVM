cls
..\bin\nvmc %1.pas -s %1.asm -v
@IF %ERRORLEVEL% NEQ 0 EXIT /b 1
type %1.asm
..\bin\nvmtest %1.nvm
:exit
