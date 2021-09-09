SIZE    equ     2000                     ; Sizes of the buffers.
SIZE2   equ     4004                     ; outbuff will have to be two times + 4 bigger. 
EXIT    equ     60                       ; Exit - syscall number.
WRITE   equ     1                        ; Writing - syscall number.
STDOUT  equ     1                        ; Number indicating STDOUT.
MASKCB  equ     0b10000000               ; Masks for zeroing encoding bytes: continuation byte
MASK2B  equ     0b11000000               ; 2-byte encoding
MASK3B  equ     0b11100000               ; 3-byte encoding
MASK4B  equ     0b11110000               ; 4-byte encoding
MOD     equ     0x10FF80                 ; Modulo value for calculating polynomial.
UTF8MAX equ     0x10FFFF                 ; Our "utf8" maximum value.
SMALL4  equ     0x10000                  ; Smallest value to encode on 4-bytes
SMALL3  equ     0x800                    ; Smallest value to encode on 3-bytes
SMALL2  equ     0x80                     ; Smallest value to encode on 2-bytes

%macro modulo 1                          ; Perform %1 %= MOD. Invalidates r8.
        xor     rdx, rdx                 ; Zero rdx for div.
        mov     rax, %1                  ; Place rdx in rax for div.
        mov     r8, MOD                  ; Set the value of modulo to MOD.
        div     r8                       ; Divide rax by r8. The remainder will be in rdx.
        mov     %1, rdx                  ; Retrieve the remainder from rdx.
%endmacro

%macro conbyte 0                         ; Transfers one continuation byte from r15 to r9.
        xor     r9, r9                   ; Clear r9.
        mov     r9b, r15b                ; Copy 8 lowest bits from r15 to r9.
        and     r9b, 0x3F                ; Zero two highest bits.
        add     r9b, 0x80                ; Set two highest bits to 0b10.
        shr     r15, 6                   ; Remove last 6 bits from r15.
%endmacro

%macro sigbyte 2                         ; Transfers byte-signaling byte from r15 to r9.
                                         ; %1 -- mask to zero the highest bits.
                                         ; %2 -- encoding for the highest bits.
        xor     r9, r9                   ; Clear r9.
        mov     r9b, r15b                ; Copy 8 lowest bits from r15 to r9.
        and     r9b, %1                  ; Use %1 mask on r9b.
        add     r9b, %2                  ; Use %2 mask on r9b. 
%endmacro

%macro readin 1                          ; Reads up to %1 bytes to inbuff.
        xor     rax, rax                 ; rax -- set to 0 means reading.
        xor     rdi, rdi                 ; rdi -- set to 0 means stdin is the source.
        mov     rsi, inbuff              ; rsi -- address to write the read data to.
        mov     rdx, %1                  ; rdx -- max number of bytes to read.  
        syscall                          ; Evaluate. 
%endmacro                                ; rax will contain the number of bytes actually read.

%macro writeout 0                        ; Writes r14 bytes from the outbuff to stdout.
        mov     rax, WRITE               ; rax -- set to WRITE means writing.
        mov     rdi, STDOUT              ; rdi -- set to STDOUT tell where the output will be.
        mov     rsi, outbuff             ; rsi -- sets outbuff to be the source of data.
        mov     rdx, r14                 ; r14 -- number of bytes to be written.
        syscall                          ; Evaluate.
%endmacro

section .bss
        inbuff  resb SIZE                ; Buffer for reading the input from stdin.
        outbuff resb SIZE2               ; Buffer for wrting to stdout.
        
section .text
        global _start
        
_start:
        cmp     [rsp], byte 1            ; Check for correct number of parameters - n > 0,
        jbe     error                    ; however [rsp] == n + 1.
        
        xor     rbx, rbx                 ; rbx is a temporary iterartor for arguments.
        inc     rbx                      ; We set it to 1 so it points to the first
                                         ; polynomial coefficient.
        
bloop:                                   ; Big, outer loop for converting string args to ints.    
        cmp     rbx, [rsp]               ; while (iterator < n)
        jae     bend
                                         ; Set after-mentioned to 0:
        xor     r13, r13                 ; r13 -- iterator for string,
        xor     r15, r15                 ; r15 -- integer equivalent of the string [r10, r10+r13-1].
        
        mov     r10, [rsp+8+8*rbx]       ; r10 -- pointer to the currently processed string.
        
