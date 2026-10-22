// Axis Team: sends the push notifications the website schedules.
//
// The website writes /notifications/{id} when a leader promotes someone:
//   { type: 'promotion', store_id, member_id, promotion_id, title, body,
//     send_at: Timestamp, status: 'scheduled' }
// Every minute this finds the ones that are due and sends them to every phone
// saved on the team member (stores/{store_id}/users/{member_id}.fcm_tokens).
// Afterwards status is one of:
//   sent       delivered to at least one phone
//   no_device  they have no phone with notifications on (they'll still see
//              the congratulations screen when they open the app)
//   muted      they turned notifications off in the app
//   cancelled  the title was changed again before it went out
//   replaced   a newer promotion took its place
//   failed     every phone rejected it (see `error`)
// type 'feedback' goes to the developers' phones (dev/devices.tokens, saved
// by the Optic app).
// type 'promotion_test' (Settings → "Test the promotion") goes straight to
// the `tokens` on the doc, with fixed wording.
//
// Deploy (needs the Blaze plan): double-click deploy_notifications.command,
// or run: firebase deploy --only functions --project project-attendance-app

const { onSchedule } = require("firebase-functions/v2/scheduler");
const { onDocumentWritten } = require("firebase-functions/v2/firestore");
const { onCall, onRequest, HttpsError } = require("firebase-functions/v2/https");
const { setGlobalOptions, logger } = require("firebase-functions/v2");
const { initializeApp } = require("firebase-admin/app");
const { getFirestore, FieldValue, Timestamp } = require("firebase-admin/firestore");
const { getMessaging } = require("firebase-admin/messaging");
const { getAuth } = require("firebase-admin/auth");

initializeApp();
setGlobalOptions({ region: "us-central1", maxInstances: 1 });

const db = getFirestore();

// Tokens that will never work again (app uninstalled, signed out, ...).
const DEAD_TOKEN = new Set([
  "messaging/registration-token-not-registered",
  "messaging/invalid-registration-token",
]);

/**
 * A push to the developers' phones (the Optic app). It's a data message so
 * Optic draws it: the Optic mark as the small icon and the icon of the app
 * it's about (`data.service`) on the right. See lib/notifications.dart.
 */
function opticPush(tokens, { title, body, color, data }) {
  const strData = {};
  for (const [k, v] of Object.entries(data || {})) strData[k] = String(v == null ? "" : v);
  return {
    tokens,
    data: {
      ...strData,
      title: String(title || "Optic").slice(0, 120),
      body: String(body || "").slice(0, 300),
      color: String(color || ""),
    },
    android: { priority: "high" },
  };
}

exports.sendDueNotifications = onSchedule(
  { schedule: "every 1 minutes", timeoutSeconds: 120, retryCount: 0 },
  async () => {
    const now = Timestamp.now().toMillis();
    // Single-field query (no index needed); the time check happens here.
    const snap = await db
      .collection("notifications")
      .where("status", "==", "scheduled")
      .limit(300)
      .get();
    const due = snap.docs.filter((d) => {
      const at = d.get("send_at");
      return !at || typeof at.toMillis !== "function" || at.toMillis() <= now;
    });
    for (const doc of due) {
      try {
        await sendOne(doc.ref);
      } catch (e) {
        logger.error("Notification failed", doc.id, e);
        await doc.ref
          .update({ status: "failed", error: String(e), updated_at: FieldValue.serverTimestamp() })
          .catch(() => {});
      }
    }
    if (due.length) logger.info(`Handled ${due.length} notification(s).`);
  },
);

