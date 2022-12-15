!
! SYS_SIZE is the number of clicks (16 bytes) to be loaded.
! 0x3000 is 0x30000 bytes = 196kB, more than enough for current
! versions of linux
!
SYSSIZE = 0x3000
!
!	bootsect.s		(C) 1991 Linus Torvalds
!
! bootsect.s is loaded at 0x7c00 by the bios-startup routines, and moves
! iself out of the way to address 0x90000, and jumps there.
!
! It then loads 'setup' directly after itself (0x90200), and the system
! at 0x10000, using BIOS interrupts. 
!
! NOTE! currently system is at most 8*65536 bytes long. This should be no
! problem, even in the future. I want to keep it simple. This 512 kB
! kernel size should be enough, especially as this doesn't contain the
! buffer cache as in minix
!
! The loader has been made as simple as possible, and continuos
! read errors will result in a unbreakable loop. Reboot by hand. It
! loads pretty fast by getting whole sectors at a time whenever possible.
! 内存规划.

.globl begtext, begdata, begbss, endtext, enddata, endbss
.text
begtext:
.data
begdata:
.bss
begbss:
.text

SETUPLEN = 4				! nr of setup-sectors   setup程序 的扇区数
BOOTSEG  = 0x07c0			! original address of boot-sector  启动扇区被BIOS加载的位置
INITSEG  = 0x9000			! we move boot here - out of the way  启动扇区将要移动到的新位置
SETUPSEG = 0x9020			! setup starts here  setup程序被加载到的位置
SYSSEG   = 0x1000			! system loaded at 0x10000 (65536). 内核（kernel）被加载的位置
ENDSEG   = SYSSEG + SYSSIZE		! where to stop loading  内核的末尾位置

! ROOT_DEV:	0x000 - same type of floppy as boot.
!		0x301 - first partition on first drive etc
! 根文件系统设备号
ROOT_DEV = 0x306

entry _start
_start:
    ! 复制bootsect， 此时CPU的段寄存器（CS）指向0x07C0 （BOOTSEG），即原来bootsect程序所在的位置。
	！ 开始时bootsect“被迫”加载到0x07C00位置， 现在已将自身移至0x90000处
	mov	ax,#BOOTSEG
	mov	ds,ax
	mov	ax,#INITSEG
	mov	es,ax
	mov	cx,#256
	sub	si,si
	sub	di,di
	! CS值变为 0x9000（INITSEG）
	! 此前的0x07C00这个位置是根据“两头约定”和“定位识别”而确定的。从现在起，操作系统 已经不需要完全依赖BIOS，可以按照自己的意志 把自己的代码安排在内存中自己想要的位置。
	rep
	movw
	jmpi	go,INITSEG
	! 因为代码的整体位置发生了变化，所以代码中的各个段也会发生变化。前面已 经改变了CS，现在对DS、ES、SS和SP进行调 整。
	! 数据段寄存器（DS）、附加段寄存 器（ES）、栈基址寄存器（SS）设置成与代码段 寄存器（CS）相同的位置，并将栈顶指针SP指 向偏移地址为0xFF00处
	! SS和SP联合使用，就构成了栈数据在内存 中的位置值。
go:	mov	ax,cs
	mov	ds,ax
	mov	es,ax
! put stack at 0x9ff00.
	mov	ss,ax
	mov	sp,#0xFF00		! arbitrary value >>512  	SP（Stack Pointer）：栈顶指针寄存器， 指向栈段的当前栈顶

! load the setup-sectors directly after the bootblock.
! Note that 'es' is already set up.

! 加载setup程序。即加载中断向量表的0x13. 将软盘第二扇区开始的4个扇区，即setup.s 对应的程序加载至内存的SETUPSEG
！ int 0x19中断向量所指向的启动加载服务程序是BIOS执行的，而int 0x13的中断服务程序是Linux操作系统自身的启动代码bootsect执行的
load_setup:
	mov	dx,#0x0000		! drive 0, head 0
	mov	cx,#0x0002		! sector 2, track 0
	mov	bx,#0x0200		! address = 512, in INITSEG
	mov	ax,#0x0200+SETUPLEN	! service 2, nr of sectors
	int	0x13			! read it
	jnc	ok_load_setup		! ok - continue
	mov	dx,#0x0000
	mov	ax,#0x0000		! reset the diskette
	int	0x13
	j	load_setup

ok_load_setup:

! Get disk drive parameters, specifically nr of sectors/track

	mov	dl,#0x00
	mov	ax,#0x0800		! AH=8 is get drive parameters
	int	0x13
	mov	ch,#0x00
	seg cs
	mov	sectors,cx
	mov	ax,#INITSEG
	mov	es,ax

