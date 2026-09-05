// mac-chrome.jsx — Apple-style menubar + dock, drawn as crisp SVG
const AppleLogo = () => <svg width="15" height="18" viewBox="0 0 170 200" fill="#fff"><path d="M150.4 106.4c-.2-25.3 20.7-37.4 21.6-38-11.8-17.2-30.1-19.6-36.6-19.9-15.6-1.6-30.4 9.2-38.3 9.2-7.9 0-20.1-9-33-8.7-17 .2-32.6 9.9-41.4 25.1-17.6 30.6-4.5 75.9 12.7 100.7 8.4 12.1 18.4 25.8 31.6 25.3 12.7-.5 17.5-8.2 32.8-8.2s19.6 8.2 33 7.9c13.6-.2 22.3-12.4 30.6-24.5 9.6-14.1 13.6-27.8 13.8-28.5-.3-.1-26.5-10.2-26.8-40.4zM125.2 32.5c7-8.5 11.7-20.3 10.4-32.1-10.1.4-22.3 6.7-29.5 15.2-6.5 7.5-12.2 19.5-10.6 31 11.2.9 22.7-5.7 29.7-14.1z"/></svg>;
const WifiIcon = () => <svg width="17" height="13" viewBox="0 0 17 13" fill="none" stroke="#fff" strokeWidth="1.6" strokeLinecap="round"><path d="M1 4.2a11 11 0 0 1 15 0M3.6 7a7.3 7.3 0 0 1 9.8 0M6.2 9.8a3.6 3.6 0 0 1 4.6 0"/><circle cx="8.5" cy="12" r=".9" fill="#fff" stroke="none"/></svg>;
const BatteryIcon = () => <svg width="27" height="13" viewBox="0 0 27 13"><rect x=".75" y=".75" width="22.5" height="11.5" rx="3" fill="none" stroke="#fff" strokeOpacity=".9" strokeWidth="1.2"/><rect x="2.3" y="2.3" width="17" height="8.4" rx="1.6" fill="#fff"/><path d="M25 4.5v4a2 2 0 0 0 0-4z" fill="#fff" fillOpacity=".6"/></svg>;
const SearchIcon = () => <svg width="15" height="15" viewBox="0 0 15 15" fill="none" stroke="#fff" strokeWidth="1.7" strokeLinecap="round"><circle cx="6.3" cy="6.3" r="4.6"/><path d="M9.8 9.8l3.6 3.6"/></svg>;
const CCIcon = () => <svg width="17" height="13" viewBox="0 0 17 13" fill="none" stroke="#fff" strokeWidth="1.5"><rect x=".75" y=".75" width="15.5" height="4.6" rx="2.3"/><circle cx="4" cy="3" r="1.4" fill="#fff" stroke="none"/><rect x=".75" y="7.65" width="15.5" height="4.6" rx="2.3"/><circle cx="13" cy="10" r="1.4" fill="#fff" stroke="none"/></svg>;

function MenuBar({ active = "Finder" }) {
  return (
    <div className="menubar">
      <div className="l"><AppleLogo /><b>{active}</b><span>File</span><span>Edit</span><span>View</span><span>Go</span><span>Window</span><span>Help</span></div>
      <div className="r"><img src="assets/mascot-calm.png" alt="" style={{ width: 20, height: 20 }} /><BatteryIcon /><WifiIcon /><SearchIcon /><CCIcon /><span style={{ marginLeft: 4 }}>Sat May 16&nbsp;&nbsp;10:18 AM</span></div>
    </div>
  );
}

