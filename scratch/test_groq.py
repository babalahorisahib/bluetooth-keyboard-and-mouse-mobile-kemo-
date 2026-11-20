import os
import urllib.request
import json
import sys

api_key = os.environ.get("GROQ_API_KEY", "")
url = "https://api.groq.com/openai/v1/chat/completions"

payload = {
    "model": "qwen/qwen3.8-27b",
    "messages": [
        {"role": "system", "content": "You are KeyLink AI PC Controller. Interpret user commands and output JSON: {\"actions\": [{\"action\": \"open_app\", \"target\": \"chrome\", \"reply\": \"Chrome khol raha hoon\"}]}"},
        {"role": "user", "content": "chrome kholo"}
    ],
    "response_format": {"type": "json_object"},
    "temperature": 0.1
}

req = urllib.request.Request(
    url,
    data=json.dumps(payload).encode('utf-8'),
    headers={
        "Authorization": f"Bearer {api_key}",
        "Content-Type": "application/json",
        "User-Agent": "Mozilla/5.0 (Windows NT 10.0; Win64; x64) MobileKemo/1.0"
    }
)

try:
    with urllib.request.urlopen(req, timeout=10) as resp:
        print("Status:", resp.status)
        data = json.loads(resp.read().decode('utf-8'))
        print("Response:", data['choices'][0]['message']['content'])
except Exception as e:
    print("Error:", e)
