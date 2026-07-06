; gatinit - PID 1 minimo: monta fs, spawna shell em ttyS0 e tty0
; -- versao otimizada --
; Mudancas em relacao ao original (todas comportamentalmente identicas):
;   - spawn_shell: removido push/pop rbp/r15 (nao usados / desnecessarios,
;     o kernel preserva registradores em syscall, so rax/rcx/r11 mudam)
;   - spawn_shell: "js .done" removido (redundante, "jnz .done" ja cobre
;     retorno negativo do fork)
;   - spawn_shell: dup2/close reaproveitam edi ja setado (kernel nao mexe
;     nele entre syscalls), ao inves de recarregar 3x
;   - setup_signals: sem frame pointer (rbp nao era usado); fds de
;     signalfd4/epoll_create1 ficam em r12d/r13d ao inves de ir/voltar da memoria
;   - event_loop: epfd/sigfd lidos da memoria UMA vez antes do loop (hot path
;     real do programa) ao inves de toda iteracao
;   - _start: prctl(PR_SET_CHILD_SUBREAPER) nao precisa zerar arg3-5,
;     o kernel os ignora pra essa opcao
;   - zeragem do sigmask via xor+store ao inves de mov imediato 0 (2x)

%define SYS_read            0
%define SYS_write           1
%define SYS_open            2
%define SYS_close           3
%define SYS_ioctl           16
%define SYS_dup2            33
%define SYS_fork            57
%define SYS_execve          59
%define SYS_exit            60
%define SYS_waitid          247
%define SYS_mkdir           83
%define SYS_setsid          112
%define SYS_mount           165
%define SYS_sync            162
%define SYS_reboot          169
%define SYS_getpid          39
%define SYS_prctl           157
%define SYS_rt_sigprocmask  14
%define SYS_signalfd4       289
%define SYS_epoll_create1   291
%define SYS_epoll_ctl       233
%define SYS_epoll_wait      232
%define SYS_nanosleep       35

%define PR_SET_CHILD_SUBREAPER 36
%define SIG_BLOCK       0
%define SIGCHLD         17
%define SIGTERM         15
%define SIGINT          2
%define WEXITED         4
%define WNOHANG         1
%define EPOLL_CTL_ADD   1
%define EPOLLIN         1
%define EPOLLET         (1<<31)

%define MS_NOSUID   2
%define MS_NODEV    4
%define MS_NOEXEC   8
%define MS_RELATIME (1<<21)
%define MF_PROC (MS_NOSUID|MS_NODEV|MS_NOEXEC|MS_RELATIME)
%define MF_SYS  (MS_NOSUID|MS_NODEV|MS_NOEXEC|MS_RELATIME)

%define O_RDWR      2
%define TIOCSCTTY   0x540E
%define RB_MAGIC1   0xfee1dead
%define RB_MAGIC2   0x28121969
%define RB_POWER_OFF 0x4321fedc
%define EPOLL_EVENT_SZ  12
%define SFD_SIGINFO_SZ  128
%define SIGINFO_SZ      128

%macro PRINT 2
    mov eax, SYS_write
    mov edi, 1
    lea rsi, [rel %1]
    mov edx, %2
    syscall
%endmacro

%macro DO_MKDIR 1
    mov eax, SYS_mkdir
    lea rdi, [rel %1]
    mov esi, 0o755
    syscall
%endmacro

%macro DO_MNT 4
    mov eax, SYS_mount
    lea rdi, [rel %1]
    lea rsi, [rel %2]
    lea rdx, [rel %3]
    mov r10d, %4
    xor r8d, r8d
    syscall
%endmacro

section .data
msg_ok   db "[i] mounts ok",10
msg_ok_l equ $-msg_ok
msg_err  db "[!] mount err",10
msg_err_l equ $-msg_err
msg_re   db "[i] respawn",10
msg_re_l equ $-msg_re
msg_sd   db "[i] shutdown",10
msg_sd_l equ $-msg_sd
msg_ef   db "[!] exec failed",10
msg_ef_l equ $-msg_ef

pp  db "/proc",0
psy db "/sys",0
fp  db "proc",0
fss db "sysfs",0

shp db "/bin/sh",0
sn  db "sh",0
sa  dq sn, 0

; dois terminais: serial e VGA
tty_serial db "/dev/ttyS0",0
tty_vga    db "/dev/tty0",0

e0 db "PATH=/usr/local/sbin:/usr/local/bin:/usr/sbin:/usr/bin:/sbin:/bin",0
e1 db "HOME=/root",0
e2 db "TERM=linux",0
e3 db "USER=root",0
e4 db "SHELL=/bin/sh",0
se dq e0,e1,e2,e3,e4,0

section .bss
sigfd_v  resd 1
epfd_v   resd 1
sigmask  resq 2
sfd_info resb SFD_SIGINFO_SZ
siginfo  resb SIGINFO_SZ
evbuf    resb EPOLL_EVENT_SZ

section .text
global _start

_start:
    mov  eax, SYS_getpid
    syscall
    cmp  eax, 1
    jne  .die

    ; PR_SET_CHILD_SUBREAPER: kernel ignora arg3-5 pra essa opcao,
    ; entao nao precisa zerar edx/r10/r8
    mov  eax, SYS_prctl
    mov  edi, PR_SET_CHILD_SUBREAPER
    mov  esi, 1
    syscall

    ; monta proc e sys
    DO_MKDIR pp
    DO_MNT   fp,  pp,  fp,  MF_PROC
    DO_MKDIR psy
    DO_MNT   fss, psy, fss, MF_SYS
    PRINT    msg_ok, msg_ok_l

    ; spawna shell no serial (ttyS0) e na VGA (tty0)
    lea  rdi, [rel tty_serial]
    call spawn_shell
    lea  rdi, [rel tty_vga]
    call spawn_shell

    ; setup sinais e event loop
    call setup_signals
    call event_loop

