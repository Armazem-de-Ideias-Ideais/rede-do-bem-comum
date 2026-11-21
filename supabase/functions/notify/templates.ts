// Modelos de e-mail PT/EN da Rede do Bem Comum (texto simples + HTML mínimo).
// Conteúdo vindo de usuários é sempre escapado no HTML. Nenhum segredo aqui.

export type Locale = "pt" | "en" | "es";

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
    : locale === "es"
    ? "Rede do Bem Comum — mapa de iniciativas por el bien común. Este es un mensaje automático."
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
  // espanhol só existe no modelo takedown_confirm (Fase 2 traz o resto); os demais tipos caem para o português
  const locale: Locale = ctx.locale === "en" ? "en" : ctx.locale === "es" && ctx.kind === "takedown_confirm" ? "es" : "pt";
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
      // Desde a 0012 a ficha só é ocultada depois que quem pediu confirma pelo link enviado ao e-mail.
      const hidden = d.auto_hidden === true;
      const subject = hidden
        ? `[Moderação] Retirada confirmada por e-mail (ficha oculta): ${name}`
        : `[Moderação] Pedido de retirada na fila (ficha no ar): ${name}`;
      const body = [
        `Ficha: ${name} (${link})`,
        hidden
          ? "Quem pediu confirmou pelo link enviado ao seu e-mail e a ficha foi ocultada preventivamente em todas as superfícies."
          : "A ficha continua NO AR. Responda ao pedido em até 72 horas: confirme (tombstone) ou mantenha com justificativa.",
        d.has_email === true
          ? `E-mail informado: ${d.email_domain_matches === true ? "o domínio coincide com o do site da ficha" : "o domínio NÃO coincide com o do site da ficha"} (o endereço está no painel).`
          : "Sem e-mail informado.",
        `Relação de quem pediu: ${RELATION_PT[str(d.relation)] ?? str(d.relation)}`,
        `Motivo:\n${str(d.reason)}`,
        d.contact ? `Contato informado: ${str(d.contact)}` : "Sem contato informado.",
        hidden ? "Confirme (tombstone) ou restaure com justificativa no painel:" : "Decida no painel:",
      ];
      return { subject, ...wrap("pt", body, panel) };
    }
    case "takedown_confirm": {
      // O token nunca é registrado em log; o link usa a rota do front (#confirmar-retirada-<token> / #confirm-withdrawal-<token>).
      const token = str(d.token);
      if (!/^[0-9a-f]{64}$/.test(token)) throw new Error("takedown_confirm_sem_token");
      const confirm = `${site}/#${locale === "en" ? "confirm-withdrawal" : "confirmar-retirada"}-${token}`;
      const subject = locale === "en"
        ? "Confirm the withdrawal of a listing from Rede do Bem Comum"
        : locale === "es"
        ? "Confirma la retirada de una ficha de la Rede do Bem Comum"
        : "Confirme a retirada de uma ficha da Rede do Bem Comum";
      const body = locale === "en"
        ? [`Someone (hopefully you) asked to withdraw the listing "${name}" from the Rede do Bem Comum map using this address.`,
           "To withdraw it, open the link below. It works once and is valid for 24 hours. The listing leaves the map as soon as you confirm.",
           "If it was not you, ignore this message: nothing changes without the link."]
        : locale === "es"
        ? [`Alguien (esperamos que tú) pidió retirar la ficha "${name}" del mapa de la Rede do Bem Comum usando esta dirección.`,
           "Para retirarla, abre el enlace de abajo. Funciona una sola vez y vale por 24 horas. La ficha sale del mapa en cuanto confirmes.",
           "Si no fuiste tú, ignora este mensaje: nada cambia sin el enlace."]
        : [`Alguém (esperamos que você) pediu para retirar a ficha "${name}" do mapa da Rede do Bem Comum usando este endereço.`,
           "Para retirar, abra o link abaixo. Ele funciona uma vez só e vale por 24 horas. A ficha sai do mapa assim que você confirmar.",
           "Se não foi você, ignore esta mensagem: nada muda sem o link."];
      return { subject, ...wrap(locale, body, confirm) };
    }
    case "takedown_containment": {
      const subject = "[Moderação] ALERTA: retiradas automáticas contidas pelo disjuntor";
      const body = [
        "O disjuntor da retirada por e-mail barrou pedidos: as fichas continuam no ar e os pedidos estão na fila.",
        `Ocultações automáticas: ${str(d.hidden_last_hour)} na última hora (limite ${str(d.limit_per_hour)}) e ${str(d.hidden_last_24h)} nas últimas 24 h (limite ${str(d.limit_per_day)}).`,
        `Pedidos contidos nas últimas 24 h: ${str(d.contained_last_24h)}.`,
        "Este é o único alerta desta janela de 24 h. Veja a visão por IP e por e-mail (só hashes e domínios) e, se for abuso, desfaça em lote:",
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
