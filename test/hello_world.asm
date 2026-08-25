.include "target_test.inc"

.heap  0
.stack 128

call SayHello
halt

SayHello:
  mov r0, fmtstr
  mov r1, hellostr
  mov r2, worldstr
  syscall 1
  ret
  
fmtstr: .str "%s, %s!", 13, 10, 0

hellostr: .str "Hello", 0
worldstr: .str "World", 0