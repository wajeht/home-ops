(() => {
  if (document?.title) {
    document.title = "Jaw's Home Ops";
  }

  const title = document.querySelector("h1, h2, .title, .auth-title");
  if (title && /sign\s*in/i.test(title.textContent || "")) {
    title.textContent = "Sign In";
  }
})();
