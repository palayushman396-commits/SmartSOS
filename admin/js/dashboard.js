import {
  onAuthStateChanged,
  signOut,
} from "https://www.gstatic.com/firebasejs/10.12.2/firebase-auth.js";
import {
  collection,
  query,
  orderBy,
  limit,
  onSnapshot,
  doc,
  updateDoc,
  serverTimestamp,
} from "https://www.gstatic.com/firebasejs/10.12.2/firebase-firestore.js";
import { auth, db } from "./firebase-config.js";

const TYPES = {
  police: { label: "Police", color: "#1565C0" },
  women: { label: "Women Safety", color: "#AD1457" },
  child: { label: "Child Safety", color: "#EF6C00" },
  fire: { label: "Fire", color: "#D84315" },
  ambulance: { label: "Ambulance", color: "#2E7D32" },
};
const STATUS_LABEL = {
  initiated: "SOS initiated",
  alert_sent: "Alert sent",
  responder_notified: "Responder notified",
  responder_assigned: "Responder assigned",
  in_progress: "Assistance in progress",
  resolved: "Resolved",
  cancelled: "Cancelled",
};
const ACTIVE = ["initiated", "alert_sent", "responder_notified", "responder_assigned", "in_progress"];
const STALE_SECONDS = 60;

const incidents = new Map();
const markers = new Map();
let selectedId = null;
let firstSnapshot = true;
let didFit = false;
let map;

const $ = (id) => document.getElementById(id);

// ---------- helpers ----------
function el(tag, text, className) {
  const node = document.createElement(tag);
  if (text !== undefined && text !== null) node.textContent = text;
  if (className) node.className = className;
  return node;
}
function toDate(ts) {
  return ts && typeof ts.toDate === "function" ? ts.toDate() : null;
}
function validCoords(loc) {
  return (
    loc &&
    Number.isFinite(loc.latitude) &&
    Number.isFinite(loc.longitude) &&
    Math.abs(loc.latitude) <= 90 &&
    Math.abs(loc.longitude) <= 180
  );
}
function ago(date) {
  if (!date) return "—";
  const s = Math.max(0, Math.round((Date.now() - date.getTime()) / 1000));
  if (s < 60) return s + "s ago";
  if (s < 3600) return Math.floor(s / 60) + " min ago";
  if (s < 86400) return Math.floor(s / 3600) + " h ago";
  return date.toLocaleDateString();
}
function locInfo(inc) {
  const loc = inc.lastLocation;
  if (!validCoords(loc)) return { text: "No location", stale: true, none: true };
  const when = toDate(loc.timestamp);
  const stale = !when || (Date.now() - when.getTime()) / 1000 > STALE_SECONDS;
  const acc = Number.isFinite(loc.accuracy) ? " (±" + Math.round(loc.accuracy) + " m)" : "";
  return { text: ago(when) + acc, stale, none: false, when };
}
function isActive(inc) {
  return ACTIVE.includes(inc.status);
}
function showToast(message) {
  const t = $("toast");
  t.textContent = message;
  t.hidden = false;
  setTimeout(() => (t.hidden = true), 8000);
}
function setConn(text, cls) {
  const c = $("conn");
  c.textContent = text;
  c.className = "pill " + cls;
}

// ---------- rendering ----------
function renderCards() {
  const all = [...incidents.values()];
  $("c-active").textContent = all.filter(isActive).length;
  $("c-new").textContent = all.filter((i) => i.status === "initiated").length;
  $("c-await").textContent = all.filter((i) => isActive(i) && !i.assignedResponderId).length;
  $("c-progress").textContent = all.filter((i) => i.status === "in_progress").length;
  $("c-resolved").textContent = all.filter((i) => i.status === "resolved").length;
}

function filtered() {
  const fs = $("f-status").value;
  const ft = $("f-type").value;
  const sort = $("f-sort").value;
  let list = [...incidents.values()].filter((i) => {
    if (ft !== "all" && i.emergencyType !== ft) return false;
    if (fs === "active") return isActive(i);
    if (fs === "resolved") return !isActive(i);
    if (fs === "unassigned") return isActive(i) && !i.assignedResponderId;
    return true;
  });
  const t = (x, f) => (toDate(x[f]) ? toDate(x[f]).getTime() : 0);
  if (sort === "old") list.sort((a, b) => t(a, "createdAt") - t(b, "createdAt"));
  else if (sort === "updated") list.sort((a, b) => t(b, "updatedAt") - t(a, "updatedAt"));
  else list.sort((a, b) => t(b, "createdAt") - t(a, "createdAt"));
  return list;
}

