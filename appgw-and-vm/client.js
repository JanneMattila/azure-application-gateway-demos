const { env } = require('node:process');
const { WebSocket } = require('ws');

const serverAddress = env.SERVER_ADDRESS ?? "https://0.0.0.0:8000/wss";
const ignoreCertificateIssues = env.IGNORE_CERTIFICATE_ISSUES ?? true;

const ws = new WebSocket(serverAddress, {
    rejectUnauthorized: ignoreCertificateIssues == "true" ? false : true
});

ws.on("error", console.error);

ws.on("open", function open() {
    ws.send("Hello from Client!");

    // Send timestamp every 2 seconds
    setInterval(() => {
        const timestamp = new Date().toISOString();
        ws.send(`Timestamp: ${timestamp}`);
    }, 2000);
});

ws.on("message", function message(data) {
    console.log("received: %s", data);
});