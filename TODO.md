- assert to variables not to be named like imported modules
- use phi instruction for boolean operations as variable values
    x = y > 4 and y < 10;
    ...
        %eval =w cgtuw %y, 4
        jnz %eval, @c, @f
    @c
        %eval =w cltuw %y, 10
        jnz %eval, @t, @f
    @t
        jmp @end
    @f
        jmp @end
    @end
        %x =w phi @t 1, @f 0
- returns within statements behave like yield

