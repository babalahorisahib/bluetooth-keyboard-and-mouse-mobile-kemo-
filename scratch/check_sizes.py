import os

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

root = "C:\\"
items = []
try:
    with os.scandir(root) as it:
        for entry in it:
            try:
                if entry.is_file(follow_symlinks=False):
                    sz = entry.stat(follow_symlinks=False).st_size
                    items.append((entry.name, sz, False))
                elif entry.is_dir(follow_symlinks=False):
                    sz = get_dir_size(entry.path)
                    items.append((entry.name, sz, True))
            except Exception:
                pass
except Exception as e:
    print(e)

items.sort(key=lambda x: x[1], reverse=True)
for name, sz, is_dir in items:
    gb = sz / (1024**3)
    if gb >= 0.05:
        prefix = "DIR " if is_dir else "FILE"
        print(f"{prefix} {name:35} : {gb:6.2f} GB")
