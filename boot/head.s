/*
 *  linux/boot/head.s
 *
 *  (C) 1991  Linus Torvalds
 */

/*
 *  head.s contains the 32-bit startup code.
 *
 * 加载操作系统的时候，计算机刚刚加电，只有BIOS程序在运行，而且此时计算机处在16位实模式状态，通过BIOS程序自身的代码形成的16位的中断向量表及相关的16位的中断服务程序，
 * 将操作系统在软盘上的第一扇区（512字节）的代码加载到内存，BIOS能主动操作的内容也就到此为止了。准确地说，这是一个约定。对于第一扇区代码的加载，不论 什么操作系统都是一样的；
 * 从第二扇区开始，就要由第一扇区中的代码来完成后续的代码加载工作。
 *
 * 当加载工作完成后，好像仍然没有立即执行main函数，而是打开A20，打开pe、pg，建立 IDT、GDT……然后才开始执行main函数，这是什么道理？ 原因是，Linux 0.11是一个32位的实时多任务的现代操作系统，
 * main函数肯定要执行的是32位的代码。编译操作系统代码时，是有16位和32位不同的编译选项的。如果选了16位，C语言编译出来的代码是16位模式的，结果可能是一个int 型变量，只有2字节，而不是32位的4字节……
 * 这不是Linux 0.11想要的。Linux 0.11要的是32位的编译结果。只有这样才能成为32位的操作系统代码。这样的代码才能用到32位总线（打开A20 后的总线），才能用到保护模式和分页，
 * 才能成 为32位的实时多任务的现代操作系统。
 
 * 开机时的16位实模式与main函数执行需要的 32位保护模式之间有很大的差距，这个差距谁来填补？head.s做的就是这项工作。这期间，head程序打开A20，打开pe、pg，废弃旧的、16位的中断响应机制，
 * 建立新的32位的IDT…… 这些工作都做完了，计算机已经处在32位的保护 模式状态了，调用32位main函数的一切条件已经准备完毕，这时顺理成章地调用main函数。后面 的操作就可以用32位编译的main函数完成。
 
 * NOTE!!! Startup happens at absolute address 0x00000000, which is also where
 * the page directory will exist. The startup code will be overwritten by
 * the page directory.
 * 标号_pg_dir标识内核分页机制完成后的内核 起始位置，也就是物理内存的起始位置 0x000000。
 * 在实模式下，CS本身就是代码段基址。在保护模式下，CS 本身不是代码段基址，而是代码段选择符。
 * 要将DS、ES、FS和GS等其他 寄存器从实模式转变到保护模式
 */
.text
.globl idt,gdt,pg_dir,tmp_floppy_area
pg_dir:
.globl startup_32
startup_32:
	movl $0x10,%eax
	mov %ax,%ds
	mov %ax,%es
	mov %ax,%fs
	mov %ax,%gs
	lss stack_start,%esp    # 之前是设置SP， 这时候是设置ESP，多 加了一个字母E，这是为适应保护模式而做的调 整。
	call setup_idt
	call setup_gdt          # 重新创建GDT
	movl $0x10,%eax		# reload all the segment registers
	mov %ax,%ds		# after changing gdt. CS was already
	mov %ax,%es		# reloaded in 'setup_gdt'
	mov %ax,%fs
	mov %ax,%gs
	lss stack_start,%esp
	xorl %eax,%eax
1:	incl %eax		# check that A20 really IS enabled
	movl %eax,0x000000	# loop forever if it isn't
	cmpl %eax,0x100000
	je 1b

/*
 * NOTE! 486 should set bit 16, to check for write-protect in supervisor
 * mode. Then it would be unnecessary with the "verify_area()"-calls.
 * 486 users probably want to set the NE (#5) bit also, so as to use
 * int 16 for math errors.
 */
	movl %cr0,%eax		# check math chip
	andl $0x80000011,%eax	# Save PG,PE,ET
/* "orl $0x10020,%eax" here for 486 might be good */
	orl $2,%eax		# set MP
	movl %eax,%cr0
	call check_x87
	jmp after_page_tables

/*
 * We depend on ET to be correct. This checks for 287/387.
 */
