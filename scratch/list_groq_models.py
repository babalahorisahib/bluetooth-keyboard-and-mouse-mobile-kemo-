import os
import urllib.request
import json

api_key = os.environ.get("GROQ_API_KEY", "")
req = urllib.request.Request(
    "https://api.groq.com/openai/v1/models",
    headers={
        "Authorization": f"Bearer {api_key}",
        "User-Agent": "Mozilla/5.0 (Windows NT 10.0; Win64; x64) MobileKemo/1.0"
    }
)
try:
    with urllib.request.urlopen(req, timeout=10) as resp:
        data = json.loads(resp.read().decode('utf-8'))
        for m in data.get("data", []):
            print(m["id"])
except Exception as e:
    print("Error:", e)