/* dock icons — simplified but recognisable macOS shapes */
const FinderIcon = () => <svg width="60" height="60" viewBox="0 0 60 60"><defs><linearGradient id="fd" x1="0" y1="0" x2="0" y2="1"><stop offset="0" stopColor="#4cc2ff"/><stop offset="1" stopColor="#1a7ff0"/></linearGradient></defs><rect width="60" height="60" rx="14" fill="url(#fd)"/><path d="M30 0h16a14 14 0 0 1 14 14v32a14 14 0 0 1-14 14H30z" fill="#fff" fillOpacity=".92"/><path d="M30 0a48 48 0 0 0-2 60" fill="none" stroke="#1a5fb0" strokeWidth="2.2"/><circle cx="19" cy="24" r="2.6" fill="#0b2a55"/><circle cx="41" cy="24" r="2.6" fill="#0b2a55"/><path d="M17 40q13 9 26 0" fill="none" stroke="#0b2a55" strokeWidth="2.6" strokeLinecap="round"/></svg>;
const SafariIcon = () => <svg width="60" height="60" viewBox="0 0 60 60"><defs><radialGradient id="sf" cx=".5" cy=".4"><stop offset="0" stopColor="#5fd0ff"/><stop offset="1" stopColor="#1370e8"/></radialGradient></defs><rect width="60" height="60" rx="14" fill="#fff"/><circle cx="30" cy="30" r="24" fill="url(#sf)"/>{Array.from({ length: 24 }, (_, i) => <line key={i} x1="30" y1="8" x2="30" y2={i % 6 === 0 ? 13 : 11} stroke="#fff" strokeOpacity=".8" strokeWidth="1.2" transform={`rotate(${i * 15} 30 30)`} />)}<path d="M44 16L34 34l-8-8z" fill="#ff3b30"/><path d="M16 44l10-18 8 8z" fill="#fff"/></svg>;
const CalendarIcon = () => <svg width="60" height="60" viewBox="0 0 60 60"><rect width="60" height="60" rx="14" fill="#fff"/><path d="M0 14A14 14 0 0 1 14 0h32a14 14 0 0 1 14 14v6H0z" fill="#ff3b30"/><text x="30" y="15" textAnchor="middle" fontSize="10" fontWeight="700" fill="#fff" fontFamily="-apple-system,system-ui">SAT</text><text x="30" y="49" textAnchor="middle" fontSize="30" fontWeight="500" fill="#1a1a1a" fontFamily="-apple-system,system-ui" letterSpacing="-1">16</text></svg>;
const MailIcon = () => <svg width="60" height="60" viewBox="0 0 60 60"><defs><linearGradient id="ml" x1="0" y1="0" x2="0" y2="1"><stop offset="0" stopColor="#4fc3ff"/><stop offset="1" stopColor="#1478f0"/></linearGradient></defs><rect width="60" height="60" rx="14" fill="url(#ml)"/><rect x="11" y="17" width="38" height="26" rx="4" fill="#fff"/><path d="M11 21l19 13 19-13" fill="none" stroke="#1478f0" strokeWidth="2.2" strokeLinejoin="round"/></svg>;
const NotesIcon = () => <svg width="60" height="60" viewBox="0 0 60 60"><rect width="60" height="60" rx="14" fill="#fff"/><path d="M0 14A14 14 0 0 1 14 0h32a14 14 0 0 1 14 14v6H0z" fill="#ffd60a"/><g stroke="#d8d8d8" strokeWidth="1.5"><line x1="10" y1="31" x2="50" y2="31"/><line x1="10" y1="40" x2="50" y2="40"/><line x1="10" y1="49" x2="38" y2="49"/></g></svg>;
const NotionIcon = () => <svg width="60" height="60" viewBox="0 0 60 60"><rect width="60" height="60" rx="14" fill="#fff" stroke="#e5e5e5"/><path d="M17 15l22-1.6c2.7-.2 3.4 0 5.1 1.2l7 4.9c1.2.8 1.6 1.1 1.6 2v27c0 1.7-.6 2.7-2.8 2.9L24.6 53c-1.6.1-2.4-.2-3.3-1.2l-5.2-6.7c-1-1.3-1.4-2.2-1.4-3.4V17.7c0-1.4.6-2.6 2.3-2.7z" fill="#000"/><path d="M39 17.5l-20.5 1.4c-1.4.1-1.7.9-1.1 1.6l3.6 4.1c.5.5 1 .8 2 .7l21.5-1.5c1-.1 1.2-.6.8-1l-3.8-4.5c-.5-.6-1.2-.9-2.5-.8z" fill="#fff"/><path d="M21.5 27v19.6c0 1.1.5 1.4 1.7 1.3l22-1.3c1.2-.1 1.4-.8 1.4-1.7V26.4c0-.9-.3-1.4-1.1-1.3L22.5 26c-.8.1-1 .5-1 1z" fill="#fff"/><path d="M28 30.5v13l4.6 4.9v-10l7.9 10.3 3-.2V30l-3 .2v11.4l-8.5-11.5z" fill="#000"/></svg>;
const CompostIcon = () => <div style={{ width: 60, height: 60, borderRadius: 14, background: "linear-gradient(160deg,#7ba76a,#3a5d2f)", display: "grid", placeItems: "center" }}><img src="assets/mascot-calm.png" alt="" style={{ width: 50, height: 50 }} /></div>;
const TrashIcon = () => <svg width="60" height="60" viewBox="0 0 60 60"><rect width="60" height="60" rx="14" fill="none"/><path d="M17 16h26l-2.4 30a3 3 0 0 1-3 2.8H22.4a3 3 0 0 1-3-2.8z" fill="#cfd3d8" stroke="#8f959c"/><rect x="14" y="12" width="32" height="4" rx="1.5" fill="#e6e8eb" stroke="#8f959c"/><g stroke="#8f959c" strokeWidth="1.2"><line x1="24" y1="20" x2="25" y2="45"/><line x1="30" y1="20" x2="30" y2="45"/><line x1="36" y1="20" x2="35" y2="45"/></g></svg>;

function Dock({ bounce = 0 }) {
  const apps = [<FinderIcon />, <SafariIcon />, <CalendarIcon />, <MailIcon />, <NotesIcon />, <NotionIcon />];
  return (
    <div className="dock">
      {apps.map((a, i) => <div key={i} className="app">{a}</div>)}
      <div className="app" style={{ transform: `translateY(${-bounce}px)`, boxShadow: `0 ${4 + bounce * 0.4}px ${10 + bounce}px rgba(0,0,0,.28)` }}><CompostIcon /></div>
      <span className="sep" /><div className="app" style={{ boxShadow: "none" }}><TrashIcon /></div>
    </div>
  );
}

function Wallpaper({ kind, T }) {
  const d = 8 * Math.sin(T * 0.25), e = 6 * Math.cos(T * 0.19);
  const blob = (c) => `radial-gradient(closest-side, ${c} 0%, ${c.replace(/[\d.]+\)$/, "0)")} 100%)`;
  const c1 = kind === "sequoia" ? "rgba(63,124,240,.55)" : "rgba(255,255,255,.14)";
  const c2 = kind === "sequoia" ? "rgba(138,77,224,.55)" : "rgba(255,255,255,.10)";
  return <div className={`wall ${kind}`}><i style={{ left: 300 + d * 4, top: 200 + e * 3, width: 900, height: 700, background: blob(c1) }} /><i style={{ left: 1000 - d * 3, top: 380 - e * 4, width: 860, height: 720, background: blob(c2) }} /></div>;
}

Object.assign(window, { MenuBar, Dock, Wallpaper });
