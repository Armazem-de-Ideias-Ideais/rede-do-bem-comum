// Modelos de e-mail PT/EN da Rede do Bem Comum (texto simples + HTML mínimo).
// Conteúdo vindo de usuários é sempre escapado no HTML. Nenhum segredo aqui.

export type Locale = "pt" | "en";

export interface NotificationContext {
  id: number;
  kind: string;
  locale: string;
  to: { type: "moderator" | "account" | "address"; email?: string | null };
  entity: { id: string; name: string; slug: string | null } | null;
  data: Record<string, unknown>;
  created_at: string;
}

export interface RenderedEmail {
  subject: string;
  text: string;
  html: string;
  replyTo?: string;
}

const esc = (v: unknown): string =>
  String(v ?? "").replace(/[&<>"']/g, (c) =>
    ({ "&": "&amp;", "<": "&lt;", ">": "&gt;", '"': "&quot;", "'": "&#39;" }[c] as string)
  );

const str = (v: unknown): string => (v === null || v === undefined ? "" : String(v));

function entityLink(site: string, slug: string | null | undefined): string {
  return slug ? `${site}/#i-${encodeURIComponent(slug)}` : site;
}

function wrap(locale: Locale, paragraphs: string[], footerLink: string): { text: string; html: string } {
  const footer = locale === "en"
    ? "Rede do Bem Comum — a map of initiatives for the common good. This is an automatic message."
    : "Rede do Bem Comum — mapa de iniciativas pelo bem comum. Esta é uma mensagem automática.";
  const text = [...paragraphs, "", footerLink, "", "—", footer].join("\n");
  const html = `<!doctype html><html lang="${locale}"><body style="font-family:system-ui,sans-serif;line-height:1.5;max-width:560px">` +
    paragraphs.map((p) => `<p>${esc(p).replace(/\n/g, "<br>")}</p>`).join("") +
    `<p><a href="${esc(footerLink)}">${esc(footerLink)}</a></p>` +
    `<hr><p style="color:#666;font-size:13px">${esc(footer)}</p></body></html>`;
  return { text, html };
}

const RELATION_PT: Record<string, string> = {
  representative: "representante da iniciativa", member: "integrante", mentioned: "pessoa mencionada", other: "outro",
};

export function render(ctx: NotificationContext, site: string): RenderedEmail {
  const locale: Locale = ctx.locale === "en" ? "en" : "pt";
  const en = locale === "en";
  const d = ctx.data ?? {};
  const name = str(ctx.entity?.name);
  const link = entityLink(site, ctx.entity?.slug);
  const account = `${site}/#conta`;
  const panel = `${site}/#painel`;
  const ent = (k: string) => (d[k] ?? {}) as { name?: string; slug?: string };

  switch (ctx.kind) {
    case "connect_received": {
      const from = ent("from_entity"), to = ent("to_entity");
      const subject = en ? `Connection request for ${str(to.name)}` : `Pedido de conexão para ${str(to.name)}`;
      const body = en
        ? [`${str(from.name)} would like to connect with ${str(to.name)}.`, `Message:\n${str(d.message)}`,
           "Your contact details stay private unless you accept. Sign in to reply:"]
        : [`${str(from.name)} quer se conectar com ${str(to.name)}.`, `Mensagem:\n${str(d.message)}`,
           "Seu contato fica reservado e só é compartilhado se você aceitar. Entre para responder:"];
      return { subject, ...wrap(locale, body, account) };
    }
    case "connect_accepted": {
      const to = ent("to_entity");
      const subject = en ? `${str(to.name)} accepted your connection request` : `${str(to.name)} aceitou seu pedido de conexão`;
      const body = en
        ? [`Good news: ${str(to.name)} accepted your request.`, `How to reach them: ${str(d.contact)}`,
           "You can see all your connections in your account:"]
        : [`Boa notícia: ${str(to.name)} aceitou seu pedido.`, `Como entrar em contato: ${str(d.contact)}`,
           "Todas as suas conexões ficam na sua conta:"];
      return { subject, ...wrap(locale, body, account) };
    }
    case "claim_code": {
      const subject = en ? `Verification code: ${str(d.code)}` : `Código de verificação: ${str(d.code)}`;
      const body = en
        ? [`Someone asked to manage the entry "${name}" on Rede do Bem Comum using this address.`,
           `Your code is ${str(d.code)}. It is valid for 30 minutes.`,
           "If it wasn't you, ignore this message: nothing changes without the code."]
        : [`Alguém pediu para gerir a ficha "${name}" na Rede do Bem Comum usando este endereço.`,
           `Seu código é ${str(d.code)}. Ele vale por 30 minutos.`,
           "Se não foi você, ignore esta mensagem: nada muda sem o código."];
      return { subject, ...wrap(locale, body, link) };
    }
    case "claim_approved": {
      const subject = en ? `You now manage "${name}"` : `Você agora gere a ficha "${name}"`;
      const body = en
        ? [`Your claim for "${name}" was approved.`, "You can now edit the entry, publish offers and needs, and answer connection requests."]
        : [`Sua reivindicação da ficha "${name}" foi aprovada.`, "Agora você pode editar a ficha, publicar ofertas e necessidades e responder pedidos de conexão."];
      return { subject, ...wrap(locale, body, account) };
    }
    case "claim_rejected": {
      const subject = en ? `Claim for "${name}" not approved` : `Reivindicação de "${name}" não aprovada`;
      const body = en
        ? [`Your claim for "${name}" was not approved.`, `Reason: ${str(d.rationale)}`, "You can try another verification path."]
        : [`Sua reivindicação da ficha "${name}" não foi aprovada.`, `Motivo: ${str(d.rationale)}`, "Você pode tentar outro caminho de verificação."];
      return { subject, ...wrap(locale, body, account) };
    }
    case "claim_pending": {
      const subject = `[Moderação] Reivindicação a analisar: ${name}`;
      const body = [
        `Ficha: ${name} (${link})`, `Caminho: ${str(d.method)}`, `Declaração:\n${str(d.statement)}`,
        d.published_code ? `Código publicado esperado: ${str(d.published_code)}` : "",
        d.evidence_url ? `Onde conferir: ${str(d.evidence_url)}` : "",
        d.claimant_email ? `Conta: ${str(d.claimant_email)}` : "",
        "Decida no painel:",
      ].filter(Boolean);
      return { subject, ...wrap("pt", body, panel) };
    }
    case "takedown_request": {
      const hidden = d.auto_hidden === true;
      const subject = `[Moderação] Pedido de retirada${hidden ? " (já oculta)" : ""}: ${name}`;
      const body = [
        `Ficha: ${name} (${link})`,
        hidden ? "A ficha foi ocultada preventivamente em todas as superfícies." : "ATENÇÃO: a ficha NÃO foi ocultada automaticamente (disjuntor de volume). Avalie já.",
        `Relação de quem pediu: ${RELATION_PT[str(d.relation)] ?? str(d.relation)}`,
        `Motivo:\n${str(d.reason)}`,
        d.contact ? `Contato informado: ${str(d.contact)}` : "Sem contato informado.",
        "Confirme (tombstone) ou restaure com justificativa no painel:",
      ];
      return { subject, ...wrap("pt", body, panel) };
    }
    case "contact_message": {
      const subject = `[Contato] ${str(d.subject)}`;
      const body = [`De: ${str(d.sender_name)} <${str(d.reply_to)}>`, `Idioma: ${str(d.locale)}`, str(d.body),
                    "Responda diretamente a este e-mail. Fila no painel:"];
      return { subject, ...wrap("pt", body, panel), replyTo: str(d.reply_to) || undefined };
    }
    case "invite_accepted": {
      const subject = `[Moderação] Convite aceito: ${name}`;
      return { subject, ...wrap("pt", [`A iniciativa aceitou o convite e a ficha "${name}" foi publicada já gerida por ela.`], link) };
    }
    default:
      throw new Error(`tipo de notificação desconhecido: ${ctx.kind}`);
  }
}