check_x87:
	fninit
	fstsw %ax
	cmpb $0,%al
	je 1f			/* no coprocessor: have to set bits */
	movl %cr0,%eax
	xorl $6,%eax		/* reset MP, set EM */
	movl %eax,%cr0
	ret
.align 2
1:	.byte 0xDB,0xE4		/* fsetpm for 287, ignored by 387 */
	ret

/*
 *  setup_idt
 *
 *  sets up a idt with 256 entries pointing to
 *  ignore_int, interrupt gates. It then loads
 *  idt. Everything that wants to install itself
 *  in the idt-table may do so themselves. Interrupts
 *  are enabled elsewhere, when we can be relatively
 *  sure everything is ok. This routine will be over-
 *  written by the page tables.
 */
setup_idt:
	lea ignore_int,%edx
	movl $0x00080000,%eax
	movw %dx,%ax		/* selector = 0x0008 = cs */
	movw $0x8E00,%dx	/* interrupt gate - dpl=0, present */

	lea idt,%edi
	mov $256,%ecx
rp_sidt:
	movl %eax,(%edi)
	movl %edx,4(%edi)
	addl $8,%edi
	dec %ecx
	jne rp_sidt
	lidt idt_descr
	ret

/*
 *  setup_gdt
 *
 *  This routines sets up a new gdt and loads it.
 *  Only two entries are currently built, the same
 *  ones that were built in init.s. The routine
 *  is VERY complicated at two whole lines, so this
 *  rather long comment is certainly needed :-).
 *  This routine will beoverwritten by the page tables.
 */
setup_gdt:
	lgdt gdt_descr
	ret

/*
 * I put the kernel page tables right after the page directory,
 * using 4 of them to span 16 Mb of physical memory. People with
 * more than 16MB will have to expand this.
 */
.org 0x1000
pg0:

.org 0x2000
pg1:

.org 0x3000
pg2:

.org 0x4000
pg3:

.org 0x5000
/*
 * tmp_floppy_area is used by the floppy-driver when DMA cannot
 * reach to a buffer-block. It needs to be aligned, so that it isn't
 * on a 64kB border.
 */
tmp_floppy_area:
	.fill 1024,1,0

/*
 * 将main函数入口地址和L6标号压栈： main函数在正常情况下是不应该退出的。如果main函数异常退出，就会返回这里的标号L6处继续执行，此时，还可以做一些系统调用
 *
 */
after_page_tables:
	pushl $0		# These are the parameters to main :-)
	pushl $0
	pushl $0
	pushl $L6		# return address for main, if it decides to.
	pushl $main
	jmp setup_paging  # 开始创建分页机制
L6:
	jmp L6			# main should never return here, but
				# just in case, we know what happens.

/* This is the default interrupt "handler" :-) */
int_msg:
	.asciz "Unknown interrupt\n\r"
.align 2
ignore_int:
	pushl %eax
	pushl %ecx
	pushl %edx
	push %ds
	push %es
	push %fs
	movl $0x10,%eax
	mov %ax,%ds
	mov %ax,%es
	mov %ax,%fs
	pushl $int_msg
	call printk
	popl %eax
	pop %fs
	pop %es
	pop %ds
	popl %edx
	popl %ecx
	popl %eax
	iret