// Instant push notification whenever a feedback ticket is created, replied to by a user, or reopened.
exports.onFeedbackWritten = onDocumentWritten(
  {
    document: "users/{userId}/feedback/{ticketId}",
    region: "us-central1",
    maxInstances: 1,
  },
  async (event) => {
    if (!event.data || !event.data.after.exists) return;

    const before = event.data.before && event.data.before.exists ? event.data.before.data() : null;
    const after = event.data.after.data();
    const isNew = !before;
    const isBug = after.type === "Bug";
    const name = after.submitter_name || "Someone";
    const app = after.app || after.app_name || "Axis Team";
    const location = (after.location || after.page || "").trim();
    const ticketPath = `users/${event.params.userId}/feedback/${event.params.ticketId}`;

    let title = "";
    let body = "";

    const locPrefix = location ? `[${app} • ${location}] ` : `[${app}] `;

    if (isNew) {
      title = isBug ? `🔴 Bug from ${name}` : `🔵 Improvement from ${name}`;
      body = (locPrefix + String(after.message || "")).slice(0, 300);
    } else {
      const repliesBefore = Array.isArray(before.replies) ? before.replies.length : 0;
      const repliesAfter = Array.isArray(after.replies) ? after.replies.length : 0;
      const reopenedBefore = Number(before.reopened_count || 0);
      const reopenedAfter = Number(after.reopened_count || 0);

      if (reopenedAfter > reopenedBefore) {
        title = `↩️ ${name} reopened a ticket`;
        body = (locPrefix + String(after.message || "")).slice(0, 300);
      } else if (after.last_reply_from === "user" && repliesAfter > repliesBefore) {
        const lastReply = after.replies[repliesAfter - 1];
        title = `💬 ${lastReply.name || name} replied`;
        body = String(lastReply.text || "").slice(0, 300);
      } else {
        return;
      }
    }

    // Per-app switches in Optic (App → Alerts): new tickets vs. replies/reopens.
    const serviceId = serviceIdForApp(app);
    const alertKey = isNew ? "new_feedback" : "feedback_replies";
    if (!(await developersWant(serviceId, alertKey))) {
      logger.info(`Feedback push skipped: ${serviceId}.${alertKey} is off in Optic`);
      return;
    }

    const devices = await db.collection("dev").doc("devices").get();
    const tokens = [...new Set((devices.get("tokens") || []).filter((t) => typeof t === "string" && t))];
    if (!tokens.length) {
      logger.warn("No developer device tokens found in dev/devices");
      return;
    }

    const res = await getMessaging().sendEachForMulticast(
      opticPush(tokens, {
        title,
        body,
        color: isBug ? "#FF4C52" : "#4C8DFF",
        data: {
          type: "feedback",
          service: serviceId,
          ticket_type: isBug ? "Bug" : "Improvement",
          ticket_path: ticketPath,
          app: app,
          location: location,
        },
      }),
    );

    const dead = [];
    res.responses.forEach((r, i) => {
      if (!r.success && DEAD_TOKEN.has(r.error && r.error.code)) dead.push(tokens[i]);
    });
    if (dead.length) await devices.ref.update({ tokens: FieldValue.arrayRemove(...dead) });
    logger.info(`Feedback push sent instantly: ${title} (${res.successCount} succeeded, ${res.failureCount} failed)`);
  }
);