loop1:                                   ; Inner loop, iterating through the string.
        cmp     [r10+r13], byte 0        ; while (*iterator != '\0')
        je      end1
               
        mov     rax, 10                  ; r15 *= 10
        mul     r15
        mov     r15, rax
        
        xor     r9, r9                   ; r9  -- temporary container for processed character
        mov     r9b, [r10+r13] 
                                         ; Validation of program parameters.
        cmp     r9, 48                   ; if (r9 < 48 or 57 < r9)  
        jb      error                    ;      end with error code 1  
        cmp     r9, 57                   ; else
        ja      error                    ;      proceed
        
        sub     r9, 48                   ; To get the digit values subtract 48 ('0').
        add     r15, r9                  ; Add new digit to r15.
        modulo  r15                      ; Check the value with modulo macro.
        
        inc     r13                      ; r13++  -- increment the iterator.
        jmp     loop1
end1:                                    ; Finished processing rbx-th string argument.

        mov     [rsp+8+8*rbx], QWORD r15 ; Replace the string pointer with numeric value.   
        inc     rbx                      ; rbx++  -- increment the iterator.
        jmp     bloop
bend:                                    ; Finished converting polynomial coefficients.
                                         ; Hereinafter:
                                         ; [rsp] -- number of coefficients + 1
                                         ; [rsp+8+8*k] -- k-th coefficient

read:                                
        mov     [rsp+8], byte 0          ; We use the unused '1st' parameter to indicate encodings
                                         ; broken by reding to the buffer.
                                         
        readin  SIZE                     ; Read up to SIZE bytes from the stdin to the inbuff.
        mov     r12, rax                 ; r12 -- number of bytes read to the buffer.
        
        cmp     rax, 0                   ; if (nothing was read)
        je      end                      ;      exit with code 0
        
        xor     r13, r13                 ; r13 -- iterator for the inbuffer.
        xor     r14, r14                 ; r14 -- iterator for the outbuffer.       
        
convert:                                 ; The loop converting utf8 from inbuff to uint.
                                         ; Checks whether encoding was correct,
                                         ; calculates w(x - 0x80) + 0x80, converts it back to utf8
                                         ; and writes it to outbuff.
                                         
        xor     r15, r15                 ; r15 -- utf8-encoded value.
        xor     rbx, rbx                 ; rbx -- counter of continuation bytes.
                                         ; Let c = [inbuff+r13] in:   
        cmp     [inbuff+r13], byte 0x80  ; if (c >= 0x80) 
        jae     big                      ;      Character is not 1-byte-encoded, go to 'big'.
        mov     al, [inbuff+r13]         ; else
        mov     [outbuff+r14], al        ;      Copy c to the end of the outbuff as it is.
        inc     r14                      ; r14++;
        jmp     endconv                  ; do {convert} while (condition at endconv)
        
big:                                     ; The character is encoded on 2-4 bytes.       
        cmp     [inbuff+r13], byte 0xF8  ; if (c >= 0xF8) -- it is too big
        jae     error                    ;      exit with error code 1
        
        cmp     [inbuff+r13], byte 0xF0  ; if (0xF0 <= c <= 0xF7) -- 4-byte codepoint
        jae     bytes4                   ;      go to the 4-byte section
        
        cmp     [inbuff+r13], byte 0xE0  ; if (0xE0 <= c <= 0xEF) -- 3-byte codepoint
        jae     bytes3                   ;      go to the 3-byte section
        
        cmp     [inbuff+r13], byte 0xC2  ; if (0xC2 <= c <= 0xDF) -- 2-byte codepoint
        jae     bytes2                   ;      go to the 2-byte section
                                        
                                         ; else -- c is either invalid or a continuation byte
        jmp     error                    ;      exit with error code 1
        
