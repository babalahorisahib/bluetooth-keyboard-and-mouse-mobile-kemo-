import os, sys

def get_dir_size(path):
    total = 0
    try:
        with os.scandir(path) as it:
            for entry in it:
                try:
                    if entry.is_file(follow_symlinks=False):
                        total += entry.stat(follow_symlinks=False).st_size
                    elif entry.is_dir(follow_symlinks=False):
                        total += get_dir_size(entry.path)
                except Exception:
                    pass
    except Exception:
        pass
    return total

targets = [
    "C:\\Users\\Administrator\\.gradle",
    "C:\\Users\\Administrator\\.cargo",
    "C:\\Users\\Administrator\\.rustup",
    "C:\\Users\\Administrator\\.android",
    "C:\\Users\\Administrator\\.vscode",
    "C:\\Users\\Administrator\\Downloads",
    "C:\\Users\\Administrator\\AppData\\Local\\Temp",
    "C:\\Users\\Administrator\\AppData\\Local\\Android",
    "C:\\Users\\Administrator\\AppData\\Local\\pip",
    "C:\\Android",
    "C:\\Windows\\Temp",
    "C:\\$Recycle.Bin",
    "C:\\AI Bond Check",
    "C:\\kaamwaam",
    "C:\\Mobile Kemo",
    "C:\\photo editor",
    "C:\\Voice Transcriber",
    "C:\\VoiceWaveAI",
    "C:\\bluetooth keyboard and mouse",
]

for t in targets:
    if os.path.exists(t):
        sz = get_dir_size(t)
        gb = sz / (1024**3)
        print(f"{t:55} : {gb:6.2f} GB", flush=True)
