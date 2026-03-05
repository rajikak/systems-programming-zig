default:
	@zig run container.zig -freference-trace=11 -- mount=/tmp/anvilci/ uid=0 debug=true command='ls -alh'

strace:
	@zig build-exe container.zig;strace -f ./container mount=/tmp/anvilci/ uid=0 debug=true command='go build -tags lambda.norpc -o bootstrap .'   

ns:
	zig run -I . namespace2.zig -lc -D_GNU_SOURCE

ns3:
	zig run -I . namespace3.zig -lc -D_GNU_SOURCE

ns4:
	zig run namespace4.zig

clean:
	umount /tmp/anvilci/*;rm -rf /tmp/anvilci/*
