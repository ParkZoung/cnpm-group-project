(function () {
  'use strict';

  const BUSINESS_TIME_ZONE = 'Asia/Ho_Chi_Minh';
  const BUSINESS_UTC_OFFSET_HOURS = 7;
  const METRIC_IDS = [
    'totalRoomsValue',
    'availableRoomsValue',
    'bookingsTodayValue',
    'totalCustomersValue',
    'revenueValue'
  ];

  const state = {
    roomCounts: {
      available: null,
      maintenance: null,
      inactive: null
    }
  };

  const $ = function (id) {
    return document.getElementById(id);
  };

  function db() {
    if (!window.gostaySupabase) {
      throw new Error('Supabase chưa được khởi tạo.');
    }
    return window.gostaySupabase;
  }

  function setMetric(id, value) {
    const node = $(id);
    node.textContent = value;
    node.setAttribute('aria-busy', 'false');
  }

  function createMessageRow(message) {
    const row = document.createElement('tr');
    const cell = document.createElement('td');
    cell.colSpan = 6;
    cell.textContent = message;
    row.appendChild(cell);
    return row;
  }

  function showFeedback(message, isError, canRetry) {
    const feedback = $('dashboardFeedback');
    $('dashboardFeedbackText').textContent = message;
    $('dashboardRetryButton').hidden = !canRetry;
    feedback.hidden = !message;
    feedback.className = message
      ? 'booking-feedback is-visible ' + (isError ? 'is-error' : 'is-success')
      : 'booking-feedback';
  }

  function setLoadingState() {
    METRIC_IDS.forEach(function (id) {
      const node = $(id);
      node.textContent = '—';
      node.setAttribute('aria-busy', 'true');
    });
    $('recentBookingsTableBody').replaceChildren(
      createMessageRow('Đang tải dữ liệu đặt phòng...')
    );
    showFeedback('', false, false);
  }

  function getBusinessDayUtcInterval(now) {
    const parts = new Intl.DateTimeFormat('en-CA', {
      timeZone: BUSINESS_TIME_ZONE,
      year: 'numeric',
      month: '2-digit',
      day: '2-digit'
    }).formatToParts(now || new Date());
    const values = {};

    parts.forEach(function (part) {
      if (part.type !== 'literal') values[part.type] = Number(part.value);
    });

    const startMilliseconds = Date.UTC(
      values.year,
      values.month - 1,
      values.day
    ) - (BUSINESS_UTC_OFFSET_HOURS * 60 * 60 * 1000);

    return {
      start: new Date(startMilliseconds).toISOString(),
      end: new Date(startMilliseconds + (24 * 60 * 60 * 1000)).toISOString()
    };
  }

  function countQuery(table) {
    return db().from(table).select('id', { count: 'exact', head: true });
  }

  function roomStatusCountQuery(status) {
    return countQuery('rooms').eq('status', status);
  }

  function unwrap(result) {
    if (result.status === 'rejected') throw result.reason;
    if (result.value.error) throw result.value.error;
    return result.value;
  }

  function renderCountResult(result, id) {
    try {
      const response = unwrap(result);
      setMetric(id, Number(response.count || 0).toLocaleString('vi-VN'));
      return true;
    } catch (error) {
      console.error('[dashboard] Không thể tải chỉ số ' + id + ':', error);
      setMetric(id, '—');
      return false;
    }
  }

  function renderRoomStatusResult(result, status, displayedId) {
    try {
      const response = unwrap(result);
      state.roomCounts[status] = Number(response.count || 0);
      if (displayedId) {
        setMetric(displayedId, state.roomCounts[status].toLocaleString('vi-VN'));
      }
      return true;
    } catch (error) {
      state.roomCounts[status] = null;
      console.error('[dashboard] Không thể tải số phòng ' + status + ':', error);
      if (displayedId) setMetric(displayedId, '—');
      return false;
    }
  }

  function formatMoney(value) {
    return new Intl.NumberFormat('vi-VN', {
      style: 'currency',
      currency: 'VND',
      maximumFractionDigits: 0
    }).format(Number(value || 0));
  }

  function formatDate(value) {
    if (!value) return '—';
    const dateParts = String(value).slice(0, 10).split('-');
    return dateParts.length === 3 ? dateParts.reverse().join('/') : '—';
  }

  function bookingStatus(status) {
    return {
      pending: { label: 'Chờ xác nhận', className: 'status-warning' },
      confirmed: { label: 'Đã xác nhận', className: 'status-success' },
      checked_in: { label: 'Đã nhận phòng', className: 'status-success' },
      completed: { label: 'Hoàn thành', className: 'status-success' },
      cancelled: { label: 'Đã hủy', className: 'status-danger' }
    }[status] || { label: status || 'Không xác định', className: 'status-warning' };
  }

  function appendTextCell(row, value, strong) {
    const cell = document.createElement('td');
    const content = strong ? document.createElement('strong') : cell;
    content.textContent = value;
    if (strong) cell.appendChild(content);
    row.appendChild(cell);
  }

  function renderRecentBookings(bookingsResult, roomsResult) {
    const body = $('recentBookingsTableBody');

    try {
      const bookings = unwrap(bookingsResult).data || [];
      let rooms = [];
      try {
        rooms = unwrap(roomsResult).data || [];
      } catch (roomError) {
        console.error('[dashboard] Không thể tải thông tin phòng:', roomError);
      }
      const roomsById = new Map(rooms.map(function (room) {
        return [String(room.id), room];
      }));

      if (!bookings.length) {
        body.replaceChildren(createMessageRow('Chưa có đặt phòng nào.'));
        return true;
      }

      const fragment = document.createDocumentFragment();
      bookings.forEach(function (booking) {
        const row = document.createElement('tr');
        const room = roomsById.get(String(booking.room_id));
        const roomName = room
          ? String(room.name || 'Thông tin phòng').replace(/\s+\d+\s*$/, '').trim()
          : 'Không xác định';
        const status = bookingStatus(booking.booking_status);

        appendTextCell(row, booking.booking_code || '—');
        appendTextCell(row, booking.guest_name || 'Chưa cập nhật', true);
        appendTextCell(row, roomName);
        appendTextCell(row, formatDate(booking.check_in_date));
        appendTextCell(row, formatMoney(booking.total_amount));

        const statusCell = document.createElement('td');
        const badge = document.createElement('span');
        badge.className = 'status-badge ' + status.className;
        badge.textContent = status.label;
        statusCell.appendChild(badge);
        row.appendChild(statusCell);
        fragment.appendChild(row);
      });

      body.replaceChildren(fragment);
      return true;
    } catch (error) {
      console.error('[dashboard] Không thể tải booking gần đây:', error);
      body.replaceChildren(createMessageRow('Không thể tải đặt phòng gần đây.'));
      return false;
    }
  }

  function renderRevenue(result) {
    try {
      const rows = unwrap(result).data || [];
      const revenue = rows.reduce(function (sum, booking) {
        const amount = Number(booking.total_amount);
        return Number.isFinite(amount) ? sum + amount : sum;
      }, 0);
      setMetric('revenueValue', formatMoney(revenue));
      return true;
    } catch (error) {
      console.error('[dashboard] Không thể tải doanh thu:', error);
      setMetric('revenueValue', '—');
      return false;
    }
  }

  async function loadDashboard(adminContext) {
    setLoadingState();

    if (adminContext && adminContext.profile && adminContext.profile.full_name) {
      $('adminUserName').textContent = adminContext.profile.full_name;
    }

    const interval = getBusinessDayUtcInterval(new Date());
    const requests = [
      countQuery('rooms'),
      roomStatusCountQuery('available'),
      roomStatusCountQuery('maintenance'),
      roomStatusCountQuery('inactive'),
      countQuery('bookings')
        .gte('created_at', interval.start)
        .lt('created_at', interval.end),
      countQuery('profiles').eq('role', 'customer'),
      db().from('bookings')
        .select('total_amount')
        .eq('payment_status', 'paid')
        .neq('booking_status', 'cancelled'),
      db().from('bookings')
        .select('booking_code, room_id, guest_name, check_in_date, total_amount, booking_status, created_at')
        .order('created_at', { ascending: false })
        .limit(5),
      db().from('rooms').select('id, room_number, name')
    ];
    const results = await Promise.allSettled(requests);
    const outcomes = [
      renderCountResult(results[0], 'totalRoomsValue'),
      renderRoomStatusResult(results[1], 'available', 'availableRoomsValue'),
      renderRoomStatusResult(results[2], 'maintenance'),
      renderRoomStatusResult(results[3], 'inactive'),
      renderCountResult(results[4], 'bookingsTodayValue'),
      renderCountResult(results[5], 'totalCustomersValue'),
      renderRevenue(results[6]),
      renderRecentBookings(results[7], results[8])
    ];
    const successful = outcomes.filter(Boolean).length;

    if (successful === outcomes.length) {
      showFeedback('', false, false);
    } else if (successful === 0) {
      showFeedback(
        'Không thể tải dữ liệu dashboard. Vui lòng thử lại.',
        true,
        true
      );
    } else {
      showFeedback(
        'Một số dữ liệu chưa thể tải. Các số liệu khác vẫn được hiển thị.',
        true,
        true
      );
    }
  }

  async function initialize() {
    try {
      const adminContext = await window.gostayAdminReady;
      if (!adminContext) return;
      await loadDashboard(adminContext);
    } catch (error) {
      console.error('[dashboard] Khởi tạo dashboard thất bại:', error);
      showFeedback(
        'Không thể tải dữ liệu dashboard. Vui lòng thử lại.',
        true,
        true
      );
    }
  }

  $('dashboardRetryButton').addEventListener('click', initialize);
  initialize();
}());