function renderTable() {
  const tbody = $("rows");
  tbody.replaceChildren();
  const list = filtered();
  $("empty").hidden = list.length > 0;
  for (const inc of list) {
    const type = TYPES[inc.emergencyType] || { label: inc.emergencyType, color: "#555" };
    const loc = locInfo(inc);
    const tr = document.createElement("tr");
    if (inc.id === selectedId) tr.className = "selected";
    tr.addEventListener("click", () => select(inc.id, true));

    const tdType = el("td");
    const dot = el("span", "", "dot");
    dot.style.background = type.color;
    tdType.append(dot, document.createTextNode(" " + type.label));

    const tdLoc = el("td", loc.text, loc.stale && !loc.none ? "warn" : "");
    if (loc.stale && !loc.none) tdLoc.textContent += " ⚠ stale";

    tr.append(
      tdType,
      el("td", inc.userName || "Unknown"),
      el("td", toDate(inc.createdAt) ? toDate(inc.createdAt).toLocaleString() : "…"),
      el("td", STATUS_LABEL[inc.status] || inc.status, "badge s-" + inc.status),
      tdLoc,
      el("td", inc.assignedResponderId ? "Assigned" : "—"),
      el("td", "Not available yet", "muted")
    );
    tbody.append(tr);
  }
}

function renderMap() {
  const activeWithLoc = [...incidents.values()].filter((i) => isActive(i) && validCoords(i.lastLocation));
  const keep = new Set(activeWithLoc.map((i) => i.id));

  for (const [id, m] of markers) {
    if (!keep.has(id)) {
      map.removeLayer(m);
      markers.delete(id);
    }
  }
  for (const inc of activeWithLoc) {
    const type = TYPES[inc.emergencyType] || { color: "#555", label: inc.emergencyType };
    const latlng = [inc.lastLocation.latitude, inc.lastLocation.longitude];
    const stale = locInfo(inc).stale;
    let m = markers.get(inc.id);
    if (!m) {
      m = L.circleMarker(latlng, { radius: 11, weight: 3 }).addTo(map);
      m.on("click", () => select(inc.id, false));
      markers.set(inc.id, m);
    }
    m.setLatLng(latlng);
    m.setStyle({
      color: inc.id === selectedId ? "#000" : "#fff",
      fillColor: type.color,
      fillOpacity: stale ? 0.4 : 0.95,
    });
    m.bindTooltip(
      (inc.userName || "Unknown") + " · " + type.label + (stale ? " (stale)" : ""),
      { direction: "top" }
    );
  }
    if (!didFit && activeWithLoc.length > 0) {
    const first = activeWithLoc[0];
    map.setView([first.lastLocation.latitude, first.lastLocation.longitude], 14);
    didFit = true;
  }
  const missing = [...incidents.values()].filter((i) => isActive(i) && !validCoords(i.lastLocation)).length;
  $("map-note").textContent =
    missing > 0 ? missing + " active incident(s) have no valid location and are not on the map." : "";
}

function renderDetail() {
  const box = $("detail");
  box.replaceChildren(el("h2", "Incident details"));
  const inc = incidents.get(selectedId);
  if (!inc) {
    box.append(el("p", "Select an incident from the map or the table.", "note"));
    return;
  }
  const type = TYPES[inc.emergencyType] || { label: inc.emergencyType };
  const loc = locInfo(inc);

  const rows = [
    ["Incident ID", inc.id],
    ["Type", type.label],
    ["User", inc.userName || "Unknown"],
    ["Trigger", inc.triggerSource === "voice" ? "Voice trigger" : "SOS button"],
    ["Created", toDate(inc.createdAt) ? toDate(inc.createdAt).toLocaleString() : "…"],
    ["Status", STATUS_LABEL[inc.status] || inc.status],
    ["Last location", loc.none ? "No location" : loc.text + (loc.stale ? " – stale" : "")],
    ["Coordinates", loc.none ? "—" : inc.lastLocation.latitude.toFixed(5) + ", " + inc.lastLocation.longitude.toFixed(5)],
    ["Assigned to", inc.assignedResponderId ? inc.assignedResponderId : "Nobody"],
    ["Video room", inc.liveKitRoomName || "—"],
  ];
  const dl = el("dl");
  for (const [k, v] of rows) dl.append(el("dt", k), el("dd", v));
  box.append(dl);

  if (loc.stale && !loc.none && isActive(inc)) {
    box.append(el("p", "Location has not updated recently. The phone may be offline or the app closed. Do not assume the user is safe.", "banner warn-box"));
  }
  if (!loc.none) {
    const a = el("a", "Open directions in Google Maps", "btn-link");
    a.href =
      "https://www.google.com/maps/dir/?api=1&destination=" +
      inc.lastLocation.latitude + "," + inc.lastLocation.longitude;
    a.target = "_blank";
    a.rel = "noopener noreferrer";
    box.append(a);
  }

  box.append(el("p", "Live audio/video: not available yet (Phase 6).", "note"));

  if (isActive(inc)) {
    const actions = el("div", "", "actions");
    const add = (label, status, cls) => {
      const b = el("button", label, cls || "");
      b.type = "button";
      b.addEventListener("click", () => changeStatus(inc, status));
      actions.append(b);
    };
    if (inc.status === "initiated") add("Acknowledge", "responder_notified");
    if (!inc.assignedResponderId) add("Assign to me", "responder_assigned");
    if (inc.status !== "in_progress") add("Mark in progress", "in_progress");
    add("Resolve", "resolved", "danger");
    box.append(actions);
  }
}

