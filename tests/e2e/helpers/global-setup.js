const { startStaticServer } = require('./static-server');

module.exports = async function globalSetup() {
  const server = await startStaticServer();

  return async function globalTeardown() {
    await new Promise(function (resolve, reject) {
      server.close(function (error) {
        if (error) reject(error);
        else resolve();
      });
    });
  };
};
