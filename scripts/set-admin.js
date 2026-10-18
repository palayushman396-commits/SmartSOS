const { initializeApp, cert } = require("firebase-admin/app");
const { getAuth } = require("firebase-admin/auth");
const serviceAccount = require("./serviceAccountKey.json");

initializeApp({ credential: cert(serviceAccount) });

const email = process.argv[2];
if (!email) {
  console.error("Usage: node set-admin.js user@example.com");
  process.exit(1);
}

(async () => {
  const auth = getAuth();
  const user = await auth.getUserByEmail(email);
  await auth.setCustomUserClaims(user.uid, { admin: true });
  console.log("Admin claim set for " + email + " (uid: " + user.uid + ")");
  process.exit(0);
})().catch((err) => {
  console.error("Failed:", err.message);
  process.exit(1);
});