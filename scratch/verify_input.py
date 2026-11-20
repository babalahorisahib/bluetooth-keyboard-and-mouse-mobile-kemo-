import asyncio
import json
import websockets
import sys

async def test():
    uri = "ws://127.0.0.1:58921"
    print(f"Connecting to {uri}...")
    async with websockets.connect(uri) as ws:
        # 1. Auth Request
        auth_msg = {
            "v": 1,
            "type": "AUTH_REQUEST",
            "payload": {
                "device_id": "test-device-uuid-1234",
                "auth_token": "01b929a6-9752-472f-ab1c-9250d702ecc2"
            }
        }
        await ws.send(json.dumps(auth_msg))
        resp = await ws.recv()
        print(f"Auth response: {resp}")

        # 2. Mouse move
        move_msg = {
            "v": 1,
            "type": "MOUSE_MOVE",
            "payload": { "dx": 10.0, "dy": 10.0 }
        }
        await ws.send(json.dumps(move_msg))
        print("Sent MOUSE_MOVE")

        # 3. Touch event
        touch_msg = {
            "v": 1,
            "type": "TOUCH_EVENT",
            "payload": { "action": "tap", "x": 0.5, "y": 0.5 }
        }
        await ws.send(json.dumps(touch_msg))
        print("Sent TOUCH_EVENT")

        # 4. Shortcut desktop
        shortcut_msg = {
            "v": 1,
            "type": "SHORTCUT",
            "payload": { "action": "desktop" }
        }
        await ws.send(json.dumps(shortcut_msg))
        print("Sent SHORTCUT desktop")

        # 5. Voice command
        voice_msg = {
            "v": 1,
            "type": "VOICE_COMMAND",
            "payload": { "text": "chrome kholo" }
        }
        await ws.send(json.dumps(voice_msg))
        print("Sent VOICE_COMMAND")

        # Wait for voice response
        voice_resp = await asyncio.wait_for(ws.recv(), timeout=10.0)
        print(f"Voice Response: {voice_resp}")

asyncio.run(test())
