import os
import urllib.request
import json

api_key = os.environ.get("GROQ_API_KEY", "")

for model in ["openai/gpt-oss-20b", "openai/gpt-oss-120b", "qwen/qwen3.8-27b"]:
    payload = {
        "model": model,
        "messages": [
            {"role": "system", "content": "You are PC assistant. Return JSON object: {\"reply\": \"roman urdu reply\", \"action\": \"open_app\", \"target\": \"chrome\"}"},
            {"role": "user", "content": "chrome open karo"}
        ],
        "response_format": {"type": "json_object"},
        "temperature": 0.1,
        "max_tokens": 150
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
            data = json.loads(resp.read().decode('utf-8'))
            print(f"{model}: SUCCESS -> {data['choices'][0]['message']['content']}")
    except urllib.error.HTTPError as e:
        print(f"{model}: HTTP {e.code}: {e.read().decode('utf-8')[:120]}")
