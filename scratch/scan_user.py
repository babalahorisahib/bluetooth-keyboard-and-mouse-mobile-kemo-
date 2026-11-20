import os

FILE_ATTRIBUTE_REPARSE_POINT = 0x400

def is_reparse_point(path):
    try:
        attrs = os.stat(path, follow_symlinks=False).st_file_attributes
        return bool(attrs & FILE_ATTRIBUTE_REPARSE_POINT)
    except Exception:
        return False

def get_real_dir_size(path):
    total = 0
    try:
        with os.scandir(path) as it:
            for entry in it:
                try:
                    if entry.is_file(follow_symlinks=False):
                        if not is_reparse_point(entry.path):
                            total += entry.stat(follow_symlinks=False).st_size
                    elif entry.is_dir(follow_symlinks=False):
                        if not is_reparse_point(entry.path):
                            total += get_real_dir_size(entry.path)
                except Exception:
                    pass
    except Exception:
        pass
    return total

user_dir = "C:\\Users\\Administrator"
for item in os.listdir(user_dir):
    p = os.path.join(user_dir, item)
    if is_reparse_point(p):
        print(f"[JUNCTION] {item}")
        continue
    if os.path.isdir(p):
        sz = get_real_dir_size(p)
        gb = sz / (1024**3)
        if gb >= 0.3:
            print(f"DIR  {item:30} : {gb:6.2f} GB", flush=True)
