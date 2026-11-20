import os
import urllib.request
import json

api_key = os.environ.get("GROQ_API_KEY", "")
models_to_test = ["openai/gpt-oss-20b", "openai/gpt-oss-120b", "allam-2-7b", "qwen/qwen3.8-27b"]

for model in models_to_test:
    payload = {
        "model": model,
        "messages": [
            {"role": "user", "content": "Ping"}
        ],
        "max_tokens": 10
    }
    req = urllib.request.Request(
        "https://api.groq.com/openai/v1/chat/completions",
        data=json.dumps(payload).encode('utf-8'),
        headers={
            "Authorization": f"Bearer {api_key}",
            "Content-Type": "application/json",
            "User-Agent": "Mozilla/5.0 (Windows NT 10.0; Win64; x64) MobileKemo/1.0"
        }
    )
    try:
        with urllib.request.urlopen(req, timeout=10) as resp:
            print(f"{model}: SUCCESS ({resp.status})")
    except urllib.error.HTTPError as e:
        print(f"{model}: HTTP Error {e.code}: {e.read().decode('utf-8')[:120]}")
    except Exception as e:
        print(f"{model}: {e}")