.die:
    mov  eax, SYS_exit
    mov  edi, 1
    syscall

; spawn_shell: faz fork, redireciona fds pro terminal em [rdi], execve /bin/sh
; rdi = ponteiro pra string do terminal (ex: "/dev/ttyS0")
; obs: nao precisa salvar/restaurar registradores porque _start nao
; depende de r15 sobreviver a chamada, e rbp nunca eh usado aqui.
spawn_shell:
    mov  r15, rdi           ; salva ponteiro do terminal

    PRINT msg_re, msg_re_l

    mov eax, SYS_fork
    syscall
    test eax, eax
    jnz  .done              ; !=0: pai (>0) ou erro (<0), ambos retornam

    ; filho
    mov eax, SYS_setsid
    syscall

    ; abre o terminal
    mov eax, SYS_open
    mov rdi, r15
    mov esi, O_RDWR
    xor edx, edx
    syscall
    test eax, eax
    js   .exec_anyway       ; se nao abriu, tenta exec mesmo assim
    mov  r15d, eax

    ; dup2 stdin/stdout/stderr (edi fica com o fd o tempo todo, kernel
    ; nao mexe nele entre syscalls, entao seta so uma vez)
    mov eax, SYS_dup2
    mov edi, r15d
    xor esi, esi
    syscall
    mov eax, SYS_dup2
    mov esi, 1
    syscall
    mov eax, SYS_dup2
    mov esi, 2
    syscall
    mov eax, SYS_close
    syscall

    ; define como terminal controlador
    mov eax, SYS_ioctl
    xor edi, edi
    mov esi, TIOCSCTTY
    xor edx, edx
    syscall

.exec_anyway:
    mov eax, SYS_execve
    lea rdi, [rel shp]
    lea rsi, [rel sa]
    lea rdx, [rel se]
    syscall

    ; execve falhou
    mov eax, SYS_write
    mov edi, 2
    lea rsi, [rel msg_ef]
    mov edx, msg_ef_l
    syscall
    mov eax, SYS_exit
    mov edi, 1
    syscall

.done:
    ret

; setup_signals: sem frame pointer (nao usado). Mantem sigfd/epfd em
; r12d/r13d durante a montagem do epoll_ctl pra evitar reload de memoria.
setup_signals:
    lea  rdi, [rel sigmask]
    xor  eax, eax
    mov  [rdi], rax
    mov  [rdi+8], rax
    bts  qword [rdi], SIGCHLD
    bts  qword [rdi], SIGTERM
    bts  qword [rdi], SIGINT

    mov  eax, SYS_rt_sigprocmask
    mov  edi, SIG_BLOCK
    lea  rsi, [rel sigmask]
    xor  edx, edx
    mov  r10d, 8
    syscall

    mov  eax, SYS_signalfd4
    mov  edi, -1
    lea  rsi, [rel sigmask]
    mov  edx, 8
    mov  r10d, 0x80000
    syscall
    mov  r12d, eax                  ; cache do sigfd
    mov  dword [rel sigfd_v], eax

    mov  eax, SYS_epoll_create1
    mov  edi, 0x80000
    syscall
    mov  r13d, eax                  ; cache do epfd
    mov  dword [rel epfd_v], eax

    sub  rsp, EPOLL_EVENT_SZ
    mov  dword [rsp], EPOLLIN|EPOLLET
    mov  dword [rsp+4], r12d
    mov  eax, SYS_epoll_ctl
    mov  edi, r13d
    mov  esi, EPOLL_CTL_ADD
    mov  edx, r12d
    lea  r10, [rsp]
    syscall
    add  rsp, EPOLL_EVENT_SZ
    ret

; event_loop: epfd/sigfd carregados uma unica vez da memoria antes do
; loop principal (esse eh o hot path real do programa).
event_loop:
    mov  r12d, dword [rel epfd_v]
    mov  r13d, dword [rel sigfd_v]
.top:
    mov  eax, SYS_epoll_wait
    mov  edi, r12d
    lea  rsi, [rel evbuf]
    mov  edx, 1
    mov  r10d, -1
    syscall
    test eax, eax
    jle  .top
    mov  eax, SYS_read
    mov  edi, r13d
    lea  rsi, [rel sfd_info]
    mov  edx, SFD_SIGINFO_SZ
    syscall
    test eax, eax
    jle  .top
    mov  eax, dword [rel sfd_info]
    cmp  eax, SIGCHLD
    je   .child
    ; SIGTERM/SIGINT: shutdown
    PRINT msg_sd, msg_sd_l
    mov  eax, SYS_sync
    syscall
    sub  rsp, 16
    mov  qword [rsp], 0
    mov  qword [rsp+8], 200000000
    mov  eax, SYS_nanosleep
    mov  rdi, rsp
    xor  esi, esi
    syscall
    add  rsp, 16
    mov  eax, SYS_reboot
    mov  edi, RB_MAGIC1
    mov  esi, RB_MAGIC2
    mov  edx, RB_POWER_OFF
    xor  r10d, r10d
    syscall
.halt: hlt
    jmp .halt
.child:
    ; reap
    mov  eax, SYS_waitid
    xor  edi, edi
    mov  esi, -1
    lea  rdx, [rel siginfo]
    mov  r10d, WEXITED|WNOHANG
    xor  r8d, r8d
    syscall
    jmp  .top
