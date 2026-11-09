/**
 * Mobile-only Settings section (id=phone). Staged by PhoneGuest into
 * $XRK_HOME/plugins/web/xrk-mobile-ui/ — Desktop/CLI never see this package.
 * Talks only to Face `/api/xrk-mobile/*` (host plugin → MobileApi).
 */
window.__ModuleLoader__.load({
  id: "xrk-mobile-ui",
  factory: (require) => {
    var module = { exports: {} };
    var exports = module.exports;
    Object.defineProperty(exports, Symbol.toStringTag, { value: "Module" });

    var react = require("react");
    var jsx = require("react/jsx-runtime");
    var primitives = require("@xrkseek/client-ui-primitives");
    var h = jsx.jsx;
    var hs = jsx.jsxs;
    var useState = react.useState;
    var useEffect = react.useEffect;
    var useCallback = react.useCallback;
    var Switch = primitives.Switch;
    var Button = primitives.Button;

    var CSS_ID = "xrk-mobile-ui/phone-section.css";
    var CSS_TEXT =
      ".xrkPhone{display:flex;flex-direction:column;gap:16px;padding:4px 2px 24px;color:var(--dsw-alias-label-primary)}" +
      ".xrkPhone h2{margin:0;font-size:18px;font-weight:600;line-height:24px}" +
      ".xrkPhone .intro{margin:0;color:var(--dsw-alias-label-secondary);font-size:13px;line-height:18px}" +
      ".xrkPhone .card{border:1px solid var(--dsw-alias-border-subtle,rgba(0,0,0,.08));border-radius:12px;background:var(--dsw-alias-bg-elevated,transparent);padding:4px 0}" +
      ".xrkPhone .row{display:flex;align-items:center;gap:12px;min-height:48px;padding:10px 14px}" +
      ".xrkPhone .row + .row{border-top:1px solid var(--dsw-alias-border-subtle,rgba(0,0,0,.06))}" +
      ".xrkPhone .meta{flex:1;min-width:0}" +
      ".xrkPhone .title{font-size:14px;font-weight:500;line-height:20px}" +
      ".xrkPhone .hint{margin-top:2px;color:var(--dsw-alias-label-secondary);font-size:12px;line-height:16px}" +
      ".xrkPhone .err{color:var(--dsw-alias-state-danger,#a54743);font-size:13px}" +
      ".xrkPhone .warn{color:var(--dsw-alias-state-warning,#8a6a1a);font-size:12px;line-height:16px;margin:0 14px 8px}" +
      ".xrkPhone .seg{display:flex;flex-wrap:wrap;gap:8px}" +
      ".xrkPhone .seg button{min-height:36px;border-radius:8px;border:1px solid var(--dsw-alias-border-subtle,rgba(0,0,0,.12));background:var(--dsw-alias-interactive-bg-hover,transparent);color:inherit;padding:6px 12px;font:inherit;cursor:pointer}" +
      ".xrkPhone .seg button[aria-pressed=true]{border-color:var(--dsw-alias-brand-primary,#4b67b4);background:var(--dsw-alias-state-business-soft,#dee8ff);color:var(--dsw-alias-state-business-primary,#213262)}" +
      ".xrkPhone .slider{width:100%;accent-color:var(--dsw-alias-brand-primary,#4b67b4)}" +
      ".xrkPhone .steps{margin:0;padding:0 14px 12px 32px;color:var(--dsw-alias-label-secondary);font-size:12px;line-height:18px}" +
      ".xrkPhone .steps li{margin:4px 0}" +
      ".xrkPhone .romNote{margin:0 14px 12px;padding:8px 10px;border-radius:8px;background:var(--dsw-alias-state-warning-soft,rgba(138,106,26,.12));color:var(--dsw-alias-state-warning,#8a6a1a);font-size:12px;line-height:16px}";

    // Mirrors Flutter RestrictedSettingsGuidePage / RomFamily (sideload a11y greys out).
    var ROM_GUIDES = {
      vivo: {
        label: "vivo / iQOO",
        steps: [
          "先去无障碍试开「XRK 手机操控」；若开关灰掉再继续。",
          "打开本应用的「应用信息」。",
          "点右上角三个点 →「允许受限制的设置」，验证锁屏密码。",
          "再回无障碍打开「XRK 手机操控」。",
        ],
        note: "不同 OriginOS 位置可能不同；没有三个点时把应用信息页翻到底。",
      },
      xiaomi: {
        label: "小米 / Redmi",
        steps: [
          "先去无障碍试开「XRK 手机操控」；若开关灰掉再继续。",
          "打开本应用的「应用信息」。",
          "在「高级设置」里打开「允许受限制的设置」。",
          "再回无障碍打开「XRK 手机操控」。",
        ],
      },
      oppo: {
        label: "OPPO / OnePlus / realme",
        steps: [
          "先去无障碍试开「XRK 手机操控」；若开关灰掉再继续。",
          "打开本应用的「应用信息」。",
          "点右上角三个点 →「允许受限制的设置」，验证锁屏密码。",
          "再回无障碍打开「XRK 手机操控」。",
        ],
        note: "ColorOS 有时找不到该选项：用系统文件管理找到安装包覆盖安装一次（不用卸载），再开无障碍。",
      },
      honor: {
        label: "荣耀",
        steps: [
          "先去无障碍试开「XRK 手机操控」；若开关灰掉再继续。",
          "打开本应用的「应用信息」。",
          "点右上角三个点 →「允许受限制的设置」，验证锁屏密码。",
          "再回无障碍打开「XRK 手机操控」。",
        ],
      },
      huawei: {
        label: "华为",
        steps: [
          "HarmonyOS 4 及更早大多没有「受限制的设置」这一步，直接去无障碍打开 XRK。",
          "若无障碍里出现「受限制的设置」提示，按「原生 / 其他」步骤做。",
        ],
      },
      stock: {
        label: "原生 / 其他",
        steps: [
          "先去无障碍试开「XRK 手机操控」；若开关灰掉再继续。",
          "打开本应用的「应用信息」。",
          "点右上角三个点 →「允许受限制的设置」，验证锁屏密码。",
          "再回无障碍打开「XRK 手机操控」。",
        ],
      },
    };

    function romOf(manufacturer) {
      var m = String(manufacturer || "").toLowerCase();
      if (m.indexOf("vivo") >= 0 || m.indexOf("iqoo") >= 0) return "vivo";
      if (m.indexOf("xiaomi") >= 0 || m.indexOf("redmi") >= 0 || m.indexOf("poco") >= 0) return "xiaomi";
      if (m.indexOf("oppo") >= 0 || m.indexOf("oneplus") >= 0 || m.indexOf("realme") >= 0) return "oppo";
      if (m.indexOf("honor") >= 0) return "honor";
      if (m.indexOf("huawei") >= 0) return "huawei";
      return "stock";
    }

    function ensureCss() {
      if (typeof document === "undefined") return;
      if (document.querySelector('style[data-plugin-css="' + CSS_ID + '"]')) return;
      var tag = document.createElement("style");
      tag.dataset.plugin = "xrk-mobile-ui";
      tag.dataset.pluginCss = CSS_ID;
      tag.textContent = CSS_TEXT;
      document.head.appendChild(tag);
    }

    async function api(path, init) {
      var r = await fetch("/api/xrk-mobile" + path, {
        credentials: "same-origin",
        headers: init && init.body ? { "content-type": "application/json" } : undefined,
        method: (init && init.method) || "GET",
        body: init && init.body !== undefined ? JSON.stringify(init.body) : undefined,
      });
      var text = await r.text();
      var json = null;
      try {
        json = text ? JSON.parse(text) : null;
      } catch (_) {
        json = null;
      }
      if (!r.ok) {
        var err = new Error((json && json.error) || text || r.statusText);
        err.status = r.status;
        throw err;
      }
      return json;
    }

    var CONFIRM = [
      { id: "ask", label: "每次询问", hint: "敏感步骤与首进 App 都确认" },
      { id: "task", label: "本任务免确认", hint: "任务内可一次豁免后续确认" },
      { id: "always", label: "免确认", hint: "硬规则与视觉门仍生效" },
    ];

    var UNLOCKS = [
      {
        id: "systemPages",
        label: "系统设置页",
        hint: "允许操作系统设置 / 权限 / 安装器等（高风险）",
        risk: "开启后模型可进入系统设置类页面，可能改权限或安全选项。确定解除？",
      },
      {
        id: "secretFields",
        label: "密码 / 验证码框",
        hint: "允许在密码与验证码输入框打字（键入内容不进日志）",
        risk: "开启后模型可在密码、验证码、支付码框输入。确定解除？",
      },
      {
        id: "ownApp",
        label: "本应用界面",
        hint: "允许操作 XRK Harness 自己的界面",
        risk: "开启后模型可操作本应用屏幕。确定解除？",
      },
    ];

    function PhoneSection() {
      ensureCss();
      var snap = useState(null);
      var data = snap[0];
      var setData = snap[1];
      var errState = useState(null);
      var error = errState[0];
      var setError = errState[1];
      var busyState = useState(false);
      var busy = busyState[0];
      var setBusy = busyState[1];
      var noticeState = useState(null);
      var notice = noticeState[0];
      var setNotice = noticeState[1];
      var romState = useState(null);
      var romPick = romState[0];
      var setRomPick = romState[1];
      var previewState = useState("");
      var screenPreview = previewState[0];
      var setScreenPreview = previewState[1];

      var reload = useCallback(function () {
        return api("/phone-settings")
          .then(function (next) {
            setData(next);
            setError(null);
            setRomPick(function (cur) {
              if (cur) return cur;
              var maker =
                next && next.status && next.status.device
                  ? next.status.device.manufacturer
                  : "";
              return romOf(maker);
            });
          })
          .catch(function (e) {
            setError(String(e && e.message ? e.message : e));
          });
      }, []);

      useEffect(function () {
        void reload();
      }, [reload]);

      var enabled = !!(data && data.status && data.status.enabled);
      var engineSafeMode = !!(data && data.status && data.status.engineSafeMode);
      var disclosureAccepted = !!(
        data &&
        data.status &&
        data.status.disclosureAccepted
      );
      var a11yOn = !!(data && data.status && data.status.a11y && data.status.a11y.enabled);
      var a11yConnected = !!(data && data.status && data.status.a11y && data.status.a11y.serviceConnected);
      var bridgeOn = !!(data && data.status && data.status.bridgeListening);
      var notifyOn = !!(data && data.status && data.status.notifications);
      var confirmMode =
        (data && data.policies && data.policies.confirmMode) || "ask";
      var unlocks =
        (data && data.policies && data.policies.unlocks) || {
          systemPages: false,
          secretFields: false,
          ownApp: false,
        };
      var opacity =
        data && data.overlay && typeof data.overlay.idleOpacity === "number"
          ? data.overlay.idleOpacity
          : 0.7;
      var autoCollapse = !!(data && data.overlay && data.overlay.autoCollapse);
      var device = (data && data.status && data.status.device) || {};
      var mayRestricted = !!(device.sideloaded || device.restricted);
      var romId = romPick || romOf(device.manufacturer);
      var romGuide = ROM_GUIDES[romId] || ROM_GUIDES.stock;
      var background = (data && data.status && data.status.background) || {};
      var a11yKeeper = (data && data.status && data.status.a11yKeeper) || {};
      var bgMode = background.mode || "off";
      var bgReady = !!background.ready;
      var bgAndroidOk = background.androidOk !== false;
      var keeperGranted = !!a11yKeeper.granted;
      var keeperPath = a11yKeeper.path || "";
      var keeperCmd = a11yKeeper.command || "";
      var skills = (data && data.status && data.status.skills) || {};
      var skillAsk = !!skills.askAfterSuccess;
      var interruption = (data && data.status && data.status.taskInterruption) || {};
      var interruptVisible = !!interruption.visible;
      var interruptToken =
        interruption.batchToken != null ? String(interruption.batchToken) : "";

      function requestEngineRestart() {
        if (typeof window.__xrkRestartEngine === "function") {
          try {
            if (window.__xrkRestartEngine()) return true;
          } catch (_) {}
        }
        return false;
      }

      async function mutate(fn) {
        if (busy) return;
        setBusy(true);
        setNotice(null);
        try {
          await fn();
          await reload();
        } catch (e) {
          setError(String(e && e.message ? e.message : e));
        } finally {
          setBusy(false);
        }
      }

      async function setEnabled(next) {
        if (busy) return;
        if (next && engineSafeMode) {
          setError("安全模式下不能开启手机操控（与原生设置一致）。请先退出安全模式再开。");
          return;
        }
        setBusy(true);
        setNotice(null);
        setError(null);
        try {
          var accepted = disclosureAccepted;
          if (next && !accepted) {
            var msg =
              "开启手机操控后，助手可以读屏幕并代为点按。确认开启？\n\n" +
              "若引擎正在运行，切换后会自动重启以加载 / 卸载 phone_* 工具。";
            if (typeof window.confirm === "function" && !window.confirm(msg)) {
              return;
            }
            accepted = true;
          }
          var out = await api("/phone-settings/enabled", {
            method: "POST",
            body: {
              enabled: next,
              disclosureAccepted: accepted ? true : undefined,
            },
          });
          if (out && out.needsRestart) {
            if (requestEngineRestart()) {
              setNotice(
                next
                  ? "已开启，正在重启引擎以使工具生效…"
                  : "已关闭，正在重启引擎以卸载工具…",
              );
            } else {
              setNotice("已切换。请到引擎页手动重启，phone_* 工具才会更新。");
            }
          } else if (out && out.ok) {
            setNotice(next ? "已开启（下次启动引擎后生效）" : "已关闭");
          }
          await reload();
        } catch (e) {
          var msg = String(e && e.message ? e.message : e);
          if (msg.indexOf("safe_mode") >= 0) {
            setError("安全模式下不能开启手机操控。请先退出安全模式。");
          } else if (msg.indexOf("disclosure_required") >= 0) {
            setError("请先确认手机操控披露后再开启。");
          } else {
            setError(msg);
          }
        } finally {
          setBusy(false);
        }
      }

      function setUnlock(id, next) {
        if (next) {
          var spec = UNLOCKS.find(function (u) {
            return u.id === id;
          });
          if (spec && typeof window.confirm === "function" && !window.confirm(spec.risk)) {
            return;
          }
        }
        var body = { unlocks: {} };
        body.unlocks[id] = next;
        void mutate(function () {
          return api("/phone-settings/policies", {
            method: "POST",
            body: body,
          });
        });
      }

      return hs("div", { className: "xrkPhone" }, [
        h("h2", { key: "t" }, "手机操控"),
        h(
          "p",
          { key: "i", className: "intro" },
          "这里是手机操控（开关 · 确认 · 无障碍入口），不是应用全部设置。模型 / 插件 / 通用在「应用设置」。无障碍灰掉时看下方各品牌引导；完整原生页也含同样步骤。",
        ),
        error ? h("div", { key: "e", className: "err" }, error) : null,
        notice ? h("p", { key: "n", className: "warn" }, notice) : null,
        !data && !error
          ? h("p", { key: "l", className: "hint" }, "加载中…")
          : null,
        data
          ? hs("div", { key: "c1", className: "card" }, [
              hs("div", { key: "en", className: "row" }, [
                hs("div", { key: "m", className: "meta" }, [
                  h("div", { className: "title" }, "启用手机操控"),
                  h(
                    "div",
                    { className: "hint" },
                    engineSafeMode
                      ? "安全模式中：不能开启（与原生设置一致）"
                      : enabled
                        ? "工具与悬浮条可用（切换后可能需重启引擎）"
                        : disclosureAccepted
                          ? "关闭后 phone_* 工具返回错误"
                          : "首次开启需确认披露；关闭后 phone_* 不可用",
                  ),
                ]),
                h(Switch, {
                  key: "sw",
                  checked: enabled,
                  "aria-label": "启用手机操控",
                  disabled: busy || (engineSafeMode && !enabled),
                  onCheckedChange: function (next) {
                    void setEnabled(next);
                  },
                }),
              ]),
              hs("div", { key: "a11y", className: "row" }, [
                hs("div", { key: "m", className: "meta" }, [
                  h("div", { className: "title" }, "无障碍服务"),
                  h(
                    "div",
                    { className: "hint" },
                    a11yOn
                      ? a11yConnected
                        ? "已开启并已连接"
                        : "已开启，等待服务连接"
                      : "需在系统设置中打开本应用无障碍",
                  ),
                ]),
                h(
                  Button,
                  {
                    key: "b",
                    variant: "secondary",
                    size: "sm",
                    disabled: busy,
                    onClick: function () {
                      void mutate(function () {
                        return api("/phone-settings/open-accessibility", {
                          method: "POST",
                          body: {},
                        });
                      });
                    },
                  },
                  a11yOn ? "打开系统设置" : "去开启",
                ),
              ]),
              !a11yOn || mayRestricted
                ? hs("div", { key: "rom", className: "row", style: { alignItems: "flex-start", flexDirection: "column", gap: 8 } }, [
                    hs("div", { key: "m", className: "meta", style: { width: "100%" } }, [
                      h("div", { className: "title" }, "无障碍开关灰掉？各品牌引导"),
                      h(
                        "div",
                        { className: "hint" },
                        "Android 13+ 侧载常见「受限制的设置」。先选品牌，再按步骤（与原版原生引导一致）。",
                      ),
                    ]),
                    hs(
                      "div",
                      { key: "chips", className: "seg", style: { width: "100%" } },
                      Object.keys(ROM_GUIDES).map(function (id) {
                        return h(
                          "button",
                          {
                            key: id,
                            type: "button",
                            "aria-pressed": id === romId ? "true" : "false",
                            onClick: function () {
                              setRomPick(id);
                            },
                          },
                          ROM_GUIDES[id].label,
                        );
                      }),
                    ),
                    hs(
                      "ol",
                      { key: "steps", className: "steps" },
                      romGuide.steps.map(function (step, i) {
                        return h("li", { key: i }, step);
                      }),
                    ),
                    romGuide.note
                      ? h("div", { key: "note", className: "romNote" }, romGuide.note)
                      : null,
                    hs("div", { key: "acts", className: "seg", style: { width: "100%", paddingBottom: 4 } }, [
                      h(
                        Button,
                        {
                          key: "info",
                          variant: "secondary",
                          size: "sm",
                          disabled: busy,
                          onClick: function () {
                            void mutate(function () {
                              return api("/phone-settings/open-app-details", {
                                method: "POST",
                                body: {},
                              });
                            });
                          },
                        },
                        "应用信息",
                      ),
                      h(
                        Button,
                        {
                          key: "a11y2",
                          variant: "secondary",
                          size: "sm",
                          disabled: busy,
                          onClick: function () {
                            void mutate(function () {
                              return api("/phone-settings/open-accessibility", {
                                method: "POST",
                                body: {},
                              });
                            });
                          },
                        },
                        "再开无障碍",
                      ),
                    ]),
                  ])
                : null,
              hs("div", { key: "st", className: "row" }, [
                hs("div", { key: "m", className: "meta" }, [
                  h("div", { className: "title" }, "桥接与通知"),
                  h(
                    "div",
                    { className: "hint" },
                    (bridgeOn ? "桥接监听中" : "桥接未监听") +
                      " · " +
                      (notifyOn ? "通知已允许" : "通知未允许（确认卡片可能改用回前台）"),
                  ),
                ]),
                h(
                  Button,
                  {
                    key: "b",
                    variant: "secondary",
                    size: "sm",
                    disabled: busy,
                    onClick: function () {
                      void mutate(function () {
                        return api("/phone-settings/open-app-details", {
                          method: "POST",
                          body: {},
                        });
                      });
                    },
                  },
                  "应用详情",
                ),
              ]),
            ])
          : null,
        data
          ? hs("div", { key: "c1b", className: "card" }, [
              hs("div", { key: "bg", className: "row" }, [
                hs("div", { key: "m", className: "meta" }, [
                  h("div", { className: "title" }, "后台能力"),
                  h(
                    "div",
                    { className: "hint" },
                    !bgAndroidOk
                      ? "当前系统版本不支持完整后台预览（需 Android 14+）"
                      : bgReady
                        ? "后台就绪 · 模式 " + bgMode
                        : "后台未就绪 · 模式 " + bgMode + (background.reason ? "（" + background.reason + "）" : ""),
                  ),
                ]),
              ]),
              hs("div", { key: "keep", className: "row" }, [
                hs("div", { key: "m", className: "meta" }, [
                  h("div", { className: "title" }, "无障碍自动恢复"),
                  h(
                    "div",
                    { className: "hint" },
                    keeperGranted
                      ? "已授予 WRITE_SECURE_SETTINGS，服务被关时可尝试自动拉回"
                      : "未授权。可用一键（Shizuku / 自带 ADB）或手动执行命令。" +
                        (keeperPath ? " 路径：" + keeperPath : ""),
                  ),
                  !keeperGranted && keeperCmd
                    ? h(
                        "pre",
                        {
                          className: "hint",
                          style: {
                            margin: "8px 0 0",
                            whiteSpace: "pre-wrap",
                            wordBreak: "break-all",
                            fontSize: 11,
                            opacity: 0.85,
                          },
                        },
                        keeperCmd,
                      )
                    : null,
                ]),
                h(
                  Button,
                  {
                    key: "b",
                    variant: "secondary",
                    size: "sm",
                    disabled: busy || keeperGranted,
                    onClick: function () {
                      void mutate(function () {
                        return api("/phone-settings/grant-secure-settings", {
                          method: "POST",
                          body: {},
                        }).then(function (out) {
                          if (out && out.pending) {
                            setNotice("已发起授权，请在弹窗中允许");
                            return out;
                          }
                          if (out && out.ok === false) {
                            throw new Error(out.reason || "授权失败");
                          }
                          setNotice("授权完成");
                          return out;
                        });
                      });
                    },
                  },
                  keeperGranted ? "已授权" : "一键授权",
                ),
              ]),
              hs("div", { key: "test", className: "row", style: { alignItems: "flex-start" } }, [
                hs("div", { key: "m", className: "meta" }, [
                  h("div", { className: "title" }, "读一下当前屏幕"),
                  h(
                    "div",
                    { className: "hint" },
                    "本机自检，不会发给模型。用于确认无障碍是否真的能读到前台界面。",
                  ),
                  screenPreview
                    ? h(
                        "pre",
                        {
                          className: "hint",
                          style: {
                            margin: "8px 0 0",
                            maxHeight: 160,
                            overflow: "auto",
                            whiteSpace: "pre-wrap",
                            wordBreak: "break-word",
                            fontSize: 11,
                          },
                        },
                        screenPreview,
                      )
                    : null,
                ]),
                h(
                  Button,
                  {
                    key: "b",
                    variant: "secondary",
                    size: "sm",
                    disabled: busy || !a11yConnected,
                    onClick: function () {
                      void mutate(function () {
                        return api("/phone-settings/test-screen", {
                          method: "POST",
                          body: {},
                        }).then(function (out) {
                          if (!out || !out.ok) {
                            throw new Error((out && out.reason) || "读取失败");
                          }
                          setScreenPreview(String(out.text || "").slice(0, 2000));
                          setNotice("已读到当前屏幕（仅本机显示）");
                          return out;
                        });
                      });
                    },
                  },
                  "读取",
                ),
              ]),
            ])
          : null,
        data && interruptVisible
          ? hs("div", { key: "c1c", className: "card" }, [
              hs("div", { key: "int", className: "row" }, [
                hs("div", { key: "m", className: "meta" }, [
                  h("div", { className: "title" }, "任务中断待确认"),
                  h(
                    "div",
                    { className: "hint" },
                    interruption.detail || "有手机任务被打断，确认后工具才能继续。",
                  ),
                ]),
                h(
                  Button,
                  {
                    key: "b",
                    size: "sm",
                    disabled: busy,
                    onClick: function () {
                      void mutate(function () {
                        return api("/phone-settings/ack-interruption", {
                          method: "POST",
                          body: interruptToken ? { batchToken: interruptToken } : {},
                        }).then(function (out) {
                          if (!out || out.ok === false) throw new Error((out && out.error) || "确认失败");
                          setNotice("已确认中断");
                          return out;
                        });
                      });
                    },
                  },
                  "确认继续",
                ),
              ]),
            ])
          : null,
        data
          ? hs("div", { key: "c1d", className: "card" }, [
              hs("div", { key: "sk", className: "row" }, [
                hs("div", { key: "m", className: "meta" }, [
                  h("div", { className: "title" }, "成功后询问是否存技能"),
                  h("div", { className: "hint" }, "任务跑通后弹出「存成技能」提示（与原生设置一致）"),
                ]),
                h(Switch, {
                  checked: skillAsk,
                  "aria-label": "成功后询问是否存技能",
                  disabled: busy,
                  onCheckedChange: function (next) {
                    void mutate(function () {
                      return api("/phone-settings/skill-prompt", {
                        method: "POST",
                        body: { enabled: next },
                      });
                    });
                  },
                }),
              ]),
            ])
          : null,
        data
          ? hs("div", { key: "c2", className: "card" }, [
              hs("div", { key: "cm", className: "row", style: { alignItems: "flex-start" } }, [
                hs("div", { key: "m", className: "meta" }, [
                  h("div", { className: "title" }, "确认方式"),
                  h("div", { className: "hint", style: { marginBottom: 8 } }, "硬规则（支付/密码框等）仍可单独解除"),
                  hs(
                    "div",
                    { className: "seg" },
                    CONFIRM.map(function (opt) {
                      return h(
                        "button",
                        {
                          key: opt.id,
                          type: "button",
                          "aria-pressed": confirmMode === opt.id,
                          disabled: busy,
                          title: opt.hint,
                          onClick: function () {
                            void mutate(function () {
                              return api("/phone-settings/policies", {
                                method: "POST",
                                body: { confirmMode: opt.id },
                              });
                            });
                          },
                        },
                        opt.label,
                      );
                    }),
                  ),
                ]),
              ]),
            ])
          : null,
        data
          ? hs("div", { key: "c2b", className: "card" }, [
              h(
                "p",
                { key: "w", className: "warn" },
                "解除限制会放宽硬规则，默认全关。任务进行中无法新开高风险项。",
              ),
              UNLOCKS.map(function (u) {
                return hs("div", { key: u.id, className: "row" }, [
                  hs("div", { key: "m", className: "meta" }, [
                    h("div", { className: "title" }, u.label),
                    h("div", { className: "hint" }, u.hint),
                  ]),
                  h(Switch, {
                    checked: !!unlocks[u.id],
                    "aria-label": u.label,
                    disabled: busy,
                    onCheckedChange: function (next) {
                      setUnlock(u.id, next);
                    },
                  }),
                ]);
              }),
            ])
          : null,
        data
          ? hs("div", { key: "c3", className: "card" }, [
              hs("div", { key: "op", className: "row", style: { flexDirection: "column", alignItems: "stretch" } }, [
                hs("div", { className: "meta" }, [
                  h("div", { className: "title" }, "悬浮条闲置透明度"),
                  h("div", { className: "hint" }, Math.round(opacity * 100) + "%"),
                ]),
                h("input", {
                  className: "slider",
                  type: "range",
                  min: 30,
                  max: 100,
                  step: 5,
                  value: Math.round(opacity * 100),
                  disabled: busy,
                  "aria-label": "悬浮条闲置透明度",
                  onChange: function (ev) {
                    var v = Number(ev.target.value) / 100;
                    setData(Object.assign({}, data, {
                      overlay: Object.assign({}, data.overlay, { idleOpacity: v }),
                    }));
                  },
                  onMouseUp: function (ev) {
                    var v = Number(ev.target.value) / 100;
                    void mutate(function () {
                      return api("/phone-settings/overlay", {
                        method: "POST",
                        body: { idleOpacity: v },
                      });
                    });
                  },
                  onTouchEnd: function (ev) {
                    var v = Number(ev.target.value) / 100;
                    void mutate(function () {
                      return api("/phone-settings/overlay", {
                        method: "POST",
                        body: { idleOpacity: v },
                      });
                    });
                  },
                }),
              ]),
              hs("div", { key: "ac", className: "row" }, [
                hs("div", { key: "m", className: "meta" }, [
                  h("div", { className: "title" }, "闲置时自动收起"),
                  h("div", { className: "hint" }, "胶囊闲置后折回悬浮球"),
                ]),
                h(Switch, {
                  checked: autoCollapse,
                  "aria-label": "闲置时自动收起",
                  disabled: busy,
                  onCheckedChange: function (next) {
                    void mutate(function () {
                      return api("/phone-settings/overlay", {
                        method: "POST",
                        body: { autoCollapse: next },
                      });
                    });
                  },
                }),
              ]),
            ])
          : null,
      ]);
    }

    /** Face `sessions.list` returns `{ ok, value: { items: [...] } }`. */
    function pickSessionId(apiHandle) {
      return apiHandle.sessions
        .list({})
        .then(function (res) {
          var value = res && res.result && res.result.ok ? res.result.value : null;
          var rows =
            (value && Array.isArray(value.items) && value.items) ||
            (value && Array.isArray(value.sessions) && value.sessions) ||
            (Array.isArray(value) ? value : []) ||
            [];
          var running = rows.find(function (s) {
            return s && s.running;
          });
          var pick = running || rows[0];
          return pick && pick.sessionId ? pick.sessionId : null;
        })
        .catch(function () {
          return null;
        });
    }

    async function deliverSteers(apiHandle, items) {
      if (!items || !items.length) return;
      var sessionId = await pickSessionId(apiHandle);
      if (!sessionId) return;
      for (var i = 0; i < items.length; i++) {
        var text = String(items[i] || "").trim();
        if (!text) continue;
        await apiHandle.sessions.prompt({
          sessionId: sessionId,
          mode: "steer",
          content: [{ type: "text", text: text }],
        });
      }
    }

    function startSteerPump(ctx) {
      var stopped = false;
      var timer = 0;
      async function tick() {
        if (stopped) return;
        try {
          var pending = await api("/phone-settings/steer-pending");
          var items = (pending && pending.items) || [];
          if (items.length) {
            var connection = ctx.get("connection");
            var apiHandle = connection && connection.api;
            if (apiHandle && apiHandle.sessions) {
              await deliverSteers(apiHandle, items);
            }
          }
        } catch (_) {
          /* MobileApi / host plugin absent off-phone */
        }
        if (!stopped) timer = window.setTimeout(tick, 1200);
      }
      timer = window.setTimeout(tick, 800);
      return function () {
        stopped = true;
        window.clearTimeout(timer);
      };
    }

    var inject = ["slots", "locale", "connection"];

    function apply(ctx) {
      // Phone control UI lives on native PhoneControlScreen (FAB ball).
      // Do NOT inject Host Settings › 手机操控 — that page was a white-screen
      // stub and duplicated the Go settings hub.
      ctx.effect(function () {
        return startSteerPump(ctx);
      }, "xrk-mobile-ui: steer pump");

      ctx.effect(function () {
        var prev = window.__xrkPhoneSteerDrain;
        window.__xrkPhoneSteerDrain = function () {
          var connection = ctx.get("connection");
          var apiHandle = connection && connection.api;
          if (!apiHandle || !apiHandle.sessions) return Promise.resolve();
          return api("/phone-settings/steer-pending").then(function (pending) {
            return deliverSteers(apiHandle, (pending && pending.items) || []);
          });
        };
        return function () {
          if (window.__xrkPhoneSteerDrain !== undefined) {
            if (prev !== undefined) window.__xrkPhoneSteerDrain = prev;
            else delete window.__xrkPhoneSteerDrain;
          }
        };
      }, "xrk-mobile-ui: steer drain bridge");
    }

    exports.apply = apply;
    exports.inject = inject;
    return module.exports;
  },
});
