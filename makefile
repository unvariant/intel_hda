AUDIO_FILE = small.wav

qemu: OS.bin
	qemu-system-i386 -device intel-hda,debug=10 -device hda-duplex -drive if=ide,format=raw,index=0,file=OS.bin

bochs: OS.bin
	bochs -f .bochsrc

debug: OS.bin
	qemu-system-i386 -s -S -device intel-hda,debug=10 -device hda-duplex -drive if=ide,format=raw,index=0,file=OS.bin

OS.bin: bootsect.bin
	cat bootsect.bin > OS.bin

bootsect.bin: bootsect.asm
	AUDIO_FILE=$(AUDIO_FILE) nasm -f bin bootsect.asm -o bootsect.bin

clean:
	rm *.bin
