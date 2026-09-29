/**
 * SilentHelp Cloud Functions — the SECONDARY cloud layer.
 *
 * The critical offline SOS (location + SMS) happens entirely on-device and is
 * NEVER moved here. These functions only add server-side value:
 *   - onEmergencyEventCreated: validate + notify trusted devices via FCM + audit
 *   - setUserRole: admin-only callable to assign roles (custom claims)
 *   - registerAsTrustedContact: server-controlled trusted_contact role grant
 *   - cleanupExpiredEvents: scheduled retention cleanup (privacy)
 *
 * Auth + App Check are enforced on callable functions.
 */
import {initializeApp} from "firebase-admin/app";
import {getAuth} from "firebase-admin/auth";
import {getFirestore, FieldValue} from "firebase-admin/firestore";
import {getMessaging} from "firebase-admin/messaging";
import {onDocumentCreated} from "firebase-functions/v2/firestore";
import {onCall, HttpsError} from "firebase-functions/v2/https";
import {onSchedule} from "firebase-functions/v2/scheduler";
import {logger} from "firebase-functions";

initializeApp();
const db = getFirestore();

// Retain emergency events for 30 days, then auto-delete (privacy).
const RETENTION_DAYS = 30;

/**
 * When an emergency event is written by a client, validate it, write an audit
 * record, and notify the owner's other logged-in devices via FCM.
 * FCM here is a NON-CRITICAL supplement to the SMS already sent on-device.
 */
export const onEmergencyEventCreated = onDocumentCreated(
  "emergencyEvents/{eventId}",
  async (event) => {
    const snap = event.data;
    if (!snap) return;
    const data = snap.data();
    const ownerUid = data.ownerUid as string | undefined;
    if (!ownerUid) {
      logger.warn("Event missing ownerUid; skipping", {id: event.params.eventId});
      return;
    }

    // Set a TTL field so Firestore auto-expires the doc (privacy retention).
    const expireAt = new Date();
    expireAt.setDate(expireAt.getDate() + RETENTION_DAYS);
    await snap.ref.set({expireAt}, {merge: true});

    // Audit log (server-only collection).
    await db.collection("auditLogs").add({
      type: "emergency_event",
      ownerUid,
      eventId: event.params.eventId,
      at: FieldValue.serverTimestamp(),
      // Do NOT log phone numbers or precise location.
      triggerType: data.triggerType ?? "unknown",
    });

    // Notify the owner's registered devices (non-critical status push).
    try {
      const tokensSnap = await db
        .collection("notificationTokens")
        .where("ownerUid", "==", ownerUid)
        .get();
      const tokens = tokensSnap.docs
        .map((d) => d.get("token") as string)
        .filter(Boolean);
      if (tokens.length > 0) {
        await getMessaging().sendEachForMulticast({
          tokens,
          notification: {
            title: "Emergency recorded",
            body: "Your SOS was logged and synced.",
          },
          data: {type: "emergency_status", eventId: event.params.eventId},
        });
      }
    } catch (e) {
      logger.error("FCM notify failed", e);
    }
  }
);

/** Admin-only: assign a role via custom claims. Prevents self-escalation. */
export const setUserRole = onCall(
  {enforceAppCheck: true},
  async (request) => {
    if (!request.auth) {
      throw new HttpsError("unauthenticated", "Sign in required.");
    }
    const callerRole = request.auth.token.role;
    if (callerRole !== "admin") {
      throw new HttpsError("permission-denied", "Admins only.");
    }
    const {targetUid, role} = request.data as {targetUid: string; role: string};
    const allowed = ["user", "trusted_contact", "admin"];
    if (!targetUid || !allowed.includes(role)) {
      throw new HttpsError("invalid-argument", "Invalid targetUid/role.");
    }
    await getAuth().setCustomUserClaims(targetUid, {role});
    await db.collection("auditLogs").add({
      type: "role_change",
      by: request.auth.uid,
      targetUid,
      role,
      at: FieldValue.serverTimestamp(),
    });
    return {ok: true};
  }
);

/**
 * A user accepts an invite to be someone's trusted contact. The role is set
 * server-side (never by the client writing its own profile).
 */
export const registerAsTrustedContact = onCall(
  {enforceAppCheck: true},
  async (request) => {
    if (!request.auth) {
      throw new HttpsError("unauthenticated", "Sign in required.");
    }
    // Only elevate from plain user; never downgrade an admin.
    const current = request.auth.token.role;
    if (current === "admin") return {ok: true, role: "admin"};
    await getAuth().setCustomUserClaims(request.auth.uid, {
      role: "trusted_contact",
    });
    return {ok: true, role: "trusted_contact"};
  }
);

/**
 * Scheduled cleanup as a backstop to Firestore TTL: delete emergency events
 * older than the retention window. Runs daily.
 */
export const cleanupExpiredEvents = onSchedule("every 24 hours", async () => {
  const cutoff = new Date();
  cutoff.setDate(cutoff.getDate() - RETENTION_DAYS);
  const old = await db
    .collection("emergencyEvents")
    .where("timestamp", "<", cutoff.toISOString())
    .limit(400)
    .get();
  const batch = db.batch();
  old.docs.forEach((d) => batch.delete(d.ref));
  await batch.commit();
  logger.info(`cleanupExpiredEvents removed ${old.size} events`);
});