bytes4:                                  ; 4-byte section
        mov     rbx, 3                   ; rbx -- 3 continuation bytes required.
        mov     rbp, SMALL4              ; The smallest value to encode in 4 bytes.
                                         ; Get value from the first byte of encoding:
        mov     r15b, [inbuff+r13]       ; Copy c to to r15.
        xor     r15, MASK4B              ; Zero the encoding bytes.
        shl     r15, 18                  ; The 1st bit of the 1st byte of the 4-byte utf8-encoded
                                         ; character is the 19th bit of its binary value.
        jmp     conbs                    ; Go to the continuation bytes management section.
                                        
bytes3:                                  ; 3-byte section
        mov     rbx, 2                   ; rbx -- 2 continuation bytes required.
        mov     rbp, SMALL3              ; The smallest value to encode in 3 bytes.
                                         ; Get value from the first byte of encoding:
        mov     r15b, [inbuff+r13]       ; Copy c to to r15.
        xor     r15, MASK3B              ; Zero the encoding bytes.
        shl     r15, 12                  ; The 1st bit of the 1st byte of the 3-byte utf8-encoded
                                         ; character is the 13th bit of its binary value.       
        jmp     conbs                    ; Go to the continuation bytes management section.
        
bytes2:                                  ; 2-byte section
        mov     rbx, 1                   ; rbx -- 1 continuation byte required.
        mov     rbp, SMALL2              ; The smallest value to encode in 2 bytes.
                                         ; Get value from the first byte of encoding:        
        mov     r15b, [inbuff+r13]       ; Copy c to to r15.
        xor     r15, MASK2B              ; Zero the encoding bytes.
        shl     r15, 6                   ; The 1st bit of the 1st byte of the 2-byte utf8-encoded
                                         ; character is the 7th bit of its binary value.        
        
conbs:                                   ; Continuation bytes management section:
        cmp     rbx, 0                   ; Check if there are any more continuation bytes to read.
        je      shortest                 ; If not, go to the was-it-the-shortest validation point. 

        inc     r13                      ; r13++ -- move to the next byte in inbuff.
        cmp     r13, r12                 ; if (r13 >= r12) -- inbuff ended and we need rbx more bytes.
        jb      suffic                   ; else -- there are still bytes to process, 
                                         ;      go to 'sufficient' section.
                                         
        xor     r13, r13                 ; Read rbx more bytes to the beginning of inbuff
        readin  rbx                      ; and treat them as continuation bytes.
        mov    [rsp+8], byte 1           ; We set the flag to 1.
        
        cmp     rax, rbx                 ; If there were less than rbx bytes read,
        jb      error                    ;      exit with error code 1.
        
suffic:
        cmp     [inbuff+r13], byte 0xC0  ; For c to be a correct continuation byte it has to satisfy:
        jae     error                    ; (0x7F < c < 0xC0). If it does not - exit with 
        cmp     [inbuff+r13], byte 0x7F  ; error code 1.
        jbe     error
        

        xor     r9, r9                   ; r9  -- value of the currently decoded byte. 
        mov     r8, 6                    ; r8  -- temporary constant = 6 for mul and sub.

        mov     r9b, [inbuff+r13]        ; Copy c to r9.
        xor     r9, MASKCB               ; Zero the encoding bytes.
        
        mov     rax, rbx                 ; rax = (rbx - 1) * 6 
        mul     r8                       ; rax -- the number of bytes to shift-left r9.
        sub     rax, r8
        
        mov     cl, al                   ; We move rax to rcx to be able to use variable in shifting.
        shl     r9, cl                   ; Shift left according to the position of that byte in the
                                         ; current encoding.
        add     r15, r9                  ; Add it to the character decoded value.

        dec     rbx                      ; rbx-- -- We need one byte less.
        jmp     conbs                    ; while-loop jump.
        
shortest:                                ; Was-it-the-shortest validation point
        cmp     r15, rbp                 ; If the decoded value is greater than or equal to 
                                         ; the smallest value to encode in k bytes, go to 
        jae     poly                     ; the computation of polynomial section
                                         ; else
        jmp     error                    ;      exit with error code 1   
                
poly:                                    ; The computation of polynomial section.
        cmp     r15, UTF8MAX             ; Check if the decoded value does not exceed utf8 range.
        ja      error                    ; If it does, exit with error code 1.
        
        sub     r15, 0x80                ; Let r15 = r15 - 0x80 for the computation of polynomial.                

        xor     r9, r9                   ; r9  -- iterator for polynomial coefficients.
        inc     r9                       ; We set it to 1 for simplicity.
        xor     r10, r10                 ; r10 -- partial sums of w (x - 0x80).
        xor     r11, r11                 ; Consecutive powers of r15.
        inc     r11                      ; We start from r15^0.
        
