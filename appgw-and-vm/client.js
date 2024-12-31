const fs = require('node:fs');
const { env } = require('node:process');
const { WebSocket } = require('ws');

const serverAddress = env.SERVER_ADDRESS ?? "https://0.0.0.0:8000/wss";
const certFile = env.CERT_FILE ?? "/temp/vm_cert.pem";

const ignoreCertificateIssues = env.IGNORE_CERTIFICATE_ISSUES ?? true;

// Load trusted root certificates
const caCerts = [
    fs.readFileSync(certFile)
];

const ws = new WebSocket(serverAddress, {
    rejectUnauthorized: ignoreCertificateIssues == "true" ? false : true,
    ca: caCerts // Add this option to provide trusted root certificates
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