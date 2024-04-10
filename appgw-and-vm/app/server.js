// Set environment variables:
// export KEY_FILE=/etc/ssl/private/server.key
// export CERT_FILE=/etc/ssl/certs/server.crt
// In shell, run the following command to start the server:
// node server.js
const https = require('node:https');
const fs = require('node:fs');
const { env } = require('node:process');

const keyFile = env.KEY_FILE ?? "/temp/vm_key.pem";
const certFile = env.CERT_FILE ?? "/temp/vm_cert.pem";

const options = {
    key: fs.readFileSync(keyFile),
    cert: fs.readFileSync(certFile),
};

https.createServer(options, (req, res) => {
    res.writeHead(200);
    res.end("Node App\n");
}).listen(8000, '0.0.0.0');

console.log("Server running at https://vm.demo.janne:8000/");
