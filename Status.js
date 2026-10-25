.pragma library

.import "StatusStrings.js" as Strings

// Turns the official kDrive tray tooltip into widget state. The tooltip is the
// only data kDrive 3.x exposes safely on Linux: its GUI <-> server channel
// takes a single client, and the server quits when that client drops.
//
// Tooltip shapes (one line per sync folder, any kDrive UI language):
//   "Folder /run/media/rl/kDrive: Sync is running."
//   "Folder Documents/kDrive: Last Sync was successful. (Sync is paused)"
//   "Please sign in"

// Worst state first: the overall state of several folders is the first one hit.
var severity = ["error", "stopped", "signin", "nofolder", "undefined", "conflicts", "paused", "starting", "running", "ok"]

var labels = {
  error: "Erreur de synchronisation",
  stopped: "Synchronisation arrêtée",
  signin: "Connexion requise",
  nofolder: "Aucun dossier synchronisé",
  undefined: "État inconnu",
  conflicts: "Conflits à résoudre",
  paused: "En pause",
  starting: "Démarrage de la synchronisation",
  running: "Synchronisation en cours",
  ok: "À jour",
  offline: "kDrive n'est pas lancé"
}

// Nerd Font glyphs, matching the rest of the Omarchy bar.
var icons = {
  error: "󰅤",
  stopped: "󰅤",
  signin: "󰌾",
  nofolder: "󰉖",
  undefined: "󰅤",
  conflicts: "󰀦",
  paused: "󰏤",
  starting: "󰑓",
  running: "󰑓",
  ok: "󰅟",
  offline: "󰅛"
}

function isProblem(state) {
  return ["error", "stopped", "signin", "undefined", "conflicts"].indexOf(state) !== -1
}

function matchState(message) {
  var text = String(message || "").trim()
  if (text === "") return "error"   // kDrive leaves the text empty for SyncStatus::Error
  for (var state in Strings.states) {
    if (Strings.states[state].indexOf(text) !== -1) return state
  }
  return "undefined"
}

// "%1 (Sync is paused)" wraps the folder status when that folder is paused.
function stripPaused(message) {
  for (var i = 0; i < Strings.pausedSuffixes.length; i++) {
    var parts = Strings.pausedSuffixes[i].split("%1")
    var prefix = parts[0], suffix = parts[1] || ""
    if (message.length >= prefix.length + suffix.length
        && message.indexOf(prefix) === 0
        && message.slice(message.length - suffix.length) === suffix)
      return { message: message.slice(prefix.length, message.length - suffix.length), paused: true }
  }
  return { message: message, paused: false }
}

// "Folder %1: %2" -> { path, message }, or null when the line has another shape.
function splitFolderLine(line) {
  for (var i = 0; i < Strings.folderFormats.length; i++) {
    var format = Strings.folderFormats[i]
    var head = format.split("%1")[0]
    var middle = format.split("%1")[1].split("%2")[0]
    if (line.indexOf(head) !== 0) continue
    var rest = line.slice(head.length)
    // Folder paths may contain the separator; the status never does, so cut at the last one.
    var cut = rest.lastIndexOf(middle)
    if (cut >= 0) return { path: rest.slice(0, cut), message: rest.slice(cut + middle.length) }
    // SyncStatus::Error leaves the status empty, and the trailing space was trimmed away.
    var bare = middle.replace(/\s+$/, "")
    if (bare !== "" && rest.slice(-bare.length) === bare) return { path: rest.slice(0, rest.length - bare.length), message: "" }
  }
  return null
}

// kDrive shortens paths under $HOME to a relative path; turn them back into absolute ones.
function absolutePath(path, home) {
  if (path === "" || path.charAt(0) === "/") return path
  return String(home || "").replace(/\/$/, "") + "/" + path
}

function worst(states) {
  var best = severity.length
  for (var i = 0; i < states.length; i++) {
    var rank = severity.indexOf(states[i])
    if (rank !== -1 && rank < best) best = rank
  }
  return best < severity.length ? severity[best] : "undefined"
}

// Returns { state, folders: [{ path, state, message, paused }] }.
function parse(tooltip, home) {
  var lines = String(tooltip || "").split("\n").map(function(l) { return l.trim() }).filter(function(l) { return l !== "" })
  var folders = []
  for (var i = 0; i < lines.length; i++) {
    var folder = splitFolderLine(lines[i])
    if (!folder) continue
    var unwrapped = stripPaused(folder.message)
    var state = matchState(unwrapped.message)
    if (unwrapped.paused && state !== "error" && state !== "stopped") state = "paused"
    folders.push({ path: absolutePath(folder.path, home), state: state, message: folder.message, paused: unwrapped.paused })
  }
  if (folders.length > 0) return { state: worst(folders.map(function(f) { return f.state })), folders: folders }
  // Whole-tooltip messages: "Please sign in", "Synchronization is paused", ...
  return { state: lines.length > 0 ? matchState(lines.join(" ")) : "starting", folders: [] }
}
