/*
 *  linux/mm/page.s
 *
 *  (C) 1991  Linus Torvalds
 */

/*
 * page.s contains the low-level page-exception code.
 * the real work is done in mm.c
 */

/*
 * 用户程序执行时，用户进程与父进程解除了共享页面的关系，页目录项、页表也已经释放。这意味着页目录项的内容为0，包 括P位也为0。
 * 用户程序一开始执行，MMU解析 线性地址值时就会发现对应的页目录项P位为0， 因此产生缺页中断来加载用户代码。
 * 缺页中断信号产生后，page_fault这个服务程序将对此进行响应. -> memory.c do_no_page()
 *
 */
.globl page_fault       # 声明为全局变量。将在traps.c中用于设置页异常描述符。

page_fault:
	xchgl %eax,(%esp)       # 取出错码到eax
	pushl %ecx
	pushl %edx
	push %ds
	push %es
	push %fs
	movl $0x10,%edx         # 置内核数据段选择符
	mov %dx,%ds
	mov %dx,%es
	mov %dx,%fs
	movl %cr2,%edx          # 取引起页面异常的线性地址
	pushl %edx              # 将该线性地址和出错码压入栈中，作为将调用函数的参数
	pushl %eax
	testl $1,%eax           # 测试页存在标志P（为0），如果不是缺页引起的异常则跳转
	jne 1f
	call do_no_page         # 调用缺页处理函数
	jmp 2f
1:	call do_wp_page         # 调用写保护处理函数
2:	addl $8,%esp            # 丢弃压入栈的两个参数，弹出栈中寄存器并退出中断。
	pop %fs
	pop %es
	pop %ds
	popl %edx
	popl %ecx
	popl %eax
	iret