function renderAll() {
  renderCards();
  renderTable();
  renderMap();
  renderDetail();
}

function select(id, panMap) {
  selectedId = id;
  const inc = incidents.get(id);
  if (panMap && inc && validCoords(inc.lastLocation)) {
    map.setView([inc.lastLocation.latitude, inc.lastLocation.longitude], 16);
  }
  renderAll();
}

// ---------- actions ----------
async function changeStatus(inc, status) {
  if (status === "resolved" && !confirm("Mark this incident as resolved?")) return;
  const update = { status, updatedAt: serverTimestamp() };
  if (status === "responder_assigned") update.assignedResponderId = auth.currentUser.uid;
  if (status === "resolved") {
    update.resolvedAt = serverTimestamp();
    update.resolvedBy = auth.currentUser.uid;
  }
  try {
    await updateDoc(doc(db, "incidents", inc.id), update);
  } catch (err) {
    showToast("Could not update the incident: " + (err.code || "unknown error"));
  }
}

// ---------- realtime listener ----------
function listen() {
  const q = query(collection(db, "incidents"), orderBy("createdAt", "desc"), limit(200));
  onSnapshot(
    q,
    { includeMetadataChanges: false },
    (snap) => {
      setConn("Live", "pill-ok");
      $("banner").hidden = true;
      snap.docChanges().forEach((ch) => {
        if (ch.type === "removed") {
          incidents.delete(ch.doc.id);
          return;
        }
        const data = { id: ch.doc.id, ...ch.doc.data() };
        if (ch.type === "added" && !firstSnapshot && data.status === "initiated") {
          const t = TYPES[data.emergencyType] || { label: data.emergencyType };
          showToast("🚨 New " + t.label + " SOS from " + (data.userName || "Unknown"));
          document.title = "🚨 New SOS – SmartSOS Admin";
        }
        incidents.set(ch.doc.id, data);
      });
      firstSnapshot = false;
      renderAll();
    },
    (err) => {
      setConn("Disconnected", "pill-bad");
      const b = $("banner");
      b.textContent =
        err.code === "permission-denied"
          ? "Access denied. This account is not authorised to read incidents."
          : "Connection problem (" + (err.code || "unknown") + "). Retrying…";
      b.hidden = false;
    }
  );
}

// ---------- start ----------
function initMap() {
  map = L.map("map").setView([20.5937, 78.9629], 5);
  L.tileLayer("https://tile.openstreetmap.org/{z}/{x}/{y}.png", {
    maxZoom: 19,
    attribution: "&copy; OpenStreetMap contributors",
  }).addTo(map);
}

onAuthStateChanged(auth, async (user) => {
  if (!user) {
    window.location.href = "login.html";
    return;
  }
  const token = await user.getIdTokenResult();
  if (token.claims.admin !== true) {
    await signOut(auth);
    window.location.href = "login.html";
    return;
  }
  $("user-email").textContent = user.email;
  if (!map) {
    initMap();
    ["f-status", "f-type", "f-sort"].forEach((id) => $(id).addEventListener("change", renderTable));
    setInterval(renderAll, 15000); // refresh "x s ago" and stale flags
    window.addEventListener("focus", () => (document.title = "SmartSOS Admin – Dashboard"));
    listen();
  }
});

$("logout").addEventListener("click", async () => {
  await signOut(auth);
  window.location.href = "login.html";
});