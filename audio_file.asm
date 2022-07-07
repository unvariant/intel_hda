    align 512
    AUDIO_FILE_START equ $

%defstr AUDIO_FILE %!AUDIO_FILE
incbin AUDIO_FILE

    align 512
    AUDIO_FILE_END equ $