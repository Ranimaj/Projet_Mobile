/**
 * Notifications push ciblées — module « Gestion Annonces ».
 *
 * Déclenchée à la création d'un document `annonces/{id}`. Si `sendPush` est
 * vrai, envoie une notification FCM aux topics ciblés :
 *   - aucun ciblage              -> topic `all_campus`
 *   - filières et/ou années      -> un message par combinaison
 *                                   (filière ET année), via une condition FCM.
 *
 * Les topics (`majorTopics`, `yearTopics`) sont calculés par l'app Flutter
 * (SegmentTopics) : l'abonnement des appareils et l'envoi utilisent donc
 * exactement les mêmes noms.
 */
const { onDocumentCreated } = require("firebase-functions/v2/firestore");
const { initializeApp } = require("firebase-admin/app");
const { getMessaging } = require("firebase-admin/messaging");
const { FieldValue } = require("firebase-admin/firestore");

initializeApp();

const MAJOR_RE = /^major_[a-z0-9-]+$/;
const YEAR_RE = /^year_[a-z0-9-]+$/;
const MAX_TARGETS = 10; // garde-fou : max 10 filières / 10 années

/** Topics ciblés -> liste de conditions/topics FCM à envoyer. */
function buildTargets(majorTopics, yearTopics) {
  if (majorTopics.length === 0 && yearTopics.length === 0) {
    return [{ topic: "all_campus" }];
  }
  if (yearTopics.length === 0) return majorTopics.map((m) => ({ topic: m }));
  if (majorTopics.length === 0) return yearTopics.map((y) => ({ topic: y }));

  const targets = [];
  for (const m of majorTopics) {
    for (const y of yearTopics) {
      targets.push({ condition: `'${m}' in topics && '${y}' in topics` });
    }
  }
  return targets;
}

exports.sendAnnoncePush = onDocumentCreated("annonces/{annonceId}", async (event) => {
  const snap = event.data;
  if (!snap) return;
  const data = snap.data();
  if (data.sendPush !== true || data.pushSentAt) return; // pas demandé / déjà envoyé

  const majorTopics = (Array.isArray(data.majorTopics) ? data.majorTopics : [])
    .filter((t) => typeof t === "string" && MAJOR_RE.test(t))
    .slice(0, MAX_TARGETS);
  const yearTopics = (Array.isArray(data.yearTopics) ? data.yearTopics : [])
    .filter((t) => typeof t === "string" && YEAR_RE.test(t))
    .slice(0, MAX_TARGETS);

  const urgent = data.isUrgent === true;
  const title = `${urgent ? "🚨 " : ""}${data.category === "Officielle" ? "Annonce officielle" : "Nouvelle annonce"}`;
  const body = String(data.title || "").slice(0, 120);

  const messages = buildTargets(majorTopics, yearTopics).map((target) => ({
    ...target,
    notification: { title, body },
    data: { annonceId: event.params.annonceId, type: "annonce" },
    android: { priority: urgent ? "high" : "normal" },
    apns: { headers: { "apns-priority": urgent ? "10" : "5" } },
  }));

  const messaging = getMessaging();
  const results = await Promise.allSettled(messages.map((m) => messaging.send(m)));
  const failed = results.filter((r) => r.status === "rejected");
  failed.forEach((r) => console.error("Envoi FCM échoué:", r.reason));

  // Marque l'annonce comme notifiée (évite un double envoi en cas de retry).
  if (failed.length < messages.length) {
    await snap.ref.update({ pushSentAt: FieldValue.serverTimestamp() });
  }
});
