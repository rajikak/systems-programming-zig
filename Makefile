default:
	@zig run container.zig -freference-trace=11 -- mount=/tmp/anvilci/ uid=0 debug=true command='ls -alh'

strace:
	@zig build-exe container.zig -O Debug;strace -f ./container mount=/tmp/anvilci/ uid=0 debug=true command='go build -tags lambda.norpc -o bootstrap .'   


clone:
	@zig run clone5.zig -freference-trace=11

clone2:
	@zig build-exe clone5.zig;strace --sumary-only --follow-clone -f ./clone5

ns:
	zig run -I . namespace2.zig -lc -D_GNU_SOURCE

ns3:
	zig run -I . namespace3.zig -lc -D_GNU_SOURCE

ns4:
	zig run namespace4.zig

clean:
	umount /tmp/anvilci/*;rm -rf /tmp/anvilci/*

pr1:
	gcc pivot_root.c -o pivot_root 
	cp /home/ec2-user/busybox /tmp/rootfs
	PS1='bbsh$ ' sudo ./pivot_root /tmp/rootfs/ /busybox sh;

pr:
	@zig build-exe pivot_root.zig --name zig_pivot_root -freference-trace=11
	cp /home/ec2-user/busybox /tmp/zigrootfs
	PS1='bbsh$ ' sudo ./zig_pivot_root /tmp/zigrootfs/ /busybox s
	# exeucute in the container
	#PATH=/
	#busybox ln busybox ln
	#ln busybox ls
	#ln busybox echo
	#ls
	#echo 'hello world'
