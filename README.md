# Diakrytynizator

### Run:  
```
input | ./diakrytynizator a0 a1 a2 ... an
```

Lets define:  
```
w(x) = x if x <= 0x7F else (an * x^n + ... + a2 * x^2 + a1 * x + a0) % 0x10FF80
```

### Result:  
```
str([W(x - 0x80) + 0x80 for x in input])
```

### Examples:
```
> echo "Zażółć gęślą jaźń…" | ./diakrytynizator 0 1; echo $?
Zażółć gęślą jaźń…
0
```

```
> echo "Zażółć gęślą jaźń…" | ./diakrytynizator 133; echo $?
Zaąąąą gąąlą jaąąą
0
```

```
> echo -e "abc\n\x80" | ./diakrytynizator 7; echo $?
abc
1
```

### Compilation:  
```
nasm -f elf64 -w+all -w+error -o diakrytynizator.o diakrytynizator.asm
ld --fatal-warnings -o diakrytynizator diakrytynizator.o
```


# Concurrent Hexer "Noteć"  

x86_64 assembly implementation of function:
```
uint64_t notec(uint32_t n, char const *calc);
```
Given:
N - max number of 'Noteć's
Where:  
n - id number of instances  
calc - pointer to command for Noteć  

### Command syntax:

```
0-9, a-f, A-F - a number in base 16. Enters the input mode. 
    Reading any other sigin quits the input mode and pushes the number on the stack.
= - quit input mode
+ - remove two top numbers from the stack and add their sum at the top
* - remove two top numbers from the stack and add their product at the top
- - negate the number at the top of the stack
& - remove two top numbers from the stack and add their "AND" at the top
| - remove two top numbers from the stack and add their "OR" at the top
^ - remove two top numbers from the stack and add their "XOR" at the top
~ - bitwise negate the number at the top of the stack
Z - remove one number from the top of the stack
Y - duplicate the number at the top of the stack
X - swap two top numbers at the stack
N - add the number of 'Noteć's at the top of the stack
n - add the id number of this 'Noteć's instance at the top of the stack
g - call the int64_t debug(uint32_t n, uint64_t *stack_pointer) function
W - take the top number from the stack, treat it like id number of Noteć instance 'm'. 
    Wait for 'W' operation of Noteć 'm' and then swap the values on the tops of thier stacks
```

### Compilation & linking

```
nasm -DN=$N -f elf64 -w+all -w+error -o notec.o notec.asm
gcc -DN=$N -c -Wall -Wextra -O2 -std=c11 -o example.o example.c
gcc notec.o example.o -lpthread -o example
```
