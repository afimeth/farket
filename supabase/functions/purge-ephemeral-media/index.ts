// Farket — kaybolan medya süpürücüsü.
//
// collect_expired_ephemeral_media() süresi dolmuş satırları 'purged' işaretleyip
// silinecek Storage yollarını döndürüyor; Postgres, Storage'daki gerçek dosyaları
// silemiyor (storage.objects'e doğrudan DELETE, protect_objects_delete trigger'ı
// tarafından engelli — bkz. 20260817040000_photo_storage.sql). Bu fonksiyon o
// boşluğu kapatır: RPC'yi service_role ile çağırıp dönen yolları siler.
//
// Neyin ne zaman silindiği (bkz. 20260822080000_ephemeral_media.sql):
//   * açılan medya  -> açılıştan 1 saat sonra (arada şikâyet gelmediyse)
//   * açılmayan     -> gönderimden 24 saat sonra
//   * şikâyet edilen-> report_hold_until (30 gün) dolana kadar dokunulmaz
//
// ÖNEMLİ: purge-deleted-photos günlük yeterliyken bu SAATLİK çalışmalı — 1 saatlik
// şikâyet payı günlük bir işle anlamını yitirir, dosyalar gereğinden uzun durur.
// Zamanlama: Dashboard → Edge Functions → Schedules (saat başı) ya da pg_cron+pg_net.
//
// Elle test: supabase functions serve purge-ephemeral-media
//   curl -X POST http://127.0.0.1:54321/functions/v1/purge-ephemeral-media \
//     -H "Authorization: Bearer <service_role_key>"

import { createClient } from "jsr:@supabase/supabase-js@2";

const BUCKET = "ephemeral-media";
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

  const { data, error } = await supabase.rpc("collect_expired_ephemeral_media");
  if (error) {
    return new Response(JSON.stringify({ error: error.message }), {
      status: 500,
      headers: { "Content-Type": "application/json" },
    });
  }

  const paths: string[] = (data?.paths ?? []).filter(
    (p: unknown): p is string => typeof p === "string" && p.length > 0,
  );

  let removedCount = 0;
  const failures: string[] = [];
  for (let i = 0; i < paths.length; i += DELETE_BATCH_SIZE) {
    const batch = paths.slice(i, i + DELETE_BATCH_SIZE);
    const { error: removeError } = await supabase.storage.from(BUCKET).remove(batch);
    if (removeError) {
      // Satır DB'de zaten 'purged' işaretlendi; dosya kaldıysa burada raporlanır.
      // Bir sonraki çalıştırma bu yolu tekrar üretmez, elle temizlenmesi gerekir.
      failures.push(...batch);
    } else {
      removedCount += batch.length;
    }
  }

  return new Response(
    JSON.stringify({
      rows_marked_purged: data?.count ?? 0,
      storage_files_removed: removedCount,
      storage_failures: failures,
    }),
    { headers: { "Content-Type": "application/json" } },
  );
});