async function sendOne(ref) {
  // Claim it so it's never sent twice.
  const data = await db.runTransaction(async (tx) => {
    const d = await tx.get(ref);
    if (!d.exists || d.get("status") !== "scheduled") return null;
    tx.update(ref, { status: "sending", claimed_at: FieldValue.serverTimestamp() });
    return d.data();
  });
  if (!data) return;

  const finish = (status, extra = {}) =>
    ref.update({ status, ...extra, updated_at: FieldValue.serverTimestamp() });

  // A feedback ticket (new, replied or reopened): to the developers' phones
  // (the Optic app saves them in dev/devices.tokens). Bugs show in red.
  if (data.type === "feedback") {
    // If ticket_path is present on a real ticket, onFeedbackWritten handles real-time delivery
    if (data.ticket_path && data.source !== "manual") {
      return finish("sent", { note: "Handled in real-time by onFeedbackWritten" });
    }

    const devices = await db.collection("dev").doc("devices").get();
    const tokens = [...new Set((devices.get("tokens") || []).filter((t) => typeof t === "string" && t))];
    if (!tokens.length) return finish("no_device");
    const bug = data.ticket_type === "Bug";
    const res = await getMessaging().sendEachForMulticast(
      opticPush(tokens, {
        title: data.title || (bug ? "New bug" : "New improvement"),
        body: data.body,
        color: bug ? "#FF4C52" : "#4C8DFF",
        data: {
          type: "feedback",
          service: serviceIdForApp(data.app),
          ticket_type: bug ? "Bug" : "Improvement",
          ticket_path: String(data.ticket_path || ""),
          app: String(data.app || "Axis Team"),
          location: String(data.location || ""),
        },
      }),
    );
    const dead = [];
    res.responses.forEach((r, i) => {
      if (!r.success && DEAD_TOKEN.has(r.error && r.error.code)) dead.push(tokens[i]);
    });
    if (dead.length) await devices.ref.update({ tokens: FieldValue.arrayRemove(...dead) });
    return finish(res.successCount > 0 ? "sent" : "failed", {
      sent_at: FieldValue.serverTimestamp(),
      success_count: res.successCount,
      failure_count: res.failureCount,
    });
  }

  // Settings → "Test the promotion": straight to the phone that asked.
  if (data.type === "promotion_test") {
    const tokens = (Array.isArray(data.tokens) ? data.tokens : [])
      .filter((t) => typeof t === "string" && t)
      .slice(0, 3);
    if (!tokens.length) return finish("no_device");
    const to = String(data.to || "Operator").slice(0, 40);
    const first = String(data.first_name || "").slice(0, 30);
    const res = await getMessaging().sendEachForMulticast({
      tokens,
      notification: {
        title: first ? `Congratulations, ${first}! 🎉` : "Congratulations! 🎉",
        body: `You've been promoted to ${to}. Tap to see your new title.`,
      },
      data: { type: "promotion_test", store_id: String(data.store_id || "") },
      android: { priority: "high", notification: { sound: "default", tag: ref.id } },
      apns: { payload: { aps: { sound: "default" } } },
    });
    const errors = res.responses.filter((r) => !r.success).map((r) => (r.error && r.error.code) || "error");
    return finish(res.successCount > 0 ? "sent" : "failed", {
      sent_at: FieldValue.serverTimestamp(),
      success_count: res.successCount,
      failure_count: res.failureCount,
      ...(errors.length ? { error: errors.join(", ") } : {}),
    });
  }

  if (!data.store_id || !data.member_id) return finish("failed", { error: "Missing store or member" });

  const memberRef = db
    .collection("stores")
    .doc(String(data.store_id))
    .collection("users")
    .doc(String(data.member_id));
  const member = await memberRef.get();
  if (!member.exists) return finish("failed", { error: "Team member not found" });

  if (data.type === "promotion") {
    const promo = member.get("promotion") || {};
    if (promo.id && data.promotion_id && promo.id !== data.promotion_id) return finish("replaced");
    if (promo.to && member.get("title") !== promo.to) return finish("cancelled");
  }
  if (member.get("notifications_enabled") === false) return finish("muted");

  const tokens = [...new Set((member.get("fcm_tokens") || []).filter((t) => typeof t === "string" && t))];
  if (!tokens.length) return finish("no_device");

  const res = await getMessaging().sendEachForMulticast({
    tokens,
    notification: { title: String(data.title || "Axis Team"), body: String(data.body || "") },
    data: {
      type: String(data.type || ""),
      promotion_id: String(data.promotion_id || ""),
      store_id: String(data.store_id || ""),
    },
    android: {
      priority: "high",
      notification: { sound: "default", tag: String(data.promotion_id || ref.id) },
    },
    apns: { payload: { aps: { sound: "default" } } },
  });

  const dead = [];
  const errors = [];
  res.responses.forEach((r, i) => {
    if (r.success) return;
    const code = r.error && r.error.code;
    errors.push(code || String(r.error));
    if (DEAD_TOKEN.has(code)) dead.push(tokens[i]);
  });
  if (dead.length) await memberRef.update({ fcm_tokens: FieldValue.arrayRemove(...dead) });

  return finish(res.successCount > 0 ? "sent" : "failed", {
    sent_at: FieldValue.serverTimestamp(),
    success_count: res.successCount,
    failure_count: res.failureCount,
    ...(errors.length ? { error: errors.join(", ") } : {}),
  });
}

// Enable or disable dev store mode: stores/{store_id}.is_dev = true|false
exports.setDevStore = onCall(async (request) => {
  const { storeId, isDev } = request.data || {};
  if (!storeId) {
    throw new HttpsError("invalid-argument", "storeId is required");
  }
  const storeRef = db.collection("stores").doc(String(storeId));
  const doc = await storeRef.get();
  if (!doc.exists) {
    throw new HttpsError("not-found", `Store ${storeId} does not exist`);
  }
  await storeRef.set({ is_dev: Boolean(isDev) }, { merge: true });
  return { success: true, storeId, isDev: Boolean(isDev) };
});

/**
 * Automatically synchronize user email changes from Firestore users/{userId}
 * into Firebase Authentication so that sign-in uses the updated email
 * while preserving the user's password.
 */
