# XRK Harness 0.8.0-rc.2

- guest 引擎 `@xrkseek/harness-cli@0.8.0-rc.2`（与远程桥同一套 `xrk-phone` playbook）
- 手机操控浮层：收球交叉淡入、按压不再挤出首字；读屏拒因可读
- HTTP 主机：自签 HTTPS 可连；裸贴 host:port 若对端只认 HTTPS 会自动升级
- HTTP 主机状态：Face 加载失败 / 探活掉线会退出「已连接」，切换主机列表会刷新
- 根网页加载中系统返回不再误退后台（承 rc.1）
- 设置球菜单最上方增加「刷新」：本机重载 Face，远程则重连/重载
- 球菜单「Host 设置」：文案由「对话设置」改名；Host 未就绪时不显示该项