### 中文

**XRK Harness 手机版 0.7.17**

- 机内引擎升级为 `@xrkseek/harness-cli@0.7.17`（`runtimeVersion` 含 `xrk0.7.17`）
- **覆盖更新**：runtime 指纹变化时重装 rootfs 并抬回 `/root`（会话 / 设置 / 凭据保留）；同 runtime 仅壳升级时软愈合（清坏 `.env` / 锁 / pid），不重解整包
- 手机文件树与权限页更清晰；设置增加个性化入口

### English

**XRK Harness Mobile 0.7.17**

- On-device engine `@xrkseek/harness-cli@0.7.17` (`runtimeVersion` includes `xrk0.7.17`)
- **Overlay upgrades**: when the runtime fingerprint changes, reinstall rootfs and carry `/root` (sessions / settings / credentials kept); shell-only bumps soft-heal (bad `.env` / locks / pid) without re-extracting
- Clearer phone-files / permission UI; personalization entry in Settings
