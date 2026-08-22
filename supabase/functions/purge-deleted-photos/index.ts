// Farket — günlük temizlik orkestratörü.
//
// purge_deleted_accounts() DB satırlarını temizleyip silinmesi gereken Storage
// yollarını (deleted_photo_paths) döndürüyor ama Postgres, Storage'daki gerçek
// dosyaları silemiyor (storage.objects'e doğrudan DELETE, protect_objects_delete
// trigger'ı tarafından engelli — bkz. 20260817040000_photo_storage.sql notu).
// Bu Edge Function o boşluğu kapatır: RPC'yi service_role ile çağırır, dönen
// yolları profile-photos bucket'ından fiziksel olarak siler.
//
// Zamanlanmış çalıştırma: Supabase Dashboard → Edge Functions → Schedules
// (günlük, örn. 03:10 UTC) ya da pg_cron + pg_net ile HTTP tetikleme.
// Elle test: supabase functions serve purge-deleted-photos
//   curl -X POST http://127.0.0.1:54321/functions/v1/purge-deleted-photos \
//     -H "Authorization: Bearer <service_role_key>"
//
// Güvenlik: yalnızca service_role çağırabilir — verify_jwt varsayılan açık,
// ayrıca aşağıda rol claim'i açıkça kontrol ediliyor.

import { createClient } from "jsr:@supabase/supabase-js@2";

const BUCKET = "profile-photos";
const DELETE_BATCH_SIZE = 100;

Deno.serve(async (req) => {
  const authHeader = req.headers.get("Authorization") ?? "";
  const token = authHeader.replace(/^Bearer\s+/i, "");
  const serviceKey = Deno.env.get("SUPABASE_SERVICE_ROLE_KEY") ?? "";
  if (!serviceKey || token !== serviceKey) {
    return new Response(JSON.stringify({ error: "service_role gerekli" }), {
      status: 403,
      headers: { "Content-Type": "application/json" },
    });
  }

  const supabase = createClient(
    Deno.env.get("SUPABASE_URL") ?? "",
    serviceKey,
  );

  const { data, error } = await supabase.rpc("purge_deleted_accounts");
  if (error) {
    return new Response(JSON.stringify({ error: error.message }), {
      status: 500,
      headers: { "Content-Type": "application/json" },
    });
  }

  const paths: string[] = (data?.deleted_photo_paths ?? []).filter(
    (p: unknown): p is string => typeof p === "string" && p.length > 0,
  );

  let removedCount = 0;
  const failures: string[] = [];
  for (let i = 0; i < paths.length; i += DELETE_BATCH_SIZE) {
    const batch = paths.slice(i, i + DELETE_BATCH_SIZE);
    const { error: removeError } = await supabase.storage.from(BUCKET).remove(batch);
    if (removeError) {
      // Kısmi hata: kalan batch'lere devam et, sonuçta raporla — bir sonraki
      // günlük çalıştırma DB tarafında yeni yol üretmez ama burada loglanan
      // yollar elle temizlenebilir.
      failures.push(...batch);
    } else {
      removedCount += batch.length;
    }
  }

  return new Response(
    JSON.stringify({
      purged_accounts: data?.purged_count ?? 0,
      storage_files_removed: removedCount,
      storage_failures: failures,
    }),
    { headers: { "Content-Type": "application/json" } },
  );
});
