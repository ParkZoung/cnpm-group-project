document.addEventListener('DOMContentLoaded', function () {
  const searchBox = document.querySelector('.search-box');
  if (!searchBox) return;

  const triggers = searchBox.querySelectorAll('.search-trigger');
  const panels = searchBox.querySelectorAll('.search-panel');

  function closePanels(exceptId) {
    panels.forEach(function (panel) {
      if (panel.id !== exceptId) panel.hidden = true;
    });
    triggers.forEach(function (trigger) {
      trigger.setAttribute('aria-expanded', trigger.dataset.panel === exceptId ? 'true' : 'false');
    });
  }

  triggers.forEach(function (trigger) {
    trigger.addEventListener('click', function () {
      const panel = document.getElementById(trigger.dataset.panel);
      const willOpen = panel.hidden;
      closePanels(willOpen ? panel.id : null);
      panel.hidden = !willOpen;
    });
  });

  document.addEventListener('click', function (event) {
    // Keep the panel open even when a calendar click redraws its own button.
    if (!event.composedPath().includes(searchBox)) closePanels();
  });

  searchBox.querySelectorAll('.place-option').forEach(function (option) {
    option.addEventListener('click', function () {
      document.getElementById('destination-value').textContent = option.dataset.place;
      document.getElementById('destination-input').value = option.dataset.place;
      closePanels();
    });
  });

  const counterValues = { adults: 1, children: 0, rooms: 1 };
  const minimums = { adults: 1, children: 0, rooms: 1 };

  searchBox.querySelectorAll('.guest-row button').forEach(function (button) {
    button.addEventListener('click', function () {
      const row = button.closest('.guest-row');
      const key = row.dataset.counter;
      counterValues[key] = Math.max(minimums[key], Math.min(10, counterValues[key] + Number(button.dataset.change)));
      row.querySelector('b').textContent = counterValues[key];
      document.getElementById(key + '-input').value = counterValues[key];
      document.getElementById('guests-value').textContent = counterValues.adults + ' người lớn · ' + counterValues.children + ' trẻ em · ' + counterValues.rooms + ' phòng';
    });
  });

  const today = new Date();
  today.setHours(0, 0, 0, 0);
  let checkin = null;
  let checkout = null;
  const weekdays = ['Thứ 2', 'Thứ 3', 'Thứ 4', 'Thứ 5', 'Thứ 6', 'Thứ 7', 'CN'];

  function isoDate(date) {
    const offsetDate = new Date(date.getTime() - date.getTimezoneOffset() * 60000);
    return offsetDate.toISOString().slice(0, 10);
  }

  function shortDate(date) {
    return String(date.getDate()).padStart(2, '0') + '/' + String(date.getMonth() + 1).padStart(2, '0');
  }

  function renderCalendar() {
    const months = document.getElementById('calendar-months');
    months.innerHTML = '';

    [0, 1].forEach(function (offset) {
      const monthDate = new Date(today.getFullYear(), today.getMonth() + offset, 1);
      const month = document.createElement('div');
      month.className = 'calendar-month';
      month.innerHTML = '<h4>tháng ' + (monthDate.getMonth() + 1) + ' năm ' + monthDate.getFullYear() + '</h4>';
      const grid = document.createElement('div');
      grid.className = 'calendar-grid';
      weekdays.forEach(function (day) {
        const label = document.createElement('span');
        label.textContent = day;
        grid.appendChild(label);
      });

      const firstDay = (monthDate.getDay() + 6) % 7;
      for (let blank = 0; blank < firstDay; blank += 1) grid.appendChild(document.createElement('i'));
      const totalDays = new Date(monthDate.getFullYear(), monthDate.getMonth() + 1, 0).getDate();

      for (let day = 1; day <= totalDays; day += 1) {
        const date = new Date(monthDate.getFullYear(), monthDate.getMonth(), day);
        const button = document.createElement('button');
        button.type = 'button';
        button.className = 'calendar-day';
        button.textContent = day;
        button.disabled = date < today;
        button.dataset.date = isoDate(date);
        if ((checkin && date.getTime() === checkin.getTime()) || (checkout && date.getTime() === checkout.getTime())) button.classList.add('selected');
        if (checkin && checkout && date > checkin && date < checkout) button.classList.add('in-range');
        button.addEventListener('click', function () { selectDate(date); });
        grid.appendChild(button);
      }
      month.appendChild(grid);
      months.appendChild(month);
    });
  }

  function selectDate(date) {
    if (!checkin || checkout || date <= checkin) {
      checkin = date;
      checkout = null;
      document.getElementById('checkin-value').textContent = shortDate(date);
      document.getElementById('checkout-value').textContent = 'Trả phòng';
      document.getElementById('checkin-input').value = isoDate(date);
      document.getElementById('checkout-input').value = '';
      document.getElementById('calendar-hint').textContent = 'Chọn ngày trả phòng';
    } else {
      checkout = date;
      document.getElementById('checkout-value').textContent = shortDate(date);
      document.getElementById('checkout-input').value = isoDate(date);
      document.getElementById('calendar-hint').textContent = 'Đã chọn ngày nhận và trả phòng';
      setTimeout(closePanels, 180);
    }
    renderCalendar();
  }

  renderCalendar();
});
