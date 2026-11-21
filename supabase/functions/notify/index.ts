// Supabase Edge Function "notify" — envia por Resend os e-mails enfileirados em app.notification_outbox.
//
// Chamada por:
//   1) Database Webhook (INSERT em app.notification_outbox) → corpo { type, table, schema, record: { id, ... } }
//   2) Drenagem periódica (pg_cron/agendador)               → corpo { "drain": true }
// Autorização: cabeçalho x-webhook-secret = NOTIFY_WEBHOOK_SECRET, ou Authorization: Bearer <service role key>.
//
// Variáveis de ambiente (segredos da função; NUNCA no repositório):
//   RESEND_API_KEY, MODERATOR_EMAIL, SITE_URL, FROM_EMAIL, NOTIFY_WEBHOOK_SECRET (recomendado)
//   SUPABASE_URL e SUPABASE_SERVICE_ROLE_KEY são fornecidas pelo próprio Supabase.
//
// Privacidade: os logs registram só id e tipo da notificação — nunca endereços, códigos ou mensagens.
// Retirada por e-mail (0012): o token de confirmação chega só pelo contexto de notification_claim (vem de
// app.notification_secrets, que o banco apaga quando o envio é concluído), nunca pelo webhook, e nunca é registrado em log.

import { createClient } from "jsr:@supabase/supabase-js@2";
import { type NotificationContext, render } from "./templates.ts";

const env = (k: string): string => Deno.env.get(k) ?? "";
const SUPABASE_URL = env("SUPABASE_URL");
const SERVICE_KEY = env("SUPABASE_SERVICE_ROLE_KEY");
const RESEND_API_KEY = env("RESEND_API_KEY");
const MODERATOR_EMAIL = env("MODERATOR_EMAIL");
const SITE_URL = env("SITE_URL").replace(/\/+$/, "");
const FROM_EMAIL = env("FROM_EMAIL");
const WEBHOOK_SECRET = env("NOTIFY_WEBHOOK_SECRET");
const DRY_RUN = env("NOTIFY_DRY_RUN") === "1"; // testes: não chama a Resend nem marca como enviado

const db = createClient(SUPABASE_URL, SERVICE_KEY, {
  db: { schema: "api" },
  auth: { persistSession: false, autoRefreshToken: false },
});

const json = (status: number, body: unknown) =>
  new Response(JSON.stringify(body), { status, headers: { "content-type": "application/json" } });

function safeEqual(a: string, b: string): boolean {
  if (!a || !b || a.length !== b.length) return false;
  let diff = 0;
  for (let i = 0; i < a.length; i++) diff |= a.charCodeAt(i) ^ b.charCodeAt(i);
  return diff === 0;
}

function authorized(req: Request): boolean {
  const secret = req.headers.get("x-webhook-secret") ?? "";
  const bearer = req.headers.get("authorization") ?? "";
  return (WEBHOOK_SECRET !== "" && safeEqual(secret, WEBHOOK_SECRET)) ||
    (SERVICE_KEY !== "" && safeEqual(bearer, `Bearer ${SERVICE_KEY}`));
}

const EMAIL_RE = /^[^@\s<>"]+@[^@\s<>"]+\.[a-z]{2,}$/i;

async function sendViaResend(id: number, to: string, mail: ReturnType<typeof render>): Promise<void> {
  const res = await fetch("https://api.resend.com/emails", {
    method: "POST",
    headers: {
      Authorization: `Bearer ${RESEND_API_KEY}`,
      "Content-Type": "application/json",
      "Idempotency-Key": `rbc-notify-${id}`, // reenvio da mesma notificação não duplica o e-mail
    },
    body: JSON.stringify({
      from: FROM_EMAIL,
      to: [to],
      subject: mail.subject,
      text: mail.text,
      html: mail.html,
      ...(mail.replyTo && EMAIL_RE.test(mail.replyTo) ? { reply_to: mail.replyTo } : {}),
    }),
  });
  if (!res.ok) {
    // corpo da Resend pode ecoar o destinatário: registra só o status
    throw new Error(`resend_http_${res.status}`);
  }
}

async function processOne(id: number): Promise<"sent" | "skipped" | "failed"> {
  const { data, error } = await db.rpc("notification_claim", { p_id: id });
  if (error) {
    console.error(`notify: claim ${id} falhou (${error.code})`);
    return "failed";
  }
  if (!data) return "skipped"; // já enviado, em envio ou esgotado
  const ctx = data as NotificationContext;
  let ok = false;
  let errText: string | null = null;
  try {
    const to = ctx.to.type === "moderator" ? MODERATOR_EMAIL : (ctx.to.email ?? "");
    if (!EMAIL_RE.test(to)) throw new Error("sem_destinatario_valido");
    const mail = render(ctx, SITE_URL);
    if (DRY_RUN) {
      console.log(`notify: [dry-run] ${id} ${ctx.kind}`);
      // em dry-run devolve o item para a fila
      await db.rpc("notification_done", { p_id: id, p_ok: false, p_error: "dry_run" });
      return "skipped";
    }
    await sendViaResend(id, to, mail);
    ok = true;
  } catch (e) {
    errText = e instanceof Error ? e.message.slice(0, 200) : "erro";
  }
  const done = await db.rpc("notification_done", { p_id: id, p_ok: ok, p_error: errText });
  if (done.error) console.error(`notify: done ${id} falhou (${done.error.code})`);
  console.log(`notify: ${id} ${ctx.kind} ${ok ? "enviado" : "falhou: " + errText}`);
  return ok ? "sent" : "failed";
}

Deno.serve(async (req: Request) => {
  if (req.method !== "POST") return json(405, { error: "method_not_allowed" });
  if (!authorized(req)) return json(401, { error: "unauthorized" });
  const missing = ["SUPABASE_URL", "SUPABASE_SERVICE_ROLE_KEY", "RESEND_API_KEY", "MODERATOR_EMAIL", "SITE_URL", "FROM_EMAIL"]
    .filter((k) => env(k) === "");
  if (missing.length && !DRY_RUN) return json(500, { error: "config", missing });

  let body: Record<string, unknown> = {};
  try {
    body = await req.json();
  } catch {
    return json(400, { error: "invalid_json" });
  }

  let ids: number[] = [];
  const record = body.record as { id?: unknown } | undefined;
  if (record && Number.isSafeInteger(Number(record.id))) {
    ids = [Number(record.id)];
  } else if (body.drain === true) {
    const { data, error } = await db.rpc("notification_pending", { p_limit: 50 });
    if (error) return json(500, { error: "pending_failed" });
    ids = ((data ?? []) as unknown[]).map(Number).filter(Number.isSafeInteger);
  } else {
    return json(400, { error: "expected_record_or_drain" });
  }

  const result = { sent: 0, skipped: 0, failed: 0 };
  for (const id of ids) result[await processOne(id)]++;
  return json(200, result);
});