exports.onUserWritten = onDocumentWritten(
  {
    document: "users/{userId}",
    region: "us-central1",
    maxInstances: 10,
  },
  async (event) => {
    if (!event.data || !event.data.after.exists) return;

    const before = event.data.before && event.data.before.exists ? event.data.before.data() : null;
    const after = event.data.after.data();
    const userId = event.params.userId;

    const newEmail = (after.email || "").trim();
    const oldEmail = (before ? before.email || "" : "").trim();

    if (!newEmail || newEmail.toLowerCase() === oldEmail.toLowerCase()) return;

    logger.info(`Detected email change for user ${userId}: "${oldEmail}" -> "${newEmail}"`);

    const auth = getAuth();
    let authUser = null;

    // 1. Try finding by userId as Auth localId
    try {
      authUser = await auth.getUser(userId);
    } catch (err) {
      if (err.code !== "auth/user-not-found") {
        logger.error(`Error fetching user ${userId} from Auth:`, err);
      }
    }

    // 2. If not found by uid, try finding by oldEmail
    if (!authUser && oldEmail) {
      try {
        authUser = await auth.getUserByEmail(oldEmail);
      } catch (err) {
        if (err.code !== "auth/user-not-found") {
          logger.error(`Error fetching user by old email ${oldEmail}:`, err);
        }
      }
    }

    // 3. Update Firebase Auth user's email if found (password is preserved)
    if (authUser) {
      try {
        await auth.updateUser(authUser.uid, { email: newEmail });
        logger.info(`Successfully updated Firebase Auth email for UID ${authUser.uid} to ${newEmail} (password preserved)`);
      } catch (err) {
        logger.error(`Failed to update Auth email for UID ${authUser.uid}:`, err);
      }
    } else {
      logger.warn(`No Firebase Auth user found matching UID ${userId} or email ${oldEmail}`);
    }

    // 4. Also synchronize store-level user documents if owned_stores is present
    const ownedStores = Array.isArray(after.owned_stores) ? after.owned_stores : [];
    for (const storeId of ownedStores) {
      try {
        const storeUserRef = db.collection("stores").doc(String(storeId)).collection("users").doc(userId);
        const storeUserSnap = await storeUserRef.get();
        if (storeUserSnap.exists && storeUserSnap.get("email") !== newEmail) {
          await storeUserRef.update({ email: newEmail });
        }
      } catch (err) {
        logger.warn(`Failed to sync email to store ${storeId}/users/${userId}:`, err);
      }
    }
  }
);

/**
 * Automatically synchronize store user email changes from
 * stores/{storeId}/users/{memberId} into root users and Firebase Auth.
 */
exports.onStoreUserWritten = onDocumentWritten(
  {
    document: "stores/{storeId}/users/{memberId}",
    region: "us-central1",
    maxInstances: 10,
  },
  async (event) => {
    if (!event.data || !event.data.after.exists) return;

    const before = event.data.before && event.data.before.exists ? event.data.before.data() : null;
    const after = event.data.after.data();
    const { storeId, memberId } = event.params;

    const newEmail = (after.email || "").trim();
    const oldEmail = (before ? before.email || "" : "").trim();

    if (!newEmail || newEmail.toLowerCase() === oldEmail.toLowerCase()) return;

    logger.info(`Detected store user email change in stores/${storeId}/users/${memberId}: "${oldEmail}" -> "${newEmail}"`);

    // Check if root users document exists with memberId
    const rootUserRef = db.collection("users").doc(memberId);
    const rootSnap = await rootUserRef.get();
    if (rootSnap.exists) {
      if (rootSnap.get("email") !== newEmail) {
        await rootUserRef.update({ email: newEmail, updated_at: FieldValue.serverTimestamp() });
      }
    } else {
      const querySnap = await db.collection("users")
        .where("storeId", "==", storeId)
        .where("userId", "==", memberId)
        .limit(1)
        .get();
      if (!querySnap.empty) {
        const targetDoc = querySnap.docs[0];
        if (targetDoc.get("email") !== newEmail) {
          await targetDoc.ref.update({ email: newEmail, updated_at: FieldValue.serverTimestamp() });
        }
      }
    }
  }
);

/**
 * HTTP endpoint allowing an authenticated user to change their account email.
 * Updates both Firebase Authentication and Firestore documents, keeping password intact.
 */
