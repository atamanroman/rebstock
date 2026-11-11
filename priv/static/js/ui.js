(() => {
  let returnFocus;
  let returnHref;
  let modalHistory = false;
  let overlayRequest;

  const filterTable = (input) => {
    input.hidden = false;
    const table = document.getElementById(input.dataset.tableFilter);
    const query = input.value.trim().toLocaleLowerCase();
    table?.querySelectorAll("tbody tr").forEach((row) => {
      row.hidden = !row.textContent.toLocaleLowerCase().includes(query);
    });
  };
  const setBackgroundInert = (inert) => {
    document
      .querySelectorAll(".site-header, .site-main, .site-footer")
      .forEach((el) => {
        el.inert = inert;
      });
  };
  const update = () => {
    document.querySelectorAll(".site-nav a").forEach((link) => {
      const path = new URL(link.href).pathname;
      const active =
        path === "/"
          ? location.pathname === "/"
          : location.pathname === path ||
            location.pathname.startsWith(path + "/");
      if (active) link.setAttribute("aria-current", "page");
      else link.removeAttribute("aria-current");
    });
    document.querySelectorAll("[data-table-filter]").forEach(filterTable);
    const dialog = document.querySelector('#overlay [role="dialog"]');
    setBackgroundInert(Boolean(dialog));
    if (dialog) {
      const heading = dialog.querySelector("h1, h2");
      if (heading) {
        heading.id = "overlay-title";
        dialog.setAttribute("aria-labelledby", heading.id);
        dialog.removeAttribute("aria-label");
      }
    }
  };
  const reportError = (message) => {
    const form = document.querySelector(
      "#overlay .form-card, .site-main .form-card",
    );
    let status = document.getElementById("request-status");
    if (form) {
      status = form.querySelector(".request-error");
      if (!status) {
        status = document.createElement("p");
        status.className = "form-error request-error";
        status.setAttribute("role", "alert");
        status.tabIndex = -1;
        form.prepend(status);
      }
    }
    if (status) {
      status.textContent = message;
      status.hidden = false;
      if (form) status.focus();
    }
  };
  const closeOverlay = () => {
    if (overlayRequest && overlayRequest.request.method !== "GET") return;
    overlayRequest?.request.abort();
    const overlay = document.getElementById("overlay");
    if (!overlay) return;
    overlay.replaceChildren();
    overlay.className = "hidden";
    setBackgroundInert(false);
    if (returnFocus?.isConnected) returnFocus.focus();
    if (modalHistory) {
      modalHistory = false;
      history.back();
    }
  };

  document.addEventListener("DOMContentLoaded", update);
  document.addEventListener("input", (event) => {
    if (event.target.matches("[data-table-filter]")) filterTable(event.target);
  });
  document.addEventListener("click", (event) => {
    document
      .querySelectorAll(".user-menu[open], .list-menu[open]")
      .forEach((menu) => {
        if (!menu.contains(event.target)) menu.open = false;
      });
    if (
      event.target.closest(".overlay-close") ||
      event.target.classList.contains("overlay-backdrop")
    )
      closeOverlay();
  });
  document.addEventListener("htmx:before:request", (event) => {
    const { ctx } = event.detail;
    document
      .querySelectorAll(".request-status, .request-error")
      .forEach((status) => {
        status.hidden = true;
      });
    ctx.sourceElement.setAttribute("aria-busy", "true");
    if (ctx.target?.id === "overlay" || ctx.sourceElement.closest("#overlay")) {
      overlayRequest = ctx;
      if (!document.querySelector('#overlay [role="dialog"]')) {
        returnFocus = ctx.sourceElement;
        returnHref = returnFocus.getAttribute("href");
      }
    }
  });
  document.addEventListener("htmx:after:history:update", (event) => {
    const source = event.detail.sourceElement;
    if (
      event.detail.history.type === "push" &&
      source?.getAttribute("hx-target") === "#overlay"
    )
      modalHistory = true;
  });
  document.addEventListener("htmx:after:swap", (event) => {
    const { ctx } = event.detail;
    update();
    const error = document.querySelector(".form-error");
    const dialog = document.querySelector('#overlay [role="dialog"]');
    if (ctx.target === document.body || ctx.target?.tagName === "BODY") {
      modalHistory = false;
      const previous =
        returnHref &&
        [...document.querySelectorAll("a[href]")].find(
          (link) => link.getAttribute("href") === returnHref,
        );
      (previous || document.getElementById("main"))?.focus({
        preventScroll: true,
      });
      returnHref = null;
    } else if (error) {
      error.focus();
    } else if (
      dialog &&
      (ctx.target?.id === "overlay" || ctx.hx?.retarget === "#overlay")
    ) {
      dialog.focus();
    }
  });
  document.addEventListener("htmx:finally:request", (event) => {
    const { ctx } = event.detail;
    ctx.sourceElement.removeAttribute("aria-busy");
    if (overlayRequest === ctx) overlayRequest = null;
  });
  document.addEventListener("htmx:error", (event) => {
    if (event.detail.error?.name !== "AbortError")
      reportError(
        "The request failed. Check your connection and try again; your form is still here.",
      );
  });
  document.addEventListener("htmx:response:error", (event) => {
    const status = event.detail.ctx.response.status;
    if (status !== 422)
      reportError(
        status === 403
          ? "You do not have permission to make this change."
          : "This request could not be completed. Your form has been kept; please try again.",
      );
  });
  document.addEventListener("keydown", (event) => {
    const dialog = document.querySelector('#overlay [role="dialog"]');
    if (!dialog) {
      if (event.key === "Escape")
        document
          .querySelectorAll(".user-menu[open], .list-menu[open]")
          .forEach((menu) => {
            menu.open = false;
            menu.querySelector("summary").focus();
          });
      return;
    }
    if (event.key === "Escape") {
      event.preventDefault();
      closeOverlay();
    }
    if (event.key === "Tab") {
      const controls = [
        ...dialog.querySelectorAll(
          'a[href], button, input:not([type="hidden"]), select, textarea, summary, [tabindex="0"]',
        ),
      ].filter((el) => !el.disabled && el.getClientRects().length);
      const first = controls[0],
        last = controls.at(-1);
      if (
        event.shiftKey &&
        (document.activeElement === first || document.activeElement === dialog)
      ) {
        event.preventDefault();
        last?.focus();
      } else if (!event.shiftKey && document.activeElement === last) {
        event.preventDefault();
        first?.focus();
      }
    }
  });
})();