! Print some inane message  加载system时间比较长，输出信息: “Loading system..."

	mov	ah,#0x03		! read cursor pos
	xor	bh,bh
	int	0x10
	
	mov	cx,#24
	mov	bx,#0x0007		! page 0, attribute 7 (normal)
	mov	bp,#msg1
	mov	ax,#0x1301		! write string, move cursor
	int	0x10

! ok, we've written the message, now
! we want to load the system (at 0x10000)
! 加载system模块. 扇区数是240个
! 至此,整个操作系统的代码已全部加载至内存.

	mov	ax,#SYSSEG
	mov	es,ax		! segment of 0x010000
	call	read_it   ! 调用read_it完成system的加载.
	call	kill_motor

! After that we check which root-device to use. If the device is
! defined (!= 0), nothing is done and the given device is used.
! Otherwise, either /dev/PS0 (2,28) or /dev/at0 (2,8), depending
! on the number of sectors that the BIOS reports currently.
! 确认根设备号.
! 0.11使用Minix操作系统的文件系统管理方式，要求系统必须存在一个根文件系统，其他文件系统挂接其上，而不是同等地位。
! 这里的文件系统指的不是操作系统内核中的文件系统代码，而是有配套的文件系统格式的设备，如一张格式化好的软盘。

	seg cs
	mov	ax,root_dev
	cmp	ax,#0
	jne	root_defined
	seg cs
	mov	bx,sectors
	mov	ax,#0x0208		! /dev/ps0 - 1.2Mb
	cmp	bx,#15
	je	root_defined
	mov	ax,#0x021c		! /dev/PS0 - 1.44Mb
	cmp	bx,#18
	je	root_defined
undef_root:
	jmp undef_root
root_defined:           ！根据前面检测计算机中实际安装的驱动器信 息，确认根设备
	seg cs
	mov	root_dev,ax

! after that (everyting loaded), we jump to
! the setup-routine loaded directly after
! the bootblock:
! 跳转至0x90200处，就是前面讲过的第二批程序——setup程序加载的位置。CS：IP指向 setup程序的第一条指令，意味着由setup程序 接着bootsect程序继续执行

	jmpi	0,SETUPSEG

! This routine loads the system at address 0x10000, making sure
! no 64kB boundaries are crossed. We try to load it as fast as
! possible, loading whole tracks whenever we can.
!
! in:	es - starting address segment (normally 0x1000)
!
sread:	.word 1+SETUPLEN	! sectors read of current track
head:	.word 0			! current head
track:	.word 0			! current track

read_it:
	mov ax,es
	test ax,#0x0fff
die:	jne die			! es must be at 64kB boundary
	xor bx,bx		! bx is starting address within segment
rp_read:
	mov ax,es
	cmp ax,#ENDSEG		! have we loaded all yet?
	jb ok1_read
	ret
ok1_read:
	seg cs
	mov ax,sectors
	sub ax,sread
	mov cx,ax
	shl cx,#9
	add cx,bx
	jnc ok2_read
	je ok2_read
	xor ax,ax
	sub ax,bx
	shr ax,#9
ok2_read:
	call read_track
	mov cx,ax
	add ax,sread
	seg cs
	cmp ax,sectors
	jne ok3_read
	mov ax,#1
	sub ax,head
	jne ok4_read
	inc track
ok4_read:
	mov head,ax
	xor ax,ax
ok3_read:
	mov sread,ax
	shl cx,#9
	add bx,cx
	jnc rp_read
	mov ax,es
	add ax,#0x1000
	mov es,ax
	xor bx,bx
	jmp rp_read

read_track:
	push ax
	push bx
	push cx
	push dx
	mov dx,track
	mov cx,sread
	inc cx
	mov ch,dl
	mov dx,head
	mov dh,dl
	mov dl,#0
	and dx,#0x0100
	mov ah,#2
	int 0x13
	jc bad_rt
	pop dx
	pop cx
	pop bx
	pop ax
	ret
bad_rt:	mov ax,#0
	mov dx,#0
	int 0x13
	pop dx
	pop cx
	pop bx
	pop ax
	jmp read_track

!/*
! * This procedure turns off the floppy drive motor, so
! * that we enter the kernel in a known state, and
! * don't have to worry about it later.
! */
kill_motor:
	push dx
	mov dx,#0x3f2
	mov al,#0
	outb
	pop dx
	ret

sectors:
	.word 0

msg1:
	.byte 13,10
	.ascii "Loading system ..."
	.byte 13,10,13,10

.org 508                ！注意：508即为0x1FC，当前段是0x9000，所以地 址是0x901FC
root_dev:
	.word ROOT_DEV
boot_flag:
	.word 0xAA55

.text
endtext:
.data
enddata:
.bss
endbss:
