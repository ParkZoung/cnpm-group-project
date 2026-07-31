(function () {
  'use strict';

  // The browser only knows the application API. Database credentials and the
  // Supabase Data API are deliberately kept behind the Edge Function.
  const API_URL = 'https://wpecaxsuadawaxadxqhj.supabase.co/functions/v1/api';
  const SESSION_KEY = 'gostay.api.session';
  const listeners = new Set();

  function readSession() {
    try {
      return JSON.parse(localStorage.getItem(SESSION_KEY)) || null;
    } catch (_) {
      localStorage.removeItem(SESSION_KEY);
      return null;
    }
  }

  function saveSession(session, event) {
    if (session) localStorage.setItem(SESSION_KEY, JSON.stringify(session));
    else localStorage.removeItem(SESSION_KEY);
    listeners.forEach(function (listener) {
      try { listener(event, session); } catch (error) { console.error(error); }
    });
  }

  async function request(path, body, authenticated) {
    const session = readSession();
    const headers = { 'Content-Type': 'application/json' };
    if (authenticated !== false && session && session.access_token) {
      headers.Authorization = 'Bearer ' + session.access_token;
    }

    let response;
    try {
      response = await fetch(API_URL + path, {
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

  function QueryBuilder(table) {
    this.payload = {
      table: table,
      operation: 'select',
      columns: '*',
      filters: [],
      orders: []
    };
  }

  QueryBuilder.prototype.select = function (columns, options) {
    this.payload.columns = columns || '*';
    this.payload.selectOptions = options || {};
    if (this.payload.operation !== 'select') this.payload.returning = true;
    return this;
  };
  QueryBuilder.prototype.insert = function (values) {
    this.payload.operation = 'insert';
    this.payload.values = values;
    return this;
  };
  QueryBuilder.prototype.update = function (values) {
    this.payload.operation = 'update';
    this.payload.values = values;
    return this;
  };
  QueryBuilder.prototype.delete = function () {
    this.payload.operation = 'delete';
    return this;
  };
  QueryBuilder.prototype.eq = function (column, value) {
    this.payload.filters.push({ operator: 'eq', column: column, value: value });
    return this;
  };
  QueryBuilder.prototype.in = function (column, values) {
    this.payload.filters.push({ operator: 'in', column: column, value: values });
    return this;
  };
  QueryBuilder.prototype.neq = function (column, value) {
    this.payload.filters.push({ operator: 'neq', column: column, value: value });
    return this;
  };
  QueryBuilder.prototype.gte = function (column, value) {
    this.payload.filters.push({ operator: 'gte', column: column, value: value });
    return this;
  };
  QueryBuilder.prototype.order = function (column, options) {
    this.payload.orders.push({
      column: column,
      ascending: !options || options.ascending !== false
    });
    return this;
  };
  QueryBuilder.prototype.limit = function (value) {
    this.payload.limit = value;
    return this;
  };
  QueryBuilder.prototype.single = function () {
    this.payload.resultMode = 'single';
    return this;
  };
  QueryBuilder.prototype.maybeSingle = function () {
    this.payload.resultMode = 'maybeSingle';
    return this;
  };
  QueryBuilder.prototype.then = function (resolve, reject) {
    return request('/query', this.payload, true).then(resolve, reject);
  };

  const client = {
    from: function (table) {
      return new QueryBuilder(table);
    },
    rpc: function (name, args) {
      return request('/rpc', { name: name, args: args || {} }, true);
    },
    functions: {
      invoke: function (name, options) {
        return request('/function', {
          name: name,
          body: options && options.body ? options.body : {}
        }, true);
      }
    },
    auth: {
      getSession: async function () {
        const session = readSession();
        if (!session) return { data: { session: null }, error: null };
        let result = await request('/auth/session', {}, true);
        if (result.error && session.refresh_token) {
          const refreshed = await request('/auth/refresh', {
            refresh_token: session.refresh_token
          }, false);
          if (!refreshed.error && refreshed.data && refreshed.data.session) {
            saveSession(refreshed.data.session, 'TOKEN_REFRESHED');
            result = { data: { user: refreshed.data.user }, error: null };
            return {
              data: { session: refreshed.data.session },
              error: null
            };
          }
        }
        if (result.error) {
          saveSession(null, 'SIGNED_OUT');
          return { data: { session: null }, error: result.error };
        }
        session.user = result.data.user;
        saveSession(session, 'TOKEN_REFRESHED');
        return { data: { session: session }, error: null };
      },
      signInWithPassword: async function (credentials) {
        const result = await request('/auth/login', credentials, false);
        if (!result.error && result.data && result.data.session) {
          saveSession(result.data.session, 'SIGNED_IN');
        }
        return result;
      },
      signUp: async function (input) {
        const result = await request('/auth/register', input, false);
        if (!result.error && result.data && result.data.session) {
          saveSession(result.data.session, 'SIGNED_IN');
        }
        return result;
      },
      signOut: async function () {
        const result = await request('/auth/logout', {}, true);
        saveSession(null, 'SIGNED_OUT');
        return { error: result.error || null };
      },
      onAuthStateChange: function (listener) {
        listeners.add(listener);
        return {
          data: {
            subscription: {
              unsubscribe: function () { listeners.delete(listener); }
            }
          }
        };
      }
    }
  };

  window.gostaySupabase = client;
}());
