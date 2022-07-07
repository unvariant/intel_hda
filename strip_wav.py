import sys

def expect(data, start, s):
    end = start + len(s)
    try:
        assert data[start:end] == s
    except:
        exit(f"expected {s} at offset {start}..{end}, found {data[start:end]}")

if __name__ == "__main__":
    argv = sys.argv
    argc = len(argv)

    if argc < 2:
        exit("""strips non essential metadata from wav file(s)
usage: python3 strip_wav.py [file(s) to strip]
        strip single file:\tpython3 strip_wav.py example0.wav
        strip multiple files:\tpython3 strip_wav.py example0.wav example1.wav""")

    files = argv[1:]
    for name in files:
        file = open(name, "rb")
        data = file.read()
        file.close()
        # https://web.archive.org/web/20120113025807/http://technology.niagarac.on.ca:80/courses/ctec1631/WavFileFormat.html
        expect(data, 0, b"RIFF")
        expect(data, 8, b"WAVE")
        expect(data, 12, b"fmt")
        expect(data, 16, b"\x10\x00\x00\x00")
        expect(data, 20, b"\x01")
        static = data[36:]
        if b"data" in static:
            cutoff = static.index(b"data") + 36
            removed = cutoff - 36
            data = data[:36] + data[cutoff:]
            header_size = 44
            # file_size is not the actual size of the whole file
            # it is actually total file size - 8
            file_size = int.from_bytes(data[4:8], "little") - removed + 8
            # data size is the size of the data section
            data_size = int.from_bytes(data[40:44], "little")
            try:
                assert data_size + header_size == file_size
            except:
                exit(f"malformed file or data size, expected ({data_size} + {header_size} = {data_size + header_size}) to equal {file_size}")
            data = data[:4] + file_size.to_bytes(4, "little") + data[8:]
            file = open(name, "wb")
            file.write(data)
            file.close()
        else:
            exit("could not find `data` delimiter")
