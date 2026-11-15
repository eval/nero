// Dark mode for the API docs.
// The theme follows the OS setting, unless the reader picks one with the button
// (bottom right): auto → dark → light → auto. The choice is kept in localStorage
// and applies to the main page and the class/method list in the side frame.
(function () {
  var KEY = "nero-docs-theme"; // "dark" | "light" | absent (follow the OS)
  var LABELS = { auto: "◐ Auto", dark: "☾ Dark", light: "☀ Light" };
  var media = window.matchMedia ? window.matchMedia("(prefers-color-scheme: dark)") : null;

  function choice() {
    try {
      var value = localStorage.getItem(KEY);
      return value === "dark" || value === "light" ? value : "auto";
    } catch (e) {
      return "auto"; // storage blocked: follow the OS
    }
  }

  function store(value) {
    try {
      if (value === "auto") localStorage.removeItem(KEY);
      else localStorage.setItem(KEY, value);
    } catch (e) {}
  }

  function theme() {
    var c = choice();
    if (c !== "auto") return c;
    return media && media.matches ? "dark" : "light";
  }

  function apply(doc) {
    doc.documentElement.setAttribute("data-theme", theme());
  }

  function applyAll() {
    apply(document);
    // The list in the side frame is a separate document (same origin).
    var nav = document.getElementById("nav");
    if (nav && nav.contentDocument) {
      try { apply(nav.contentDocument); } catch (e) {}
    }
    var button = document.getElementById("theme-toggle");
    if (button) button.textContent = LABELS[choice()];
  }

  // Set the theme before the page renders, to avoid a flash of the light theme.
  apply(document);

  if (media) {
    if (media.addEventListener) media.addEventListener("change", applyAll);
    else if (media.addListener) media.addListener(applyAll);
  }
  // A choice made in another tab or frame.
  window.addEventListener("storage", function (event) {
    if (event.key === KEY || event.key === null) applyAll();
  });

  document.addEventListener("DOMContentLoaded", function () {
    var nav = document.getElementById("nav");
    if (nav) nav.addEventListener("load", applyAll);

    // The button goes on documentation pages, not in the lists of the side frame.
    if (!document.getElementById("main")) return;

    var button = document.createElement("button");
    button.id = "theme-toggle";
    button.type = "button";
    button.title = "Color theme: auto (follows your system), dark or light";
    button.addEventListener("click", function () {
      var next = { auto: "dark", dark: "light", light: "auto" }[choice()];
      store(next);
      applyAll();
    });
    document.body.appendChild(button);
    applyAll();
  });
})();
