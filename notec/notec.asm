section .bss
        align 8
        forwho  resd N + 1               ; forwho[i]-1 is the Noteć id for which i is waiting.
        values  resq N + 1               ; Values to swap after succedful connection.
        succ    resb N + 1               ; Vector of booleans for locking threads.
        
global notec
extern debug

section .text

notec:
                                         ; Saving the stack and preparing the registers.
        push    r12                      ; r12 -- a place to store stack address for calls.
        push    r13                      ; r13 -- a place to store the start stack address.
        push    r14                      ; r14 -- if the program is in number input mode.
        push    r15                      ; r15 -- accumulator for the inputted number.
        push    rbx                      ; rbx -- points to the text,
        push    rbp                      ; rbp -- n.
                                         ; rdi -- will be used as temporary registers i.e.  for swaps.
        mov     r13, rsp   
        mov     rbx, rsi
        mov     rbp, rdi
        
        xor     r12, r12 
        xor     r14, r14
        xor     r15, r15

while:                                   ; Main loop for iterating through the text input.
        cmp     [rbx], byte 0            ; if (next_char == '\0')
        je      endwhile                 ;      end loop
        
        cmp     [rbx], byte '0'          ; if (next_char < '0')
        jb      nothex                   ;      it is not a part of a hex encoded number.
        
        cmp     [rbx], byte 'f'          ; if (next_char > 'f')
        ja      nothex                   ;      it is not a part of a hex encoded number.
    
        cmp     [rbx], byte 'F'          ; if (next_char <= 'F')
        jbe     hex                      ;      it is in [0, 9] u [a, f] u [A, F] u {=}.
        
        cmp     [rbx], byte 'a'          ; if (next_char < 'a')
        jb      nothex                   ;      it is not a part of a hex encoded number.
        
hex:
        cmp     [rbx], byte '='          ; Check for '=' sign, because for the sake of simplicty
        jne     truehex                  ; we assumed it is a part of the hex encoding.

        cmp     r14, 0        
        je      incr                     ; It is not in number-reading mode. 
        
        xor     r14, r14                 ; It is in number-reading mode. 
        push    r15                      ; Hence save the current number on the stack and exit
        jmp     incr                     ; the mode.
        
truehex:
        xor     rax, rax                 ; Conversion of next_char to decimal value in rax. 
        
        cmp     [rbx], byte '9'        
        ja      capital
        
        mov     al, [rbx]                ; next_char \in [0, 9].
        sub     rax, '0'
        
        jmp     converted

capital:
        cmp     [rbx], byte 'F'
        ja      small
        
        mov     al, [rbx]                ; next_char \in [A, F].
        sub     rax, 'A'
        add     rax, 0xA
        
        jmp     converted

small:
        mov     al, [rbx]                ; next_char \in [a, f].
        sub     rax, 'a'
        add     rax, 0xA

converted:
        cmp     r14, 0                   ; Was it the first digit?
        jne     nexthex                  ; No.
        
        inc     r14                      ; Yes.
        mov     r15, rax                 ; Then just add it.
        jmp     incr
                
nexthex:
        shl     r15, 4                   ; Then first shift the accumulator and after that
        add     r15, rax                 ; add the next_char.
        jmp     incr
        
nothex:
        cmp     r14, 0                   ; Check if the program is exiting the numer-reading mode.
        je      addsig
        

        xor     r14, r14                 ; If yes, push the value from the accumulator to the stack.
        push    r15

addsig:                                  ; Addition sign.
        cmp     [rbx], byte '+'
        jne     mulsig
        
        pop     rax
        pop     rdi
        add     rax, rdi                ; Adding the two topmost values together.
        
        push    rax

        jmp     incr
        
mulsig:                                  ; Multipliaction sign.
        cmp     [rbx], byte '*'
        jne     minsig
        
        pop     rax
        pop     rdi
        mul     rdi                      ; Multiplying the two topmost values together.
        
        push    rax

        jmp     incr
        
minsig:                                  ; Arithmetic negation (minus) sign.    
        cmp     [rbx], byte '-'
        jne     andsig
        
        pop     rax 
        neg     rax                      ; Multiply the topmost value by -1.
        
        push    rax
        
        jmp     incr        
        
andsig:                                  ; And sign.        
        cmp     [rbx], byte '&'
        jne     orsig
        
        pop     rax 
        pop     rdi    
        and     rax, rdi                ; 'And' two topmost values together.
        
        push    rax

        jmp     incr
        