exports.changeUserEmail = onRequest({ cors: true, region: "us-central1" }, async (req, res) => {
  if (req.method !== "POST") {
    return res.status(405).json({ error: "Method not allowed" });
  }

  const authHeader = req.headers.authorization || "";
  if (!authHeader.startsWith("Bearer ")) {
    return res.status(401).json({ error: "Unauthorized: Missing bearer token" });
  }
  const idToken = authHeader.split("Bearer ")[1];
  let decoded;
  try {
    decoded = await getAuth().verifyIdToken(idToken);
  } catch (err) {
    return res.status(401).json({ error: "Unauthorized: Invalid token" });
  }

  const { newEmail } = req.body || {};
  if (!newEmail || typeof newEmail !== "string" || !newEmail.includes("@")) {
    return res.status(400).json({ error: "A valid email address is required" });
  }
  const cleanEmail = newEmail.trim().toLowerCase();
  const uid = decoded.uid;

  try {
    const auth = getAuth();
    await auth.updateUser(uid, { email: cleanEmail });

    // Update root users/{uid}
    const userRef = db.collection("users").doc(uid);
    await userRef.set(
      { email: cleanEmail, updated_at: FieldValue.serverTimestamp() },
      { merge: true }
    );

    // Update store documents
    const userDoc = await userRef.get();
    const ownedStores = userDoc.exists ? (userDoc.get("owned_stores") || []) : [];
    for (const sid of ownedStores) {
      try {
        const storeUserRef = db.collection("stores").doc(String(sid)).collection("users").doc(uid);
        const storeUserSnap = await storeUserRef.get();
        if (storeUserSnap.exists) {
          await storeUserRef.update({ email: cleanEmail });
        }
      } catch (_) {}
    }

    const storeId = userDoc.exists ? userDoc.get("storeId") : null;
    const memberId = userDoc.exists ? (userDoc.get("userId") || uid) : uid;
    if (storeId) {
      try {
        const storeUserRef = db.collection("stores").doc(String(storeId)).collection("users").doc(String(memberId));
        const storeUserSnap = await storeUserRef.get();
        if (storeUserSnap.exists) {
          await storeUserRef.update({ email: cleanEmail });
        }
      } catch (_) {}
    }

    return res.status(200).json({ success: true, email: cleanEmail });
  } catch (err) {
    logger.error(`changeUserEmail error for ${uid}:`, err);
    if (err.code === "auth/email-already-exists") {
      return res.status(409).json({ error: "This email address is already in use by another account." });
    }
    return res.status(500).json({ error: err.message || "Failed to update email address" });
  }
});




// ---------------------------------------------------------------------------
// Feedback from the other Axis apps (Scorecards, ...) into the Optic inbox.
//
// Those apps sign people in with their *own* Firebase projects, so they can't
// write here directly. They POST the ticket with the person's ID token from
// their project; we verify it and store the ticket at the usual
// users/{id}/feedback/{ticketId} path, where onFeedbackWritten pushes it to
// the developers' phones and Optic lists it like any other ticket.
//
// POST https://us-central1-project-attendance-app.cloudfunctions.net/submitAppFeedback
//   Authorization: Bearer <Firebase ID token from the app's own project>
//   { type: "Bug" | "Improvement", message, location?, platform?, app_version? }
// ---------------------------------------------------------------------------
const { initializeApp: initAdminApp } = require("firebase-admin/app");

// Firebase project id -> the other Axis apps Optic manages.
//   id               Optic's id for the app (lib/services.dart in Optic)
//   name             name shown in Optic (tickets' `app` field)
//   prefix           prefix for the ticket owner id (users/{prefix}_{uid})
//   adminUrl         the app's Optic admin endpoint (users list / settings);
//                    called by opticService below
//   serviceAccounts  that project's Cloud Functions accounts, trusted to POST
//                    events (new user, ...) to reportAppEvent
// Adding an app: add it here, give it an optic.js (copy Scorecards'
// functions/optic.js), and add it to kServices in Optic.
const EXTERNAL_APPS = {
  "scorecards-app": {
    id: "scorecards",
    name: "Scorecards",
    prefix: "scorecards",
    adminUrl: "https://us-central1-scorecards-app.cloudfunctions.net/opticAdmin",
    serviceAccounts: [
      "scorecards-app@appspot.gserviceaccount.com",
      "589112385745-compute@developer.gserviceaccount.com",
    ],
  },
  // Optimizer shares project-axis-app (and its service accounts) with Asset
  // Track and Axis Journal. Only Optimizer talks to Optic from there today; if
  // another of them joins, this entry needs splitting by more than project
  // and service account.
  "project-axis-app": {
    id: "optimizer",
    name: "Optimizer",
    prefix: "optimizer",
    adminUrl: "https://us-central1-project-axis-app.cloudfunctions.net/optimizerOpticAdmin",
    serviceAccounts: [
      "project-axis-app@appspot.gserviceaccount.com",
      "290026173104-compute@developer.gserviceaccount.com",
    ],
  },
};
const externalAuth = {};
function authFor(projectId) {
  if (!externalAuth[projectId]) {
    // Only the project id is needed to verify that project's ID tokens.
    externalAuth[projectId] = getAuth(initAdminApp({ projectId }, `ext-${projectId}`));
  }
  return externalAuth[projectId];
}