polyloop:
        cmp     r9, [rsp]                ; while (iterator < number of coefficients)
        jae     endploop
        
        mov     rax, [rsp+8+8*r9]        ; Multiply x^(r9-1) by (r9-1)th coefficient.
        mul     r11
        
        add     r10, rax                 ; (result += result of above multiplication)  mod MOD
        modulo  r10
            
        mov     rax, r11                 ; Increase the power of x modulo MOD.
        mul     r15
        mov     r11, rax
        modulo  r11    
        
        inc     r9                       ; Move to the next coefficient.
        jmp     polyloop
endploop:        
        mov     r15, r10                 ; Transfer the computed value from r10 to r15 for consisntecy.
        
        add     r15, 0x80                ; Now r15 =  w(x - 0x80) + 0x80
            
                                         ; Integer to utf8 encoding:
        cmp     r15, SMALL4              ; Firsly, check on how many bytes to encode.
        jge     fourb                    ; Because of the  +0x80 it will be always encoded on more
                                         ; than one byte.
        cmp     r15, SMALL3
        jge     threeb
        
                                         ; Two bytes
        conbyte                          ; Get the continuation byte to r9.
        
        mov     [outbuff+r14+1], r9b     ; Transfer it to its position in outbuff.
        inc     r14
        
        sigbyte 0x1F, 0XC0               ; Get the number-of-bytes-signaling byte to r9.
                
        mov     [outbuff+r14-1], r9b     ; Transfer it to its position in outbuff.
        inc     r14
        
        jmp     endconv                  ; Finished conversion of that character.

threeb:                                  ; Three bytes
        conbyte                          ; Get the 2nd continuation byte to r9.
        
        mov     [outbuff+r14+2], r9b     ; Transfer it to its position in outbuff.
        inc     r14
        
        conbyte                          ; Get the 1st continuation byte to r9.
        
        mov     [outbuff+r14], r9b       ; Transfer it to its position in outbuff.
        inc     r14
        
        sigbyte 0xF, 0xE0                ; Get the number-of-bytes-signaling byte to r9.
        
        mov     [outbuff+r14-2], r9b     ; Transfer it to its position in outbuff.
        inc     r14

        jmp     endconv                  ; Finished conversion of that character.

fourb:
        conbyte                          ; Get the 3rd continuation byte to r9.

        mov     [outbuff+r14+3], r9b     ; Transfer it to its position in outbuff.
        inc     r14
        
        conbyte                          ; Get the 2nd continuation byte to r9.

        mov     [outbuff+r14+1], r9b     ; Transfer it to its position in outbuff.
        inc     r14
        
        conbyte                          ; Get the 1st continuation byte to r9.

        mov     [outbuff+r14-1], r9b     ; Transfer it to its position in outbuff.
        inc     r14

        sigbyte 0x7, 0xF0                ; Get the number-of-bytes-signaling byte to r9.
        
        mov     [outbuff+r14-3], r9b     ; Transfer it to its position in outbuff.
        inc     r14
        
endconv:                                 ; Finished conversion of the current character.                  
        cmp     [rsp+8], byte 0          ; Check whether the last byte was broken and repaired.
        je      nbroken                  ; If yes, make r13 equal to r12 to force going back in loop.
        mov     r13, r12
nbroken:        
        inc     r13                      ; Move to the next byte in inbuff.
        cmp     r13, r12                 ; If something remains in the inbuffer,
        jb      convert                  ;       go to convert.

        writeout                         ; Write r14 bytes from the outbuff to stdout.
        
        cmp     r12, SIZE                ; If the buffer was full, 
        jge     read                     ;      start over by going to 'read'.
        
end:
        mov     rax, EXIT                ; exit with code 0
        xor     rdi, rdi
        syscall
        
error:
        writeout                         ; Write remains of outbuff to stdout.

        mov     rax, EXIT                ; exit with code 1
        mov     rdi, 1
        syscall
        
