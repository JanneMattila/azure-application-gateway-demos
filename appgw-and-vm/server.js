const https = require('node:https');
const { WebSocketServer } = require('ws');
const fs = require('node:fs');
const { env } = require('node:process');

const keyFile = env.KEY_FILE ?? "/temp/vm_key.pem";
const certFile = env.CERT_FILE ?? "/temp/vm_cert.pem";

const options = {
    key: fs.readFileSync(keyFile),
    cert: fs.readFileSync(certFile),
};

const server = https.createServer(options, (req, res) => {
    if (req.url === '/wss') {
        res.writeHead(426, { 'Content-Type': 'text/plain' });
        res.end('Upgrade required');
    } else {
        res.writeHead(200);
        res.end("Node App\n");
    }
});

const wss = new WebSocketServer({ noServer: true });

wss.on("connection", function connection(ws) {
    ws.on("error", console.error);
    ws.on("message", function message(data) {
        console.log('received: %s', data);
        ws.send(`Echo: ${data}`);
    });
    ws.send("Hello there!");
});

server.on('upgrade', (request, socket, head) => {
    if (request.url === '/wss') {
        wss.handleUpgrade(request, socket, head, (ws) => {
            wss.emit('connection', ws, request);
        });
    } else {
        socket.destroy();
    }
});

server.listen(8000, '0.0.0.0', () => {
    console.log("Server running at https://vm.demo.janne:8000/");
});
