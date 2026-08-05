import { fail, json } from '../../_shared/response.js';
import { requireUser } from '../middleware/authentication.js';
import { env } from '../config/environment.js';

export async function handleVietQr(body, req) {
  if (!body || typeof body.booking_id !== 'string') return fail('Invalid booking ID.', 400);
  const auth = await requireUser(req);
  if (auth.error) return auth.error;
  const result = await auth.client.rpc('customer_get_online_checkin_payment', {
    p_booking_id: body.booking_id
  });
  const row = Array.isArray(result.data) ? result.data[0] : result.data;
  if (result.error || !row || !Number.isSafeInteger(Number(row.requested_amount))) {
    return fail('Online check-in payment is not available.', 400);
  }
  const bankId = encodeURIComponent(env('GOSTAY_VIETQR_BANK_ID'));
  const accountNo = encodeURIComponent(env('GOSTAY_VIETQR_ACCOUNT_NO'));
  const template = encodeURIComponent(Deno.env.get('GOSTAY_VIETQR_TEMPLATE') || 'compact2');
  const params = new URLSearchParams({
    amount: String(row.requested_amount),
    addInfo: row.booking_code,
    accountName: env('GOSTAY_VIETQR_ACCOUNT_NAME')
  });
  return json({ data: {
    booking_code: row.booking_code,
    amount: row.requested_amount,
    status: row.online_checkin_status,
    qr_url: `https://img.vietqr.io/image/${bankId}-${accountNo}-${template}.png?${params}`
  }, error: null });
}
