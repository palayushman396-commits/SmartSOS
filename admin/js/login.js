import {
  signInWithEmailAndPassword,
  signOut,
} from "https://www.gstatic.com/firebasejs/10.12.2/firebase-auth.js";
import { auth } from "./firebase-config.js";

const form = document.getElementById("login-form");
const errorEl = document.getElementById("error");
const button = document.getElementById("submit");

function showError(message) {
  errorEl.textContent = message;
  errorEl.hidden = false;
}

function friendly(code) {
  switch (code) {
    case "auth/invalid-email":
      return "That email address is not valid.";
    case "auth/invalid-credential":
    case "auth/wrong-password":
    case "auth/user-not-found":
      return "Incorrect email or password.";
    case "auth/too-many-requests":
      return "Too many attempts. Please wait and try again.";
    case "auth/network-request-failed":
      return "No internet connection.";
    default:
      return "Login failed (" + code + ").";
  }
}

form.addEventListener("submit", async (event) => {
  event.preventDefault();
  errorEl.hidden = true;
  button.disabled = true;
  button.textContent = "Signing in...";

  try {
    const email = document.getElementById("email").value.trim();
    const password = document.getElementById("password").value;
    const cred = await signInWithEmailAndPassword(auth, email, password);

    // Force-refresh the token so a newly granted admin claim is included.
    const token = await cred.user.getIdTokenResult(true);
    if (token.claims.admin === true) {
      window.location.href = "dashboard.html";
    } else {
      await signOut(auth);
      showError("This account is not authorized for the admin dashboard.");
    }
  } catch (err) {
    showError(friendly(err.code || ""));
  } finally {
    button.disabled = false;
    button.textContent = "Log in";
  }
});