# 贡献指南

欢迎修复问题、改进原生交互、补充测试和文档。中文与英文 Issue/PR 均可。

## 开始开发

1. Fork 仓库并克隆自己的 Fork。
2. 使用 macOS 14+、Swift 6+ 和 Apple 开发工具。
3. 运行 `./Scripts/check.sh`，再运行 `./Scripts/build.sh`。
4. 用 `dist/Aether.app/Contents/MacOS/Aether --demo` 验证交互；该模式不建立真实隧道。

完整 Xcode 下还应运行 `swift test`。Command Line Tools 若缺少 XCTest/SwiftPM 框架，可先用独立检查脚本；这不等于 XCTest 已通过。

## 修改与测试

保持修改集中，优先使用 SwiftUI 原生数据流和已有组件，避免引入无必要的依赖。

- 配置解析、规范化与错误处理：覆盖不合法输入、边界和秘密脱敏。
- 权限、文件或生命周期：先说明所有权和失败路径，提供回归测试。
- UI：检查主窗口、菜单栏面板、最小窗口尺寸、键盘和 VoiceOver 标签。
- 路由与 DNS：与单元测试分开，在自己有权管理的测试环境验证；记录 IPv4/IPv6、全隧道/分流及断开恢复。
- 用户文案默认中文；API、命令、配置键保留原始写法。

不要提交真实 `.conf`、密钥、认证文件、运行时数据或含私人服务器地址的截图。示例只用测试密钥和保留地址。构建与测试脚本不得触发管理员授权或网络更改。

## 提交 Pull Request

说明具体问题、修改后的行为、已执行检查和未验证部分。视觉修改附不含个人信息的截图；安全问题先按 [SECURITY.md](SECURITY.md) 私下报告。

提交信息以决策为中心：首行说明为什么修改；在有价值时附 `Constraint:`、`Rejected:`、`Tested:`、`Not-tested:` 等 git trailers。不要把未经执行的检查写成通过。

## 发布

维护者流程见 [发布指南](docs/releasing.md)。功能方向见 [路线图](docs/roadmap.md)。参与社区讨论请遵守 [行为准则](CODE_OF_CONDUCT.md)。