exports.submitAppFeedback = onRequest(
  { cors: true, region: "us-central1", maxInstances: 2 },
  async (req, res) => {
    if (req.method !== "POST") return res.status(405).json({ error: "POST only" });

    const token = String(req.get("Authorization") || "").replace(/^Bearer\s+/i, "");
    if (!token) return res.status(401).json({ error: "Missing sign-in token" });

    // Which project issued the token? (aud = project id; verified below.)
    let projectId = "";
    try {
      const payload = JSON.parse(Buffer.from(token.split(".")[1], "base64url").toString());
      projectId = String(payload.aud || "");
    } catch (_) {
      return res.status(401).json({ error: "Bad sign-in token" });
    }
    const appInfo = EXTERNAL_APPS[projectId];
    if (!appInfo) return res.status(403).json({ error: "Unknown app" });

    let user;
    try {
      user = await authFor(projectId).verifyIdToken(token);
    } catch (e) {
      logger.warn("submitAppFeedback: token rejected", e.code || e.message);
      return res.status(401).json({ error: "Sign-in expired. Please sign in again." });
    }

    const body = req.body || {};
    const message = String(body.message || "").trim().slice(0, 4000);
    if (!message) return res.status(400).json({ error: "Message is required" });
    const type = body.type === "Bug" ? "Bug" : "Improvement";
    const location = String(body.location || "").trim().slice(0, 120);
    const ownerId = `${appInfo.prefix}_${user.uid}`;
    const tickets = db.collection("users").doc(ownerId).collection("feedback");

    // Light flood protection: one ticket per person every 15 seconds.
    const recent = await tickets.orderBy("timestamp", "desc").limit(1).get();
    const last = recent.docs[0] && recent.docs[0].get("timestamp");
    if (last && Date.now() - last.toMillis() < 15000) {
      return res.status(429).json({ error: "Please wait a moment before sending more feedback." });
    }

    const doc = await tickets.add({
      type,
      app: appInfo.name,
      location,
      message,
      submitted_by: ownerId,
      submitter_name: String(body.submitter_name || user.name || "").trim().slice(0, 80) || null,
      submitter_email: user.email || null,
      store_id: "all",
      status: "Open",
      replies: [],
      source_project: projectId,
      source_uid: user.uid,
      platform: String(body.platform || "").slice(0, 20),
      app_version: String(body.app_version || "").slice(0, 20),
      timestamp: FieldValue.serverTimestamp(),
      updated_at: FieldValue.serverTimestamp(),
    });
    logger.info(`External feedback from ${appInfo.name}: ${doc.path}`);
    return res.status(200).json({ id: doc.id });
  },
);


// ---------------------------------------------------------------------------
// Optic apps hub: per-app alerts, an activity feed, and user admin for the
// other Axis apps.
//
// dev/notification_prefs  { <appId>: { <alertKey>: false } }  set in Optic
//                         (App → Alerts). Anything missing counts as on.
// dev/activity            { events: [ {id, service, event, title, body,
//                         data, at} ] }, newest last, capped at 150. Optic
//                         shows it under each app's Alerts tab.
//
// The other apps talk to us with Google-signed identity tokens from their
// Cloud Functions service account (no shared secrets to set up):
//   app  -> reportAppEvent   "a new user signed up", ...
//   Optic -> opticService -> app's adminUrl   list users, change settings
// ---------------------------------------------------------------------------
const { onDocumentCreated } = require("firebase-functions/v2/firestore");
const { OAuth2Client } = require("google-auth-library");

const oidc = new OAuth2Client();
const REPORT_EVENT_URL =
  "https://us-central1-project-attendance-app.cloudfunctions.net/reportAppEvent";

// Optic logins allowed to manage the other apps (matches the developer list in
// Optic). They're read from functions/.env, which is not in the repository:
//   DEVELOPER_EMAILS=you@example.com,other@example.com
//   PREVERIFIED_DEVELOPERS=you@example.com
// Addresses not in PREVERIFIED_DEVELOPERS must be verified, so nobody can
// register one of them in this project and get in.
const envList = (name) =>
  String(process.env[name] || "")
    .split(",")
    .map((s) => s.trim().toLowerCase())
    .filter(Boolean);
const DEVELOPER_EMAILS = envList("DEVELOPER_EMAILS");
const PREVERIFIED_DEVELOPERS = envList("PREVERIFIED_DEVELOPERS");

function isDeveloperAuth(auth) {
  if (!auth || !auth.token) return false;
  const email = String(auth.token.email || "").toLowerCase();
  if (!DEVELOPER_EMAILS.includes(email)) return false;
  return auth.token.email_verified === true || PREVERIFIED_DEVELOPERS.includes(email);
}

