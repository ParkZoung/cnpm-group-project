const http = require('node:http');
const path = require('node:path');
const fs = require('node:fs');

const host = '127.0.0.1';
const configuredUrl = new URL(process.env.GOSTAY_E2E_BASE_URL || 'http://127.0.0.1:4173');
const port = Number(configuredUrl.port || 4173);
const frontendRoot = path.resolve(__dirname, '../../../frontend');
const contentTypes = {
  '.css': 'text/css; charset=utf-8',
  '.html': 'text/html; charset=utf-8',
  '.js': 'text/javascript; charset=utf-8',
  '.jpg': 'image/jpeg',
  '.jpeg': 'image/jpeg',
  '.png': 'image/png',
  '.svg': 'image/svg+xml'
};

function createStaticServer() {
  return http.createServer(function (request, response) {
    const requestUrl = new URL(request.url, `http://${host}:${port}`);
    const requestedPath = requestUrl.pathname === '/' ? '/index.html' : requestUrl.pathname;
    const decodedPath = decodeURIComponent(requestedPath);
    const filePath = path.resolve(frontendRoot, `.${decodedPath}`);

    if (filePath !== frontendRoot && !filePath.startsWith(frontendRoot + path.sep)) {
      response.writeHead(403);
      response.end('Forbidden');
      return;
    }

    fs.stat(filePath, function (statError, stats) {
      if (statError || !stats.isFile()) {
        response.writeHead(404);
        response.end('Not found');
        return;
      }

      response.writeHead(200, {
        'Content-Type': contentTypes[path.extname(filePath).toLowerCase()]
          || 'application/octet-stream',
        'Cache-Control': 'no-store'
      });
      fs.createReadStream(filePath).pipe(response);
    });
  });
}

function startStaticServer() {
  const server = createStaticServer();

  return new Promise(function (resolve, reject) {
    server.once('error', reject);
    server.listen(port, host, function () {
      server.removeListener('error', reject);
      resolve(server);
    });
  });
}

module.exports = {
  host,
  port,
  startStaticServer
};
