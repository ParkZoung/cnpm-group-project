(function () {
  'use strict';
  window.gostayStaffReady = (async function () {
    if (!window.gostaySupabase) return null;
    try {
      const sessionResult = await window.gostaySupabase.auth.getSession();
      const user = sessionResult.data.session && sessionResult.data.session.user;
      if (!user) throw new Error('no-session');
      const result = await window.gostaySupabase.from('profiles')
        .select('id,full_name,role,status')
        .eq('id', user.id).maybeSingle();
      if (result.error || !result.data || result.data.role !== 'staff' ||
          result.data.status !== 'active') throw new Error('not-staff');
      return { user: user, profile: result.data };
    } catch (error) {
      window.location.replace('login.html');
      return null;
    }
  }());
}());
