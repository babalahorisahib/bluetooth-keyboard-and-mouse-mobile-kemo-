const ws = new WebSocket("ws://127.0.0.1:58921");
ws.addEventListener("open", () => {
  ws.send(JSON.stringify({
    v: 1, type: "PAIR_REQUEST",
    payload: { device_id: "inspect-1", device_name: "Inspector", os: "android", pin: "135001" }
  }));
});
ws.addEventListener("message", async (e) => {
  if (e.data instanceof Blob) {
    const buf = Buffer.from(await e.data.arrayBuffer());
    console.log("Captured frame size:", buf.length, "bytes");
    const fs = require("fs");
    fs.writeFileSync("scratch/captured_test.jpg", buf);
    console.log("Saved scratch/captured_test.jpg");
    ws.send(JSON.stringify({ v: 1, type: "SCREEN_STREAM_STOP", payload: {} }));
    setTimeout(() => { ws.close(); process.exit(0); }, 200);
  } else {
    const msg = JSON.parse(e.data);
    if (msg.type === "PAIR_RESPONSE") {
      ws.send(JSON.stringify({
        v: 1, type: "SCREEN_STREAM_START",
        payload: { quality: 65, max_width: 1280, fps: 10 }
      }));
    }
  }
});
