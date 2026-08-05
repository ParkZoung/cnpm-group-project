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
    startOnlineCheckin: function (bookingId, option) {
      return invoke('customer_start_online_checkin', {
        p_booking_id: bookingId,
        p_payment_option: option
      });
    },
    claimOnlinePayment: function (bookingId) {
      return invoke('customer_claim_online_payment', { p_booking_id: bookingId });
    },
    cancel: function (bookingId) {
      return invoke('cancel_own_booking', { p_booking_id: bookingId });
    }
  });
}());
