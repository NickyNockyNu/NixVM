cls
..\bin\nvmc %1.pas -s %1.asm -v
type %1.asm
..\bin\nvmtest %1.nvm
