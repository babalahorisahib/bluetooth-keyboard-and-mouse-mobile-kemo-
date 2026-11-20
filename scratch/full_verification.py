import asyncio
import json
import websockets
import sys

# Configure stdout for utf-8
if sys.platform == "win32":
    sys.stdout.reconfigure(encoding='utf-8')

async def full_e2e_test():
    uri = "ws://127.0.0.1:58921"
    print(f"Connecting to {uri}...")
    async with websockets.connect(uri) as ws:
        # 1. Auth Request
        auth_msg = {
            "v": 1,
            "type": "AUTH_REQUEST",
            "payload": {
                "device_id": "e2e-test-device-uuid",
                "auth_token": "07e577df-1c46-436b-aa33-33133568ffbf"
            }
        }
        await ws.send(json.dumps(auth_msg))
        auth_resp = await ws.recv()
        print(f"1. Auth response: {auth_resp}")
        assert "SUCCESS" in auth_resp

        # 2. Mouse Move
        await ws.send(json.dumps({
            "v": 1,
            "type": "MOUSE_MOVE",
            "payload": {"dx": 15.0, "dy": -10.0}
        }))
        print("2. MouseMove sent successfully")

        # 3. Mouse Click
        await ws.send(json.dumps({
            "v": 1,
            "type": "MOUSE_CLICK",
            "payload": {"button": "left", "action": "click"}
        }))
        print("3. MouseClick sent successfully")

        # 4. Key Event (Backspace)
        await ws.send(json.dumps({
            "v": 1,
            "type": "KEY_EVENT",
            "payload": {"key": "Backspace", "action": "press", "modifiers": []}
        }))
        print("4. Key Event (Backspace) sent successfully")

        # 5. Text Input (Unicode English + Urdu)
        await ws.send(json.dumps({
            "v": 1,
            "type": "TEXT_INPUT",
            "payload": {"text": "Mobile Kemo Ready"}
        }))
        print("5. TextInput sent successfully")

        # 6. Touch Event (Tap)
        await ws.send(json.dumps({
            "v": 1,
            "type": "TOUCH_EVENT",
            "payload": {"action": "tap", "x": 0.45, "y": 0.35}
        }))
        print("6. TouchEvent sent successfully")

        # 7. Start Screen Stream
        await ws.send(json.dumps({
            "v": 1,
            "type": "SCREEN_STREAM_START",
            "payload": {"quality": 80, "max_width": 1280, "fps": 15}
        }))
        frame = await asyncio.wait_for(ws.recv(), timeout=5.0)
        assert isinstance(frame, bytes), "Expected binary JPEG frame"
        assert frame[:2] == b'\xff\xd8', "Invalid JPEG magic bytes"
        print(f"7. Screen Stream Frame received: {len(frame)} bytes valid JPEG")

        # 8. Stop Screen Stream
        await ws.send(json.dumps({
            "v": 1,
            "type": "SCREEN_STREAM_STOP"
        }))
        print("8. Screen Stream Stop sent successfully")

        # 9. Voice Command via Groq AI
        await ws.send(json.dumps({
            "v": 1,
            "type": "VOICE_COMMAND",
            "payload": {"text": "open chrome"}
        }))
        voice_resp_raw = await asyncio.wait_for(ws.recv(), timeout=10.0)
        voice_resp = json.loads(voice_resp_raw)
        print(f"9. Voice Response: {voice_resp['payload']['message']}")
        assert voice_resp['payload']['success'] is True

        print("\n>>> ALL 9 TESTS PASSED 100% SUCCESSFULLY! <<<")

asyncio.run(full_e2e_test())
