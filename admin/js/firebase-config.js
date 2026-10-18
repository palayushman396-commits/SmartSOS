import { initializeApp } from "https://www.gstatic.com/firebasejs/10.12.2/firebase-app.js";
import { getAuth } from "https://www.gstatic.com/firebasejs/10.12.2/firebase-auth.js";
import { getFirestore } from "https://www.gstatic.com/firebasejs/10.12.2/firebase-firestore.js";

const firebaseConfig = {
  apiKey: "AIzaSyBOAn6cwRDTAkS8xRJQVAvMynsdqToSifk",
  authDomain: "smartsos-debff.firebaseapp.com",
  projectId: "smartsos-debff",
  storageBucket: "smartsos-debff.firebasestorage.app",
  messagingSenderId: "882340860670",
  appId: "1:882340860670:web:1c9de27234d5dd07600baf",
  measurementId: "G-04PXY3HKRN"
};

const app = initializeApp(firebaseConfig);
export const auth = getAuth(app);
export const db = getFirestore(app);