section .data
mi   db "[i]",0
me   db "[!]",0
nl   db 10,0
mp   db "p",0
ms   db "s",0
md   db "d",0
pp   db "/proc",0
psy  db "/sys",0
pd   db "/dev",0
fp   db "proc",0
fss  db "sysfs",0
fd   db "devtmpfs",0
shp  db "/bin/sh",0
sn   db "sh",0
sa   dq sn,0
e0   db "PATH=/usr/local/sbin:/usr/local/bin:/usr/sbin:/usr/bin:/sbin:/bin",0
e1   db "HOME=/root",0
e2   db "TERM=linux",0
e3   db "USER=root",0
e4   db "SHELL=/bin/sh",0
se   dq e0,e1,e2,e3,e4,0
selfp  db "/proc/self/exe",0
selfn  db "init",0
selfa  dq selfn,0

align 16
sact:
    times 152 db 0

section .bss
ws      resq 1
shd     resb 1
exepath resb 256

section .text
global _start

rst:
    mov eax,15
    syscall

_start:
    mov eax,39
    syscall
    cmp eax,1
    jne x
    call sig
    call mnt
    mov eax,89
    lea rdi,[rel selfp]
    lea rsi,[rel exepath]
    mov edx,255
    syscall
    test eax,eax
    js .norsp
    mov eax,57
    syscall
    test eax,eax
    js .norsp
    jz .rspchild
    mov r14d,eax
.rspwait:
    mov eax,61
    mov edi,-1
    lea rsi,[rel ws]
    mov edx,1
    xor r10d,r10d
    syscall
    test eax,eax
    jle .rspwait
    cmp eax,r14d
    jne .rspwait
    mov eax,59
    lea rdi,[rel exepath]
    lea rsi,[rel selfa]
    lea rdx,[rel se]
    syscall
.rspchild:
.norsp:
.l:
    cmp byte[rel shd],1
    je .sd
    mov eax,57
    syscall
    test eax,eax
    js .l
    jz .c
    mov r15d,eax
.wl:
    mov eax,61
    mov edi,-1
    lea rsi,[rel ws]
    mov edx,1
    xor r10d,r10d
    syscall
    test eax,eax
    jle .wl
    cmp eax,r15d
    jne .wl
    cmp byte[rel shd],1
    je .sd
    jmp .l
.c:
    mov eax,112
    syscall
    mov eax,59
    lea rdi,[rel shp]
    lea rsi,[rel sa]
    lea rdx,[rel se]
    syscall
    mov eax,60
    mov edi,1
    syscall
.sd:
    mov eax,62
    mov edi,-1
    mov esi,15
    syscall
    xor eax,eax
    push rax
    push 500000000
    mov rdi,rsp
    xor esi,esi
    mov al,35
    syscall
    add rsp,16
    mov eax,62
    mov edi,-1
    mov esi,9
    syscall
    xor eax,eax
    push rax
    push 200000000
    mov rdi,rsp
    xor esi,esi
    mov al,35
    syscall
    add rsp,16
.wf:
    mov eax,61
    mov edi,-1
    lea rsi,[rel ws]
    mov edx,1
    xor r10d,r10d
    syscall
    test eax,eax
    jg .wf
    mov eax,169
    mov edi,0xfee1dead
    mov esi,0x28121969
    mov edx,0x4321fedc
    xor r10d,r10d
    syscall
.hl:
    hlt
    jmp .hl

x:
    mov eax,60
    mov edi,1
    syscall

sig:
    push rbp
    mov rbp,rsp
    lea rbx,[rel sact]
    lea rax,[rel shc]
    mov qword[rbx],rax
    mov rax,0x14000000
    mov qword[rbx+8],rax
    lea rax,[rel rst]
    mov qword[rbx+16],rax
    mov eax,13
    mov edi,17
    mov rsi,rbx
    xor edx,edx
    mov r10d,8
    syscall
    lea rax,[rel sht]
    mov qword[rbx],rax
    lea rax,[rel rst]
    mov qword[rbx+16],rax
    mov eax,13
    mov edi,2
    mov rsi,rbx
    xor edx,edx
    mov r10d,8
    syscall
    mov eax,13
    mov edi,15
    mov rsi,rbx
    xor edx,edx
    mov r10d,8
    syscall
    pop rbp
    ret

shc:
    push rax
    push rdx
    push rsi
    push rdi
    push r10
    push r11
.lp:
    mov eax,61
    mov edi,-1
    lea rsi,[rel ws]
    mov edx,1
    xor r10d,r10d
    syscall
    test eax,eax
    jg .lp
    pop r11
    pop r10
    pop rdi
    pop rsi
    pop rdx
    pop rax
    ret

sht:
    mov byte[rel shd],1
    ret

mnt:
    push rbp
    mov rbp,rsp
    push r12

    lea rdi,[rel mi]
    call pw
    lea rdi,[rel mp]
    call pw
    mov eax,83
    lea rdi,[rel pp]
    mov esi,0x1ed
    syscall
    mov eax,165
    lea rdi,[rel fp]
    lea rsi,[rel pp]
    lea rdx,[rel fp]
    xor r10d,r10d
    xor r8d,r8d
    syscall
    mov r12d,eax

    lea rdi,[rel mi]
    call pw
    lea rdi,[rel ms]
    call pw
    mov eax,83
    lea rdi,[rel psy]
    mov esi,0x1ed
    syscall
    mov eax,165
    lea rdi,[rel fss]
    lea rsi,[rel psy]
    lea rdx,[rel fss]
    xor r10d,r10d
    xor r8d,r8d
    syscall
    or r12d,eax

    lea rdi,[rel mi]
    call pw
    lea rdi,[rel md]
    call pw
    mov eax,83
    lea rdi,[rel pd]
    mov esi,0x1ed
    syscall
    mov eax,165
    lea rdi,[rel fd]
    lea rsi,[rel pd]
    lea rdx,[rel fd]
    xor r10d,r10d
    xor r8d,r8d
    syscall
    or r12d,eax

    test r12d,r12d
    jns .ok
    lea rdi,[rel me]
    call pw
    lea rdi,[rel mp]
    call pw
.ok:
    lea rdi,[rel nl]
    call pw
    pop r12
    pop rbp
    ret

pw:
    push rbp
    mov rbp,rsp
    push rdi
    xor rcx,rcx
.sl:
    cmp byte[rdi+rcx],0
    je .sd
    inc rcx
    jmp .sl
.sd:
    pop rsi
    mov rdx,rcx
    mov eax,1
    mov edi,1
    syscall
    pop rbp
    ret
