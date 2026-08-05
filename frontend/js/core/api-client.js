(function () {
  'use strict';

  async function request(path, body, accessToken) {
    const headers = { 'Content-Type': 'application/json' };
    if (accessToken) headers.Authorization = 'Bearer ' + accessToken;

    let response;
    try {
      response = await fetch(window.GoStayConfig.apiUrl + path, {
        method: 'POST',
        headers: headers,
        body: JSON.stringify(body || {})
      });
    } catch (_) {
      return { data: null, error: { message: 'Network request failed' } };
    }

    let payload;
    try {
      payload = await response.json();
    } catch (_) {
      payload = { error: { message: 'Invalid API response' } };
    }
    if (!response.ok && !payload.error) {
      payload.error = { message: 'API request failed (' + response.status + ')' };
    }
    return payload;
  }

  window.GoStayApiClient = Object.freeze({ request: request });
}());