/** Optic's id for an app, from the name on its tickets ("Axis Team" -> axis_team). */
function serviceIdForApp(appName) {
  const name = String(appName || "Axis Team").trim().toLowerCase();
  for (const info of Object.values(EXTERNAL_APPS)) {
    if (info.name.toLowerCase() === name) return info.id;
  }
  if (name === "axis team" || !name) return "axis_team";
  return name.replace(/[^a-z0-9]+/g, "_");
}

/** Whether the developers want this alert (Optic → app → Alerts). On unless switched off. */
async function developersWant(serviceId, alertKey) {
  try {
    const prefs = await db.collection("dev").doc("notification_prefs").get();
    const forApp = (prefs.exists && prefs.get(serviceId)) || {};
    return forApp[alertKey] !== false;
  } catch (e) {
    logger.warn("Could not read dev/notification_prefs; sending anyway", e);
    return true;
  }
}

/** Adds an entry to the activity feed Optic shows for each app. */
async function logActivity(serviceId, alertKey, title, body, data) {
  const ref = db.collection("dev").doc("activity");
  const entry = {
    id: `${Date.now()}_${Math.random().toString(36).slice(2, 8)}`,
    service: serviceId,
    event: alertKey,
    title: String(title || "").slice(0, 120),
    body: String(body || "").slice(0, 300),
    data: data || {},
    at: Timestamp.now(),
  };
  await db.runTransaction(async (tx) => {
    const snap = await tx.get(ref);
    const events = (snap.exists && Array.isArray(snap.get("events")) ? snap.get("events") : []).concat(entry);
    tx.set(ref, { events: events.slice(-150), updated_at: FieldValue.serverTimestamp() }, { merge: true });
  });
}

/**
 * Logs an app event and, if that alert is on in Optic, pushes it to every
 * developer phone (dev/devices.tokens). Tapping it opens that app in Optic.
 */
async function notifyDevelopers(serviceId, alertKey, { title, body, data = {}, color = "#FF4C52" }) {
  try {
    await logActivity(serviceId, alertKey, title, body, data);
  } catch (e) {
    logger.warn("Could not log activity", e);
  }
  if (!(await developersWant(serviceId, alertKey))) {
    logger.info(`Alert skipped: ${serviceId}.${alertKey} is off in Optic`);
    return "muted";
  }
  const devices = await db.collection("dev").doc("devices").get();
  const tokens = [...new Set((devices.get("tokens") || []).filter((t) => typeof t === "string" && t))];
  if (!tokens.length) return "no_device";

  const res = await getMessaging().sendEachForMulticast(
    opticPush(tokens, {
      title,
      body,
      color,
      data: { ...data, type: "app_event", service: serviceId, event: alertKey },
    }),
  );
  const dead = [];
  res.responses.forEach((r, i) => {
    if (!r.success && DEAD_TOKEN.has(r.error && r.error.code)) dead.push(tokens[i]);
  });
  if (dead.length) await devices.ref.update({ tokens: FieldValue.arrayRemove(...dead) });
  logger.info(`Alert ${serviceId}.${alertKey}: ${res.successCount} sent, ${res.failureCount} failed`);
  return "sent";
}

// Axis Team: a new login (/users/{uid}) was created.
exports.onAxisUserCreated = onDocumentCreated(
  { document: "users/{userId}", region: "us-central1", maxInstances: 2 },
  async (event) => {
    const userId = event.params.userId;
    // Ticket owners for the other apps (users/scorecards_x/...) aren't logins.
    if (Object.values(EXTERNAL_APPS).some((a) => userId.startsWith(`${a.prefix}_`))) return;
    const d = (event.data && event.data.data()) || {};
    const name = [d.first_name, d.last_name].filter((s) => s && String(s).trim()).join(" ");
    const who = name || d.email || "Someone";
    const role = d.role ? ` · ${d.role}` : "";
    await notifyDevelopers("axis_team", "new_user", {
      title: "🆕 New Axis Team login",
      body: `${who}${d.email && name ? ` (${d.email})` : ""}${role}`,
      data: { uid: userId },
      color: "#FF4C52",
    });
  },
);

// Axis Team: a new store was created.
exports.onAxisStoreCreated = onDocumentCreated(
  { document: "stores/{storeId}", region: "us-central1", maxInstances: 2 },
  async (event) => {
    const d = (event.data && event.data.data()) || {};
    await notifyDevelopers("axis_team", "new_store", {
      title: "🏪 New Axis Team store",
      body: `${d.name || event.params.storeId}${d.is_dev ? " (dev store)" : ""}`,
      data: { store_id: event.params.storeId },
      color: "#FF4C52",
    });
  },
);