orsig:                                  ; 'Or' sign.
        cmp     [rbx], byte '|'
        jne     xorsig
        
        pop     rax 
        pop     rdi     
        or      rax, rdi                ; 'Or' two topmost values together.
        
        push    rax

        jmp     incr
        
xorsig:                                  ; 'Xor' sign.        
        cmp     [rbx], byte '^'
        jne     notsig
        
        pop     rax 
        pop     rdi    
        xor     rax, rdi                ; 'Xor' two topmost values together.
        
        push    rax

        jmp     incr

notsig:                                  ; 'Not' sign.            
        cmp    [rbx], byte '~'
        jne    snsig
        
        pop     rax     
        not     rax                      ; Perform bitwise negation of the topmost value.       
        
        push    rax
        
        jmp     incr

snsig:                                   ; Push the n on the stack.                                              
        cmp     [rbx], byte 'n'
        jne     nsig
        
        push    rbp

        jmp     incr
        
nsig:                                    ; Push the N on the stack.
        cmp     [rbx], byte 'N'
        jne     xsig
        
        push    N 
        
        jmp     incr
        
xsig:                                    ; Swap the two topmost values.  
        cmp     [rbx], byte 'X'
        jne     ysig
        
        pop     rax 
        pop     rdi 
        
        push    rax 
        push    rdi
        
        jmp     incr

ysig:                                    ; Duplicate the topmost values.
        cmp     [rbx], byte 'Y'
        jne     zsig
        
        pop     rax 
        
        push    rax
        push    rax
        
        jmp     incr
    
zsig:                                    ; Remove the topmost value.
        cmp     [rbx], byte 'Z'
        jne     sgsig
        
        pop     rax 
        
        jmp     incr

sgsig:                                   ; Calling the debug().
        cmp     [rbx], byte 'g'
        jne     wsig
        
        mov     r12, rsp                 ; Save the stack.
        mov     rsi, rsp                 ; Set the arguments for debug().
        mov     rdi, rbp
        
        mov     rax, rsp                 ; If needed create the shadow space on the stack.
        and     rax, 0xF
        cmp     rax, 8
        jne     ok                       ; No need for that.
        sub     rsp, 8
        
ok:        
        call    debug                   
        
        mov     rsp, r12                 ; Restore the stack.

        mov     rdi, 8
        mul     rdi
        add     rsp, rax                 ; Move the stack according to the debug return value.

        jmp     incr
        
wsig:                                    ; Waiting for another Noteć to perform a swap.
        cmp     [rbx], byte 'W'
        jne     incr
        
        inc     rbp                      ; Temporary increase n (indexing is from 1).
        
        lea     r8,  [rel values]        ; Save relalative addresses.
        lea     r9,  [rel forwho]
        lea     r10, [rel succ]
        
bramka:                                  ; A gate to be lifted by other Noteć after finishing exchange.
        cmp     [r10 + rbp], byte 0      ; If it is closed - wait.
        jne     bramka
        
        pop     rdi                      ; Get the partner id.
        inc     rdi
        
        pop     rsi                      ; Transfer the value from the stack to the shared memory.
        mov     [r8  + 8 * rbp], rsi
        
        mov     [r9  + 4 * rbp], edi     ; Set the information that we are waiting and for who.
        
wait1:
        cmp     [r9  + 4 * rdi], ebp     ; Wait for partner for exchange.
        jne     wait1
        
        push    qword [r8  + 8 * rdi]    ; If they are found, copy their value from the shared memory
        mov     [r10 + rbp], byte 1      ; and close the gate to indicate finishing our part of the                
                                         ; exchnage.        
wait2:
        cmp     [r10 + rdi], byte 1      ; Wait for the partner to read our value.
        jne     wait2
        
        mov     [r9  + 4 * rbp], dword 0 ; Set that we are no longer waiting for anyone to exchange.
        mov     [r10 + rdi], byte 0      ; Open the partner's gate to allow them to access his critical
                                         ; section again.
        dec     rbp                      ; Revert the n to its original value.
                
incr:
        inc     rbx                      ; Move to the next character in the program input.
        jmp     while                    ; Go to the beginning of the loop, where the conditions are
                                         ; checked.
endwhile:        
        cmp     r14, 0                   ; Check if after the end of parsing the input there is
        je      genret                   ; an unpushed value in the accumulator.
        
        push    r15

genret:        
        pop     rax                      ; Transfer the return value to rax.
        
        mov     rsp, r13                 ; Restoring the stack.
        
        pop     rbp                      ; Restoring the modified registers.
        pop     rbx
        pop     r15
        pop     r14
        pop     r13
        pop     r12
        
        ret