/*
 * Setup_paging
 *
 * This routine sets up paging by setting the page bit
 * in cr0. The page tables are set up, identity-mapping
 * the first 16MB. The pager assumes that no illegal
 * addresses are produced (ie >4Mb on a 4Mb machine).
 *
 * NOTE! Although all physical memory should be identity
 * mapped by this routine, only the kernel page functions
 * use the >1Mb addresses directly. All "normal" functions
 * use just the lower 1Mb, or the local data space, which
 * will be mapped to some other place - mm keeps track of
 * that.
 *
 * For those with more memory than 16 Mb - tough luck. I've
 * not got it, why should you :-) The source is here. Change
 * it. (Seriously - it shouldn't be too difficult. Mostly
 * change some constants etc. I left it at 16Mb, as my machine
 * even cannot be extended past that (ok, but it was cheap :-)
 * I've tried to show which constants to change by having
 * some kind of marker at them (search for "16Mb"), but I
 * won't guarantee that's all :-( )
 */
 /** 
 * 这里是内核给自己分页：这4个页表都是内核专属的页表，将来每个用 户进程都会有它们专属的页表.
 * 内核的线性地址等于物理地址。这样做的目的是，内核可以对内存中的所有进程的内存区域任意访问。
 *
 * 页目录表只有一个，一个页目录表可以掌控1024个页表，一个页 表掌控1024个页面，一个页面4 KB，这样一个 页目录表就可以掌控1024×1024×4 KB=4 GB 大小的内存空间。
 *
 * 将一个页目录表和4个页表放在物理内存的起始位置，把页目录表和4个页表全部清零，然后把P位设置为1。
 * 每个页目录项 和页表项的最后3位，标志着其所管理的页面的 属性（一个页表本身也占用一个页面），它们分 别是U/S、R/W和P。
 * U/S: 如果U/S位设置为0，表示段 特权级为3的程序不可以访问该页面，其他特权 级都可以；如果被设置为1，表示包括段特权级 为3在内的所有程序都可以访问该页面。
 * 它的作用就是看死用户进程，阻止内核才能访问的页面 被用户进程使用。
 * R/W: 读写锁。 如果它被设置为0，说明 页面只能读不能写；如果设置为1，说明可读可 写.
 * P: 一个页目录项或一个页表项，如果和一个页 面建立了映射关系，P标志就设置为1；如果没建 立映射关系，该标志就是0。进程执行时，线性 地址值都会被MMU解析。
 * 	如果解析出某个表项的P位为0，说明该表项没有对应页面，就会产生缺页中断。
 * 	页表和页面的关系解除后，页表项就要清零。页目录项和页表解除关系后，页目录项也要清零，这样就等于把对应的页表项、页目录项的 P清零了。
 * 
 * 
 */
.align 2
setup_paging:
	movl $1024*5,%ecx		/* 5 pages - pg_dir+4 page tables  页目录表也是一页.*/
	xorl %eax,%eax
	xorl %edi,%edi			/* pg_dir is at 0x000 */
	cld;rep;stosl
	movl $pg0+7,pg_dir		/* set present bit/user r/w */
	movl $pg1+7,pg_dir+4		/*  --------- " " --------- */
	movl $pg2+7,pg_dir+8		/*  --------- " " --------- */
	movl $pg3+7,pg_dir+12		/*  --------- " " --------- */
	movl $pg3+4092,%edi
	movl $0xfff007,%eax		/*  16Mb - 4096 + 7 (r/w user,p)   7是111, P*/
	std
1:	stosl			/* fill pages backwards - more efficient :-) */
	subl $0x1000,%eax
	jge 1b
	xorl %eax,%eax		/* pg_dir is at 0x0000 */
	movl %eax,%cr3		/* cr3 - page directory start. ，CR3中存储着页目录表的基址，这样MMU解析线性地址时，先找CR3中的信息 */
	movl %cr0,%eax
	orl $0x80000000,%eax
	/**
	 * 设置CR0，打开PG. 
	 * CPU的硬件默认，在保护模式下，如果没有打开PG，线性地址恒等映射到物理地址；如果打开了PG，则线性地址需要通过MMU进行解析，以页目录表、页表、页面的三级映射模式映射到物理地址。
	 * 在此之前, PE(保护模式)已打开，CR3(页目录基地址)已设置.
	 */
	movl %eax,%cr0		/* set paging (PG) bit. */
	ret			/* this also flushes prefetch-queue  执行ret，将main函数入口地址弹出给EIP*/

.align 2
.word 0
idt_descr:
	.word 256*8-1		# idt contains 256 entries
	.long idt
.align 2
.word 0
gdt_descr:
	.word 256*8-1		# so does gdt (not that that's any
	.long gdt		# magic number, but it works for me :^)

	.align 8
idt:	.fill 256,8,0		# idt is uninitialized

gdt:	.quad 0x0000000000000000	/* NULL descriptor */
	.quad 0x00c09a0000000fff	/* 16Mb */
	.quad 0x00c0920000000fff	/* 16Mb */
	.quad 0x0000000000000000	/* TEMPORARY - don't use */
	.fill 252,8,0			/* space for LDT's and TSS's etc */
