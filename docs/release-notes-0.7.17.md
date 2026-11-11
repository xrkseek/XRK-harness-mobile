### 中文

**XRK Harness 手机版 0.7.17**

- 机内引擎升级为 `@xrkseek/harness-cli@0.7.17`（`runtimeVersion` 含 `xrk0.7.17`）
- **覆盖更新**：runtime 指纹变化时重装 rootfs 并抬回 `/root`（会话 / 设置 / 凭据保留）；同 runtime 仅壳升级时软愈合（清坏 `.env` / 锁 / pid），不重解整包
- 本机 Face 按 XRK Host：无 token 回环；权限读 `settings.describe`
- 去掉设置「个性化 / 可视化回复」旧入口
- 去掉 App 原生权限档位页与对话内切换；「访问手机文件」进设置主页；设置「手机操控」页下线（悬浮球仍可进）

### English

**XRK Harness Mobile 0.7.17**

- On-device engine `@xrkseek/harness-cli@0.7.17` (`runtimeVersion` includes `xrk0.7.17`)
- **Overlay upgrades**: when the runtime fingerprint changes, reinstall rootfs and carry `/root` (sessions / settings / credentials kept); shell-only bumps soft-heal (bad `.env` / locks / pid) without re-extracting
- Local Face matches XRK Host: open loopback; permissions via `settings.describe`
- Removed Settings「Personalization / visual replies」leftover
- Dropped native permission-tier UI; phone files on Settings hub; Settings phone-control page retired (ball nav kept)
