const ws = new WebSocket("ws://127.0.0.1:58921");

let passed = false;
let framesReceived = 0;

ws.addEventListener("open", () => {
  console.log("Connected to WebSocket server");
  ws.send(JSON.stringify({
    v: 1,
    type: "PAIR_REQUEST",
    payload: {
      device_id: "test-device-uuid-1234",
      device_name: "Test Android Phone",
      os: "android",
      pin: "135001"
    }
  }));
});

ws.addEventListener("message", async (event) => {
  const data = event.data;
  if (data instanceof Blob) {
    framesReceived++;
    const arrayBuffer = await data.arrayBuffer();
    const buf = Buffer.from(arrayBuffer);
    const isJpeg = buf[0] === 0xFF && buf[1] === 0xD8;
    console.log(`Received binary frame #${framesReceived}: size=${buf.length} bytes, isJpeg=${isJpeg}`);
    if (framesReceived === 1) {
      ws.send(JSON.stringify({
        v: 1,
        type: "TOUCH_EVENT",
        payload: { action: "tap", x: 0.5, y: 0.5 }
      }));
      console.log("Sent TOUCH_EVENT tap at (0.5, 0.5)");
    }
    if (framesReceived >= 3) {
      ws.send(JSON.stringify({ v: 1, type: "SCREEN_STREAM_STOP", payload: {} }));
      console.log("Sent SCREEN_STREAM_STOP");
      passed = true;
      setTimeout(() => ws.close(), 300);
    }
  } else {
    const text = typeof data === "string" ? data : data.toString();
    console.log("Received text message:", text);
    try {
      const json = JSON.parse(text);
      if (json.type === "PAIR_RESPONSE" && json.payload.status === "APPROVED") {
        console.log("PAIRING APPROVED with token:", json.payload.auth_token);
        ws.send(JSON.stringify({
          v: 1,
          type: "SCREEN_STREAM_START",
          payload: { quality: 60, max_width: 800, fps: 10 }
        }));
        console.log("Requested SCREEN_STREAM_START");
      }
    } catch (e) {
      console.error("JSON parse error:", e);
    }
  }
});

ws.addEventListener("close", () => {
  console.log("WebSocket closed. Test passed:", passed);
  process.exit(passed ? 0 : 1);
});

ws.addEventListener("error", (err) => {
  console.error("WebSocket error:", err);
  process.exit(1);
});

setTimeout(() => {
  if (!passed) {
    console.error("Test timed out! Frames received:", framesReceived);
    process.exit(1);
  }
}, 8000);
