// Farket — beta test girişi (yalnızca test aşaması için).
//
// Gerçek e-posta gönderimi Resend özel SMTP'ye bağlı ama domain doğrulanmadığı
// için yalnızca hesap sahibinin kendi mailine ulaşıyor (bkz. DOCTOR.md 21
// Ağustos). Farklı beta test kullanıcılarının kendi mail kutularını açmadan
// giriş yapabilmesi için: kullanıcı herhangi bir e-posta + sabit test kodunu
// yazar, bu fonksiyon kodu doğrular ve gerçek mail göndermeden Supabase
// Admin API ile bir magic-link token'ı üretip client'a döner. Client bu
// token'ı `auth.verifyOtp(type = MAGIC_LINK)` ile kullanarak oturum açar.
//
// Bu yalnızca beta için bir kısayoldur, gerçek güvenlik sınırı DEĞİLDİR —
// kod ekranda görünür durumda kalacak (bkz. LoginScreen). Store'a çıkışta
// TEST_LOGIN_ENABLED=false yapılıp bu fonksiyon devre dışı bırakılmalı.
//
// Elle test:
//   curl -X POST https://<ref>.supabase.co/functions/v1/test-login \
//     -H "Authorization: Bearer <anon_key>" -H "Content-Type: application/json" \
//     -d '{"email":"test@example.com","code":"123456"}'

import { createClient } from "jsr:@supabase/supabase-js@2";

Deno.serve(async (req) => {
  if (req.method !== "POST") {
    return new Response(JSON.stringify({ error: "POST gerekli" }), {
      status: 405,
      headers: { "Content-Type": "application/json" },
    });
  }

  const testLoginEnabled = (Deno.env.get("TEST_LOGIN_ENABLED") ?? "true") === "true";
  if (!testLoginEnabled) {
    return new Response(JSON.stringify({ error: "Test girişi kapalı" }), {
      status: 403,
      headers: { "Content-Type": "application/json" },
    });
  }

  const expectedCode = Deno.env.get("TEST_LOGIN_CODE") ?? "";
  const serviceKey = Deno.env.get("SUPABASE_SERVICE_ROLE_KEY") ?? "";
  const supabaseUrl = Deno.env.get("SUPABASE_URL") ?? "";
  if (!expectedCode || !serviceKey || !supabaseUrl) {
    return new Response(JSON.stringify({ error: "Sunucu yapılandırması eksik" }), {
      status: 500,
      headers: { "Content-Type": "application/json" },
    });
  }

  let body: { email?: string; code?: string };
  try {
    body = await req.json();
  } catch {
    return new Response(JSON.stringify({ error: "Geçersiz istek gövdesi" }), {
      status: 400,
      headers: { "Content-Type": "application/json" },
    });
  }

  const email = body.email?.trim().toLowerCase() ?? "";
  const code = body.code?.trim() ?? "";
  if (!email || !email.includes("@")) {
    return new Response(JSON.stringify({ error: "Geçerli bir e-posta gerekli" }), {
      status: 400,
      headers: { "Content-Type": "application/json" },
    });
  }
  if (code !== expectedCode) {
    return new Response(JSON.stringify({ error: "Test kodu hatalı" }), {
      status: 401,
      headers: { "Content-Type": "application/json" },
    });
  }

  const supabase = createClient(supabaseUrl, serviceKey);

  const { data, error } = await supabase.auth.admin.generateLink({
    type: "magiclink",
    email,
  });

  if (error || !data?.properties?.hashed_token) {
    return new Response(JSON.stringify({ error: error?.message ?? "Token üretilemedi" }), {
      status: 500,
      headers: { "Content-Type": "application/json" },
    });
  }

  return new Response(
    JSON.stringify({ token_hash: data.properties.hashed_token, email }),
    { headers: { "Content-Type": "application/json" } },
  );
});
