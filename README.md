# Intel High Definition Audio
Tested with Qemu version 7.0.0 on macOS Monterey 12.4

To run:
```
git clone https://github.com/unvariant/intel_hda
cd intel_hda
make qemu
```

Supported Formats:
1. wav
    - 16 or 32 bit
    - stripped on non essential metadata (using strip_wav.py)
The audio file to play can be configured with the `AUDIO_FILE` variable in `makefile`.
It normally takes a few minutes to load the audio file, it takes 3 minutes to load a 50 MB file on my computer.