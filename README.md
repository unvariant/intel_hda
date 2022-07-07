# Intel High Definition Audio
Tested with Qemu version 7.0.0 on macOS Monterey 12.4

To run:
```
git clone https://github.com/unvariant/intel_hda
cd intel_hda
make qemu
```

The code should be able to play any wav file, and the file to play can be configured with the `AUDIO_FILE` variable in `makefile`.
It normally takes a few minutes to load the audio file.