/** Which external app a Google identity token belongs to (by service account). */
async function externalAppForServiceToken(token, audience) {
  const ticket = await oidc.verifyIdToken({ idToken: token, audience });
  const p = ticket.getPayload() || {};
  const email = String(p.email || "").toLowerCase();
  if (!p.email_verified) throw new Error(`unverified service account ${email}`);
  const app = Object.values(EXTERNAL_APPS).find((a) => (a.serviceAccounts || []).includes(email));
  if (!app) throw new Error(`untrusted service account ${email || p.sub}`);
  return app;
}

// POST https://us-central1-project-attendance-app.cloudfunctions.net/reportAppEvent
//   Authorization: Bearer <Google identity token for this URL, from the app's
//                  Cloud Functions service account>
//   { event: "new_user", title, body, data?: { uid, ... }, color? }
exports.reportAppEvent = onRequest(
  { region: "us-central1", maxInstances: 2 },
  async (req, res) => {
    if (req.method !== "POST") return res.status(405).json({ error: "POST only" });
    const token = String(req.get("Authorization") || "").replace(/^Bearer\s+/i, "");
    if (!token) return res.status(401).json({ error: "Missing token" });

    let app;
    try {
      app = await externalAppForServiceToken(token, REPORT_EVENT_URL);
    } catch (e) {
      logger.warn("reportAppEvent: rejected", e.message);
      return res.status(403).json({ error: "Not allowed" });
    }

    const b = req.body || {};
    const alertKey = String(b.event || "").replace(/[^a-z0-9_]/gi, "").slice(0, 40);
    if (!alertKey) return res.status(400).json({ error: "event is required" });
    const data = {};
    if (b.data && typeof b.data === "object") {
      for (const [k, v] of Object.entries(b.data).slice(0, 20)) data[String(k).slice(0, 40)] = String(v).slice(0, 200);
    }
    const color = /^#[0-9a-f]{6}$/i.test(String(b.color || "")) ? b.color : "#7855C1";
    const result = await notifyDevelopers(app.id, alertKey, {
      title: String(b.title || `${app.name}: ${alertKey}`),
      body: String(b.body || ""),
      data,
      color,
    });
    return res.status(200).json({ ok: true, result });
  },
);

/** A Google identity token from this function's service account, for `audience`. */
async function googleIdentityToken(audience) {
  const url =
    "http://metadata.google.internal/computeMetadata/v1/instance/service-accounts/default/identity" +
    `?format=full&audience=${encodeURIComponent(audience)}`;
  const r = await fetch(url, { headers: { "Metadata-Flavor": "Google" } });
  if (!r.ok) throw new Error(`metadata identity token: HTTP ${r.status}`);
  return r.text();
}

// Optic → another app's admin endpoint (list users, change a user's settings).
// Callable: { service: "scorecards", action: "listUsers" | "getUser" |
//             "updateUser" | "userAction" | "summary", ... }
exports.opticService = onCall({ region: "us-central1", maxInstances: 2, timeoutSeconds: 60 }, async (request) => {
  if (!isDeveloperAuth(request.auth)) {
    throw new HttpsError("permission-denied", "Only Optic developer logins can manage apps.");
  }
  const data = request.data || {};
  const app = Object.values(EXTERNAL_APPS).find((a) => a.id === data.service);
  if (!app || !app.adminUrl) throw new HttpsError("not-found", `No admin endpoint for "${data.service}".`);

  let res;
  try {
    const token = await googleIdentityToken(app.adminUrl);
    res = await fetch(app.adminUrl, {
      method: "POST",
      headers: { "Content-Type": "application/json", Authorization: `Bearer ${token}` },
      body: JSON.stringify({ ...data, by: request.auth.token.email || request.auth.uid }),
      signal: AbortSignal.timeout(45000),
    });
  } catch (e) {
    logger.error(`opticService: ${app.name} unreachable`, e);
    throw new HttpsError("unavailable", `${app.name} couldn't be reached.`);
  }
  let json = {};
  try {
    json = await res.json();
  } catch (_) {}
  if (!res.ok) {
    logger.warn(`opticService: ${app.name} said ${res.status}`, json);
    const code = res.status === 404 ? "not-found" : res.status === 400 ? "invalid-argument" : res.status === 403 ? "permission-denied" : "internal";
    throw new HttpsError(code, json.error || `${app.name} returned HTTP ${res.status}`);
  }
  return json;
});
