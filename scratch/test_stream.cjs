const fs = require('fs');

async function testScreenCapture() {
  console.log('Connecting to ws://127.0.0.1:58921...');
  const ws = new WebSocket('ws://127.0.0.1:58921');

  await new Promise((resolve, reject) => {
    ws.addEventListener('open', resolve);
    ws.addEventListener('error', reject);
  });
  console.log('Connected!');

  let frameCount = 0;

  ws.addEventListener('message', async (event) => {
    if (event.data instanceof Blob) {
      frameCount++;
      const buffer = Buffer.from(await event.data.arrayBuffer());
      console.log(`Received binary frame #${frameCount}, size: ${buffer.length} bytes`);
      if (frameCount === 1) {
        fs.writeFileSync('C:\\bluetooth keyboard and mouse\\scratch\\sample_frame.jpg', buffer);
        console.log('Saved first frame to sample_frame.jpg!');
      }
      if (frameCount >= 3) {
        ws.send(JSON.stringify({ v: 1, type: 'SCREEN_STREAM_STOP', payload: {} }));
        setTimeout(() => {
          ws.close();
          console.log('Test complete!');
          process.exit(0);
        }, 500);
      }
      return;
    }

    const msg = JSON.parse(event.data.toString());
    console.log('Server message:', msg.type);

    if (msg.type === 'PAIR_RESPONSE') {
      console.log('Paired! Starting screen stream (quality 90, maxWidth 1920)...');
      ws.send(JSON.stringify({
        v: 1,
        type: 'SCREEN_STREAM_START',
        payload: {
          quality: 90,
          max_width: 1920,
          fps: 15
        }
      }));
    }
  });

  // Send pair request
  ws.send(JSON.stringify({
    v: 1,
    type: 'PAIR_REQUEST',
    payload: {
      device_id: 'test-device-uuid-1234',
      device_name: 'Test Stream Client',
      os: 'Android 14',
      pin: '135001'
    }
  }));
}

testScreenCapture().catch(console.error);
