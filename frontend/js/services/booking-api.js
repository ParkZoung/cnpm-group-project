(function () {
  'use strict';

  function invoke(name, args) {
    return window.GoStayApiClient.authenticatedRequest('/rpc', {
      name: name,
      args: args || {}
    });
  }

  window.GoStayBookingApi = Object.freeze({
    create: function (payload) {
      return invoke('create_booking', payload);
    },
    cancel: function (bookingId) {
      return invoke('cancel_own_booking', { p_booking_id: bookingId });
    }
  });
}());
