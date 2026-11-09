/**
 * Mobile Host half: same-origin Face routes → Android MobileApi loopback.
 * Written into $XRK_HOME/plugins/xrk-mobile-host by PhoneGuest (App only).
 * Client must never guess the Android port — only this proxy sees XRK_MOBILE_*.
 *
 * After enable/disable, remounts process plugins via HostWireContext so
 * `xrk-mobile-prompt` appears/disappears without restarting xrkh.
 */
async function mobileFetch(path, { method = "GET", body } = {}) {
  const api = process.env.XRK_MOBILE_API;
  const token = process.env.XRK_MOBILE_TOKEN;
  if (!api || !token) {
    const err = new Error("XRK mobile API is not configured on this launch");
    err.status = 503;
    throw err;
  }
  const r = await fetch(`${api}${path}`, {
    method,
    headers: {
      authorization: `Bearer ${token}`,
      ...(body !== undefined ? { "content-type": "application/json" } : {}),
    },
    ...(body !== undefined ? { body: JSON.stringify(body) } : {}),
  });
  const text = await r.text();
  let json = null;
  try {
    json = text ? JSON.parse(text) : null;
  } catch {
    json = null;
  }
  return { ok: r.ok, status: r.status, text, json };
}

function readBody(req) {
  return new Promise((resolve, reject) => {
    const chunks = [];
    req.on("data", (c) => chunks.push(c));
    req.on("end", () => {
      const raw = Buffer.concat(chunks).toString("utf8");
      if (!raw) return resolve(undefined);
      try {
        resolve(JSON.parse(raw));
      } catch (e) {
        reject(e);
      }
    });
    req.on("error", reject);
  });
}

function send(res, status, payload) {
  const body =
    typeof payload === "string" ? payload : JSON.stringify(payload ?? {});
  res.writeHead(status, {
    "content-type":
      typeof payload === "string"
        ? "text/plain; charset=utf-8"
        : "application/json; charset=utf-8",
    "cache-control": "no-store",
  });
  res.end(body);
  return true;
}

/** Remount phone prompt/tools from disk (Host process half; no engine restart). */
async function remountPhonePlugins(ctx) {
  const sync = ctx && typeof ctx.syncManagedProcessPlugins === "function"
    ? ctx.syncManagedProcessPlugins
    : null;
  if (!sync) return;
  try {
    await sync({
      reloadIds: ["xrk-mobile-prompt", "xrk-mobile"],
    });
  } catch (_) {
    // Soft: Android already flipped prefs; next agent recreate still picks inventory.
  }
}

const PREFIX = "/api/xrk-mobile";

export function createPlugin() {
  return {
    id: "xrk-mobile-host",
    kind: "host",
    createPublicHandler(ctx) {
      return async (req, res) => {
        const url = new URL(req.url || "/", "http://127.0.0.1");
        const path = url.pathname;
        if (!path.startsWith(PREFIX)) return false;
        const method = (req.method || "GET").toUpperCase();
        try {
          if (method === "GET" && path === `${PREFIX}/health`) {
            const out = await mobileFetch("/v1/health");
            return send(res, out.ok ? 200 : out.status, { ok: out.ok });
          }
          if (method === "GET" && path === `${PREFIX}/phone-settings`) {
            const out = await mobileFetch("/v1/phone-settings");
            return send(
              res,
              out.ok ? 200 : out.status,
              out.json ?? { ok: false, error: out.text },
            );
          }
          if (method === "GET" && path === `${PREFIX}/phone-settings/steer-pending`) {
            const out = await mobileFetch("/v1/phone-settings/steer-pending");
            return send(
              res,
              out.ok ? 200 : out.status,
              out.json ?? { ok: false, items: [] },
            );
          }
          if (method === "POST" && path === `${PREFIX}/phone-settings/enabled`) {
            const body = await readBody(req);
            const out = await mobileFetch("/v1/phone-settings/enabled", {
              method: "POST",
              body,
            });
            // Hot-utilize: remount prompt after Android wrote/cleared the plugin dir.
            if (out.json && out.json.ok) {
              await remountPhonePlugins(ctx);
            }
            return send(
              res,
              out.ok ? 200 : out.status,
              out.json ?? { ok: false, error: out.text },
            );
          }
          // Flutter / native toggle writes disk then POSTs here so Host remounts
          // without going through MobileApi enable again (no double flip).
          if (method === "POST" && path === `${PREFIX}/phone-settings/remount-plugins`) {
            await remountPhonePlugins(ctx);
            return send(res, 200, { ok: true, remounted: true });
          }
          if (method === "POST" && path === `${PREFIX}/phone-settings/run-end`) {
            const body = await readBody(req);
            const out = await mobileFetch("/v1/phone-settings/run-end", {
              method: "POST",
              body,
            });
            return send(
              res,
              out.ok ? 200 : out.status,
              out.json ?? { ok: false, error: out.text },
            );
          }
          if (method === "POST" && path === `${PREFIX}/phone-settings/policies`) {
            const body = await readBody(req);
            const out = await mobileFetch("/v1/phone-settings/policies", {
              method: "POST",
              body,
            });
            return send(
              res,
              out.ok ? 200 : out.status,
              out.json ?? { ok: false, error: out.text },
            );
          }
          if (method === "POST" && path === `${PREFIX}/phone-settings/overlay`) {
            const body = await readBody(req);
            const out = await mobileFetch("/v1/phone-settings/overlay", {
              method: "POST",
              body,
            });
            return send(
              res,
              out.ok ? 200 : out.status,
              out.json ?? { ok: false, error: out.text },
            );
          }
          if (method === "POST" && path === `${PREFIX}/phone-settings/open-accessibility`) {
            const out = await mobileFetch("/v1/phone-settings/open-accessibility", {
              method: "POST",
              body: {},
            });
            return send(
              res,
              out.ok ? 200 : out.status,
              out.json ?? { ok: false, error: out.text },
            );
          }
          if (method === "POST" && path === `${PREFIX}/phone-settings/open-app-details`) {
            const out = await mobileFetch("/v1/phone-settings/open-app-details", {
              method: "POST",
              body: {},
            });
            return send(
              res,
              out.ok ? 200 : out.status,
              out.json ?? { ok: false, error: out.text },
            );
          }
          if (method === "POST" && path === `${PREFIX}/phone-settings/steer`) {
            const body = await readBody(req);
            const out = await mobileFetch("/v1/phone-settings/steer", {
              method: "POST",
              body,
            });
            return send(
              res,
              out.ok ? 200 : out.status,
              out.json ?? { ok: false, error: out.text },
            );
          }
          return send(res, 404, { ok: false, error: "not found" });
        } catch (e) {
          const status = e && e.status ? e.status : 502;
          return send(res, status, {
            ok: false,
            error: String(e && e.message ? e.message : e),
          });
        }
      };
    },
  };
}
